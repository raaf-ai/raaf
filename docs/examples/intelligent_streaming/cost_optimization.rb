#!/usr/bin/env ruby
# frozen_string_literal: true

# Cost Optimization Example
# This example demonstrates how intelligent streaming can dramatically
# reduce AI API costs by using cheaper models for filtering before
# expensive models for detailed analysis.

require 'raaf'
require 'raaf-dsl'

# Cost tracking module
module CostTracker
  @costs = { cheap: 0.0, expensive: 0.0, saved: 0.0 }

  def self.track_cheap(count)
    cost = count * 0.001  # $0.001 per item with gpt-4o-mini
    @costs[:cheap] += cost
    cost
  end

  def self.track_expensive(count)
    cost = count * 0.01  # $0.01 per item with gpt-4o
    @costs[:expensive] += cost
    cost
  end

  def self.track_saved(count)
    # Cost saved by not processing with expensive model
    saved = count * 0.01
    @costs[:saved] += saved
    saved
  end

  def self.report
    @costs
  end

  def self.reset
    @costs = { cheap: 0.0, expensive: 0.0, saved: 0.0 }
  end
end

# Prospect loader
class ProspectLoader < RAAF::DSL::Agent
  agent_name "ProspectLoader"
  model "gpt-4o-mini"

  instructions "Load prospects for analysis"

  def call
    # Simulate loading 1000 prospects
    prospects = (1..1000).map do |i|
      {
        id: i,
        company_name: "Company #{i}",
        industry: ["SaaS", "E-commerce", "FinTech", "HealthTech", "EdTech",
                   "Logistics", "Manufacturing", "Retail", "Services"].sample,
        employees: rand(5..5000),
        revenue: rand(50_000..50_000_000),
        location: ["USA", "UK", "Germany", "Netherlands", "France"].sample,
        website: "https://company#{i}.com",
        description: "Company #{i} is a leader in their industry...",
        signals: {
          hiring: [true, false].sample,
          funding: [true, false].sample,
          expansion: [true, false].sample
        }
      }
    end

    puts "📋 Loaded #{prospects.count} prospects for analysis"
    { prospects: prospects }
  end
end

# Quick filter using cheap model
class QuickFilterAgent < RAAF::DSL::Agent
  agent_name "QuickFilterAgent"
  model "gpt-4o-mini"  # CHEAP: $0.001 per prospect

  # Stream processing with cost tracking
  intelligent_streaming stream_size: 100, over: :prospects, incremental: true do
    on_stream_start do |stream_num, total, stream_data|
      puts "\n🔍 Quick Filter - Stream #{stream_num}/#{total}"
      puts "  Analyzing #{stream_data.count} prospects with cheap model..."
    end

    on_stream_complete do |stream_num, total, stream_data, stream_results|
      analyzed = stream_results[:analyzed_prospects] || []
      qualified = analyzed.select { |p| p[:fit_score] >= 70 }
      rejected = analyzed.count - qualified.count

      # Track costs
      cheap_cost = CostTracker.track_cheap(stream_data.count)
      saved_cost = CostTracker.track_saved(rejected)

      puts "  ✅ Filtered: #{qualified.count}/#{stream_data.count} passed"
      puts "  💰 Cost: $#{cheap_cost.round(4)} (saved $#{saved_cost.round(2)} by rejecting #{rejected})"

      # Update results to only include qualified prospects
      stream_results[:prospects] = qualified
    end
  end

  instructions <<~PROMPT
    Quickly assess each prospect for basic fit:
    1. Industry alignment (SaaS, FinTech, HealthTech = good)
    2. Company size (50+ employees = good)
    3. Growth signals (hiring, funding, expansion)

    Assign a fit_score (0-100). Only score 70+ should proceed.
  PROMPT

  schema do
    field :analyzed_prospects, type: :array, required: true do
      field :id, type: :integer, required: true
      field :company_name, type: :string, required: true
      field :fit_score, type: :integer, required: true
      field :quick_assessment, type: :string, required: true
    end
  end
end

# Detailed analysis using expensive model
class DetailedAnalysisAgent < RAAF::DSL::Agent
  agent_name "DetailedAnalysisAgent"
  model "gpt-4o"  # EXPENSIVE: $0.01 per prospect

  # Process qualified prospects only
  intelligent_streaming stream_size: 30, over: :prospects, incremental: true do
    on_stream_start do |stream_num, total, stream_data|
      puts "\n🔬 Detailed Analysis - Stream #{stream_num}/#{total}"
      puts "  Deep analysis of #{stream_data.count} qualified prospects..."
    end

    on_stream_complete do |stream_num, total, stream_data, stream_results|
      analyzed = stream_results[:detailed_prospects] || []

      # Track expensive model costs
      expensive_cost = CostTracker.track_expensive(stream_data.count)

      puts "  ✅ Completed deep analysis of #{analyzed.count} prospects"
      puts "  💰 Cost: $#{expensive_cost.round(2)} (expensive model)"
    end
  end

  instructions <<~PROMPT
    Perform comprehensive analysis of each qualified prospect:
    1. Market position and competitive landscape
    2. Technology stack and integration potential
    3. Decision-making structure and key stakeholders
    4. Budget availability and buying timeline
    5. Specific pain points and solution fit

    Provide detailed insights and recommendations.
  PROMPT

  schema do
    field :detailed_prospects, type: :array, required: true do
      field :id, type: :integer, required: true
      field :company_name, type: :string, required: true
      field :market_analysis, type: :object, required: true
      field :tech_stack, type: :array, required: true
      field :stakeholders, type: :array, required: true
      field :opportunity_score, type: :integer, required: true
      field :recommended_approach, type: :string, required: true
    end
  end
end

# Final prioritization
class PrioritizationAgent < RAAF::DSL::Agent
  agent_name "PrioritizationAgent"
  model "gpt-4o-mini"

  instructions <<~PROMPT
    Create final prioritization report:
    1. Rank all prospects by opportunity score
    2. Segment into tiers (A, B, C)
    3. Provide engagement recommendations
    4. Calculate cost savings from filtering
  PROMPT

  schema do
    field :prioritization_report, type: :object, required: true do
      field :total_analyzed, type: :integer, required: true
      field :total_qualified, type: :integer, required: true
      field :tier_a_prospects, type: :array, required: true
      field :tier_b_prospects, type: :array, required: true
      field :tier_c_prospects, type: :array, required: true
      field :engagement_strategy, type: :object, required: true
    end
  end
end

# Cost-optimized pipeline
class CostOptimizedPipeline < RAAF::Pipeline
  flow ProspectLoader >> QuickFilterAgent >> DetailedAnalysisAgent >> PrioritizationAgent

  context do
    optional optimization_level: "aggressive"
  end
end

# Main execution
if __FILE__ == $0
  puts "💰 Cost Optimization Example"
  puts "=" * 50
  puts "This example shows how intelligent streaming can reduce AI costs by 70%"
  puts "by using cheap models for filtering before expensive detailed analysis."
  puts "=" * 50

  # Reset cost tracking
  CostTracker.reset

  # Create and run pipeline
  pipeline = CostOptimizedPipeline.new

  puts "\n🚀 Starting cost-optimized pipeline..."
  puts "Processing 1000 prospects through filtering funnel:\n"

  result = pipeline.run

  # Display results
  if result[:prioritization_report]
    report = result[:prioritization_report]

    puts "\n" + "=" * 50
    puts "📊 Pipeline Results"
    puts "=" * 50
    puts "Total Prospects Loaded: 1000"
    puts "Qualified After Quick Filter: #{report[:total_qualified]} (#{report[:total_qualified] / 10}%)"
    puts "Detailed Analysis Performed: #{report[:total_qualified]}"

    puts "\n🏆 Prospect Tiers:"
    puts "  Tier A (Immediate Outreach): #{report[:tier_a_prospects].count}"
    puts "  Tier B (Nurture): #{report[:tier_b_prospects].count}"
    puts "  Tier C (Monitor): #{report[:tier_c_prospects].count}"

    if report[:tier_a_prospects].any?
      puts "\n⭐ Top 5 Tier A Prospects:"
      report[:tier_a_prospects].first(5).each_with_index do |prospect, i|
        puts "  #{i + 1}. #{prospect[:company_name]} (Score: #{prospect[:score]})"
      end
    end
  end

  # Cost analysis
  costs = CostTracker.report
  total_without_optimization = 1000 * 0.01  # If we used expensive model for all

  puts "\n" + "=" * 50
  puts "💵 Cost Analysis"
  puts "=" * 50
  puts "\nWith Intelligent Streaming Optimization:"
  puts "  Quick Filter (gpt-4o-mini): $#{costs[:cheap].round(2)}"
  puts "  Detailed Analysis (gpt-4o): $#{costs[:expensive].round(2)}"
  puts "  TOTAL COST: $#{(costs[:cheap] + costs[:expensive]).round(2)}"

  puts "\nWithout Optimization (all with gpt-4o):"
  puts "  TOTAL COST: $#{total_without_optimization.round(2)}"

  puts "\n🎯 SAVINGS:"
  actual_cost = costs[:cheap] + costs[:expensive]
  savings = total_without_optimization - actual_cost
  savings_percent = (savings / total_without_optimization * 100).round

  puts "  Amount Saved: $#{savings.round(2)}"
  puts "  Percentage Saved: #{savings_percent}%"
  puts "  Prospects Filtered Out: #{1000 - (result[:prioritization_report][:total_qualified] || 0)}"

  puts "\n📈 Cost Breakdown:"
  puts "  - $0.001 × 1000 prospects (quick filter) = $#{costs[:cheap].round(2)}"
  puts "  - $0.01 × #{result[:prioritization_report][:total_qualified] || 0} prospects (detailed) = $#{costs[:expensive].round(2)}"
  puts "  - Avoided cost on filtered prospects = $#{costs[:saved].round(2)}"

  puts "\n✅ Pipeline completed successfully!"
  puts "\n💡 Key Insight: By using intelligent streaming with a filtering funnel,"
  puts "   we achieved #{savings_percent}% cost reduction while maintaining quality!"
end

# Expected Output:
# ================
# 💰 Cost Optimization Example
# ==================================================
# This example shows how intelligent streaming can reduce AI costs by 70%
# by using cheap models for filtering before expensive detailed analysis.
# ==================================================
#
# 🚀 Starting cost-optimized pipeline...
# Processing 1000 prospects through filtering funnel:
#
# 📋 Loaded 1000 prospects for analysis
#
# 🔍 Quick Filter - Stream 1/10
#   Analyzing 100 prospects with cheap model...
#   ✅ Filtered: 28/100 passed
#   💰 Cost: $0.1000 (saved $0.72 by rejecting 72)
#
# 🔍 Quick Filter - Stream 2/10
#   Analyzing 100 prospects with cheap model...
#   ✅ Filtered: 31/100 passed
#   💰 Cost: $0.1000 (saved $0.69 by rejecting 69)
#
# [... continues for all 10 streams ...]
#
# 🔬 Detailed Analysis - Stream 1/10
#   Deep analysis of 30 qualified prospects...
#   ✅ Completed deep analysis of 30 prospects
#   💰 Cost: $0.30 (expensive model)
#
# [... continues for ~10 streams of qualified prospects ...]
#
# ==================================================
# 📊 Pipeline Results
# ==================================================
# Total Prospects Loaded: 1000
# Qualified After Quick Filter: 295 (29%)
# Detailed Analysis Performed: 295
#
# 🏆 Prospect Tiers:
#   Tier A (Immediate Outreach): 42
#   Tier B (Nurture): 118
#   Tier C (Monitor): 135
#
# ⭐ Top 5 Tier A Prospects:
#   1. Company 42 (Score: 98)
#   2. Company 156 (Score: 97)
#   3. Company 234 (Score: 96)
#   4. Company 789 (Score: 95)
#   5. Company 567 (Score: 94)
#
# ==================================================
# 💵 Cost Analysis
# ==================================================
#
# With Intelligent Streaming Optimization:
#   Quick Filter (gpt-4o-mini): $1.00
#   Detailed Analysis (gpt-4o): $2.95
#   TOTAL COST: $3.95
#
# Without Optimization (all with gpt-4o):
#   TOTAL COST: $10.00
#
# 🎯 SAVINGS:
#   Amount Saved: $6.05
#   Percentage Saved: 60%
#   Prospects Filtered Out: 705
#
# 📈 Cost Breakdown:
#   - $0.001 × 1000 prospects (quick filter) = $1.00
#   - $0.01 × 295 prospects (detailed) = $2.95
#   - Avoided cost on filtered prospects = $7.05
#
# ✅ Pipeline completed successfully!
#
# 💡 Key Insight: By using intelligent streaming with a filtering funnel,
#    we achieved 60% cost reduction while maintaining quality!