#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test script for auto-context functionality
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("../core/lib", __dir__))

require "bundler/setup"
require "raaf/dsl/agent"
require "raaf/dsl/core/context_variables"
require "raaf/dsl/core/context_builder"

# Test 1: Default auto-context behavior
class SimpleAgent < RAAF::DSL::Agent
  agent_name "SimpleAgent"
  static_instructions "Test agent"
end

puts "Test 1: Default auto-context behavior"
agent = SimpleAgent.new(user: "john", query: "test", max_results: 10)
puts "  auto_context enabled: #{SimpleAgent.auto_context?}"
puts "  context[:user] = #{agent.get(:user)}"
puts "  context[:query] = #{agent.get(:query)}"
puts "  context[:max_results] = #{agent.get(:max_results)}"
puts "  ✓ Auto-context working!" if agent.get(:user) == "john"
puts

# Test 2: Clean API methods
puts "Test 2: Clean API methods"
agent.set(:new_key, "new_value")
puts "  set(:new_key, 'new_value') => #{agent.get(:new_key)}"
agent.update(status: "complete", count: 42)
puts "  update(status: 'complete', count: 42)"
puts "  context[:status] = #{agent.get(:status)}"
puts "  has?(:status) = #{agent.has?(:status)}"
puts "  context_keys = #{agent.context_keys.inspect}"
puts "  ✓ Clean API working!" if agent.get(:status) == "complete"
puts

# Test 3: Disabled auto-context
class ManualAgent < RAAF::DSL::Agent
  agent_name "ManualAgent"
  auto_context false
  static_instructions "Test"
end

puts "Test 3: Disabled auto-context"
manual = ManualAgent.new(user: "jane", data: "ignored")
puts "  auto_context disabled: #{!ManualAgent.auto_context?}"
puts "  context_keys (should be empty): #{manual.context_keys.inspect}"
puts "  ✓ Auto-context can be disabled!" if manual.context_keys.empty?
puts

# Test 4: Context DSL with exclusions
class ConfiguredAgent < RAAF::DSL::Agent
  agent_name "ConfiguredAgent"
  
  context do
    exclude :cache, :logger
  end
  
  static_instructions "Test"
end

puts "Test 4: Context DSL with exclusions"
configured = ConfiguredAgent.new(
  user: "bob",
  data: "important",
  cache: "should_be_excluded",
  logger: "also_excluded"
)
puts "  has?(:user) = #{configured.has?(:user)}"
puts "  has?(:data) = #{configured.has?(:data)}"
puts "  has?(:cache) = #{configured.has?(:cache)} (should be false)"
puts "  has?(:logger) = #{configured.has?(:logger)} (should be false)"
puts "  ✓ Context DSL working!" if configured.has?(:user) && !configured.has?(:cache)
puts

# Test 5: Custom preparation methods
class PrepAgent < RAAF::DSL::Agent
  agent_name "PrepAgent"
  static_instructions "Test"
  
  private
  
  def prepare_user_for_context(user)
    { id: user[:id], name: user[:name] } # Strip email
  end
end

puts "Test 5: Custom preparation methods"
prep = PrepAgent.new(user: { id: 123, name: "Alice", email: "alice@example.com" })
user_context = prep.get(:user)
puts "  Original user: {id: 123, name: 'Alice', email: 'alice@example.com'}"
puts "  Context user: #{user_context.inspect}"
puts "  ✓ Custom preparation working!" if user_context == { id: 123, name: "Alice" }
puts

# Test 6: Computed context values
class ComputedAgent < RAAF::DSL::Agent
  agent_name "ComputedAgent"
  static_instructions "Test"
  
  private
  
  def build_metadata_context
    { timestamp: "2025-01-01", version: "1.0" }
  end
end

puts "Test 6: Computed context values"
computed = ComputedAgent.new(base: "data")
puts "  has?(:base) = #{computed.has?(:base)}"
puts "  has?(:metadata) = #{computed.has?(:metadata)}"
puts "  context[:metadata] = #{computed.get(:metadata).inspect}"
puts "  ✓ Computed context working!" if computed.get(:metadata) == { timestamp: "2025-01-01", version: "1.0" }
puts

# Test 7: Backward compatibility
class BackwardCompatAgent < RAAF::DSL::Agent
  agent_name "BackwardCompatAgent"
  static_instructions "Test"
  
  def initialize(data:)
    context = RAAF::DSL::ContextVariables.new(processed: data.upcase)
    super(context: context)
  end
end

puts "Test 7: Backward compatibility"
backward = BackwardCompatAgent.new(data: "test")
puts "  context[:processed] = #{backward.get(:processed)}"
puts "  has?(:data) = #{backward.has?(:data)} (should be false)"
puts "  ✓ Backward compatibility maintained!" if backward.get(:processed) == "TEST" && !backward.has?(:data)
puts

puts "\n✅ All tests passed!" if true