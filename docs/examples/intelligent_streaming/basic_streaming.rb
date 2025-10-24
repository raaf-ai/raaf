#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic Intelligent Streaming Example
# This example demonstrates the simplest use of intelligent streaming
# to process a large dataset through multiple agents in a pipeline.

require 'raaf'
require 'raaf-dsl'

# Step 1: Define agents for the pipeline

# Agent that loads companies from a data source
class CompanyLoader < RAAF::DSL::Agent
  agent_name "CompanyLoader"
  model "gpt-4o-mini"

  instructions "Load company data for analysis"

  def call
    # Simulate loading 1000 companies
    companies = (1..1000).map do |i|
      {
        id: i,
        name: "Company #{i}",
        industry: ["Tech", "Finance", "Healthcare", "Retail"].sample,
        employees: rand(10..10000),
        revenue: rand(100_000..100_000_000)
      }
    end

    { companies: companies }
  end
end

# Agent that analyzes companies with streaming
class CompanyAnalyzer < RAAF::DSL::Agent
  agent_name "CompanyAnalyzer"
  model "gpt-4o-mini"

  # Configure intelligent streaming
  # Process 100 companies at a time
  intelligent_streaming stream_size: 100, over: :companies do
    # Simple progress tracking
    on_stream_complete do |stream_num, total, stream_results|
      puts "✅ Stream #{stream_num}/#{total}: Analyzed #{stream_results[:companies].count} companies"
    end
  end

  # Define expected output schema
  schema do
    field :companies, type: :array, required: true do
      field :id, type: :integer, required: true
      field :name, type: :string, required: true
      field :analysis_score, type: :integer, required: true
      field :recommendation, type: :string, required: true
    end
  end

  instructions <<~PROMPT
    Analyze each company and provide:
    1. An analysis score from 0-100
    2. A recommendation (invest, monitor, or skip)

    Base your analysis on company size and industry.
  PROMPT
end

# Agent that summarizes results
class ResultSummarizer < RAAF::DSL::Agent
  agent_name "ResultSummarizer"
  model "gpt-4o-mini"

  instructions <<~PROMPT
    Summarize the analysis results:
    - Count companies by recommendation
    - Calculate average score
    - Identify top 5 companies
  PROMPT

  schema do
    field :summary, type: :object, required: true do
      field :total_analyzed, type: :integer, required: true
      field :average_score, type: :number, required: true
      field :recommendations, type: :object, required: true
      field :top_companies, type: :array, required: true
    end
  end
end

# Step 2: Create the pipeline
class BasicStreamingPipeline < RAAF::Pipeline
  flow CompanyLoader >> CompanyAnalyzer >> ResultSummarizer

  context do
    optional analysis_type: "basic"
  end
end

# Step 3: Execute the pipeline
if __FILE__ == $0
  puts "🚀 Starting Basic Streaming Example"
  puts "=" * 50

  # Create and run pipeline
  pipeline = BasicStreamingPipeline.new(
    analysis_type: "comprehensive"
  )

  puts "\n📊 Processing 1000 companies in streams of 100..."
  result = pipeline.run

  # Display results
  puts "\n📈 Results Summary:"
  puts "-" * 30

  if result[:summary]
    summary = result[:summary]
    puts "Total Analyzed: #{summary[:total_analyzed]}"
    puts "Average Score: #{summary[:average_score].round(2)}"
    puts "\nRecommendations:"
    summary[:recommendations].each do |rec, count|
      puts "  #{rec}: #{count} companies"
    end

    puts "\nTop 5 Companies:"
    summary[:top_companies].each_with_index do |company, i|
      puts "  #{i + 1}. #{company[:name]} (Score: #{company[:score]})"
    end
  end

  puts "\n✅ Pipeline completed successfully!"
end

# Expected Output:
# ================
# 🚀 Starting Basic Streaming Example
# ==================================================
#
# 📊 Processing 1000 companies in streams of 100...
# ✅ Stream 1/10: Analyzed 100 companies
# ✅ Stream 2/10: Analyzed 100 companies
# ✅ Stream 3/10: Analyzed 100 companies
# ✅ Stream 4/10: Analyzed 100 companies
# ✅ Stream 5/10: Analyzed 100 companies
# ✅ Stream 6/10: Analyzed 100 companies
# ✅ Stream 7/10: Analyzed 100 companies
# ✅ Stream 8/10: Analyzed 100 companies
# ✅ Stream 9/10: Analyzed 100 companies
# ✅ Stream 10/10: Analyzed 100 companies
#
# 📈 Results Summary:
# ------------------------------
# Total Analyzed: 1000
# Average Score: 67.5
#
# Recommendations:
#   invest: 342 companies
#   monitor: 415 companies
#   skip: 243 companies
#
# Top 5 Companies:
#   1. Company 42 (Score: 98)
#   2. Company 156 (Score: 97)
#   3. Company 789 (Score: 96)
#   4. Company 234 (Score: 95)
#   5. Company 567 (Score: 94)
#
# ✅ Pipeline completed successfully!