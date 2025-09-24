# RAAF Tracing Troubleshooting Guide

This guide helps you diagnose and resolve common issues with RAAF's coherent tracing system.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Common Issues](#common-issues)
- [Debug Tools](#debug-tools)
- [Performance Issues](#performance-issues)
- [Integration Problems](#integration-problems)
- [Error Scenarios](#error-scenarios)
- [Advanced Debugging](#advanced-debugging)

## Quick Diagnostics

### Check if Tracing is Working

```ruby
# 1. Verify tracing is enabled
puts "Tracing disabled: #{RAAF::Tracing.disabled?}"

# 2. Check for processors
tracer = RAAF::Tracing.tracer
puts "Processor count: #{tracer.processors.size}"
puts "Processors: #{tracer.processors.map(&:class).join(', ')}"

# 3. Test basic span creation
RAAF::Tracing.trace("Test Trace") do
  puts "Inside test trace"
end

# 4. Force flush and check for errors
RAAF::Tracing.force_flush
sleep(1)
```

### Environment Check

```bash
# Check environment variables
echo "OPENAI_API_KEY: ${OPENAI_API_KEY:0:10}..." # Show first 10 chars
echo "RAAF_DISABLE_TRACING: $RAAF_DISABLE_TRACING"
echo "RAAF_DEBUG_CATEGORIES: $RAAF_DEBUG_CATEGORIES"
echo "RAAF_LOG_LEVEL: $RAAF_LOG_LEVEL"
```

## Common Issues

### 1. Spans Not Appearing

#### Symptoms
- No spans visible in OpenAI dashboard
- Console processor shows no output
- Silent failures

#### Diagnostic Steps

```ruby
# Enable detailed debugging
ENV['RAAF_DEBUG_CATEGORIES'] = 'tracing,http'
ENV['RAAF_LOG_LEVEL'] = 'debug'

# Add console processor to see local output
RAAF::Tracing.add_trace_processor(
  RAAF::Tracing::ConsoleProcessor.new(detailed: true)
)

# Test with simple component
class TestComponent
  include RAAF::Tracing::Traceable
  trace_as :test

  def run
    with_tracing(:run) do
      puts "Test component running"
      "completed"
    end
  end
end

TestComponent.new.run
RAAF::Tracing.force_flush
```

#### Common Causes & Solutions

**Cause**: No OpenAI API key
```ruby
# Check API key
puts "API Key present: #{ENV['OPENAI_API_KEY']&.length&.> 0}"

# Solution: Set API key
ENV['OPENAI_API_KEY'] = 'your-api-key'
```

**Cause**: Tracing disabled
```ruby
# Check and enable
if RAAF::Tracing.disabled?
  RAAF::Tracing.enable!
end
```

**Cause**: No processors configured
```ruby
# Add default processor
if RAAF::Tracing.tracer.processors.empty?
  RAAF::Tracing.add_trace_processor(
    RAAF::Tracing::OpenAIProcessor.new
  )
end
```

### 2. Incorrect Span Hierarchy

#### Symptoms
- Spans appear flat instead of nested
- Parent-child relationships missing
- Wrong trace IDs

#### Diagnostic Steps

```ruby
# Create hierarchy test
class ParentComponent
  include RAAF::Tracing::Traceable
  trace_as :parent

  def execute
    with_tracing(:execute) do
      puts "Parent span ID: #{current_span[:span_id]}"
      puts "Parent trace ID: #{current_span[:trace_id]}"

      child = ChildComponent.new(parent_component: self)
      child.run
    end
  end
end

class ChildComponent
  include RAAF::Tracing::Traceable
  trace_as :child

  attr_reader :parent_component

  def initialize(parent_component: nil)
    @parent_component = parent_component
  end

  def run
    with_tracing(:run) do
      puts "Child span ID: #{current_span[:span_id]}"
      puts "Child parent ID: #{current_span[:parent_id]}"
      puts "Child trace ID: #{current_span[:trace_id]}"
    end
  end
end

ParentComponent.new.execute
```

#### Common Causes & Solutions

**Cause**: Missing `@parent_component`
```ruby
# WRONG
class ChildAgent
  def initialize(parent)
    # Missing assignment
  end
end

# CORRECT
class ChildAgent
  def initialize(parent_component: nil)
    @parent_component = parent_component  # Must set this
  end
end
```

**Cause**: Parent not tracing when child starts
```ruby
# WRONG - parent not in tracing context
parent = ParentComponent.new
child = ChildComponent.new(parent_component: parent)
child.run  # No parent span active

# CORRECT - child runs within parent context
parent.with_tracing(:execute) do
  child.run
end
```

**Cause**: Components created outside trace context
```ruby
# WRONG - components created before tracing starts
pipeline = Pipeline.new
agent = Agent.new(parent_component: pipeline)

pipeline.with_tracing(:execute) do
  agent.run  # Parent relationship not established
end

# CORRECT - establish relationship within trace
pipeline.with_tracing(:execute) do
  agent = Agent.new(parent_component: pipeline)
  agent.run
end
```

### 3. Duplicate Spans

#### Symptoms
- Multiple spans for same operation
- Span count higher than expected
- Performance degradation

#### Diagnostic Steps

```ruby
# Track span creation
class SpanCounter
  def initialize
    @span_count = 0
  end

  def on_span_start(span)
    @span_count += 1
    puts "Span #{@span_count}: #{span.name}"
  end

  def on_span_end(span)
    puts "Completed: #{span.name} (#{span.duration}ms)"
  end
end

RAAF::Tracing.add_trace_processor(SpanCounter.new)

# Test nested operations
agent = TestAgent.new
agent.with_tracing(:run) do
  agent.with_tracing(:run) do  # Should reuse span
    puts "Nested operation"
  end
end
```

#### Common Causes & Solutions

**Cause**: Manual span creation alongside Traceable
```ruby
# WRONG - mixing manual and automatic
class Agent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def run
    tracer.agent_span("manual_span") do  # Creates duplicate
      with_tracing(:run) do  # Creates another span
        process()
      end
    end
  end
end

# CORRECT - use one approach
class Agent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def run
    with_tracing(:run) do  # Single span
      process()
    end
  end
end
```

**Cause**: Not checking `should_create_span?`
```ruby
# Override to prevent duplicates
class CustomAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def should_create_span?(method_name = nil, context = {})
    return false if @processing_same_method
    super
  end
end
```

### 4. Missing Span Attributes

#### Symptoms
- Spans created but empty/minimal attributes
- Component-specific data missing
- Error details not captured

#### Diagnostic Steps

```ruby
# Test attribute collection
class AttributeTestAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def initialize
    @name = "Test Agent"
    @model = "gpt-4"
  end

  def run
    with_tracing(:run) do
      puts "Current attributes: #{current_span[:attributes]}"
      "completed"
    end
  end

  def collect_span_attributes
    puts "Collecting span attributes..."
    attrs = super
    custom_attrs = {
      "agent.name" => @name,
      "agent.model" => @model
    }
    puts "Base attrs: #{attrs}"
    puts "Custom attrs: #{custom_attrs}"
    attrs.merge(custom_attrs)
  end
end

AttributeTestAgent.new.run
```

#### Common Causes & Solutions

**Cause**: Not overriding `collect_span_attributes`
```ruby
# BASIC - minimal attributes
class BasicAgent
  include RAAF::Tracing::Traceable
  trace_as :agent
  # No custom attributes
end

# ENHANCED - rich attributes
class EnhancedAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def collect_span_attributes
    super.merge({
      "agent.name" => @name,
      "agent.model" => @model,
      "agent.temperature" => @temperature,
      "agent.tools_count" => @tools&.size || 0
    })
  end
end
```

**Cause**: Exceptions in attribute collection
```ruby
def collect_span_attributes
  begin
    super.merge({
      "custom.attribute" => calculate_custom_value
    })
  rescue => e
    puts "Error collecting attributes: #{e.message}"
    super  # Fallback to base attributes
  end
end
```

### 5. Performance Issues

#### Symptoms
- Slow application performance
- High memory usage
- Delayed trace delivery

#### Diagnostic Steps

```ruby
# Monitor tracing overhead
class PerformanceMonitor
  def initialize
    @start_times = {}
    @overhead_times = []
  end

  def on_span_start(span)
    @start_times[span.span_id] = Time.now
  end

  def on_span_end(span)
    end_time = Time.now
    start_time = @start_times.delete(span.span_id)
    total_time = end_time - start_time
    span_duration = span.duration / 1000.0
    overhead = total_time - span_duration

    @overhead_times << overhead
    if overhead > 0.01  # > 10ms overhead
      puts "⚠️  High tracing overhead: #{(overhead * 1000).round(2)}ms for #{span.name}"
    end

    if @overhead_times.size % 100 == 0
      avg_overhead = @overhead_times.sum / @overhead_times.size
      puts "📊 Average tracing overhead: #{(avg_overhead * 1000).round(2)}ms"
    end
  end
end

RAAF::Tracing.add_trace_processor(PerformanceMonitor.new)
```

#### Common Causes & Solutions

**Cause**: Too many processors
```ruby
# Check processor count
puts "Processor count: #{RAAF::Tracing.tracer.processors.size}"

# Remove unnecessary processors
RAAF::Tracing.set_trace_processors(
  RAAF::Tracing::OpenAIProcessor.new  # Only keep essential ones
)
```

**Cause**: Inefficient attribute collection
```ruby
# SLOW - expensive calculations
def collect_span_attributes
  super.merge({
    "expensive.calculation" => perform_complex_calculation,  # Slow!
    "database.query" => query_database  # Network call!
  })
end

# FAST - simple values
def collect_span_attributes
  super.merge({
    "agent.name" => @name,  # Simple instance variable
    "agent.cached_value" => @cached_result  # Pre-calculated
  })
end
```

**Cause**: Memory leaks in span tracking
```ruby
# Configure memory limits
ENV['RAAF_TRACE_MAX_SPANS'] = '1000'

# Monitor memory usage
ObjectSpace.count_objects_size.each do |type, count|
  puts "#{type}: #{count}" if type.to_s.include?('Span')
end
```

## Debug Tools

### 1. Console Debug Processor

```ruby
class DetailedConsoleProcessor
  def on_span_start(span)
    puts "🟢 SPAN START: #{span.name}"
    puts "   ID: #{span.span_id}"
    puts "   Parent: #{span.parent_id || 'ROOT'}"
    puts "   Trace: #{span.trace_id}"
  end

  def on_span_end(span)
    puts "🔴 SPAN END: #{span.name}"
    puts "   Duration: #{span.duration}ms"
    puts "   Status: #{span.status}"
    puts "   Attributes: #{span.attributes.size} items"
    span.attributes.each { |k, v| puts "     #{k}: #{v}" }
    puts
  end
end

RAAF::Tracing.add_trace_processor(DetailedConsoleProcessor.new)
```

### 2. Span Validation Tool

```ruby
class SpanValidator
  def initialize
    @spans = []
    @validation_errors = []
  end

  def on_span_end(span)
    @spans << span
    validate_span(span)
  end

  def validate_span(span)
    errors = []

    # Check required fields
    errors << "Missing span_id" unless span.span_id
    errors << "Missing trace_id" unless span.trace_id
    errors << "Missing name" unless span.name
    errors << "Missing duration" unless span.duration

    # Check hierarchy
    if span.parent_id && !@spans.any? { |s| s.span_id == span.parent_id }
      errors << "Parent span not found: #{span.parent_id}"
    end

    # Check attributes
    if span.attributes.empty?
      errors << "No attributes present"
    end

    unless errors.empty?
      @validation_errors << { span: span.name, errors: errors }
      puts "❌ Span validation errors for #{span.name}:"
      errors.each { |error| puts "   - #{error}" }
    end
  end

  def summary
    puts "\n📊 Span Validation Summary:"
    puts "   Total spans: #{@spans.size}"
    puts "   Validation errors: #{@validation_errors.size}"
    if @validation_errors.any?
      puts "   Error details:"
      @validation_errors.each do |error|
        puts "     #{error[:span]}: #{error[:errors].join(', ')}"
      end
    end
  end
end

validator = SpanValidator.new
RAAF::Tracing.add_trace_processor(validator)

# Run your code...

validator.summary
```

### 3. Trace Hierarchy Visualizer

```ruby
class TraceVisualizer
  def initialize
    @spans = []
  end

  def on_span_end(span)
    @spans << {
      id: span.span_id,
      parent: span.parent_id,
      name: span.name,
      duration: span.duration,
      trace: span.trace_id
    }
  end

  def visualize_hierarchy
    traces = @spans.group_by { |span| span[:trace] }

    traces.each do |trace_id, spans|
      puts "\n🌳 Trace: #{trace_id[0..8]}..."
      visualize_spans(spans, nil, "")
    end
  end

  private

  def visualize_spans(spans, parent_id, indent)
    children = spans.select { |span| span[:parent] == parent_id }
    children.each_with_index do |span, index|
      is_last = index == children.size - 1
      prefix = is_last ? "└── " : "├── "

      puts "#{indent}#{prefix}#{span[:name]} (#{span[:duration]}ms)"

      child_indent = indent + (is_last ? "    " : "│   ")
      visualize_spans(spans, span[:id], child_indent)
    end
  end
end

visualizer = TraceVisualizer.new
RAAF::Tracing.add_trace_processor(visualizer)

# Run your code...

visualizer.visualize_hierarchy
```

## Performance Issues

### High Memory Usage

```ruby
# Monitor span memory usage
def check_span_memory
  spans_in_memory = 0
  ObjectSpace.each_object do |obj|
    spans_in_memory += 1 if obj.class.name&.include?('Span')
  end
  puts "Spans in memory: #{spans_in_memory}"
end

# Force cleanup
RAAF::Tracing.force_flush
GC.start
check_span_memory
```

### Slow Trace Processing

```ruby
# Profile processor performance
processors = RAAF::Tracing.tracer.processors
processors.each_with_index do |processor, index|
  puts "Processor #{index}: #{processor.class}"

  # Test processor speed
  test_span = double("span", name: "test", duration: 100)

  time = Benchmark.measure do
    10.times { processor.on_span_end(test_span) if processor.respond_to?(:on_span_end) }
  end

  puts "  Average time: #{(time.real / 10 * 1000).round(2)}ms per span"
end
```

## Integration Problems

### Rails Integration Issues

```ruby
# Check Rails integration
if defined?(Rails)
  puts "Rails environment: #{Rails.env}"
  puts "RAAF tracing engine loaded: #{defined?(RAAF::Tracing::Engine)}"

  # Test in Rails console
  Rails.application.routes.routes.each do |route|
    if route.name&.include?('raaf')
      puts "RAAF route: #{route.name} -> #{route.verb} #{route.path.spec}"
    end
  end
end
```

### ActiveRecord Integration

```ruby
# Test ActiveRecord processor
if defined?(ActiveRecord)
  begin
    RAAF::Tracing.add_trace_processor(
      RAAF::Tracing::ActiveRecordProcessor.new
    )
    puts "ActiveRecord processor added successfully"
  rescue => e
    puts "ActiveRecord processor error: #{e.message}"
  end
end
```

## Error Scenarios

### Network Issues with OpenAI

```ruby
# Test OpenAI connectivity
begin
  require 'net/http'
  uri = URI('https://api.openai.com/v1/traces/ingest')

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 5

  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"
  request['Content-Type'] = 'application/json'
  request.body = '{"test": true}'

  response = http.request(request)
  puts "OpenAI API status: #{response.code} #{response.message}"

rescue => e
  puts "OpenAI API connection error: #{e.message}"
end
```

### Processor Exceptions

```ruby
# Safe processor wrapper
class SafeProcessor
  def initialize(wrapped_processor)
    @wrapped_processor = wrapped_processor
  end

  def on_span_start(span)
    @wrapped_processor.on_span_start(span)
  rescue => e
    puts "⚠️  Processor error on span start: #{e.message}"
  end

  def on_span_end(span)
    @wrapped_processor.on_span_end(span)
  rescue => e
    puts "⚠️  Processor error on span end: #{e.message}"
  end

  def method_missing(method, *args, &block)
    @wrapped_processor.send(method, *args, &block)
  rescue => e
    puts "⚠️  Processor error on #{method}: #{e.message}"
  end
end

# Wrap existing processors
safe_processors = RAAF::Tracing.tracer.processors.map do |processor|
  SafeProcessor.new(processor)
end

RAAF::Tracing.set_trace_processors(*safe_processors)
```

## Advanced Debugging

### Custom Debug Categories

```ruby
# Enable specific debug categories
ENV['RAAF_DEBUG_CATEGORIES'] = 'tracing,http,spans,processors'

# Or programmatically
RAAF.logger.configure do |config|
  config.debug_categories = [:tracing, :http, :spans, :processors]
  config.log_level = :debug
end
```

### Trace Export Testing

```ruby
# Test trace export without actual network calls
class MockOpenAIProcessor
  def initialize
    @received_spans = []
  end

  def on_span_end(span)
    @received_spans << {
      name: span.name,
      duration: span.duration,
      attributes: span.attributes.dup
    }
    puts "📤 Would send span: #{span.name}"
  end

  def received_spans
    @received_spans
  end
end

# Replace OpenAI processor temporarily
mock_processor = MockOpenAIProcessor.new
RAAF::Tracing.set_trace_processors(mock_processor)

# Run your code...

# Check what would be sent
puts "Spans that would be sent to OpenAI:"
mock_processor.received_spans.each do |span|
  puts "  - #{span[:name]} (#{span[:duration]}ms)"
end
```

### Thread Safety Testing

```ruby
# Test concurrent tracing
threads = []
results = Queue.new

10.times do |i|
  threads << Thread.new do
    agent = TestAgent.new(name: "Agent#{i}")
    begin
      agent.with_tracing(:run) do
        sleep(rand(0.01..0.05))  # Random processing time
        "Agent #{i} completed"
      end
      results << { thread: i, status: :success }
    rescue => e
      results << { thread: i, status: :error, error: e.message }
    end
  end
end

threads.each(&:join)

# Collect results
thread_results = []
until results.empty?
  thread_results << results.pop
end

puts "Thread safety test results:"
thread_results.group_by { |r| r[:status] }.each do |status, group|
  puts "  #{status}: #{group.size} threads"
end
```

## Summary Checklist

When troubleshooting RAAF tracing issues:

1. ✅ **Check basic setup**: API key, tracing enabled, processors configured
2. ✅ **Verify component setup**: `include Traceable`, `trace_as`, `@parent_component`
3. ✅ **Test hierarchy**: Parent-child relationships, trace ID propagation
4. ✅ **Monitor performance**: Span count, processing time, memory usage
5. ✅ **Enable debugging**: Debug categories, console output, validation
6. ✅ **Test incrementally**: Start simple, add complexity gradually
7. ✅ **Check network**: OpenAI connectivity, processor exceptions
8. ✅ **Validate output**: Span structure, attributes, timing data

Use the debug tools and tests in this guide to isolate and resolve issues systematically.