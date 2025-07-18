#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates working batch processing capabilities in RAAF (Ruby AI Agents Factory).
# The BatchProcessor enables efficient processing of multiple requests using OpenAI's Batch API,
# which provides 50% cost savings compared to individual API calls. This is essential for
# large-scale operations like dataset processing, evaluations, content generation, and
# bulk analysis tasks.

require_relative "../lib/raaf-core"

puts "=== Working Batch Processing Example ==="
puts

# Check for API key
unless ENV["OPENAI_API_KEY"]
  puts "❌ Error: OPENAI_API_KEY environment variable is required"
  puts "Please set your OpenAI API key:"
  puts "export OPENAI_API_KEY='your-api-key-here'"
  exit 1
end

# ============================================================================
# EXAMPLE 1: BASIC BATCH PROCESSING
# ============================================================================
# Process multiple requests efficiently using OpenAI's Batch API.
# This demonstrates the fundamental pattern of batch processing.

puts "Example 1: Basic Batch Processing"
puts "-" * 50

# ⚠️  WARNING: RAAF::BatchProcessor is not implemented yet
# This is design documentation for planned batch processing features
begin
  batch_processor = RAAF::BatchProcessor.new
rescue NameError => e
  puts "❌ Error: #{e.message}"
  puts "The RAAF::BatchProcessor class is not implemented yet."
  puts "This example shows the planned API design for batch processing."
  exit 1
end

# Prepare batch requests
puts "Preparing batch requests..."
requests = [
  {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: "What is the capital of France?" }],
    max_tokens: 50
  },
  {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: "What is the capital of Germany?" }],
    max_tokens: 50
  },
  {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: "What is the capital of Italy?" }],
    max_tokens: 50
  },
  {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: "What is the capital of Spain?" }],
    max_tokens: 50
  },
  {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: "What is the capital of Portugal?" }],
    max_tokens: 50
  }
]

puts "Created #{requests.length} batch requests"

# Submit batch for processing
puts "Submitting batch to OpenAI..."
begin
  batch = batch_processor.submit_batch(
    requests,
    description: "Geography Quiz - European Capitals",
    completion_window: "24h"
  )

  puts "✅ Batch submitted successfully!"
  puts "   Batch ID: #{batch["id"]}"
  puts "   Status: #{batch["status"]}"
  puts "   Request count: #{batch["request_counts"]["total"]}"
  puts "   Completion window: #{batch["completion_window"]}"
  puts

  # NOTE: In real usage, you would wait for completion
  # For this example, we'll demonstrate the monitoring API
  puts "📊 Batch submitted. In production, you would:"
  puts "   1. Store the batch ID for later retrieval"
  puts "   2. Set up monitoring to check status periodically"
  puts "   3. Retrieve results when status is 'completed'"
  puts
rescue StandardError => e
  puts "❌ Error submitting batch: #{e.message}"
  puts "   This might be due to API limits or configuration issues"
end

# ============================================================================
# EXAMPLE 2: BATCH PROCESSING WITH AGENT INTEGRATION
# ============================================================================
# Integrate batch processing with RAAF for consistent behavior
# and advanced features like tracing and error handling.

puts "Example 2: Batch Processing with Agent Integration"
puts "-" * 50

# Create specialized batch processing agent
batch_agent = RAAF::Agent.new(
  name: "BatchProcessor",
  instructions: "You are a batch processing assistant. Process multiple requests efficiently.",
  model: "gpt-4o-mini"
)

# Create batch processing wrapper
class BatchAgentProcessor

  def initialize(agent, batch_processor)
    @agent = agent
    @batch_processor = batch_processor
  end

  def process_batch(prompts, options = {})
    # Convert prompts to batch requests
    requests = prompts.map do |prompt|
      {
        model: @agent.model,
        messages: [{ role: "user", content: prompt }],
        max_tokens: options[:max_tokens] || 100,
        temperature: options[:temperature] || 0.7
      }
    end

    # Submit batch
    batch = @batch_processor.submit_batch(
      requests,
      description: options[:description] || "Batch processing job",
      completion_window: options[:completion_window] || "24h"
    )

    {
      batch_id: batch["id"],
      status: batch["status"],
      request_count: requests.length,
      submitted_at: Time.now
    }
  end

  def check_batch_status(batch_id)
    @batch_processor.check_status(batch_id)
  end

  def get_batch_results(batch_id)
    @batch_processor.get_results(batch_id)
  end

end

# Create batch agent processor
batch_agent_processor = BatchAgentProcessor.new(batch_agent, batch_processor)

# Prepare content generation prompts
content_prompts = [
  "Write a short product description for a wireless mouse",
  "Write a short product description for a mechanical keyboard",
  "Write a short product description for a 4K monitor",
  "Write a short product description for a gaming headset",
  "Write a short product description for a webcam"
]

puts "Processing #{content_prompts.length} content generation prompts..."

begin
  batch_result = batch_agent_processor.process_batch(
    content_prompts,
    description: "Product Description Generation",
    max_tokens: 150,
    temperature: 0.8
  )

  puts "✅ Batch processing initiated!"
  puts "   Batch ID: #{batch_result[:batch_id]}"
  puts "   Status: #{batch_result[:status]}"
  puts "   Requests: #{batch_result[:request_count]}"
  puts "   Submitted: #{batch_result[:submitted_at]}"
  puts
rescue StandardError => e
  puts "❌ Error in batch processing: #{e.message}"
end

# ============================================================================
# EXAMPLE 3: BULK DATA PROCESSING
# ============================================================================
# Process large datasets efficiently using batch processing.
# This demonstrates real-world usage patterns for data analysis.

puts "Example 3: Bulk Data Processing"
puts "-" * 50

# Simulate customer feedback data
customer_feedback = [
  "The product is amazing! Fast delivery and great quality.",
  "Had some issues with the setup, but customer service was helpful.",
  "Not what I expected. The quality could be better.",
  "Excellent value for money. Would recommend to others.",
  "The user interface is confusing and needs improvement.",
  "Perfect for my needs. Works exactly as advertised.",
  "Shipping was delayed, but the product itself is good.",
  "Outstanding customer service and quick resolution.",
  "The product broke after a week of use. Very disappointed.",
  "Great experience overall. Will buy again."
]

# Create sentiment analysis batch requests
sentiment_requests = customer_feedback.map do |feedback|
  {
    model: "gpt-4o-mini",
    messages: [
      {
        role: "system",
        content: "You are a sentiment analysis assistant. Analyze the sentiment of customer feedback and respond with just: POSITIVE, NEGATIVE, or NEUTRAL."
      },
      {
        role: "user",
        content: feedback
      }
    ],
    max_tokens: 10,
    temperature: 0.1
  }
end

puts "Processing sentiment analysis for #{sentiment_requests.length} feedback items..."

begin
  sentiment_batch = batch_processor.submit_batch(
    sentiment_requests,
    description: "Customer Feedback Sentiment Analysis",
    completion_window: "24h"
  )

  puts "✅ Sentiment analysis batch submitted!"
  puts "   Batch ID: #{sentiment_batch["id"]}"
  puts "   Processing #{sentiment_batch["request_counts"]["total"]} feedback items"
  puts "   Estimated cost savings: 50% compared to individual API calls"
  puts
rescue StandardError => e
  puts "❌ Error in sentiment analysis batch: #{e.message}"
end

# ============================================================================
# EXAMPLE 4: BATCH MONITORING AND STATUS TRACKING
# ============================================================================
# Monitor batch processing progress and handle different status states.
# This demonstrates production-ready batch management.

puts "Example 4: Batch Monitoring and Status Tracking"
puts "-" * 50

# Create batch monitoring system
class BatchMonitor

  def initialize(batch_processor)
    @batch_processor = batch_processor
    @tracked_batches = {}
  end

  def track_batch(batch_id, description = "Batch job")
    @tracked_batches[batch_id] = {
      id: batch_id,
      description: description,
      created_at: Time.now,
      last_checked: nil,
      status: "unknown"
    }
  end

  def check_all_batches
    results = {}

    @tracked_batches.each do |batch_id, batch_info|
      status = @batch_processor.check_status(batch_id)

      # Update tracking info
      batch_info[:last_checked] = Time.now
      batch_info[:status] = status["status"]
      batch_info[:request_counts] = status["request_counts"]

      results[batch_id] = {
        description: batch_info[:description],
        status: status["status"],
        request_counts: status["request_counts"],
        created_at: status["created_at"],
        completion_window: status["completion_window"]
      }
    rescue StandardError => e
      results[batch_id] = {
        description: batch_info[:description],
        status: "error",
        error: e.message
      }
    end

    results
  end

  def get_summary
    statuses = @tracked_batches.values.group_by { |b| b[:status] }

    {
      total_batches: @tracked_batches.size,
      by_status: statuses.transform_values(&:size),
      oldest_batch: @tracked_batches.values.min_by { |b| b[:created_at] }&.dig(:created_at),
      newest_batch: @tracked_batches.values.max_by { |b| b[:created_at] }&.dig(:created_at)
    }
  end

end

# Create batch monitor
monitor = BatchMonitor.new(batch_processor)

# Simulate tracking multiple batches
puts "Demonstrating batch monitoring system..."
puts "In production, you would:"
puts "  1. Store batch IDs in a database"
puts "  2. Set up periodic monitoring jobs"
puts "  3. Send notifications when batches complete"
puts "  4. Handle failed batches appropriately"
puts

# Mock batch tracking
mock_batch_ids = %w[
  batch_001_sentiment_analysis
  batch_002_content_generation
  batch_003_data_classification
]

mock_batch_ids.each do |batch_id|
  monitor.track_batch(batch_id, "Demo batch - #{batch_id}")
end

summary = monitor.get_summary
puts "Batch monitoring summary:"
puts "  Total batches tracked: #{summary[:total_batches]}"
puts "  Status distribution: #{summary[:by_status]}"
puts

# ============================================================================
# EXAMPLE 5: COST OPTIMIZATION WITH BATCH PROCESSING
# ============================================================================
# Demonstrate cost savings and optimization strategies using batch processing.
# This shows the business value of batch operations.

puts "Example 5: Cost Optimization with Batch Processing"
puts "-" * 50

# Cost calculator for batch vs individual processing
class BatchCostCalculator

  # OpenAI pricing (example rates)
  PRICING = {
    "gpt-4o" => { input: 0.000005, output: 0.000015 },
    "gpt-4o-mini" => { input: 0.00000015, output: 0.0000006 },
    "gpt-4" => { input: 0.00003, output: 0.00006 }
  }.freeze

  def calculate_individual_cost(requests)
    total_cost = 0

    requests.each do |request|
      model = request[:model]
      input_tokens = estimate_tokens(request[:messages])
      output_tokens = request[:max_tokens] || 100

      pricing = PRICING[model] || PRICING["gpt-4o-mini"]
      cost = (input_tokens * pricing[:input]) + (output_tokens * pricing[:output])
      total_cost += cost
    end

    total_cost
  end

  def calculate_batch_cost(requests)
    individual_cost = calculate_individual_cost(requests)
    individual_cost * 0.5 # 50% discount for batch API
  end

  def calculate_savings(requests)
    individual_cost = calculate_individual_cost(requests)
    batch_cost = calculate_batch_cost(requests)

    {
      individual_cost: individual_cost,
      batch_cost: batch_cost,
      savings: individual_cost - batch_cost,
      savings_percentage: ((individual_cost - batch_cost) / individual_cost * 100).round(2)
    }
  end

  private

  def estimate_tokens(messages)
    # Simplified token estimation
    # In production, use tiktoken or similar
    total_chars = messages.map { |m| m[:content].length }.sum
    (total_chars / 4.0).ceil # Rough estimate: 4 chars per token
  end

end

# Calculate cost savings for our examples
calculator = BatchCostCalculator.new

# Example 1: Geography questions
geography_savings = calculator.calculate_savings(requests)
puts "Geography Quiz Batch:"
puts "  Individual API cost: $#{geography_savings[:individual_cost].round(6)}"
puts "  Batch API cost: $#{geography_savings[:batch_cost].round(6)}"
puts "  Savings: $#{geography_savings[:savings].round(6)} (#{geography_savings[:savings_percentage]}%)"
puts

# Example 2: Sentiment analysis
sentiment_savings = calculator.calculate_savings(sentiment_requests)
puts "Sentiment Analysis Batch:"
puts "  Individual API cost: $#{sentiment_savings[:individual_cost].round(6)}"
puts "  Batch API cost: $#{sentiment_savings[:batch_cost].round(6)}"
puts "  Savings: $#{sentiment_savings[:savings].round(6)} (#{sentiment_savings[:savings_percentage]}%)"
puts

# Large scale example
large_scale_requests = Array.new(1000) do |i|
  {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: "Summarize this text: Sample text #{i}" }],
    max_tokens: 50
  }
end

large_scale_savings = calculator.calculate_savings(large_scale_requests)
puts "Large Scale Processing (1000 requests):"
puts "  Individual API cost: $#{large_scale_savings[:individual_cost].round(4)}"
puts "  Batch API cost: $#{large_scale_savings[:batch_cost].round(4)}"
puts "  Savings: $#{large_scale_savings[:savings].round(4)} (#{large_scale_savings[:savings_percentage]}%)"
puts

# ============================================================================
# EXAMPLE 6: ADVANCED BATCH PROCESSING PATTERNS
# ============================================================================
# Demonstrate advanced patterns for production batch processing systems.
# This includes error handling, retry logic, and result processing.

puts "Example 6: Advanced Batch Processing Patterns"
puts "-" * 50

# Advanced batch processor with error handling and retry logic
class AdvancedBatchProcessor

  def initialize(batch_processor)
    @batch_processor = batch_processor
    @retry_limit = 3
    @retry_delay = 30 # seconds
  end

  def process_with_retry(requests, description: "Batch job", max_retries: 3)
    attempt = 0

    while attempt < max_retries
      begin
        batch = @batch_processor.submit_batch(
          requests,
          description: "#{description} (attempt #{attempt + 1})",
          completion_window: "24h"
        )

        return {
          success: true,
          batch_id: batch["id"],
          attempt: attempt + 1,
          submitted_at: Time.now
        }
      rescue StandardError => e
        attempt += 1

        if attempt >= max_retries
          return {
            success: false,
            error: e.message,
            attempts: attempt,
            failed_at: Time.now
          }
        end

        puts "  Attempt #{attempt} failed: #{e.message}"
        puts "  Retrying in #{@retry_delay} seconds..."
        sleep(@retry_delay)
      end
    end
  end

  def validate_requests(requests)
    errors = []

    requests.each_with_index do |request, index|
      # Validate required fields
      errors << "Request #{index}: missing model" unless request[:model]
      errors << "Request #{index}: missing messages" unless request[:messages]

      # Validate token limits
      if request[:max_tokens] && request[:max_tokens] > 4096
        errors << "Request #{index}: max_tokens exceeds limit (4096)"
      end

      # Validate message format
      errors << "Request #{index}: messages must be an array" if request[:messages] && !request[:messages].is_a?(Array)
    end

    errors
  end

  def chunk_requests(requests, chunk_size = 50_000)
    # OpenAI Batch API has a 50,000 request limit per batch
    chunks = []

    requests.each_slice(chunk_size) do |chunk|
      chunks << chunk
    end

    chunks
  end

end

# Create advanced batch processor
advanced_processor = AdvancedBatchProcessor.new(batch_processor)

# Example: Processing with validation and chunking
puts "Validating batch requests..."
test_requests = [
  {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: "Test request 1" }],
    max_tokens: 50
  },
  {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: "Test request 2" }],
    max_tokens: 50
  }
]

validation_errors = advanced_processor.validate_requests(test_requests)
if validation_errors.any?
  puts "❌ Validation errors found:"
  validation_errors.each { |error| puts "   - #{error}" }
else
  puts "✅ All requests are valid"
end

# Example: Chunking large request sets
puts "Demonstrating request chunking..."
large_request_set = Array.new(125_000) do |i|
  { model: "gpt-4o-mini", messages: [{ role: "user", content: "Request #{i}" }] }
end
chunks = advanced_processor.chunk_requests(large_request_set)
puts "  Original requests: #{large_request_set.size}"
puts "  Chunks created: #{chunks.size}"
puts "  Chunk sizes: #{chunks.map(&:size).join(", ")}"
puts

# ============================================================================
# EXAMPLE 7: INTEGRATION WITH TRACING AND MONITORING
# ============================================================================
# Integrate batch processing with RAAF tracing for observability.

puts "Example 7: Integration with Tracing and Monitoring"
puts "-" * 50

# Traced batch processor
class TracedBatchProcessor

  def initialize(batch_processor, tracer)
    @batch_processor = batch_processor
    @tracer = tracer
  end

  def submit_batch(requests, description: "Batch job")
    @tracer.trace("batch_submission", metadata: { request_count: requests.size, description: description }) do
      batch = @batch_processor.submit_batch(requests, description: description)

      # Log batch details
      @tracer.current_trace&.add_metadata(
        batch_id: batch["id"],
        batch_status: batch["status"],
        completion_window: batch["completion_window"]
      )

      batch
    end
  end

  def monitor_batch(batch_id)
    @tracer.trace("batch_monitoring", metadata: { batch_id: batch_id }) do
      status = @batch_processor.check_status(batch_id)

      # Log monitoring results
      @tracer.current_trace&.add_metadata(
        batch_status: status["status"],
        request_counts: status["request_counts"]
      )

      status
    end
  end

end

# Create traced batch processor
tracer = RAAF.tracer
TracedBatchProcessor.new(batch_processor, tracer)

puts "Batch processing with tracing enabled"
puts "This enables:"
puts "  - Tracking batch submission performance"
puts "  - Monitoring batch completion times"
puts "  - Analyzing batch success rates"
puts "  - Correlating batch operations with business metrics"
puts

# ============================================================================
# BEST PRACTICES SUMMARY
# ============================================================================

puts "\n=== Batch Processing Best Practices ==="
puts "=" * 50
puts <<~PRACTICES
  1. Request Planning:
     - Validate requests before submission
     - Use consistent models across batch requests
     - Optimize token usage for cost efficiency
     - Consider completion windows based on urgency

  2. Cost Optimization:
     - Use batch API for 50% cost savings
     - Choose appropriate models for tasks
     - Estimate costs before processing
     - Monitor spend across batches

  3. Error Handling:
     - Implement retry logic for failed submissions
     - Validate request format before submission
     - Handle partial failures gracefully
     - Set up monitoring for batch failures

  4. Performance:
     - Chunk large request sets appropriately
     - Use appropriate completion windows
     - Monitor processing times and optimize
     - Implement parallel processing where possible

  5. Monitoring and Observability:
     - Track batch submission and completion
     - Monitor success rates and error patterns
     - Set up alerts for long-running batches
     - Integrate with existing monitoring systems

  6. Production Considerations:
     - Store batch IDs persistently
     - Implement batch job queues
     - Set up automated result processing
     - Handle batch API rate limits

  7. Data Management:
     - Secure handling of batch request data
     - Proper cleanup of temporary files
     - Retention policies for batch results
     - Backup and recovery procedures

  8. Business Integration:
     - Align batch windows with business needs
     - Integrate with existing workflows
     - Provide progress visibility to stakeholders
     - Calculate ROI from batch processing
PRACTICES

puts "\nBatch processing example completed!"
puts "This demonstrates efficient bulk operations with 50% cost savings."
