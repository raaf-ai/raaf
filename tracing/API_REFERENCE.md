# Tracing API Reference

Complete Ruby API documentation for RAAF Tracing components.

## Table of Contents

1. [SpanTracer](#spantracer)
2. [Span Objects](#span-objects)
3. [Span Processors](#span-processors)
   - [ConsoleSpanProcessor](#consolespanprocessor)
   - [FileSpanProcessor](#filespanprocessor)
   - [OpenAIProcessor](#openaiprocessor)
   - [MemorySpanProcessor](#memoryspanprocessor)
   - [ActiveRecordProcessor](#activerecordprocessor)
4. [Rails Integration](#rails-integration)
5. [OpenTelemetry Bridge](#opentelemetry-bridge)
6. [Custom Processors](#custom-processors)
7. [Trace Management](#trace-management)

## SpanTracer

Main tracing interface for creating and managing spans.

### Constructor

```ruby
RAAF::Tracing::SpanTracer.new(provider: nil)
```

### Processor Management

```ruby
tracer.add_processor(processor)          # Add span processor
tracer.processors                       # Get all processors
```

### Span Creation

```ruby
# Basic span creation
tracer.start_span(name, kind: :internal, **attributes) do |span|
  # Your code here
end

# Without block (manual management)
span = tracer.start_span("operation_name", kind: :internal)
# ... do work ...
tracer.finish_span(span)
```

### Convenience Methods

```ruby
# Agent execution span
tracer.agent_span(agent_name, **attributes) do |span|
  # Agent logic
end

# Tool execution span
tracer.tool_span(tool_name, arguments: {x: 1}, **attributes) do |span|
  # Tool execution
end

# LLM call span
tracer.llm_span(model_name, messages: messages, **attributes) do |span|
  # LLM call
end

# Agent handoff span
tracer.handoff_span(from_agent, to_agent, **attributes) do |span|
  # Handoff logic
end

# Custom span
tracer.custom_span(name, data = {}, **attributes) do |span|
  # Custom operation
end
```

### Span Management

```ruby
tracer.current_span                     # Get current active span
tracer.finish_span(span = nil)          # Finish a span
tracer.add_event(name, **attributes)    # Add event to current span
tracer.set_attribute(key, value)        # Set attribute on current span
```

### Export and Utilities

```ruby
tracer.export_spans(format: :json)      # Export spans as JSON/Hash
tracer.trace_summary                    # Get trace summary
tracer.clear                           # Clear all spans
tracer.flush                           # Flush processors
```

## Span Objects

### Attributes

```ruby
span.span_id                           # Unique span identifier
span.trace_id                          # Parent trace identifier
span.parent_id                         # Parent span identifier
span.name                              # Span name
span.kind                              # Span kind (:agent, :llm, :tool, etc.)
span.start_time                        # Start timestamp
span.end_time                          # End timestamp
span.attributes                        # Key-value attributes
span.events                            # Time-stamped events
span.status                            # Status (:ok, :error, :cancelled)
```

### Methods

```ruby
span.set_attribute(key, value)         # Set attribute
span.add_event(name, attributes: {})   # Add event
span.set_status(status, description: nil) # Set status
span.finish(end_time: nil)             # Mark as finished
span.finished?                         # Check if finished
span.duration                          # Duration in seconds
span.to_h                              # Convert to hash
span.to_json                           # Convert to JSON
```

### Example Usage

```ruby
tracer.start_span("process_order", kind: :internal) do |span|
  span.set_attribute("order.id", order_id)
  span.set_attribute("order.total", order_total)
  
  begin
    # Process order
    process_payment(order)
    span.add_event("payment_processed", attributes: { method: "credit_card" })
    
    ship_order(order)
    span.add_event("order_shipped", attributes: { carrier: "FedEx" })
    
    span.set_status(:ok)
  rescue => e
    span.set_status(:error, description: e.message)
    span.add_event("error", attributes: { 
      exception: e.class.name,
      message: e.message 
    })
    raise
  end
end
```

## Span Processors

### ConsoleSpanProcessor

Outputs spans to console for development/debugging.

```ruby
# Constructor
processor = RAAF::Tracing::ConsoleSpanProcessor.new(
  output: $stdout,                     # Output stream (default: $stdout)
  format: :pretty                      # Format: :pretty, :json, :compact
)

# Add to tracer
tracer.add_processor(processor)
```

### FileSpanProcessor

Writes spans to a file in JSONL format.

```ruby
# Constructor
processor = RAAF::Tracing::FileSpanProcessor.new(
  file_path,                          # Path to output file
  mode: "a",                          # File mode (default: append)
  batch_size: 10                      # Batch writes (default: 1)
)

# Add to tracer
tracer.add_processor(processor)

# Methods
processor.flush                        # Force write buffered spans
processor.shutdown                     # Close file and cleanup
```

### OpenAIProcessor

Sends spans to OpenAI platform for visualization.

```ruby
# Constructor
processor = RAAF::Tracing::OpenAIProcessor.new(
  api_key: String,                     # OpenAI API key (optional, uses ENV)
  batch_size: 50,                      # Spans per batch (default: 50)
  flush_interval: 5,                   # Seconds between flushes (default: 5)
  endpoint: String                     # Custom endpoint (optional)
)

# Add to tracer
tracer.add_processor(processor)

# Methods
processor.force_flush                  # Force send all pending spans
processor.shutdown                     # Shutdown and cleanup
```

### MemorySpanProcessor

Stores spans in memory for testing/analysis.

```ruby
# Constructor
processor = RAAF::Tracing::MemorySpanProcessor.new(
  max_spans: 1000                      # Maximum spans to store
)

# Add to tracer
tracer.add_processor(processor)

# Methods
processor.spans                        # Get all stored spans
processor.clear                        # Clear stored spans
processor.find_by_name(name)          # Find spans by name
processor.find_by_kind(kind)          # Find spans by kind
processor.find_by_trace_id(trace_id)  # Find spans by trace ID
```

### ActiveRecordProcessor

Stores spans in Rails database (Rails only).

```ruby
# Constructor
processor = RAAF::Tracing::ActiveRecordProcessor.new(
  sampling_rate: 1.0,                  # Sampling rate (0.0-1.0)
  batch_size: 100,                     # Batch insert size
  auto_cleanup: true,                  # Enable automatic cleanup
  cleanup_older_than: 30.days          # Cleanup threshold
)

# Add to tracer
tracer.add_processor(processor)

# Configuration
RAAF::Tracing.configure do |config|
  config.auto_configure = true         # Auto-add ActiveRecord processor
  config.retention_days = 30           # Data retention period
  config.sampling_rate = 0.1           # Sample 10% of traces
end
```

## Rails Integration

### Installation

```bash
rails generate raaf:tracing:install
rails db:migrate
```

### Configuration

```ruby
# config/initializers/raaf_tracing.rb
RAAF::Tracing.configure do |config|
  config.auto_configure = true
  config.mount_path = '/tracing'
  config.retention_days = 30
  config.sampling_rate = 1.0
end
```

### Models

```ruby
# Query traces
RAAF::Tracing::Trace.recent(100)
RAAF::Tracing::Trace.by_workflow("Customer Support")
RAAF::Tracing::Trace.within_timeframe(1.hour.ago, Time.current)

# Query spans
RAAF::Tracing::Span.by_kind(:llm)
RAAF::Tracing::Span.errors
RAAF::Tracing::Span.slow(threshold_ms: 1000)

# Analytics
RAAF::Tracing::Trace.performance_stats(
  workflow_name: "Support",
  timeframe: 24.hours
)
```

### Web Interface

```ruby
# Mount in routes
Rails.application.routes.draw do
  mount RAAF::Tracing::Engine => '/tracing'
end

# Access at: http://localhost:3000/tracing
```

### Console Helpers

```ruby
# In Rails console
include RAAF::Tracing::RailsIntegrations::ConsoleHelpers

recent_traces(10)
traces_for("Customer Support")
slow_spans(threshold: 5000)
performance_stats(timeframe: 24.hours)
trace_summary("trace_abc123...")
error_spans(20)
```

## OpenTelemetry Bridge

### OTLP Exporter

```ruby
# Configure OTLP exporter
RAAF::Tracing::OTelBridge.configure_otlp(
  endpoint: "http://localhost:4318/v1/traces",
  headers: { "x-api-key" => "your-key" },
  compression: "gzip"
)
```

### Jaeger Integration

```ruby
# Configure Jaeger exporter
RAAF::Tracing::OTelBridge.configure_jaeger(
  endpoint: "localhost:6831",
  service_name: "raaf-application"
)
```

### Custom OpenTelemetry Exporter

```ruby
# Use any OpenTelemetry-compatible exporter
require "opentelemetry/exporter/zipkin"

exporter = OpenTelemetry::Exporter::Zipkin::Exporter.new(
  endpoint: "http://localhost:9411/api/v2/spans"
)

RAAF::Tracing::OTelBridge.use_otel_exporter(exporter)
```

## Custom Processors

### Basic Custom Processor

```ruby
class MyCustomProcessor
  def on_span_start(span)
    # Called when span starts
    puts "Starting: #{span.name}"
  end
  
  def on_span_end(span)
    # Called when span ends
    send_to_monitoring_system(span.to_h)
  end
  
  def force_flush
    # Called on manual flush
    # Flush any buffered data
  end
  
  def shutdown
    # Called on shutdown
    # Clean up resources
  end
  
  private
  
  def send_to_monitoring_system(span_data)
    # Your implementation
  end
end

# Add to tracer
tracer.add_processor(MyCustomProcessor.new)
```

### Batch Processor

```ruby
class BatchingProcessor
  def initialize(batch_size: 100, flush_interval: 10)
    @batch_size = batch_size
    @flush_interval = flush_interval
    @spans = []
    @mutex = Mutex.new
    start_flush_timer
  end
  
  def on_span_start(span)
    # No-op for start
  end
  
  def on_span_end(span)
    @mutex.synchronize do
      @spans << span.to_h
      flush if @spans.size >= @batch_size
    end
  end
  
  def force_flush
    @mutex.synchronize do
      flush
    end
  end
  
  def shutdown
    force_flush
    @timer_thread&.kill
  end
  
  private
  
  def flush
    return if @spans.empty?
    
    # Process batch
    process_batch(@spans.dup)
    @spans.clear
  end
  
  def start_flush_timer
    @timer_thread = Thread.new do
      loop do
        sleep @flush_interval
        force_flush
      end
    end
  end
  
  def process_batch(spans)
    # Send to your backend
    puts "Processing batch of #{spans.size} spans"
  end
end
```

### Filtering Processor

```ruby
class FilteringProcessor
  def initialize(delegate, &filter)
    @delegate = delegate
    @filter = filter
  end
  
  def on_span_start(span)
    return unless @filter.call(span)
    @delegate.on_span_start(span)
  end
  
  def on_span_end(span)
    return unless @filter.call(span)
    @delegate.on_span_end(span)
  end
  
  def force_flush
    @delegate.force_flush
  end
  
  def shutdown
    @delegate.shutdown
  end
end

# Usage: Only process LLM spans
llm_only = FilteringProcessor.new(
  RAAF::Tracing::ConsoleSpanProcessor.new
) do |span|
  span.kind == :llm
end

tracer.add_processor(llm_only)
```

## Trace Management

### Global Configuration

```ruby
# Configure tracing globally
RAAF.configure_tracing do |config|
  config.add_processor(RAAF::Tracing::ConsoleSpanProcessor.new)
  config.add_processor(RAAF::Tracing::OpenAIProcessor.new)
end

# Disable tracing
ENV["RAAF_DISABLE_TRACING"] = "true"
# or
RAAF::Tracing::TraceProvider.disable!

# Check if disabled
RAAF::Tracing::TraceProvider.disabled?
```

### Manual Trace Management

```ruby
# Create custom trace context
RAAF.trace("Custom Operation") do
  # All operations here share the same trace ID
  agent1.run("First task")
  agent2.run("Second task")
end

# Get current trace ID
trace_id = RAAF::Tracing::TraceProvider.current_trace_id

# Force flush all processors
RAAF::Tracing::TraceProvider.force_flush

# Shutdown tracing
RAAF::Tracing::TraceProvider.shutdown
```

### Environment Variables

```ruby
# Disable all tracing
ENV['RAAF_DISABLE_TRACING'] = 'true'

# Enable console output
ENV['RAAF_TRACE_CONSOLE'] = 'true'

# Configure batch size
ENV['RAAF_TRACE_BATCH_SIZE'] = '100'

# Configure flush interval
ENV['RAAF_TRACE_FLUSH_INTERVAL'] = '10'

# Enable debug categories
ENV['RAAF_DEBUG_CATEGORIES'] = 'tracing,http'
```

### Debug Utilities

```ruby
# Enable trace debugging
ENV['RAAF_DEBUG_CATEGORIES'] = 'tracing'

# Check active processors
puts "Active processors: #{RAAF.tracer.processors.map(&:class)}"

# Export all spans
spans = RAAF.tracer.export_spans(format: :json)
File.write("trace_export.json", JSON.pretty_generate(spans))

# Get trace summary
summary = RAAF.tracer.trace_summary
puts "Total spans: #{summary[:total_spans]}"
puts "By kind: #{summary[:by_kind]}"
puts "Errors: #{summary[:error_count]}"
```

For more details on Rails integration, see [RAILS_INTEGRATION.md](RAILS_INTEGRATION.md) and [TRACING_RAILS.md](TRACING_RAILS.md).