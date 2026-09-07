#!/usr/bin/env ruby
# frozen_string_literal: true

# State Management Streaming Example
# This example demonstrates intelligent streaming with full state management:
# - Skip already processed items
# - Load cached results
# - Persist progress after each stream

require "raaf"
require "raaf-dsl"
require "json"
require "fileutils"

# Simulate a simple cache and database
class SimpleCache
  CACHE_DIR = "/tmp/raaf_streaming_cache"

  def self.setup
    FileUtils.mkdir_p(CACHE_DIR)
  end

  def self.get(key)
    file = File.join(CACHE_DIR, "#{key}.json")
    return nil unless File.exist?(file)

    JSON.parse(File.read(file), symbolize_names: true)
  end

  def self.set(key, value)
    setup
    file = File.join(CACHE_DIR, "#{key}.json")
    File.write(file, value.to_json)
  end

  def self.clear
    FileUtils.rm_rf(CACHE_DIR)
  end
end

class ProcessedRecords
  @records = Set.new

  def self.exists?(id:)
    @records.include?(id)
  end

  def self.add(id)
    @records.add(id)
  end

  def self.insert_all(records)
    records.each { |r| add(r[:id]) }
    puts "  💾 Persisted #{records.count} records to database"
  end

  def self.count
    @records.size
  end

  def self.clear
    @records.clear
  end
end

# Data loader agent
class DataLoader < RAAF::DSL::Agent
  agent_name "DataLoader"
  model "gpt-4o-mini"

  instructions "Load dataset for processing"

  def call
    # Simulate loading a dataset where some items might already be processed
    items = (1..500).map do |i|
      {
        id: i,
        content: "Data item #{i}",
        priority: %w[high medium low].sample,
        created_at: Time.now - (i * 3600)
      }
    end

    # Simulate that items 1-50 were already processed in a previous run
    (1..50).each { |id| ProcessedRecords.add(id) }

    # Simulate that items 51-100 have cached results
    (51..100).each do |id|
      SimpleCache.set("item_#{id}", {
                        id: id,
                        processed_content: "Cached result for item #{id}",
                        score: rand(60..100),
                        cached: true
                      })
    end

    puts "📁 Loaded #{items.count} items"
    puts "  - #{ProcessedRecords.count} already processed"
    puts "  - 50 have cached results"
    puts "  - #{items.count - 100} need processing"

    { items: items }
  end
end

# Processing agent with full state management
class StateAwareProcessor < RAAF::DSL::Agent
  agent_name "StateAwareProcessor"
  model "gpt-4o-mini"

  # Configure streaming with state management
  intelligent_streaming stream_size: 50, over: :items, incremental: true do
    # Skip items that have already been processed
    skip_if do |record|
      if ProcessedRecords.exists?(id: record[:id])
        puts "  ⏭️  Skipping item #{record[:id]} (already processed)"
        true
      else
        false
      end
    end

    # Load existing results from cache
    load_existing do |record|
      cached = SimpleCache.get("item_#{record[:id]}")
      if cached
        puts "  📦 Loaded cached result for item #{record[:id]}"
        cached
      end
    end

    # Persist results after each stream completes
    persist_each_stream do |results|
      # Save to "database"
      ProcessedRecords.insert_all(results)

      # Update cache
      results.each do |result|
        SimpleCache.set("item_#{result[:id]}", result)
      end
    end

    # Progress monitoring
    on_stream_start do |stream_num, total, stream_data|
      puts "\n🚀 Starting stream #{stream_num}/#{total}"
      puts "  Processing #{stream_data.count} items..."
    end

    on_stream_complete do |stream_num, total, _stream_data, stream_results|
      processed = stream_results[:processed_items] || []
      new_items = processed.reject { |i| i[:cached] }

      puts "✅ Completed stream #{stream_num}/#{total}"
      puts "  - Processed: #{processed.count} items"
      puts "  - New: #{new_items.count}, Cached: #{processed.count - new_items.count}"

      # Calculate metrics
      avg_score = processed.map { |i| i[:score] || 0 }.sum.to_f / processed.count
      puts "  - Average score: #{avg_score.round(2)}"
    end

    on_stream_error do |stream_num, _total, stream_data, error|
      puts "❌ Stream #{stream_num} failed: #{error.message}"

      # Save failed items for retry
      SimpleCache.set("failed_stream_#{stream_num}", {
                        stream_number: stream_num,
                        item_ids: stream_data.map { |i| i[:id] },
                        error: error.message,
                        timestamp: Time.now
                      })
    end
  end

  instructions <<~PROMPT
    Process each item:
    1. Analyze the content
    2. Assign a quality score (0-100)
    3. Add processing metadata
  PROMPT

  schema do
    field :processed_items, type: :array, required: true do
      field :id, type: :integer, required: true
      field :processed_content, type: :string, required: true
      field :score, type: :integer, required: true
      field :processing_time, type: :string, required: true
    end
  end
end

# Results aggregator
class ResultAggregator < RAAF::DSL::Agent
  agent_name "ResultAggregator"
  model "gpt-4o-mini"

  instructions <<~PROMPT
    Aggregate all processed results and create a summary report
  PROMPT

  schema do
    field :report, type: :object, required: true do
      field :total_processed, type: :integer, required: true
      field :average_score, type: :number, required: true
      field :high_priority_count, type: :integer, required: true
      field :processing_stats, type: :object, required: true
    end
  end
end

# Pipeline with resumable processing
class ResumablePipeline < RAAF::Pipeline
  flow DataLoader >> StateAwareProcessor >> ResultAggregator

  context do
    optional run_id: -> { "run_#{Time.now.to_i}" }
  end
end

# Main execution
if __FILE__ == $0
  puts "🔄 State Management Streaming Example"
  puts "=" * 50

  # Option to clear previous state
  if ARGV.include?("--clear")
    puts "🗑️  Clearing previous state..."
    SimpleCache.clear
    ProcessedRecords.clear
  end

  # Create and run pipeline
  pipeline = ResumablePipeline.new

  puts "\n📊 Starting resumable processing pipeline..."
  puts "This simulates a job that can be resumed if interrupted.\n"

  result = pipeline.run

  # Display results
  if result[:report]
    report = result[:report]

    puts "\n" + ("=" * 50)
    puts "📈 Final Report"
    puts "=" * 50
    puts "Total Processed: #{report[:total_processed]}"
    puts "Average Score: #{report[:average_score].round(2)}"
    puts "High Priority Items: #{report[:high_priority_count]}"

    if report[:processing_stats]
      puts "\nProcessing Statistics:"
      report[:processing_stats].each do |key, value|
        puts "  #{key}: #{value}"
      end
    end
  end

  puts "\n✅ Pipeline completed successfully!"
  puts "\n💡 Tip: Run again to see resumable behavior (items won't be reprocessed)"
  puts "   Use --clear flag to reset and start fresh"
end

# Expected Output (First Run):
# =============================
# 🔄 State Management Streaming Example
# ==================================================
#
# 📊 Starting resumable processing pipeline...
# This simulates a job that can be resumed if interrupted.
#
# 📁 Loaded 500 items
#   - 50 already processed
#   - 50 have cached results
#   - 400 need processing
#
# 🚀 Starting stream 1/10
#   Processing 50 items...
#   ⏭️  Skipping item 1 (already processed)
#   ⏭️  Skipping item 2 (already processed)
#   ... (skips items 1-50)
# ✅ Completed stream 1/10
#   - Processed: 0 items
#   - New: 0, Cached: 0
#
# 🚀 Starting stream 2/10
#   Processing 50 items...
#   📦 Loaded cached result for item 51
#   📦 Loaded cached result for item 52
#   ... (loads items 51-100)
#   💾 Persisted 50 records to database
# ✅ Completed stream 2/10
#   - Processed: 50 items
#   - New: 0, Cached: 50
#   - Average score: 78.5
#
# 🚀 Starting stream 3/10
#   Processing 50 items...
#   💾 Persisted 50 records to database
# ✅ Completed stream 3/10
#   - Processed: 50 items
#   - New: 50, Cached: 0
#   - Average score: 82.3
#
# ... (continues for all streams)
#
# ==================================================
# 📈 Final Report
# ==================================================
# Total Processed: 450
# Average Score: 79.8
# High Priority Items: 148
#
# Processing Statistics:
#   from_cache: 50
#   newly_processed: 400
#   skipped: 50
#
# ✅ Pipeline completed successfully!
#
# 💡 Tip: Run again to see resumable behavior (items won't be reprocessed)
#    Use --clear flag to reset and start fresh

# Expected Output (Second Run - Resumable):
# ==========================================
# All items will be skipped or loaded from cache
# demonstrating the resumable nature of the pipeline
