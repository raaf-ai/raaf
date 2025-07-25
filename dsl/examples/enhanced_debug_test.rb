#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify enhanced debugging capabilities in RAAF::DSL::Agents::Base

require_relative "../lib/ai_agent_dsl"

# Add the lib directory to the load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Mock Rails logger for testing
class MockRailsLogger
  def info(msg)
    puts "[INFO] #{msg}"
  end

  def debug(msg)
    puts "[DEBUG] #{msg}"
  end

  def error(msg)
    puts "[ERROR] #{msg}"
  end
end

# Mock Rails module for testing
module Rails
  def self.logger
    @logger ||= MockRailsLogger.new
  end

  def self.env
    @env ||= MockRailsEnv.new
  end

  def self.respond_to?(method)
    %i[logger env].include?(method)
  end
end

# Mock Rails env for testing
class MockRailsEnv
  def development?
    true
  end

  def test?
    false
  end

  def production?
    false
  end
end

# Test agent that includes the enhanced debugging capabilities
class TestAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl

  agent_name "TestAgent"
  model "gpt-4o"
  max_turns 2

  def build_instructions
    "You are a test agent for debugging purposes."
  end

  def build_schema
    {
      type: "object",
      properties: {
        result: { type: "string" }
      },
      required: ["result"],
      additionalProperties: false
    }
  end
end

# Test the enhanced debugging capabilities
puts "=" * 80
puts "🔍 TESTING ENHANCED DEBUGGING CAPABILITIES"
puts "=" * 80
puts

# Create a test agent instance
context = {
  document: { name: "test.pdf", description: "Test document" },
  product: { name: "Test Product" }
}

processing_params = {
  content_type: "test_content",
  formats: ["PDF"],
  max_pages: 10
}

agent = TestAgent.new(
  context: context,
  processing_params: processing_params,
  debug: true
)

puts "📋 Agent created successfully"
puts "   Name: #{agent.agent_name}"
puts "   Class: #{agent.class.name}"
puts "   Debug enabled: #{agent.debug_enabled}"
puts

# Test debug_context_summary
puts "🔍 Testing debug_context_summary:"
puts "-" * 40
summary = agent.debug_context_summary
puts "Summary keys: #{summary.keys.join(', ')}"
puts "Agent info: #{summary[:agent_info]}"
puts

# Test inspect_context
puts "🔍 Testing inspect_context:"
puts "-" * 40
begin
  context_summary = agent.inspect_context
  puts "Context inspection completed"
  puts "Summary: #{context_summary}"
rescue StandardError => e
  puts "Context inspection error: #{e.message}"
end
puts

# Test inspect_prompts
puts "🔍 Testing inspect_prompts:"
puts "-" * 40
begin
  agent.inspect_prompts
  puts "Prompt inspection completed"
rescue StandardError => e
  puts "Prompt inspection error: #{e.message}"
end
puts

# Test debug_components_available?
puts "🔍 Testing debug_components_available?:"
puts "-" * 40
available = agent.debug_components_available?
puts "Debug components available: #{available}"
puts

# Test convenience methods exist
puts "🔍 Testing convenience methods:"
puts "-" * 40
convenience_methods = %i[
  run_with_minimal_debug
  run_with_standard_debug
  run_with_verbose_debug
  run_with_debug
]

convenience_methods.each do |method|
  if agent.respond_to?(method)
    puts "✅ #{method} - available"
  else
    puts "❌ #{method} - missing"
  end
end
puts

puts "=" * 80
puts "🏁 ENHANCED DEBUGGING TEST COMPLETE"
puts "=" * 80
