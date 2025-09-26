# frozen_string_literal: true

# Test script to verify pipeline span hierarchy
# Run with: ruby test_pipeline_span_hierarchy.rb

# Add lib paths
$LOAD_PATH.unshift File.expand_path('core/lib', __dir__)
$LOAD_PATH.unshift File.expand_path('dsl/lib', __dir__)
$LOAD_PATH.unshift File.expand_path('tracing/lib', __dir__)

require 'raaf-core'
require 'raaf-dsl'
require 'raaf-tracing'

# Enable debug tracing
ENV['RAAF_DEBUG_CATEGORIES'] = 'tracing'

puts "🧪 Testing Pipeline Span Hierarchy"
puts "=" * 50

# Create a simple console processor to see spans
class TestConsoleProcessor
  def initialize
    @spans = []
  end

  def on_span_end(span)
    @spans << {
      name: span.name,
      span_id: span.span_id,
      parent_id: span.parent_id,
      kind: span.kind
    }

    puts "📊 Span: #{span.name} (#{span.kind}) | ID: #{span.span_id[0..7]}... | Parent: #{span.parent_id&.[](0..7)}..."
  end

  def print_hierarchy
    puts "\n🌳 Span Hierarchy:"
    root_spans = @spans.select { |s| s[:parent_id].nil? }

    root_spans.each do |root|
      print_span_tree(root, 0)
    end
  end

  private

  def print_span_tree(span, indent)
    prefix = "  " * indent
    puts "#{prefix}├─ #{span[:name]} (#{span[:kind]})"

    children = @spans.select { |s| s[:parent_id] == span[:span_id] }
    children.each do |child|
      print_span_tree(child, indent + 1)
    end
  end
end

# Set up tracing
tracer = RAAF::Tracing::SpanTracer.new
console_processor = TestConsoleProcessor.new
tracer.add_processor(console_processor)

# Register tracer globally
RAAF::Tracing::TracingRegistry.set_tracer(tracer)

# Create test agents
class TestAgent1 < RAAF::DSL::Agent
  agent_name "TestAgent1"
  instructions "You are agent 1. Just say 'Hello from Agent 1'"
  model "gpt-4o-mini"
end

class TestAgent2 < RAAF::DSL::Agent
  agent_name "TestAgent2"
  instructions "You are agent 2. Just say 'Hello from Agent 2'"
  model "gpt-4o-mini"
end

# Create test pipeline
class TestPipeline < RAAF::Pipeline
  flow TestAgent1 >> TestAgent2

  context do
    optional test_input: "test message"
  end
end

begin
  puts "\n🚀 Running Pipeline..."

  # Create and run pipeline
  pipeline = TestPipeline.new(test_input: "Hello pipeline!")
  result = pipeline.run

  puts "\n✅ Pipeline completed successfully!"
  puts "Result: #{result.inspect}"

  # Print the span hierarchy
  console_processor.print_hierarchy

rescue StandardError => e
  puts "\n❌ Error: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3).join("\n")}"
end

puts "\n🎯 Expected hierarchy should be:"
puts "├─ Pipeline span"
puts "  ├─ TestAgent1 LLM call"
puts "  └─ TestAgent2 LLM call"
puts "\nIf agents appear as children of pipeline, the fix worked! 🎉"