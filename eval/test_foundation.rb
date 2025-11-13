#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test runner for foundation classes
require "minitest/autorun"
require "active_support/core_ext/hash/indifferent_access"

# Require the foundation classes
require_relative "lib/raaf/eval/dsl/field_context"
require_relative "lib/raaf/eval/dsl/evaluator_definition"
require_relative "lib/raaf/eval/dsl/evaluation_result"

class FieldContextTest < Minitest::Test
  def setup
    @result_hash = {
      output: "This is the AI output",
      baseline_output: "This is the baseline output",
      usage: {
        total_tokens: 150,
        prompt_tokens: 50,
        completion_tokens: 100
      },
      baseline_usage: {
        total_tokens: 120,
        prompt_tokens: 40,
        completion_tokens: 80
      },
      configuration: {
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000
      },
      latency_ms: 250.5
    }
  end

  def test_field_value_extraction
    context = RAAF::Eval::DSL::FieldContext.new("output", @result_hash)
    assert_equal "This is the AI output", context.value
  end

  def test_nested_field_extraction
    context = RAAF::Eval::DSL::FieldContext.new("usage.total_tokens", @result_hash)
    assert_equal 150, context.value
  end

  def test_baseline_value_detection
    context = RAAF::Eval::DSL::FieldContext.new("output", @result_hash)
    assert_equal "This is the baseline output", context.baseline_value
  end

  def test_delta_calculation
    context = RAAF::Eval::DSL::FieldContext.new("usage.total_tokens", @result_hash)
    assert_equal 30, context.delta
    assert_equal 25.0, context.delta_percentage
  end

  def test_convenience_accessors
    context = RAAF::Eval::DSL::FieldContext.new("output", @result_hash)
    assert_equal 150, context.usage["total_tokens"]
    assert_equal 50, context.usage["prompt_tokens"]
    assert_equal 100, context.usage["completion_tokens"]
    assert_equal "gpt-4", context.configuration["model"]
    assert_equal 0.7, context.configuration["temperature"]
    assert_equal 1000, context.configuration["max_tokens"]
    assert_equal 250.5, context.latency_ms
  end

  def test_field_exists
    context = RAAF::Eval::DSL::FieldContext.new("output", @result_hash)
    assert context.field_exists?("usage.total_tokens")
    refute context.field_exists?("nonexistent")
  end

  def test_missing_field_error
    assert_raises(RAAF::Eval::DSL::FieldNotFoundError) do
      RAAF::Eval::DSL::FieldContext.new("missing_field", @result_hash)
    end
  end
end

class EvaluatorDefinitionTest < Minitest::Test
  def setup
    @definition = RAAF::Eval::DSL::EvaluatorDefinition.new
  end

  def test_field_selection
    @definition.add_field("output")
    @definition.add_field("usage.total_tokens", as: "tokens")

    assert_equal 2, @definition.selected_fields.size
    assert_equal({ path: "output", alias: nil }, @definition.get_field("output"))
    assert_equal({ path: "usage.total_tokens", alias: "tokens" }, @definition.get_field_by_alias("tokens"))
  end

  def test_field_evaluator_attachment
    config = { evaluators: [{ name: :quality }], combine_with: :AND }
    @definition.add_field_evaluator("output", config)

    assert_equal config, @definition.get_field_evaluator("output")
  end

  def test_progress_callbacks
    events = []
    @definition.add_progress_callback { |event| events << event }

    event = { status: "start", progress: 0 }
    @definition.trigger_progress(event)

    assert_equal [event], events
  end

  def test_history_configuration
    @definition.configure_history(auto_save: true, tags: ["test"])

    assert @definition.history_config[:auto_save]
    assert_equal ["test"], @definition.history_config[:tags]
  end
end

class EvaluationResultTest < Minitest::Test
  def setup
    @field_results = {
      "output" => {
        passed: true,
        score: 0.9,
        details: { quality: "high" },
        message: "Output quality is high"
      },
      "usage.total_tokens" => {
        passed: false,
        score: 0.4,
        details: { efficiency: "low" },
        message: "Token usage is inefficient"
      }
    }
  end

  def test_passed_method
    result = RAAF::Eval::DSL::EvaluationResult.new(field_results: @field_results)
    refute result.passed?

    all_passed = {
      "output" => { passed: true, score: 0.9 },
      "tokens" => { passed: true, score: 0.8 }
    }
    result2 = RAAF::Eval::DSL::EvaluationResult.new(field_results: all_passed)
    assert result2.passed?
  end

  def test_field_results_access
    result = RAAF::Eval::DSL::EvaluationResult.new(field_results: @field_results)

    assert_equal @field_results["output"], result.field_result("output")
    assert_equal ["output"], result.passed_fields
    assert_equal ["usage.total_tokens"], result.failed_fields
  end

  def test_aggregate_scores
    result = RAAF::Eval::DSL::EvaluationResult.new(field_results: @field_results)

    assert_equal 0.65, result.average_score
    assert_equal 0.4, result.min_score
    assert_equal 0.9, result.max_score
  end

  def test_summary_generation
    metadata = {
      execution_time_ms: 1250.5,
      evaluator_name: "quality_evaluator"
    }
    result = RAAF::Eval::DSL::EvaluationResult.new(
      field_results: @field_results,
      metadata: metadata
    )

    summary = result.summary
    refute summary[:passed]
    assert_equal 1, summary[:passed_fields]
    assert_equal 1, summary[:failed_fields]
    assert_equal 0.65, summary[:average_score]
    assert_equal 1250.5, summary[:execution_time_ms]
  end
end

# Run the tests
if __FILE__ == $0
  puts "\n>>> Running Foundation Layer Tests\n"
  puts "=" * 50

  # Count tests
  test_count = 0
  [FieldContextTest, EvaluatorDefinitionTest, EvaluationResultTest].each do |test_class|
    test_count += test_class.instance_methods.grep(/^test_/).size
  end

  puts "Running #{test_count} tests from 3 test classes\n"
  puts "=" * 50
end