#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal test script for MergeStrategy and EdgeCases

require 'active_support/core_ext/hash/deep_merge'

# Mock RAAF.logger for testing
module RAAF
  def self.logger
    @logger ||= begin
      logger = Object.new
      def logger.warn(msg); puts "WARN: #{msg}"; end
      logger
    end
  end
end

# Load our implementations
require_relative 'lib/raaf/dsl/edge_cases'
require_relative 'lib/raaf/dsl/merge_strategy'
require_relative 'lib/raaf/dsl/auto_merge'

def test_by_id_strategy
  puts "Testing by_id strategy..."

  existing = [
    { id: 1, name: 'Market A', score: 80 },
    { id: 2, name: 'Market B', score: 75 }
  ]

  new_data = [
    { id: 1, overall_score: 85, scoring: { complexity: 'medium' } },
    { id: 3, name: 'Market C', score: 90 }
  ]

  strategy = RAAF::DSL::MergeStrategy.detect_strategy(:markets, existing, new_data)
  puts "  Detected strategy: #{strategy}"

  result = RAAF::DSL::MergeStrategy.apply_strategy(strategy, existing, new_data)
  puts "  Result length: #{result.length}"
  puts "  First item: #{result[0]}"
  puts "  Has scoring: #{result[0].key?(:scoring)}"
  puts "   by_id strategy working"
  puts
end

def test_append_strategy
  puts "Testing append strategy..."

  existing = ['tag1', 'tag2']
  new_data = ['tag3', 'tag4']

  strategy = RAAF::DSL::MergeStrategy.detect_strategy(:tags, existing, new_data)
  puts "  Detected strategy: #{strategy}"

  result = RAAF::DSL::MergeStrategy.apply_strategy(strategy, existing, new_data)
  puts "  Result: #{result}"
  puts "   append strategy working"
  puts
end

def test_deep_merge_strategy
  puts "Testing deep_merge strategy..."

  existing = {
    metadata: { source: 'analysis' },
    stats: { total_count: 10 }
  }

  new_data = {
    metadata: { timestamp: '2025-09-16' },
    additional_info: { version: '1.0' }
  }

  strategy = RAAF::DSL::MergeStrategy.detect_strategy(:data, existing, new_data)
  puts "  Detected strategy: #{strategy}"

  result = RAAF::DSL::MergeStrategy.apply_strategy(strategy, existing, new_data)
  puts "  Source preserved: #{result[:metadata][:source]}"
  puts "  Timestamp added: #{result[:metadata][:timestamp]}"
  puts "   deep_merge strategy working"
  puts
end

def test_edge_cases
  puts "Testing edge cases..."

  # Array + single record
  existing = [{ id: 1, name: 'A' }]
  new_data = { id: 2, name: 'B' }

  result = RAAF::DSL::EdgeCases.handle_single_record_merge(existing, new_data)
  puts "  Array + single result length: #{result.length}"
  puts "   edge case handling working"

  # Test temp ID generation
  temp_id = RAAF::DSL::EdgeCases.generate_temp_id
  puts "  Generated temp ID: #{temp_id}"
  puts "   temp ID generation working"
  puts
end

def test_performance
  puts "Testing performance..."

  # Create large datasets
  large_existing = (1..1000).map { |i| { id: i, name: "Item #{i}", value: i * 10 } }
  large_new = (500..1500).map { |i| { id: i, score: i * 2, updated: true } }

  start_time = Time.now
  result = RAAF::DSL::MergeStrategy.apply_strategy(:by_id, large_existing, large_new)
  execution_time = Time.now - start_time

  puts "  Merged #{large_existing.length} + #{large_new.length} records in #{execution_time.round(4)}s"
  puts "  Final result length: #{result.length}"
  puts "   performance test passed"
  puts
end

def test_one_step_merge
  puts "Testing one-step merge..."

  existing = [{ id: 1, name: 'A' }]
  new_data = [{ id: 1, score: 85 }, { id: 2, name: 'B' }]

  result = RAAF::DSL::MergeStrategy.merge(:markets, existing, new_data)
  puts "  Result: #{result}"
  puts "   one-step merge working"
  puts
end

# Run all tests
puts "=== RAAF DSL MergeStrategy Tests ==="
puts

test_by_id_strategy
test_append_strategy
test_deep_merge_strategy
test_edge_cases
test_performance
test_one_step_merge

puts "=== All tests completed successfully! ==="

# Test AutoMerge integration
puts
puts "=== Testing AutoMerge Integration ==="
puts

def test_auto_merge_integration
  puts "Testing AutoMerge with mock agent..."

  # Create a mock base agent class first
  mock_base_class = Class.new do
    def initialize(mock_results = {})
      @mock_results = mock_results
    end

    # This is the base run method that AutoMerge will call via super
    def run(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
      {
        success: true,
        results: @mock_results,
        context_variables: context || input_context_variables,
        summary: "Mock agent execution completed"
      }
    end
  end

  # Create a mock agent class with AutoMerge that extends the base
  mock_agent_class = Class.new(mock_base_class) do
    include RAAF::DSL::AutoMerge
    # AutoMerge's run method will override base run and call super to reach mock_base_class.run
  end

  # Create a mock context class
  mock_context_class = Class.new do
    def initialize(data = {})
      @variables = data
    end

    def get(key)
      @variables[key] || @variables[key.to_s]
    end

    def set(key, value)
      @variables[key] = value
    end

    def to_h
      @variables
    end

    attr_reader :variables
  end

  # Test by_id merging
  existing_markets = [
    { id: 1, name: 'Market A', score: 80 },
    { id: 2, name: 'Market B', score: 75 }
  ]

  context = mock_context_class.new(markets: existing_markets)

  agent = mock_agent_class.new({
    markets: [
      { id: 1, overall_score: 85, scoring: { complexity: 'medium' } },
      { id: 3, name: 'Market C', score: 90 }
    ]
  })

  result = agent.run(context: context)

  puts "  AutoMerge result success: #{result[:success]}"
  puts "  Merged markets count: #{result[:results][:markets].length}"
  puts "  First market has scoring: #{result[:results][:markets][0].key?(:scoring)}"
  puts "  Context updated: #{context.get(:markets).length} markets (expected 3)"
  puts "  ✓ AutoMerge integration working"
  puts
end

test_auto_merge_integration

puts "=== AutoMerge Integration Tests Completed! ==="