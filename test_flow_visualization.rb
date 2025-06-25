#!/usr/bin/env ruby
# Script to create test data for flow visualization
# Run with: rails runner test_flow_visualization.rb

puts "Creating test data for flow visualization..."

# Create a test trace
trace = OpenAIAgents::Tracing::TraceRecord.create!(
  trace_id: "trace_flow_test_#{SecureRandom.hex(16)}",
  workflow_name: "Customer Support Flow Test",
  status: "completed",
  started_at: 5.minutes.ago,
  ended_at: Time.current,
  metadata: { test: true, purpose: "flow_visualization" }
)

# Create agent spans
support_agent_span = OpenAIAgents::Tracing::SpanRecord.create!(
  span_id: "span_#{SecureRandom.hex(12)}",
  trace_id: trace.trace_id,
  parent_id: nil,
  name: "agent.CustomerSupportAgent",
  kind: "agent",
  status: "ok",
  start_time: 5.minutes.ago,
  end_time: 4.minutes.ago,
  duration_ms: 60000,
  span_attributes: {
    "agent" => {
      "name" => "CustomerSupportAgent",
      "tools" => ["search_knowledge_base", "check_order_status", "escalate_to_human"],
      "handoffs" => ["TechnicalSupportAgent", "BillingAgent"]
    }
  }
)

# Create tool calls from the support agent
tool_span1 = OpenAIAgents::Tracing::SpanRecord.create!(
  span_id: "span_#{SecureRandom.hex(12)}",
  trace_id: trace.trace_id,
  parent_id: support_agent_span.span_id,
  name: "search_knowledge_base",
  kind: "tool",
  status: "ok",
  start_time: 4.minutes.ago + 10.seconds,
  end_time: 4.minutes.ago + 15.seconds,
  duration_ms: 5000,
  span_attributes: {
    "function" => {
      "name" => "search_knowledge_base",
      "input" => { "query" => "password reset procedure" },
      "output" => { "results" => ["Step 1: Go to login page", "Step 2: Click forgot password"] }
    }
  }
)

tool_span2 = OpenAIAgents::Tracing::SpanRecord.create!(
  span_id: "span_#{SecureRandom.hex(12)}",
  trace_id: trace.trace_id,
  parent_id: support_agent_span.span_id,
  name: "check_order_status",
  kind: "tool",
  status: "ok",
  start_time: 4.minutes.ago + 20.seconds,
  end_time: 4.minutes.ago + 22.seconds,
  duration_ms: 2000,
  span_attributes: {
    "function" => {
      "name" => "check_order_status",
      "input" => { "order_id" => "ORD-12345" },
      "output" => { "status" => "shipped", "tracking_number" => "1Z999AA1012345678" }
    }
  }
)

# Create a handoff span
handoff_span = OpenAIAgents::Tracing::SpanRecord.create!(
  span_id: "span_#{SecureRandom.hex(12)}",
  trace_id: trace.trace_id,
  parent_id: support_agent_span.span_id,
  name: "handoff",
  kind: "handoff",
  status: "ok",
  start_time: 4.minutes.ago + 30.seconds,
  end_time: 4.minutes.ago + 31.seconds,
  duration_ms: 1000,
  span_attributes: {
    "handoff" => {
      "from" => "CustomerSupportAgent",
      "to" => "TechnicalSupportAgent",
      "reason" => "Customer needs technical assistance"
    }
  }
)

# Create technical support agent
tech_agent_span = OpenAIAgents::Tracing::SpanRecord.create!(
  span_id: "span_#{SecureRandom.hex(12)}",
  trace_id: trace.trace_id,
  parent_id: nil,
  name: "agent.TechnicalSupportAgent",
  kind: "agent",
  status: "ok",
  start_time: 3.minutes.ago,
  end_time: 1.minute.ago,
  duration_ms: 120000,
  span_attributes: {
    "agent" => {
      "name" => "TechnicalSupportAgent",
      "tools" => ["run_diagnostics", "check_system_status", "create_ticket"],
      "handoffs" => ["CustomerSupportAgent"]
    }
  }
)

# Technical agent uses tools
tech_tool_span = OpenAIAgents::Tracing::SpanRecord.create!(
  span_id: "span_#{SecureRandom.hex(12)}",
  trace_id: trace.trace_id,
  parent_id: tech_agent_span.span_id,
  name: "run_diagnostics",
  kind: "tool",
  status: "ok",
  start_time: 2.minutes.ago + 10.seconds,
  end_time: 2.minutes.ago + 20.seconds,
  duration_ms: 10000,
  span_attributes: {
    "function" => {
      "name" => "run_diagnostics",
      "input" => { "system" => "authentication", "user_id" => "USR-789" },
      "output" => { "status" => "healthy", "last_login" => "2024-01-15T10:30:00Z" }
    }
  }
)

# Create a custom operation span
custom_span = OpenAIAgents::Tracing::SpanRecord.create!(
  span_id: "span_#{SecureRandom.hex(12)}",
  trace_id: trace.trace_id,
  parent_id: tech_agent_span.span_id,
  name: "analyze_logs",
  kind: "custom",
  status: "ok",
  start_time: 2.minutes.ago + 30.seconds,
  end_time: 2.minutes.ago + 35.seconds,
  duration_ms: 5000,
  span_attributes: {
    "custom" => {
      "name" => "analyze_logs",
      "data" => { "log_count" => 1523, "errors_found" => 3 }
    },
    "output" => { "analysis" => "3 authentication errors found in the last hour" }
  }
)

# Create some failed tool calls for variety
failed_tool_span = OpenAIAgents::Tracing::SpanRecord.create!(
  span_id: "span_#{SecureRandom.hex(12)}",
  trace_id: trace.trace_id,
  parent_id: tech_agent_span.span_id,
  name: "create_ticket",
  kind: "tool",
  status: "error",
  start_time: 1.minute.ago + 40.seconds,
  end_time: 1.minute.ago + 42.seconds,
  duration_ms: 2000,
  span_attributes: {
    "function" => {
      "name" => "create_ticket",
      "input" => { "priority" => "high", "description" => "Authentication issues" },
      "output" => "[Error: Ticket system unavailable]"
    },
    "status" => {
      "description" => "Ticket system API returned 503"
    }
  }
)

puts "\nTest data created successfully!"
puts "Trace ID: #{trace.trace_id}"
puts "\nCreated:"
puts "- 2 agents (CustomerSupportAgent, TechnicalSupportAgent)"
puts "- 5 tool calls (including 1 failed)"
puts "- 1 custom operation"
puts "- 1 handoff between agents"
puts "\nVisit /tracing/flows to see the visualization!"