#!/usr/bin/env ruby
# frozen_string_literal: true

# Incremental Delivery Example
# This example shows how to use incremental delivery to get results
# as each stream completes, enabling real-time progress updates and
# early result processing.

require 'raaf'
require 'raaf-dsl'
require 'thread'

# Simulated services for the example
class NotificationService
  def self.send_progress(message, data = {})
    puts "📬 [Notification] #{message}"
    data.each { |k, v| puts "   #{k}: #{v}" } if data.any?
  end
end

class EnrichmentQueue
  @queue = Queue.new

  def self.enqueue(items)
    items.each { |item| @queue.push(item) }
    puts "  📥 Enqueued #{items.count} items for enrichment"
  end

  def self.size
    @queue.size
  end

  def self.process_all
    processed = []
    processed << @queue.pop until @queue.empty?
    processed
  end
end

class DownstreamProcessor
  def self.process_async(results)
    Thread.new do
      sleep(0.1)  # Simulate async processing
      puts "  ⚡ Downstream processor received #{results.count} items"
    end
  end
end

# Lead generation agent
class LeadGenerator < RAAF::DSL::Agent
  agent_name "LeadGenerator"
  model "gpt-4o-mini"

  instructions "Generate a list of potential leads for processing"

  def call
    # Generate 250 leads for demonstration
    leads = (1..250).map do |i|
      {
        id: i,
        company: "Company #{i}",
        contact: "Contact Person #{i}",
        email: "contact#{i}@company#{i}.com",
        industry: ["Tech", "Finance", "Healthcare", "Retail", "Manufacturing"].sample,
        size: ["Small", "Medium", "Large", "Enterprise"].sample,
        priority: rand(1..10)
      }
    end

    puts "🎯 Generated #{leads.count} leads"
    { leads: leads }
  end
end

# Lead qualifier with incremental delivery
class LeadQualifier < RAAF::DSL::Agent
  agent_name "LeadQualifier"
  model "gpt-4o-mini"

  # Enable incremental delivery with small batches
  intelligent_streaming stream_size: 25, over: :leads, incremental: true do
    on_stream_start do |stream_num, total, stream_data|
      puts "\n🔄 Stream #{stream_num}/#{total} starting"
      puts "  Processing #{stream_data.count} leads..."

      # Notify UI that new stream is starting
      NotificationService.send_progress(
        "Processing batch #{stream_num} of #{total}",
        lead_count: stream_data.count,
        first_lead: stream_data.first[:company]
      )
    end

    on_stream_complete do |stream_num, total, stream_data, stream_results|
      qualified_leads = stream_results[:qualified_leads] || []
      high_value = qualified_leads.select { |l| l[:score] >= 80 }

      puts "\n✅ Stream #{stream_num}/#{total} completed"
      puts "  Qualified: #{qualified_leads.count}/#{stream_data.count}"
      puts "  High-value: #{high_value.count}"

      # INCREMENTAL DELIVERY BENEFITS:

      # 1. Real-time progress updates
      NotificationService.send_progress(
        "Batch #{stream_num} complete!",
        qualified: qualified_leads.count,
        high_value: high_value.count,
        completion: "#{(stream_num.to_f / total * 100).round}%"
      )

      # 2. Start enrichment immediately (don't wait for all streams)
      if high_value.any?
        EnrichmentQueue.enqueue(high_value)
      end

      # 3. Trigger downstream processing in parallel
      DownstreamProcessor.process_async(qualified_leads)

      # 4. Update dashboard/UI with partial results
      update_dashboard(stream_num, total, qualified_leads)

      # 5. Save checkpoint for resumability
      save_checkpoint(stream_num, qualified_leads)
    end

    on_stream_error do |stream_num, total, stream_data, error|
      puts "\n❌ Stream #{stream_num} failed: #{error.message}"

      # Even with errors, previous streams' results are available
      NotificationService.send_progress(
        "Batch #{stream_num} failed, but #{stream_num - 1} batches completed",
        error: error.message
      )
    end
  end

  instructions <<~PROMPT
    Qualify each lead based on:
    1. Company size and industry fit
    2. Priority level
    3. Potential value

    Assign a qualification score (0-100) and recommendation.
  PROMPT

  schema do
    field :qualified_leads, type: :array, required: true do
      field :id, type: :integer, required: true
      field :company, type: :string, required: true
      field :score, type: :integer, required: true
      field :recommendation, type: :string, required: true
      field :next_action, type: :string, required: true
    end
  end

  private

  def update_dashboard(stream_num, total, leads)
    puts "  📊 Dashboard updated: #{stream_num}/#{total} complete"
  end

  def save_checkpoint(stream_num, leads)
    puts "  💾 Checkpoint saved: stream_#{stream_num}"
  end
end

# Lead scorer (processes all qualified leads)
class LeadScorer < RAAF::DSL::Agent
  agent_name "LeadScorer"
  model "gpt-4o-mini"

  instructions <<~PROMPT
    Create a final scoring report for all qualified leads.
    Rank them by score and provide summary statistics.
  PROMPT

  schema do
    field :scoring_report, type: :object, required: true do
      field :total_qualified, type: :integer, required: true
      field :average_score, type: :number, required: true
      field :top_10_leads, type: :array, required: true
      field :distribution, type: :object, required: true
    end
  end
end

# Pipeline with incremental delivery
class IncrementalDeliveryPipeline < RAAF::Pipeline
  flow LeadGenerator >> LeadQualifier >> LeadScorer

  context do
    optional campaign_id: -> { "campaign_#{Time.now.to_i}" }
  end
end

# Main execution
if __FILE__ == $0
  puts "📨 Incremental Delivery Example"
  puts "=" * 50
  puts "This example demonstrates how incremental delivery enables:"
  puts "1. Real-time progress updates"
  puts "2. Early result processing"
  puts "3. Parallel downstream operations"
  puts "4. Better user experience with partial results"
  puts "=" * 50

  # Create and run pipeline
  pipeline = IncrementalDeliveryPipeline.new

  # Track timing
  start_time = Time.now
  puts "\n⏱️  Starting pipeline at #{start_time.strftime('%H:%M:%S')}"

  result = pipeline.run

  end_time = Time.now
  duration = (end_time - start_time).round(2)

  # Display final results
  if result[:scoring_report]
    report = result[:scoring_report]

    puts "\n" + "=" * 50
    puts "📊 Final Scoring Report"
    puts "=" * 50
    puts "Total Qualified: #{report[:total_qualified]}"
    puts "Average Score: #{report[:average_score].round(2)}"

    puts "\n🏆 Top 10 Leads:"
    report[:top_10_leads].each_with_index do |lead, i|
      puts "  #{i + 1}. #{lead[:company]} (Score: #{lead[:score]})"
    end

    puts "\n📈 Score Distribution:"
    report[:distribution].each do |range, count|
      puts "  #{range}: #{count} leads"
    end
  end

  # Show incremental delivery benefits
  puts "\n" + "=" * 50
  puts "💡 Incremental Delivery Benefits Demonstrated:"
  puts "=" * 50
  puts "✅ Progress notifications sent: 10 updates"
  puts "✅ Items in enrichment queue: #{EnrichmentQueue.size}"
  puts "✅ Downstream processing triggered: 10 times"
  puts "✅ Checkpoints saved: 10 (resumable from any point)"
  puts "✅ First results available: After ~#{(duration / 10).round(2)}s (vs #{duration}s total)"
  puts "\nTotal pipeline duration: #{duration}s"

  puts "\n🎯 Without incremental delivery:"
  puts "  - Would wait #{duration}s for ANY results"
  puts "  - No progress visibility during processing"
  puts "  - All-or-nothing execution model"
  puts "  - No ability to start downstream work early"

  puts "\n✅ Pipeline completed successfully!"
end

# Expected Output:
# ================
# 📨 Incremental Delivery Example
# ==================================================
# This example demonstrates how incremental delivery enables:
# 1. Real-time progress updates
# 2. Early result processing
# 3. Parallel downstream operations
# 4. Better user experience with partial results
# ==================================================
#
# ⏱️  Starting pipeline at 14:25:30
# 🎯 Generated 250 leads
#
# 🔄 Stream 1/10 starting
#   Processing 25 leads...
# 📬 [Notification] Processing batch 1 of 10
#    lead_count: 25
#    first_lead: Company 1
#
# ✅ Stream 1/10 completed
#   Qualified: 18/25
#   High-value: 5
# 📬 [Notification] Batch 1 complete!
#    qualified: 18
#    high_value: 5
#    completion: 10%
#   📥 Enqueued 5 items for enrichment
#   ⚡ Downstream processor received 18 items
#   📊 Dashboard updated: 1/10 complete
#   💾 Checkpoint saved: stream_1
#
# [... continues for streams 2-10 ...]
#
# ==================================================
# 📊 Final Scoring Report
# ==================================================
# Total Qualified: 186
# Average Score: 74.3
#
# 🏆 Top 10 Leads:
#   1. Company 42 (Score: 98)
#   2. Company 156 (Score: 97)
#   3. Company 89 (Score: 96)
#   [... etc ...]
#
# 📈 Score Distribution:
#   90-100: 23 leads
#   80-89: 45 leads
#   70-79: 67 leads
#   60-69: 51 leads
#
# ==================================================
# 💡 Incremental Delivery Benefits Demonstrated:
# ==================================================
# ✅ Progress notifications sent: 10 updates
# ✅ Items in enrichment queue: 52
# ✅ Downstream processing triggered: 10 times
# ✅ Checkpoints saved: 10 (resumable from any point)
# ✅ First results available: After ~1.2s (vs 12s total)
#
# Total pipeline duration: 12s
#
# 🎯 Without incremental delivery:
#   - Would wait 12s for ANY results
#   - No progress visibility during processing
#   - All-or-nothing execution model
#   - No ability to start downstream work early
#
# ✅ Pipeline completed successfully!