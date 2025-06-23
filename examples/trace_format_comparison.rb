#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare trace formats between Python and Ruby implementations

require_relative "../lib/openai_agents"
require "json"
require "time"

puts "=== Trace Format Comparison ==="
puts

# Create a sample span to analyze
span = OpenAIAgents::Tracing::Span.new(
  name: "TestAgent",
  kind: :agent
)
span.set_attribute("agent.name", "TestAgent")
span.set_attribute("agent.tools", ["tool1", "tool2"])
span.set_attribute("agent.handoffs", [])
span.set_attribute("agent.output_type", "text")
span.finish

puts "Ruby Span Details:"
puts "  Span ID: #{span.span_id}"
puts "  Trace ID: #{span.trace_id}"
puts "  Started at: #{span.start_time.utc.iso8601}"
puts "  Ended at: #{span.end_time.utc.iso8601}"
puts

# What Ruby sends
ruby_payload = {
  "data" => [
    {
      "object" => "trace",
      "id" => span.trace_id,
      "workflow_name" => "openai-agents-ruby",
      "metadata" => {
        "sdk.language" => "ruby",
        "sdk.version" => "0.1.0"
      },
      "spans" => [
        {
          "object" => "trace.span",
          "id" => span.span_id,
          "trace_id" => span.trace_id,
          "parent_span_id" => nil,
          "started_at" => span.start_time.utc.iso8601,
          "ended_at" => span.end_time.utc.iso8601,
          "type" => "agent",
          "name" => "TestAgent",
          "handoffs" => [],
          "tools" => ["tool1", "tool2"],
          "output_type" => "text"
        }
      ]
    }
  ]
}

puts "Ruby Payload:"
puts JSON.pretty_generate(ruby_payload)
puts

# Based on Python SDK research, here's what might be different:
puts "Potential Differences from Python SDK:"
puts

# 1. Timestamp format
python_timestamp = span.start_time.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')
puts "1. Timestamp Format:"
puts "   Ruby:   #{span.start_time.utc.iso8601}"
puts "   Python: #{python_timestamp} (with milliseconds)"
puts

# 2. ID formats
puts "2. ID Formats:"
puts "   Span ID length: #{span.span_id.length} chars"
puts "   - Format: span_<24 hex chars>"
puts "   Trace ID length: #{span.trace_id.length} chars"
puts "   - Format: trace_<32 hex chars>"
puts

# 3. Missing fields that Python might include
puts "3. Potential Missing Fields:"
puts "   - group_id: Links multiple conversation traces"
puts "   - disabled: Flag to disable tracing"
puts "   - span_id: Python might use both 'id' and 'span_id'"
puts "   - Millisecond precision in timestamps"
puts

# 4. Headers comparison
puts "4. Headers:"
puts "   Ruby sends:"
puts "   - Authorization: Bearer <api_key>"
puts "   - Content-Type: application/json"
puts "   - OpenAI-Beta: traces=v1"
puts "   - User-Agent: openai-agents-ruby/0.1.0"
puts
puts "   Python might also send:"
puts "   - OpenAI-Organization: <org_id>"
puts "   - OpenAI-Project: <project_id>"
puts

# Test with different timestamp formats
puts "5. Testing Different Formats:"
puts

# Try with milliseconds
modified_payload = ruby_payload.deep_dup
modified_payload["data"][0]["spans"][0]["started_at"] = span.start_time.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')
modified_payload["data"][0]["spans"][0]["ended_at"] = span.end_time.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')

puts "With millisecond timestamps:"
puts "  started_at: #{modified_payload["data"][0]["spans"][0]["started_at"]}"
puts "  ended_at: #{modified_payload["data"][0]["spans"][0]["ended_at"]}"
puts

# Check if span type should be different
puts "6. Span Type Names:"
puts "   Ruby uses: 'agent', 'generation', 'tool', 'handoff'"
puts "   Python might use: 'agent', 'llm', 'function', 'handoff'"
puts

puts "=== Summary ==="
puts "The most likely differences causing the 401 error:"
puts "1. Project-scoped API keys (sk-proj-) may not work with traces API"
puts "2. The traces API might require special access or be SDK-restricted"
puts "3. Minor format differences (timestamps, field names) are unlikely to cause 401"
puts
puts "A 401 error specifically means authentication failed, not format issues."