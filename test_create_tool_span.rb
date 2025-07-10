#!/usr/bin/env ruby
# Script to create a test tool span
# Run with: rails runner test_create_tool_span.rb

puts "Creating test tool span..."

# Create a test trace first
trace = OpenAIAgents::Tracing::TraceRecord.create!(
  trace_id: "trace_#{SecureRandom.hex(16)}",
  workflow_name: "Test Tool Workflow",
  status: "completed",
  started_at: 1.minute.ago,
  ended_at: Time.current,
  metadata: { test: true }
)

# Create a tool span
tool_span = OpenAIAgents::Tracing::SpanRecord.create!(
  span_id: "span_#{SecureRandom.hex(12)}",
  trace_id: trace.trace_id,
  parent_id: nil,
  name: "test_function",
  kind: "tool",
  status: "ok",
  start_time: 1.minute.ago,
  end_time: Time.current,
  duration_ms: 1000,
  span_attributes: {
    "function" => {
      "name" => "test_function",
      "input" => { "param1" => "value1", "param2" => "value2" },
      "output" => { "result" => "success", "data" => "test data" }
    }
  }
)

puts "Created tool span: #{tool_span.span_id}"

# Create another tool span with different function
tool_span2 = OpenAIAgents::Tracing::SpanRecord.create!(
  span_id: "span_#{SecureRandom.hex(12)}",
  trace_id: trace.trace_id,
  parent_id: nil,
  name: "calculate_distance",
  kind: "tool",
  status: "ok",
  start_time: 30.seconds.ago,
  end_time: 29.seconds.ago,
  duration_ms: 1000,
  span_attributes: {
    "function" => {
      "name" => "calculate_distance",
      "input" => { "from" => "New York", "to" => "London" },
      "output" => { "distance_miles" => 3459, "distance_km" => 5567 }
    }
  }
)

puts "Created tool span: #{tool_span2.span_id}"

# Create a failed tool span
failed_span = OpenAIAgents::Tracing::SpanRecord.create!(
  span_id: "span_#{SecureRandom.hex(12)}",
  trace_id: trace.trace_id,
  parent_id: nil,
  name: "web_search",
  kind: "tool",
  status: "error",
  start_time: 20.seconds.ago,
  end_time: 19.seconds.ago,
  duration_ms: 1000,
  span_attributes: {
    "function" => {
      "name" => "web_search",
      "input" => { "query" => "latest news" },
      "output" => "[Error: API rate limit exceeded]"
    },
    "status" => {
      "description" => "API rate limit exceeded"
    }
  }
)

puts "Created failed tool span: #{failed_span.span_id}"

# Check if they show up
tool_count = OpenAIAgents::Tracing::SpanRecord.by_kind("tool").count
puts "\nTotal tool spans in database: #{tool_count}"
puts "\nNow check /tracing/tools to see if they appear!"
