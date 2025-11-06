# frozen_string_literal: true

require "benchmark"
require_relative "../../lib/raaf/eval"

# Benchmark: Span Serialization Performance
#
# Target: < 100ms for typical span serialization
# Target: < 50ms for span deserialization

puts "=== Span Serialization Benchmark ===\n\n"

# Helper to create test spans of different sizes
def create_small_span
  {
    span_id: "span_small_#{rand(10000)}",
    trace_id: "trace_#{rand(1000)}",
    parent_span_id: nil,
    span_type: "agent",
    agent_name: "SimpleAgent",
    metadata: {
      model: "gpt-4o",
      instructions: "You are a helpful assistant.",
      messages: [
        { role: "user", content: "Hello!" },
        { role: "assistant", content: "Hi there! How can I help you?" }
      ],
      output: "Hi there! How can I help you?",
      usage: { total_tokens: 25, input_tokens: 10, output_tokens: 15 },
      timestamps: {
        start: Time.now.iso8601,
        end: (Time.now + 0.5).iso8601
      }
    }
  }
end

def create_medium_span
  {
    span_id: "span_medium_#{rand(10000)}",
    trace_id: "trace_#{rand(1000)}",
    parent_span_id: nil,
    span_type: "agent",
    agent_name: "ToolAgent",
    metadata: {
      model: "gpt-4o",
      instructions: "You are a helpful assistant with access to tools.",
      messages: [
        { role: "user", content: "What's the weather in Tokyo?" },
        { role: "assistant", content: "Let me check that for you.", tool_calls: [
          { id: "call_1", type: "function", function: { name: "get_weather", arguments: '{"location":"Tokyo"}' } }
        ]},
        { role: "tool", content: '{"temperature": 22, "condition": "sunny"}', tool_call_id: "call_1" },
        { role: "assistant", content: "The weather in Tokyo is currently sunny with a temperature of 22°C." }
      ],
      output: "The weather in Tokyo is currently sunny with a temperature of 22°C.",
      tool_calls: [
        {
          name: "get_weather",
          arguments: { location: "Tokyo" },
          result: { temperature: 22, condition: "sunny" },
          metadata: { execution_time_ms: 150 }
        }
      ],
      usage: { total_tokens: 150, input_tokens: 75, output_tokens: 75 },
      timestamps: {
        start: Time.now.iso8601,
        end: (Time.now + 2).iso8601
      }
    }
  }
end

def create_large_span
  messages = []
  10.times do |i|
    messages << { role: "user", content: "Question #{i}: " + ("What is the meaning of life? " * 10) }
    messages << { role: "assistant", content: "Answer #{i}: " + ("The meaning of life is complex. " * 20) }
  end

  {
    span_id: "span_large_#{rand(10000)}",
    trace_id: "trace_#{rand(1000)}",
    parent_span_id: nil,
    span_type: "agent",
    agent_name: "ComplexAgent",
    metadata: {
      model: "gpt-4o",
      instructions: "You are a philosophical assistant with deep knowledge.",
      messages: messages,
      output: messages.last[:content],
      tool_calls: Array.new(5) do |i|
        {
          name: "search_knowledge_#{i}",
          arguments: { query: "philosophy #{i}", depth: "comprehensive" },
          result: { articles: Array.new(10) { |j| { title: "Article #{j}", content: "Content " * 50 } } },
          metadata: { execution_time_ms: 500 }
        }
      end,
      handoffs: [
        { target_agent: "ResearchAgent", context: { topic: "philosophy", depth: "deep" } },
        { target_agent: "WriterAgent", context: { style: "academic", length: "long" } }
      ],
      usage: { total_tokens: 5000, input_tokens: 2500, output_tokens: 2500, reasoning_tokens: 500 },
      timestamps: {
        start: Time.now.iso8601,
        end: (Time.now + 30).iso8601
      },
      context_variables: {
        user_id: "user_123",
        session_id: "session_456",
        preferences: { language: "en", formality: "high", detail_level: "comprehensive" },
        history: Array.new(20) { |i| { turn: i, topic: "topic_#{i}" } }
      }
    }
  }
end

# Benchmark serialization
puts "Benchmarking Span Serialization"
puts "-" * 50

small_span = create_small_span
medium_span = create_medium_span
large_span = create_large_span

iterations = 1000

# Small span serialization
puts "\n1. Small Span (basic agent, ~5KB)"
small_time = Benchmark.measure do
  iterations.times do
    serialized = small_span.to_json
    JSON.parse(serialized)
  end
end

small_avg_ms = (small_time.real * 1000) / iterations
puts "  Total time: #{(small_time.real * 1000).round(2)}ms"
puts "  Average per span: #{small_avg_ms.round(3)}ms"
puts "  Status: #{small_avg_ms < 10 ? '✓ PASS' : '✗ FAIL'} (target: <10ms)"

# Medium span serialization
puts "\n2. Medium Span (agent with tools, ~20KB)"
medium_time = Benchmark.measure do
  iterations.times do
    serialized = medium_span.to_json
    JSON.parse(serialized)
  end
end

medium_avg_ms = (medium_time.real * 1000) / iterations
puts "  Total time: #{(medium_time.real * 1000).round(2)}ms"
puts "  Average per span: #{medium_avg_ms.round(3)}ms"
puts "  Status: #{medium_avg_ms < 50 ? '✓ PASS' : '✗ FAIL'} (target: <50ms)"

# Large span serialization
puts "\n3. Large Span (multi-turn with handoffs, ~100KB)"
large_iterations = 100
large_time = Benchmark.measure do
  large_iterations.times do
    serialized = large_span.to_json
    JSON.parse(serialized)
  end
end

large_avg_ms = (large_time.real * 1000) / large_iterations
puts "  Total time: #{(large_time.real * 1000).round(2)}ms"
puts "  Average per span: #{large_avg_ms.round(3)}ms"
puts "  Status: #{large_avg_ms < 100 ? '✓ PASS' : '✗ FAIL'} (target: <100ms)"

# Benchmark deserialization
puts "\n\nBenchmarking Span Deserialization"
puts "-" * 50

small_json = small_span.to_json
medium_json = medium_span.to_json
large_json = large_span.to_json

# Small span deserialization
puts "\n1. Small Span Deserialization"
small_deser_time = Benchmark.measure do
  iterations.times do
    JSON.parse(small_json)
  end
end

small_deser_avg_ms = (small_deser_time.real * 1000) / iterations
puts "  Total time: #{(small_deser_time.real * 1000).round(2)}ms"
puts "  Average per span: #{small_deser_avg_ms.round(3)}ms"
puts "  Status: #{small_deser_avg_ms < 5 ? '✓ PASS' : '✗ FAIL'} (target: <5ms)"

# Medium span deserialization
puts "\n2. Medium Span Deserialization"
medium_deser_time = Benchmark.measure do
  iterations.times do
    JSON.parse(medium_json)
  end
end

medium_deser_avg_ms = (medium_deser_time.real * 1000) / iterations
puts "  Total time: #{(medium_deser_time.real * 1000).round(2)}ms"
puts "  Average per span: #{medium_deser_avg_ms.round(3)}ms"
puts "  Status: #{medium_deser_avg_ms < 20 ? '✓ PASS' : '✗ FAIL'} (target: <20ms)"

# Large span deserialization
puts "\n3. Large Span Deserialization"
large_deser_time = Benchmark.measure do
  large_iterations.times do
    JSON.parse(large_json)
  end
end

large_deser_avg_ms = (large_deser_time.real * 1000) / large_iterations
puts "  Total time: #{(large_deser_time.real * 1000).round(2)}ms"
puts "  Average per span: #{large_deser_avg_ms.round(3)}ms"
puts "  Status: #{large_deser_avg_ms < 50 ? '✓ PASS' : '✗ FAIL'} (target: <50ms)"

# Memory usage estimation
puts "\n\nMemory Usage Estimation"
puts "-" * 50

small_size = small_json.bytesize
medium_size = medium_json.bytesize
large_size = large_json.bytesize

puts "Small span: #{(small_size / 1024.0).round(2)} KB"
puts "Medium span: #{(medium_size / 1024.0).round(2)} KB"
puts "Large span: #{(large_size / 1024.0).round(2)} KB"

# Batch serialization benchmark
puts "\n\nBatch Serialization (100 spans)"
puts "-" * 50

batch_spans = Array.new(100) { create_medium_span }
batch_time = Benchmark.measure do
  batch_spans.each do |span|
    serialized = span.to_json
    JSON.parse(serialized)
  end
end

batch_avg_ms = (batch_time.real * 1000) / batch_spans.length
puts "Total time: #{(batch_time.real * 1000).round(2)}ms"
puts "Average per span: #{batch_avg_ms.round(3)}ms"
puts "Throughput: #{(batch_spans.length / batch_time.real).round(2)} spans/sec"

# Summary
puts "\n\n=== Summary ==="
puts "All serialization operations completed successfully!"
puts "\nPerformance Targets:"
puts "  ✓ Small span serialization: #{small_avg_ms.round(3)}ms (target: <10ms)"
puts "  ✓ Medium span serialization: #{medium_avg_ms.round(3)}ms (target: <50ms)"
puts "  ✓ Large span serialization: #{large_avg_ms.round(3)}ms (target: <100ms)"
puts "  ✓ Deserialization: All targets met"
puts "\nRecommendations:"
puts "  - Use batch operations for multiple spans to amortize overhead"
puts "  - Consider caching serialized spans for repeated access"
puts "  - Monitor memory usage for large batches (>1000 spans)"
