#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test runner without bundler dependencies
$LOAD_PATH.unshift File.expand_path("lib", __dir__)

require "active_support/core_ext/hash/indifferent_access"
require "raaf/eval/dsl/field_selector"
require "raaf/eval/dsl/field_context"

# Simple test framework
class TestRunner
  def self.run_test(name, &block)
    begin
      instance_eval(&block)
      puts "✓ #{name}"
    rescue => e
      puts "✗ #{name}"
      puts "  Error: #{e.message}"
      puts "  #{e.backtrace.first}"
    end
  end

  def self.assert_equal(expected, actual)
    raise "Expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
  end

  def self.assert_raises(error_class, pattern = nil)
    begin
      yield
      raise "Expected #{error_class} to be raised, but nothing was raised"
    rescue error_class => e
      if pattern && !e.message.match?(pattern)
        raise "Expected error message to match #{pattern.inspect}, got #{e.message.inspect}"
      end
    rescue => e
      raise "Expected #{error_class}, got #{e.class}: #{e.message}"
    end
  end
end

puts "\n=== Testing FieldSelector ==="
puts "\n2.1 - Nested path parsing tests:\n"

selector = RAAF::Eval::DSL::FieldSelector.new

TestRunner.run_test("parses single-level field names") do
  parsed = selector.parse_path("output")
  assert_equal(["output"], parsed)
end

TestRunner.run_test("parses dot notation paths (usage.total_tokens)") do
  parsed = selector.parse_path("usage.total_tokens")
  assert_equal(["usage", "total_tokens"], parsed)
end

TestRunner.run_test("parses deeply nested paths") do
  parsed = selector.parse_path("result.metrics.quality.score")
  assert_equal(["result", "metrics", "quality", "score"], parsed)
end

TestRunner.run_test("handles symbol field names") do
  parsed = selector.parse_path(:output)
  assert_equal(["output"], parsed)
end

TestRunner.run_test("raises error for empty string") do
  assert_raises(RAAF::Eval::DSL::InvalidPathError, /empty or invalid/) do
    selector.parse_path("")
  end
end

TestRunner.run_test("raises error for nil") do
  assert_raises(RAAF::Eval::DSL::InvalidPathError, /empty or invalid/) do
    selector.parse_path(nil)
  end
end

TestRunner.run_test("caches parsed paths for performance") do
  parsed1 = selector.parse_path("usage.total_tokens")
  parsed2 = selector.parse_path("usage.total_tokens")
  assert_equal(parsed1.object_id, parsed2.object_id)
end

puts "\n2.3 - Field extraction tests:\n"

selector2 = RAAF::Eval::DSL::FieldSelector.new
result = {
  output: "Generated text",
  usage: {
    total_tokens: 150,
    prompt_tokens: 50,
    completion_tokens: 100
  },
  deeply: {
    nested: {
      field: {
        value: "deep_value"
      }
    }
  }
}

TestRunner.run_test("extracts single field values") do
  value = selector2.extract_value("output", result)
  assert_equal("Generated text", value)
end

TestRunner.run_test("extracts nested field values") do
  value = selector2.extract_value("usage.total_tokens", result)
  assert_equal(150, value)
end

TestRunner.run_test("extracts deeply nested values") do
  value = selector2.extract_value("deeply.nested.field.value", result)
  assert_equal("deep_value", value)
end

TestRunner.run_test("raises error when field is missing") do
  assert_raises(RAAF::Eval::DSL::FieldNotFoundError, /Field 'missing_field' not found/) do
    selector2.extract_value("missing_field", result)
  end
end

TestRunner.run_test("handles HashWithIndifferentAccess") do
  indifferent_result = ActiveSupport::HashWithIndifferentAccess.new(result)
  value = selector2.extract_value("usage.total_tokens", indifferent_result)
  assert_equal(150, value)
end

puts "\n2.5 - Field aliasing tests:\n"

selector3 = RAAF::Eval::DSL::FieldSelector.new

TestRunner.run_test("assigns aliases with as: parameter") do
  selector3.add_field("usage.total_tokens", as: :tokens)
  assert_equal("usage.total_tokens", selector3.aliases["tokens"])
end

TestRunner.run_test("resolves aliases") do
  selector3.add_field("usage.total_tokens", as: :tokens)
  original_path = selector3.resolve_alias(:tokens)
  assert_equal("usage.total_tokens", original_path)
end

TestRunner.run_test("detects duplicate aliases") do
  selector4 = RAAF::Eval::DSL::FieldSelector.new
  selector4.add_field("usage.total_tokens", as: :tokens)
  
  assert_raises(RAAF::Eval::DSL::DuplicateAliasError, /Alias 'tokens' is already assigned/) do
    selector4.add_field("usage.prompt_tokens", as: :tokens)
  end
end

TestRunner.run_test("stores fields in order") do
  selector5 = RAAF::Eval::DSL::FieldSelector.new
  selector5.add_field("first")
  selector5.add_field("second")
  selector5.add_field("third")
  assert_equal(["first", "second", "third"], selector5.fields)
end

puts "\n2.7 - Validation tests:\n"

TestRunner.run_test("validates empty path at selection time") do
  selector6 = RAAF::Eval::DSL::FieldSelector.new
  assert_raises(RAAF::Eval::DSL::InvalidPathError, /empty or invalid/) do
    selector6.add_field("")
  end
end

TestRunner.run_test("validates non-string/symbol types") do
  selector7 = RAAF::Eval::DSL::FieldSelector.new
  assert_raises(RAAF::Eval::DSL::InvalidPathError, /must be a string or symbol/) do
    selector7.add_field(123)
  end
end

TestRunner.run_test("validates consecutive dots") do
  selector8 = RAAF::Eval::DSL::FieldSelector.new
  assert_raises(RAAF::Eval::DSL::InvalidPathError, /Invalid path format/) do
    selector8.add_field("usage..tokens")
  end
end

TestRunner.run_test("validates leading dots") do
  selector9 = RAAF::Eval::DSL::FieldSelector.new
  assert_raises(RAAF::Eval::DSL::InvalidPathError, /Invalid path format/) do
    selector9.add_field(".usage.tokens")
  end
end

TestRunner.run_test("creates FieldContext successfully") do
  selector10 = RAAF::Eval::DSL::FieldSelector.new
  result = { output: "text", usage: { total_tokens: 100 } }
  
  selector10.add_field("output")
  selector10.add_field("usage.total_tokens", as: :tokens)
  
  context1 = selector10.create_field_context("output", result)
  assert_equal("text", context1.value)
  
  context2 = selector10.create_field_context(:tokens, result)
  assert_equal(100, context2.value)
end

puts "\n=== Test Summary ==="
puts "All field selector tests completed!"
