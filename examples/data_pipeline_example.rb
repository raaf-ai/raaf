#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/data_pipeline"

# Set API key from environment
OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY", nil)
end

puts "=== Data Pipeline Example ==="
puts

# Example 1: Basic pipeline
puts "Example 1: Basic Data Pipeline"
puts "-" * 50

# Create a simple pipeline
simple_pipeline = OpenAIAgents::DataPipeline::Pipeline.new("simple_pipeline")

# Add stages
simple_pipeline
  .add_stage(OpenAIAgents::DataPipeline::MapStage.new("uppercase", &:upcase))
  .add_stage(OpenAIAgents::DataPipeline::MapStage.new("reverse", &:reverse))
  .add_stage(OpenAIAgents::DataPipeline::OutputStage.new("print", destination: :stdout))

# Process data
puts "Processing 'hello world' through pipeline:"
result = simple_pipeline.process("hello world")
puts "Final result: #{result}"
puts

# Example 2: Agent-based transformation
puts "Example 2: Agent-based Transformation"
puts "-" * 50

# Create data processing agent
data_agent = OpenAIAgents::Agent.new(
  name: "DataProcessor",
  model: "gpt-4o-mini",
  instructions: "You process and clean data. Extract key information and format it nicely."
)

# Create pipeline with agent
agent_pipeline = OpenAIAgents::DataPipeline::PipelineBuilder.build("agent_pipeline") do
  # Parse JSON
  map do |data| 
    
    JSON.parse(data)
  rescue StandardError
    { raw: data }
    
  end
  
  # Transform with agent
  transform(
    agent: data_agent,
    prompt: "Extract and summarize key information from: {{data}}"
  )
  
  # Output result
  output(destination: :stdout, format: :json)
end

# Test data
test_data = {
  user: { name: "John Doe", age: 30, email: "john@example.com" },
  orders: [
    { id: 1, amount: 100.50, status: "completed" },
    { id: 2, amount: 250.00, status: "pending" }
  ]
}.to_json

puts "Processing user data through agent pipeline:"
agent_pipeline.run(test_data)
puts

# Example 3: Filter and validation pipeline
puts "Example 3: Filter and Validation Pipeline"
puts "-" * 50

# Define validation schema
user_schema = {
  name: { required: true, type: String },
  email: { required: true, pattern: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i },
  age: { required: false, type: Integer }
}

# Create validation pipeline
validation_pipeline = OpenAIAgents::DataPipeline::PipelineBuilder.build("validation") do
  # Validate data
  validate(schema: user_schema) do |data|
    errors = []
    errors << "Age must be positive" if data[:age] && data[:age] < 0
    errors << "Name too short" if data[:name] && data[:name].length < 2
    errors
  end
  
  # Filter valid adults
  filter { |data| data[:age] && data[:age] >= 18 }
  
  # Format output
  map { |data| "Valid adult user: #{data[:name]} (#{data[:age]})" }
  
  output(destination: :stdout)
end

# Test data
test_users = [
  { name: "Alice", email: "alice@example.com", age: 25 },
  { name: "B", email: "invalid-email", age: 30 },
  { name: "Charlie", email: "charlie@example.com", age: 16 },
  { name: "David", email: "david@example.com", age: -5 }
]

puts "Processing users through validation pipeline:"
test_users.each do |user|
  puts "\nProcessing: #{user.inspect}"
  begin
    validation_pipeline.run(user)
  rescue StandardError => e
    puts "  Error: #{e.message}"
  end
end
puts

# Example 4: ETL pipeline with enrichment
puts "Example 4: ETL Pipeline with Enrichment"
puts "-" * 50

# Create enrichment source (mock database)
user_database = {
  "123" => { premium: true, credits: 1000 },
  "456" => { premium: false, credits: 100 },
  "789" => { premium: true, credits: 5000 }
}

# Create ETL pipeline
etl_pipeline = OpenAIAgents::DataPipeline::PipelineBuilder.build("etl") do
  # Extract - parse CSV-like data
  map do |line|
    parts = line.split(",")
    { id: parts[0], name: parts[1], purchases: parts[2].to_i }
  end
  
  # Transform - calculate metrics
  map do |data|
    data[:avg_purchase] = data[:purchases] > 0 ? rand(50..200) : 0
    data[:status] = data[:purchases] > 10 ? "active" : "inactive"
    data
  end
  
  # Enrich with external data
  enrich(source: ->(data) { user_database[data[:id]] || {} }) do |data, enrichment|
    data.merge(enrichment)
  end
  
  # Load - output as JSON
  output(destination: :stdout, format: :json)
end

# Test data
csv_data = [
  "123,Alice Smith,15",
  "456,Bob Jones,3",
  "789,Carol White,25"
]

puts "Processing CSV data through ETL pipeline:"
csv_data.each do |line|
  puts "\nInput: #{line}"
  puts "Output:"
  etl_pipeline.run(line)
end
puts

# Example 5: Stream processing
puts "Example 5: Stream Processing"
puts "-" * 50

# Create stream processing pipeline
stream_pipeline = OpenAIAgents::DataPipeline::Pipeline.new("stream_processor")

# Add stages for log processing
stream_pipeline
  .add_stage(OpenAIAgents::DataPipeline::MapStage.new("parse_log") do |line|
    if (match = line.match(/\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[(\w+)\] (.+)/))
      { timestamp: match[1], level: match[2], message: match[3] }
    else
      { timestamp: Time.now.to_s, level: "INFO", message: line }
    end
  end)
  .add_stage(OpenAIAgents::DataPipeline::FilterStage.new("errors_only") do |log|
    %w[ERROR CRITICAL].include?(log[:level])
  end)

# Simulate log stream
log_stream = [
  "[2024-01-15 10:30:00] [INFO] Application started",
  "[2024-01-15 10:30:15] [ERROR] Database connection failed",
  "[2024-01-15 10:30:20] [WARN] Retry attempt 1",
  "[2024-01-15 10:30:25] [ERROR] Database still unavailable",
  "[2024-01-15 10:30:30] [CRITICAL] System shutting down"
]

puts "Processing log stream for errors:"
stream_pipeline.process_stream(log_stream) do |result|
  puts "  Alert: #{result[:level]} at #{result[:timestamp]} - #{result[:message]}" if result
end
puts

# Example 6: Batch processing with parallelization
puts "Example 6: Batch Processing"
puts "-" * 50

# Create batch processing pipeline
batch_pipeline = OpenAIAgents::DataPipeline::Pipeline.new(
  "batch_processor",
  batch_options: { parallel: true, max_threads: 2, chunk_size: 3 }
)

# Add processing stages
batch_pipeline
  .add_stage(OpenAIAgents::DataPipeline::MapStage.new("simulate_work") do |item|
    # Simulate some work
    sleep(0.1)
    { id: item, processed_at: Time.now.to_f, result: item * 2 }
  end)

# Process batch
batch_data = (1..10).to_a
puts "Processing batch of #{batch_data.size} items in parallel:"
start_time = Time.now
results = batch_pipeline.process_batch(batch_data)
duration = Time.now - start_time

puts "Completed in #{duration.round(2)}s (should be ~0.5s with parallelization)"
puts "First 3 results: #{results.first(3).inspect}"
puts

# Example 7: Split and aggregate
puts "Example 7: Split and Aggregate Operations"
puts "-" * 50

# Create pipeline with split stage
split_pipeline = OpenAIAgents::DataPipeline::PipelineBuilder.build("splitter") do
  # Split sentence into words
  split { |sentence| sentence.split(/\s+/) }
  
  # Process each word
  map { |word| { word: word, length: word.length, reversed: word.reverse } }
  
  output(destination: :stdout, format: :json)
end

puts "Splitting and processing sentence:"
split_pipeline.run("The quick brown fox")
puts

# Create aggregation pipeline
aggregate_pipeline = OpenAIAgents::DataPipeline::Pipeline.new("aggregator")
aggregate_pipeline
  .add_stage(OpenAIAgents::DataPipeline::AggregateStage.new("batch", window_size: 3) do |items|
    {
      count: items.size,
      values: items,
      sum: items.sum,
      avg: items.sum.to_f / items.size
    }
  end)

puts "\nAggregating numbers in windows of 3:"
(1..7).each do |num|
  result = aggregate_pipeline.process(num)
  puts "  Window complete: #{result.inspect}" if result
end
puts

# Example 8: Complex multi-stage pipeline
puts "Example 8: Complex Multi-stage Pipeline"
puts "-" * 50

# Create agent for analysis
analysis_agent = OpenAIAgents::Agent.new(
  name: "DataAnalyst",
  model: "gpt-4o-mini",
  instructions: "You analyze data patterns and provide insights."
)

# Build complex pipeline
complex_pipeline = OpenAIAgents::DataPipeline::PipelineBuilder.build("analytics") do
  # Stage 1: Parse and clean
  map do |raw_data|
    data = begin
      JSON.parse(raw_data)
    rescue StandardError
      { error: "Invalid JSON" }
    end
    data[:processed] = true
    data
  end
  
  # Stage 2: Validate
  validate do |data|
    errors = []
    errors << "Missing required fields" unless data[:id] && data[:value]
    errors << "Value out of range" if data[:value] && (data[:value] < 0 || data[:value] > 1000)
    errors
  end
  
  # Stage 3: Enrich with calculations
  map do |data|
    data[:squared] = data[:value]**2
    data[:category] = case data[:value]
                      when 0..100 then "low"
                      when 101..500 then "medium"
                      else "high"
                      end
    data
  end
  
  # Stage 4: Agent analysis
  transform(
    agent: analysis_agent,
    prompt: "Analyze this data point and identify any patterns or anomalies: {{data}}"
  )
  
  # Stage 5: Output
  output(destination: :stdout, format: :json)
end

# Test complex pipeline
test_records = [
  { id: 1, value: 50, type: "A" }.to_json,
  { id: 2, value: 500, type: "B" }.to_json,
  { id: 3, value: 1500, type: "C" }.to_json # Will fail validation
]

puts "Processing records through complex pipeline:"
test_records.each_with_index do |record, i|
  puts "\nRecord #{i + 1}:"
  begin
    complex_pipeline.run(record)
  rescue StandardError => e
    puts "  Pipeline error: #{e.message}"
  end
end
puts

# Example 9: Pipeline metrics and monitoring
puts "Example 9: Pipeline Metrics"
puts "-" * 50

# Create monitored pipeline
monitored_pipeline = OpenAIAgents::DataPipeline::Pipeline.new("monitored")

# Add stages
monitored_pipeline
  .add_stage(OpenAIAgents::DataPipeline::FilterStage.new("even_only", &:even?))
  .add_stage(OpenAIAgents::DataPipeline::MapStage.new("double") { |n| n * 2 })
  .add_stage(OpenAIAgents::DataPipeline::ValidationStage.new("range_check") do |n|
    n > 20 ? ["Value too large"] : []
  end)

# Process data and collect metrics
puts "Processing numbers 1-10 through monitored pipeline:"
(1..10).each do |num|
  
  result = monitored_pipeline.process(num)
  puts "  #{num} -> #{result}" if result
rescue StandardError => e
  puts "  #{num} -> Error: #{e.message}"
  
end

# Display metrics
metrics = monitored_pipeline.metrics
puts "\nPipeline metrics:"
puts "  Processed: #{metrics[:processed]}"
puts "  Errors: #{metrics[:errors]}"
puts "  Skipped: #{metrics[:skipped]}"
puts

# Example 10: Using predefined templates
puts "Example 10: Pipeline Templates"
puts "-" * 50

# Create agent for log analysis
log_agent = OpenAIAgents::Agent.new(
  name: "LogAnalyzer",
  model: "gpt-4o-mini",
  instructions: "You analyze log entries and suggest solutions for errors."
)

# Use log processing template
log_template = OpenAIAgents::DataPipeline::Templates.log_pipeline("error_analysis", log_agent)

# Simulate log data
error_logs = [
  "[ERROR] Database connection timeout after 30s",
  "[WARN] Memory usage at 85%",
  "[ERROR] Failed to parse user input: unexpected token",
  "[INFO] Service started successfully"
]

puts "Using log pipeline template:"
# NOTE: In real usage, this would process the logs and save analysis
puts "  Created pipeline: error_analysis"
puts "  Stages: parse -> filter -> analyze -> output"
puts "  Would analyze #{error_logs.count { |l| l.include?("[ERROR]") || l.include?("[WARN]") }} error/warning logs"

# Best practices
puts "\n=== Data Pipeline Best Practices ==="
puts "-" * 50
puts <<~PRACTICES
  1. Pipeline Design:
     - Keep stages focused and composable
     - Use meaningful stage names
     - Validate early in the pipeline
     - Handle errors gracefully
  
  2. Performance:
     - Use parallel processing for large batches
     - Implement streaming for continuous data
     - Avoid blocking operations in stages
     - Monitor pipeline metrics
  
  3. Agent Integration:
     - Use agents for complex transformations
     - Provide clear prompts with context
     - Consider token usage and costs
     - Cache agent responses when possible
  
  4. Error Handling:
     - Validate data at entry points
     - Use continue_on_error for resilience
     - Log errors with context
     - Implement retry logic
  
  5. Data Quality:
     - Define clear schemas
     - Implement data validation
     - Track data lineage
     - Monitor data quality metrics
  
  6. Scalability:
     - Design for horizontal scaling
     - Use appropriate batch sizes
     - Implement backpressure
     - Consider memory usage
  
  7. Monitoring:
     - Track pipeline metrics
     - Set up alerts for failures
     - Monitor processing times
     - Analyze bottlenecks
  
  8. Testing:
     - Test stages in isolation
     - Use sample data sets
     - Verify error handling
     - Benchmark performance
PRACTICES

puts "\nData pipeline example completed!"
