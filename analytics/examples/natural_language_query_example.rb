#!/usr/bin/env ruby
# frozen_string_literal: true

# Natural Language Query Example for Trace Analysis
#
# This example demonstrates AI-powered querying of trace data using natural
# language. Users can ask questions about agent performance, errors, and
# patterns in plain English.

require_relative "../lib/openai_agents"

puts "=== Natural Language Query Example ==="
puts "Demonstrates AI-powered trace analysis with natural language"
puts "-" * 60

# Example 1: Setup Natural Language Query Engine
puts "\n=== Example 1: NLQ Engine Setup ==="

nlq_engine = OpenAIAgents::Tracing::NaturalLanguageQuery.new(
  model: "gpt-4o",
  trace_database: "traces.db", 
  cache_queries: true,
  explain_queries: true
)

puts "✅ Natural Language Query engine configured"

# Example 2: Query Trace Data
puts "\n=== Example 2: Natural Language Queries ==="

queries = [
  "What agents were slowest last week?",
  "Show me all errors from the database toolkit",
  "Which tools were called most frequently today?",
  "Find expensive operations costing more than $0.10"
]

queries.each_with_index do |query, i|
  puts "  #{i+1}. Query: '#{query}'"
  result = nlq_engine.query(query)
  puts "     SQL: #{result[:sql]}"
  puts "     Results: #{result[:results].length} items"
end

puts "\n✅ Natural Language Query example completed"