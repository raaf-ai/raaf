#!/usr/bin/env ruby
# frozen_string_literal: true

# AI Analyzer Example
#
# Demonstrates intelligent trace analysis using AI to provide optimization
# suggestions, root cause analysis, and performance insights.

require "raaf"

puts "=== AI Analyzer Example ==="
puts "Demonstrates intelligent trace analysis and optimization suggestions"
puts "-" * 60

# Setup AI Analyzer
ai_analyzer = RAAF::Tracing::AIAnalyzer.new(
  model: "gpt-4o",
  analysis_depth: :comprehensive,
  cache_results: true
)

puts "✅ AI Analyzer configured"

# Example analysis
sample_traces = [
  { agent: "DataProcessor", duration: 5000, errors: 2, cost: 0.15 },
  { agent: "ReportGenerator", duration: 1200, errors: 0, cost: 0.05 }
]

puts "\n=== AI Analysis Results ==="
analysis = ai_analyzer.analyze_traces(sample_traces)

puts "🎯 Key Findings:"
analysis[:findings].each { |finding| puts "  - #{finding}" }

puts "\n⚡ Optimization Suggestions:"
analysis[:optimizations].each { |opt| puts "  - #{opt}" }

puts "\n✅ AI Analyzer example completed"