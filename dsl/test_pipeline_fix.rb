#!/usr/bin/env ruby
# Test script to verify the pipeline validation fix

require_relative 'lib/raaf-dsl'

# Define a simple agent that provides a field
class DataAgent < RAAF::DSL::Agent
  agent_name "DataAgent"
  model "gpt-4o"
  
  context do
    required :input
    output :processed_data
  end
  
  def self.provided_fields
    [:processed_data]
  end
  
  def call
    { processed_data: "processed_#{input}" }
  end
end

# Define an agent that requires the field from the first agent
class ProcessorAgent < RAAF::DSL::Agent
  agent_name "ProcessorAgent"
  model "gpt-4o"
  
  context do
    required :processed_data  # This should be provided by DataAgent
    output :final_result
  end
  
  def self.provided_fields
    [:final_result]
  end
  
  def call
    { final_result: "final_#{processed_data}" }
  end
end

# Define a pipeline that chains these agents
class TestPipeline < RAAF::Pipeline
  flow DataAgent >> ProcessorAgent
  
  context do
    required :input
  end
end

puts "Testing pipeline validation fix..."
puts

begin
  # This should now work without validation errors
  pipeline = TestPipeline.new(input: "test_data")
  puts "✅ Pipeline created successfully!"
  
  # Validate pipeline
  pipeline.validate_pipeline!
  puts "✅ Pipeline validation passed!"
  
rescue => e
  puts "❌ Pipeline validation failed:"
  puts e.message
  puts
  puts "Error backtrace:"
  puts e.backtrace.first(5)
end

puts
puts "Fix verification complete."