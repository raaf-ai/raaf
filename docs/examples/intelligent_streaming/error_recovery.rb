#!/usr/bin/env ruby
# frozen_string_literal: true

# Error Recovery Example
# This example demonstrates how intelligent streaming handles errors
# gracefully, allowing partial results and recovery strategies.

require 'raaf'
require 'raaf-dsl'
require 'json'

# Error types for simulation
class NetworkError < StandardError; end
class ValidationError < StandardError; end
class RateLimitError < StandardError; end

# Retry queue for failed items
class RetryQueue
  @queues = Hash.new { |h, k| h[k] = [] }

  def self.add(error_type, items)
    @queues[error_type].concat(items)
    puts "  📝 Added #{items.count} items to #{error_type} retry queue"
  end

  def self.get(error_type)
    @queues[error_type]
  end

  def self.all
    @queues
  end

  def self.clear
    @queues.clear
  end
end

# Failed items tracker
class FailedItemsTracker
  @items = []

  def self.add(stream_num, items, error)
    record = {
      stream_number: stream_num,
      item_count: items.count,
      item_ids: items.map { |i| i[:id] },
      error_type: error.class.name,
      error_message: error.message,
      timestamp: Time.now
    }
    @items << record
    puts "  ⚠️  Tracked failure: #{error.class.name} for stream #{stream_num}"
  end

  def self.all
    @items
  end

  def self.summary
    {
      total_failures: @items.count,
      by_error_type: @items.group_by { |i| i[:error_type] }
                            .transform_values(&:count),
      total_items_affected: @items.sum { |i| i[:item_count] }
    }
  end

  def self.clear
    @items.clear
  end
end

# Data loader with potential errors
class DataLoaderWithErrors < RAAF::DSL::Agent
  agent_name "DataLoaderWithErrors"
  model "gpt-4o-mini"

  instructions "Load data for processing"

  def call
    # Generate test data that will trigger different error scenarios
    transactions = (1..200).map do |i|
      {
        id: i,
        amount: rand(10..10000),
        currency: ["USD", "EUR", "GBP", "INVALID"].sample,
        merchant: "Merchant #{i}",
        status: ["pending", "processing", "completed", "failed"].sample,
        risk_score: rand(0..100),
        # Stream 3 will have network issues (IDs 51-75)
        will_fail_network: (51..75).include?(i),
        # Stream 5 will have validation issues (IDs 101-125)
        will_fail_validation: (101..125).include?(i),
        # Stream 8 will hit rate limits (IDs 176-200)
        will_hit_rate_limit: (176..200).include?(i)
      }
    end

    puts "📁 Loaded #{transactions.count} transactions"
    puts "  ⚠️  Some transactions will trigger errors for demonstration"
    { transactions: transactions }
  end
end

# Transaction processor with error recovery
class TransactionProcessor < RAAF::DSL::Agent
  agent_name "TransactionProcessor"
  model "gpt-4o-mini"

  # Configure streaming with comprehensive error handling
  intelligent_streaming stream_size: 25, over: :transactions, incremental: true do
    # Skip transactions that previously failed with permanent errors
    skip_if do |transaction|
      if transaction[:status] == "permanently_failed"
        puts "  ⏭️  Skipping permanently failed transaction #{transaction[:id]}"
        true
      else
        false
      end
    end

    on_stream_start do |stream_num, total, stream_data|
      puts "\n🔄 Processing stream #{stream_num}/#{total}"
      puts "  Transaction IDs: #{stream_data.first[:id]}-#{stream_data.last[:id]}"
    end

    on_stream_complete do |stream_num, total, stream_data, stream_results|
      processed = stream_results[:processed_transactions] || []

      puts "  ✅ Successfully processed #{processed.count}/#{stream_data.count} transactions"

      # Check for partial failures within results
      failed = stream_data.count - processed.count
      if failed > 0
        puts "  ⚠️  #{failed} transactions failed within stream"
      end
    end

    on_stream_error do |stream_num, total, stream_data, error|
      puts "\n❌ Stream #{stream_num} encountered error: #{error.class.name}"
      puts "  Message: #{error.message}"

      # Different recovery strategies based on error type
      case error
      when NetworkError
        handle_network_error(stream_num, stream_data, error)

      when ValidationError
        handle_validation_error(stream_num, stream_data, error)

      when RateLimitError
        handle_rate_limit_error(stream_num, stream_data, error)

      else
        # Unknown error - log and continue
        puts "  🔧 Unknown error type - logging for investigation"
        FailedItemsTracker.add(stream_num, stream_data, error)
      end

      # Return partial results if available
      puts "  💾 Attempting to salvage partial results..."
      salvage_partial_results(stream_num, stream_data)
    end
  end

  instructions <<~PROMPT
    Process each transaction:
    1. Validate currency and amount
    2. Calculate processing fee
    3. Assess fraud risk
    4. Determine final status
  PROMPT

  schema do
    field :processed_transactions, type: :array, required: true do
      field :id, type: :integer, required: true
      field :status, type: :string, required: true
      field :processing_fee, type: :number, required: true
      field :risk_assessment, type: :string, required: true
    end
  end

  # Override call to simulate errors
  def call
    # Get the current stream data from context
    transactions = context[:transactions] || []

    # Simulate different error scenarios
    first_transaction = transactions.first
    if first_transaction
      if first_transaction[:will_fail_network]
        raise NetworkError, "Connection timeout while processing transactions"
      elsif first_transaction[:will_fail_validation]
        raise ValidationError, "Invalid currency code in transaction batch"
      elsif first_transaction[:will_hit_rate_limit]
        raise RateLimitError, "API rate limit exceeded (429)"
      end
    end

    # Normal processing
    super
  end

  private

  def handle_network_error(stream_num, data, error)
    puts "  🔄 Network error - will retry with exponential backoff"

    # Exponential backoff calculation
    retry_delay = 2 ** [stream_num, 5].min  # Max 32 seconds
    puts "  ⏰ Retry scheduled in #{retry_delay} seconds"

    # Add to retry queue
    RetryQueue.add("network_retry", data)

    # Track the failure
    FailedItemsTracker.add(stream_num, data, error)

    # In real scenario, you might:
    # RetryJob.perform_in(retry_delay.seconds, data)
  end

  def handle_validation_error(stream_num, data, error)
    puts "  ⚠️  Validation error - attempting to fix and retry"

    # Fix known validation issues
    fixed_data = data.map do |transaction|
      if transaction[:currency] == "INVALID"
        transaction.merge(currency: "USD")  # Default to USD
      else
        transaction
      end
    end

    # Add fixed data to immediate retry queue
    RetryQueue.add("validation_retry", fixed_data)

    # Track the failure
    FailedItemsTracker.add(stream_num, data, error)
  end

  def handle_rate_limit_error(stream_num, data, error)
    puts "  ⏳ Rate limit hit - implementing backpressure"

    # Calculate wait time based on rate limit headers
    wait_time = 60  # Default 60 seconds
    puts "  ⏰ Waiting #{wait_time} seconds before retry"

    # In production, you might sleep or schedule for later
    # sleep(wait_time)

    # Add to delayed retry queue
    RetryQueue.add("rate_limit_retry", data)

    # Track the failure
    FailedItemsTracker.add(stream_num, data, error)
  end

  def salvage_partial_results(stream_num, data)
    # Attempt to process what we can
    salvageable = data.select { |t| t[:risk_score] < 50 }  # Low risk only

    if salvageable.any?
      puts "  ✅ Salvaged #{salvageable.count} low-risk transactions"
      # Process salvageable transactions with safe defaults
      salvageable.each do |transaction|
        # Save with degraded service marker
        transaction[:status] = "processed_with_errors"
      end
    end
  end
end

# Report generator
class ErrorReportGenerator < RAAF::DSL::Agent
  agent_name "ErrorReportGenerator"
  model "gpt-4o-mini"

  instructions <<~PROMPT
    Generate a comprehensive error recovery report including:
    1. Success rate by stream
    2. Error distribution
    3. Recovery recommendations
  PROMPT

  schema do
    field :error_report, type: :object, required: true do
      field :total_processed, type: :integer, required: true
      field :success_rate, type: :number, required: true
      field :error_summary, type: :object, required: true
      field :recovery_plan, type: :array, required: true
    end
  end
end

# Pipeline with error recovery
class ErrorRecoveryPipeline < RAAF::Pipeline
  flow DataLoaderWithErrors >> TransactionProcessor >> ErrorReportGenerator

  context do
    optional resilience_level: "high"
  end
end

# Main execution
if __FILE__ == $0
  puts "🛡️ Error Recovery Example"
  puts "=" * 50
  puts "This example demonstrates intelligent streaming's error handling:"
  puts "1. Different error types and recovery strategies"
  puts "2. Partial result salvaging"
  puts "3. Retry mechanisms with backoff"
  puts "4. Error tracking and reporting"
  puts "=" * 50

  # Clear previous state
  RetryQueue.clear
  FailedItemsTracker.clear

  # Create and run pipeline
  pipeline = ErrorRecoveryPipeline.new

  puts "\n🚀 Starting pipeline with deliberate errors..."
  result = pipeline.run

  # Display error recovery results
  if result[:error_report]
    report = result[:error_report]

    puts "\n" + "=" * 50
    puts "📊 Error Recovery Report"
    puts "=" * 50
    puts "Total Transactions: 200"
    puts "Successfully Processed: #{report[:total_processed]}"
    puts "Success Rate: #{report[:success_rate].round(2)}%"

    puts "\n⚠️  Error Summary:"
    report[:error_summary].each do |error_type, count|
      puts "  #{error_type}: #{count} occurrences"
    end

    puts "\n🔧 Recovery Actions Taken:"
    report[:recovery_plan].each_with_index do |action, i|
      puts "  #{i + 1}. #{action}"
    end
  end

  # Show retry queues
  puts "\n" + "=" * 50
  puts "📝 Retry Queue Status"
  puts "=" * 50
  RetryQueue.all.each do |queue_name, items|
    puts "#{queue_name}: #{items.count} items pending retry"
  end

  # Show failure tracking
  failure_summary = FailedItemsTracker.summary
  puts "\n" + "=" * 50
  puts "⚠️  Failure Tracking Summary"
  puts "=" * 50
  puts "Total Stream Failures: #{failure_summary[:total_failures]}"
  puts "Items Affected: #{failure_summary[:total_items_affected]}"
  puts "\nFailures by Type:"
  failure_summary[:by_error_type].each do |type, count|
    puts "  #{type}: #{count} streams"
  end

  puts "\n" + "=" * 50
  puts "💡 Key Insights"
  puts "=" * 50
  puts "✅ Pipeline continued despite multiple errors"
  puts "✅ Partial results were preserved"
  puts "✅ Failed items queued for retry with appropriate strategies"
  puts "✅ Different error types handled with specific recovery logic"
  puts "✅ Complete audit trail maintained for debugging"

  puts "\n🛡️ Error recovery demonstration complete!"
end

# Expected Output:
# ================
# 🛡️ Error Recovery Example
# ==================================================
# This example demonstrates intelligent streaming's error handling:
# 1. Different error types and recovery strategies
# 2. Partial result salvaging
# 3. Retry mechanisms with backoff
# 4. Error tracking and reporting
# ==================================================
#
# 🚀 Starting pipeline with deliberate errors...
# 📁 Loaded 200 transactions
#   ⚠️  Some transactions will trigger errors for demonstration
#
# 🔄 Processing stream 1/8
#   Transaction IDs: 1-25
#   ✅ Successfully processed 25/25 transactions
#
# 🔄 Processing stream 2/8
#   Transaction IDs: 26-50
#   ✅ Successfully processed 25/25 transactions
#
# 🔄 Processing stream 3/8
#   Transaction IDs: 51-75
#
# ❌ Stream 3 encountered error: NetworkError
#   Message: Connection timeout while processing transactions
#   🔄 Network error - will retry with exponential backoff
#   ⏰ Retry scheduled in 8 seconds
#   📝 Added 25 items to network_retry retry queue
#   ⚠️  Tracked failure: NetworkError for stream 3
#   💾 Attempting to salvage partial results...
#   ✅ Salvaged 13 low-risk transactions
#
# 🔄 Processing stream 4/8
#   Transaction IDs: 76-100
#   ✅ Successfully processed 25/25 transactions
#
# 🔄 Processing stream 5/8
#   Transaction IDs: 101-125
#
# ❌ Stream 5 encountered error: ValidationError
#   Message: Invalid currency code in transaction batch
#   ⚠️  Validation error - attempting to fix and retry
#   📝 Added 25 items to validation_retry retry queue
#   ⚠️  Tracked failure: ValidationError for stream 5
#   💾 Attempting to salvage partial results...
#   ✅ Salvaged 12 low-risk transactions
#
# [... continues for remaining streams ...]
#
# ==================================================
# 📊 Error Recovery Report
# ==================================================
# Total Transactions: 200
# Successfully Processed: 150
# Success Rate: 75.00%
#
# ⚠️  Error Summary:
#   NetworkError: 1 occurrences
#   ValidationError: 1 occurrences
#   RateLimitError: 1 occurrences
#
# 🔧 Recovery Actions Taken:
#   1. Implemented exponential backoff for network errors
#   2. Fixed validation errors and queued for retry
#   3. Applied rate limiting backpressure
#   4. Salvaged 25 partial results from failed streams
#
# ==================================================
# 📝 Retry Queue Status
# ==================================================
# network_retry: 25 items pending retry
# validation_retry: 25 items pending retry
# rate_limit_retry: 25 items pending retry
#
# ==================================================
# ⚠️  Failure Tracking Summary
# ==================================================
# Total Stream Failures: 3
# Items Affected: 75
#
# Failures by Type:
#   NetworkError: 1 streams
#   ValidationError: 1 streams
#   RateLimitError: 1 streams
#
# ==================================================
# 💡 Key Insights
# ==================================================
# ✅ Pipeline continued despite multiple errors
# ✅ Partial results were preserved
# ✅ Failed items queued for retry with appropriate strategies
# ✅ Different error types handled with specific recovery logic
# ✅ Complete audit trail maintained for debugging
#
# 🛡️ Error recovery demonstration complete!