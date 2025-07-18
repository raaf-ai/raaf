#!/usr/bin/env ruby
# frozen_string_literal: true

# Distributed Tracing Example
#
# This example demonstrates comprehensive distributed tracing across multiple
# services and applications using the RAAF (Ruby AI Agents Factory) gem. Features include:
#
# - Cross-service trace correlation with trace IDs
# - Baggage propagation for contextual data
# - HTTP middleware integration for automatic tracing  
# - Background job integration for async operations
# - Performance profiling and bottleneck identification
# - Service topology mapping and dependency analysis
# - Replay functionality for debugging
# - OpenTelemetry compatibility

require_relative "../lib/raaf-tracing"

puts "=== Distributed Tracing Example ==="
puts "Demonstrates cross-service tracing and correlation"
puts "-" * 60

# Example 1: Distributed Tracer Setup
puts "\n=== Example 1: Distributed Tracer Configuration ==="

distributed_tracer = RAAF::Tracing::DistributedTracer.new(
  service_name: "ai-agents-main",
  service_version: "1.0.0",
  environment: "production",
  correlation_headers: ["x-trace-id", "x-span-id"],
  baggage_headers: ["x-user-id", "x-tenant-id"],
  propagation_format: :w3c_trace_context
)

puts "✅ Distributed tracer configured:"
puts "  - Service: #{distributed_tracer.service_name}"
puts "  - Propagation: #{distributed_tracer.propagation_format}"
puts "  - Headers: #{distributed_tracer.correlation_headers.join(', ')}"

# Example 2: Cross-Service Trace Propagation
puts "\n=== Example 2: Cross-Service Trace Propagation ==="

# Simulate multi-service workflow
services = [
  { name: "api-gateway", port: 3000, role: "entry_point" },
  { name: "user-service", port: 3001, role: "authentication" },
  { name: "ai-agents", port: 3002, role: "processing" },
  { name: "notification-service", port: 3003, role: "delivery" }
]

root_span = distributed_tracer.start_span("user_request",
  service: "api-gateway",
  operation: "POST /api/v1/process",
  user_id: "user_123",
  tenant_id: "tenant_456"
)

puts "🌐 Simulating distributed trace across #{services.length} services:"
services.each_with_index do |service, i|
  child_span = distributed_tracer.start_span("#{service[:role]}_operation",
    parent: root_span,
    service: service[:name],
    operation: service[:role],
    port: service[:port]
  )
  
  puts "  #{i+1}. #{service[:name]} (#{service[:role]}) - Span: #{child_span.span_id}"
  
  distributed_tracer.finish_span(child_span)
end

distributed_tracer.finish_span(root_span)
puts "✅ Distributed trace completed with correlation ID: #{root_span.trace_id}"

# Example 3: HTTP Middleware Integration
puts "\n=== Example 3: HTTP Middleware Integration ==="

# Configure HTTP middleware for automatic tracing
http_middleware = distributed_tracer.create_http_middleware do |config|
  config.auto_instrument = true
  config.extract_headers = true
  config.inject_headers = true
  config.track_request_size = true
  config.track_response_size = true
end

puts "🌐 HTTP Middleware configured:"
puts "  - Auto-instrumentation: #{http_middleware.auto_instrument?}"
puts "  - Header extraction: #{http_middleware.extract_headers?}"
puts "  - Request tracking: #{http_middleware.track_request_size?}"

# Simulate HTTP requests with tracing
http_requests = [
  { method: "GET", path: "/users/123", service: "user-service" },
  { method: "POST", path: "/agents/run", service: "ai-agents", body_size: 1024 },
  { method: "POST", path: "/notify", service: "notification-service", body_size: 512 }
]

puts "\n📡 Tracing HTTP requests:"
http_requests.each do |req|
  span = http_middleware.trace_request(req[:method], req[:path], req[:service])
  puts "  #{req[:method]} #{req[:path]} → #{span.span_id}"
  if req[:body_size]
    span.set_attribute("http.request.body.size", req[:body_size])
  end
  http_middleware.finish_request(span, status: 200, response_size: 256)
end

puts "✅ HTTP requests traced successfully"

puts "\n✅ Distributed Tracing example completed"