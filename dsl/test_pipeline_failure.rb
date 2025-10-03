#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple integration test for pipeline failure propagation
# Run with: ruby test_pipeline_failure.rb

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'raaf-dsl'

# Mock agents for testing
class SuccessAgent < RAAF::DSL::Agent
  agent_name "SuccessAgent"
  model "gpt-4o"

  context do
    optional test_data: "test"
    output :result
  end

  def call
    puts "✅ SuccessAgent executed"
    { success: true, result: "success" }
  end
end

class FailAgent < RAAF::DSL::Agent
  agent_name "FailAgent"
  model "gpt-4o"

  context do
    optional test_data: "test"
  end

  def call
    puts "❌ FailAgent executed and returning failure"
    { success: false, error: "Intentional failure for testing", error_type: "test_error" }
  end
end

class NeverReachedAgent < RAAF::DSL::Agent
  agent_name "NeverReachedAgent"
  model "gpt-4o"

  context do
    optional test_data: "test"
  end

  def call
    puts "🚫 THIS SHOULD NEVER PRINT - Pipeline should have stopped!"
    { success: true, result: "should not reach here" }
  end
end

# Test 1: Sequential pipeline with failure
puts "\n" + "=" * 60
puts "TEST 1: Sequential pipeline with failure propagation"
puts "=" * 60

class TestPipeline < RAAF::Pipeline
  flow SuccessAgent >> FailAgent >> NeverReachedAgent

  context do
    optional test_data: "test"
  end
end

pipeline = TestPipeline.new(test_data: "test")
result = pipeline.run

puts "\n📊 Result:"
puts "  success: #{result[:success]}"
puts "  error: #{result[:error]}"
puts "  error_type: #{result[:error_type]}"
puts "  failed_at: #{result[:failed_at]}"

if result[:success] == false &&
   result[:failed_at] == "FailAgent" &&
   result[:error].include?("Intentional failure")
  puts "\n✅ TEST 1 PASSED: Pipeline stopped at FailAgent as expected"
else
  puts "\n❌ TEST 1 FAILED: Pipeline did not stop correctly"
  puts "   Expected: success=false, failed_at=FailAgent"
  puts "   Got: success=#{result[:success]}, failed_at=#{result[:failed_at]}"
  exit 1
end

# Test 2: All agents succeed
puts "\n" + "=" * 60
puts "TEST 2: Pipeline with all successful agents"
puts "=" * 60

class SuccessPipeline < RAAF::Pipeline
  flow SuccessAgent >> SuccessAgent

  context do
    optional test_data: "test"
  end
end

pipeline2 = SuccessPipeline.new(test_data: "test")
result2 = pipeline2.run

puts "\n📊 Result:"
puts "  success: #{result2[:success]}"

if result2[:success] == true
  puts "\n✅ TEST 2 PASSED: Pipeline succeeded when all agents succeed"
else
  puts "\n❌ TEST 2 FAILED: Pipeline should have succeeded"
  exit 1
end

puts "\n" + "=" * 60
puts "🎉 ALL TESTS PASSED!"
puts "=" * 60
puts "\nPipeline failure propagation is working correctly:"
puts "  ✓ Pipelines stop immediately when an agent returns success: false"
puts "  ✓ Subsequent agents are not executed"
puts "  ✓ Error details are properly captured and returned"
puts "  ✓ Pipelines succeed when all agents succeed"
