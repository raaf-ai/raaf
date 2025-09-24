# RAAF Coherent Tracing Guide

**RAAF Coherent Tracing** provides a unified, intelligent tracing system that automatically maintains proper span hierarchies across complex multi-agent workflows while preventing duplicate spans and ensuring thread safety.

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Span Hierarchy Examples](#span-hierarchy-examples)
- [Component Integration](#component-integration)
- [Configuration](#configuration)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)
- [Performance Considerations](#performance-considerations)
- [Migration Guide](#migration-guide)

## Overview

Coherent Tracing solves the common problems in distributed agent systems where:
- Spans are duplicated across nested calls
- Parent-child relationships are lost or incorrect
- Trace context doesn't propagate properly
- Different components create conflicting spans

The system provides a **unified Traceable module** that components include to automatically participate in coherent tracing with smart span lifecycle management.

## Key Features

### 🎯 **Smart Span Lifecycle Management**
- Automatic detection and prevention of duplicate spans
- Intelligent span reuse for compatible nested calls
- Proper cleanup and restoration of span context

### 🌳 **Coherent Span Hierarchy**
- Automatic parent-child relationship establishment
- Trace ID propagation across component boundaries
- Support for complex multi-level workflows

### 🔒 **Thread Safety**
- Independent trace contexts per thread
- No shared mutable state between threads
- Safe concurrent execution of multiple workflows

### 🏷️ **Component-Specific Attributes**
- Each component type controls its own span attributes
- Extensible attribute collection system
- Rich metadata for debugging and monitoring

## Architecture

```
┌─────────────────┐
│ RAAF::Tracing:: │
│   Traceable     │
│                 │
│ - Span creation │
│ - Hierarchy mgmt│
│ - Lifecycle     │
│ - Cleanup       │
└─────────────────┘
         │
         │ Include
         ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Pipeline      │    │     Agent       │    │      Tool       │
│                 │    │                 │    │                 │
│ trace_as        │    │ trace_as        │    │ trace_as        │
│ :pipeline       │    │ :agent          │    │ :tool           │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Core Components

1. **Traceable Module**: Core tracing functionality
2. **Component Types**: Pipeline, Agent, Tool, Runner, Component
3. **Span Management**: Creation, hierarchy, lifecycle
4. **Attribute Collection**: Component-specific data gathering

## Getting Started

### 1. Include Traceable in Your Components

```ruby
class MyAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def initialize(name, parent_component: nil)
    @name = name
    @parent_component = parent_component
  end

  def run(message)
    with_tracing(:run) do
      # Your agent logic here
      process_message(message)
    end
  end

  # Define what data goes into spans
  def collect_span_attributes
    super.merge({
      "agent.name" => @name,
      "agent.model" => @model,
      "agent.temperature" => @temperature
    })
  end
end
```

### 2. Set Up Parent-Child Relationships

```ruby
# Create components with parent references
pipeline = MyPipeline.new(name: "DataProcessing")
agent = MyAgent.new(name: "Analyzer", parent_component: pipeline)
tool = MyTool.new(name: "Calculator", parent_component: agent)

# Execute workflow - spans will automatically have proper hierarchy
pipeline.execute do
  agent.run("process this data") do
    tool.calculate(1, 2, 3)
  end
end
```

### 3. View Traces

Traces are automatically sent to configured processors (OpenAI dashboard by default):

```ruby
# Configure processors
RAAF::Tracing.add_trace_processor(
  RAAF::Tracing::ConsoleProcessor.new
)

# View at: https://platform.openai.com/traces
```

## Span Hierarchy Examples

### Basic Pipeline → Agent → Tool Hierarchy

```ruby
class DataPipeline
  include RAAF::Tracing::Traceable
  trace_as :pipeline

  def execute
    with_tracing(:execute) do
      @agents.each(&:run)
    end
  end
end

class AnalysisAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def initialize(parent_component: nil)
    @parent_component = parent_component
  end

  def run
    with_tracing(:run) do
      @tools.each(&:execute)
    end
  end
end

class CalculatorTool
  include RAAF::Tracing::Traceable
  trace_as :tool

  def initialize(parent_component: nil)
    @parent_component = parent_component
  end

  def execute(args)
    with_tracing(:execute) do
      perform_calculation(args)
    end
  end
end

# Usage creates this hierarchy:
# Pipeline:DataPipeline [trace_id: abc123]
# ├── Agent:AnalysisAgent [parent: Pipeline, trace_id: abc123]
#     └── Tool:CalculatorTool [parent: Agent, trace_id: abc123]
```

### Multi-Agent Pipeline with Parallel Execution

```ruby
class ParallelPipeline
  include RAAF::Tracing::Traceable
  trace_as :pipeline

  def execute
    with_tracing(:execute) do
      # All agents share the same parent (pipeline) span
      threads = @agents.map do |agent|
        Thread.new { agent.run }
      end
      threads.each(&:join)
    end
  end
end

# Creates this hierarchy:
# Pipeline:ParallelPipeline [trace_id: def456]
# ├── Agent:Agent1 [parent: Pipeline, trace_id: def456]
# ├── Agent:Agent2 [parent: Pipeline, trace_id: def456]
# └── Agent:Agent3 [parent: Pipeline, trace_id: def456]
```

### Nested Pipeline Execution

```ruby
class MasterPipeline
  include RAAF::Tracing::Traceable
  trace_as :pipeline

  def execute
    with_tracing(:execute) do
      # Child pipelines have this as parent
      @sub_pipelines.each { |pipeline| pipeline.execute }
    end
  end
end

# Creates hierarchical pipelines:
# Pipeline:MasterPipeline [trace_id: ghi789]
# ├── Pipeline:DataPipeline [parent: MasterPipeline, trace_id: ghi789]
# │   ├── Agent:DataAgent1 [parent: DataPipeline, trace_id: ghi789]
# │   └── Agent:DataAgent2 [parent: DataPipeline, trace_id: ghi789]
# └── Pipeline:ReportPipeline [parent: MasterPipeline, trace_id: ghi789]
#     └── Agent:ReportAgent [parent: ReportPipeline, trace_id: ghi789]
```

## Component Integration

### Custom Component Types

```ruby
class CustomProcessor
  include RAAF::Tracing::Traceable
  trace_as :processor  # Custom component type

  def initialize(config, parent_component: nil)
    @config = config
    @parent_component = parent_component
  end

  def process(data)
    with_tracing(:process) do
      # Your processing logic
      transform_data(data)
    end
  end

  def collect_span_attributes
    super.merge({
      "processor.type" => @config[:type],
      "processor.batch_size" => @config[:batch_size],
      "processor.parallel" => @config[:parallel]
    })
  end

  def collect_result_attributes(result)
    super.merge({
      "result.items_processed" => result[:count],
      "result.processing_time" => result[:duration]
    })
  end
end
```

### RAAF DSL Agent Integration

```ruby
class SmartAgent < RAAF::DSL::Agent
  include RAAF::Tracing::Traceable
  trace_as :agent

  instructions "You are a helpful assistant"
  model "gpt-4"

  def initialize(parent_component: nil, **options)
    @parent_component = parent_component
    super(**options)
  end

  def run(message)
    with_tracing(:run) do
      super(message)
    end
  end

  def collect_span_attributes
    super.merge({
      "agent.model" => model,
      "agent.temperature" => temperature,
      "agent.max_tokens" => max_tokens,
      "agent.tools_count" => tools.size
    })
  end
end
```

### Tool Integration

```ruby
class WebSearchTool
  include RAAF::Tracing::Traceable
  trace_as :tool

  def initialize(api_key, parent_component: nil)
    @api_key = api_key
    @parent_component = parent_component
  end

  def search(query, limit: 10)
    with_tracing(:search, query: query, limit: limit) do
      perform_web_search(query, limit)
    end
  end

  def collect_span_attributes
    super.merge({
      "tool.name" => "web_search",
      "tool.api_provider" => "google",
      "tool.rate_limit" => 100
    })
  end

  def collect_result_attributes(result)
    super.merge({
      "result.items_found" => result.size,
      "result.search_time" => result.metadata[:search_time]
    })
  end

  private

  def perform_web_search(query, limit)
    # Your search implementation
  end
end
```

## Configuration

### Environment Variables

```bash
# Basic tracing control
export RAAF_DISABLE_TRACING=false          # Enable/disable tracing
export RAAF_TRACE_CONSOLE=true             # Show traces in console
export RAAF_DEBUG_CATEGORIES=tracing       # Enable tracing debug output

# Advanced configuration
export RAAF_TRACE_BATCH_SIZE=50            # Batch size for OpenAI export
export RAAF_TRACE_FLUSH_INTERVAL=5         # Flush interval in seconds
export RAAF_TRACE_MAX_SPANS=1000           # Max spans to keep in memory
```

### Programmatic Configuration

```ruby
# Configure processors
RAAF::Tracing.configure do |config|
  # Add console output for development
  config.add_processor(RAAF::Tracing::ConsoleProcessor.new)

  # Add file output for debugging
  config.add_processor(RAAF::Tracing::FileProcessor.new("traces.jsonl"))

  # Add custom processor
  config.add_processor(MyCustomProcessor.new)
end

# Replace all processors
RAAF::Tracing.set_trace_processors(
  RAAF::Tracing::OpenAIProcessor.new,
  MyCustomProcessor.new
)

# Disable tracing temporarily
RAAF::Tracing.disable!

# Re-enable tracing
RAAF::Tracing.enable!
```

### Custom Processors

```ruby
class MetricsProcessor
  def on_span_start(span)
    @start_time = Time.now
  end

  def on_span_end(span)
    duration = Time.now - @start_time

    # Send metrics to your monitoring system
    MyMetrics.timing("raaf.span.duration", duration, tags: {
      component_type: span.kind,
      component_name: span.attributes["component.name"],
      success: span.attributes["success"]
    })
  end

  def force_flush
    MyMetrics.flush
  end

  def shutdown
    MyMetrics.close
  end
end

RAAF::Tracing.add_trace_processor(MetricsProcessor.new)
```

## Advanced Usage

### Manual Span Creation

```ruby
class DataProcessor
  include RAAF::Tracing::Traceable
  trace_as :processor

  def complex_operation(data)
    with_tracing(:complex_operation) do
      # Phase 1: Validation
      with_tracing(:validation, data_size: data.size) do
        validate_data(data)
      end

      # Phase 2: Transformation
      with_tracing(:transformation) do
        transform_data(data)
      end

      # Phase 3: Storage
      with_tracing(:storage) do
        store_data(data)
      end
    end
  end
end
```

### Conditional Tracing

```ruby
class ConditionalAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def run(message, trace: true)
    if trace
      with_tracing(:run) do
        process_message(message)
      end
    else
      process_message(message)
    end
  end

  def should_create_span?(method_name = nil, context = {})
    # Custom logic for span creation
    return false if context[:skip_tracing]
    return false if method_name == :internal_method
    super
  end
end
```

### Cross-Thread Trace Propagation

```ruby
class ParallelProcessor
  include RAAF::Tracing::Traceable
  trace_as :processor

  def process_in_parallel(items)
    with_tracing(:parallel_process) do
      # Capture current trace context
      trace_context = {
        trace_id: trace_id,
        parent_span: current_span
      }

      threads = items.map do |item|
        Thread.new do
          # Create child processor with trace context
          child_processor = ChildProcessor.new(trace_context: trace_context)
          child_processor.process(item)
        end
      end

      threads.each(&:join)
    end
  end
end

class ChildProcessor
  include RAAF::Tracing::Traceable
  trace_as :processor

  def initialize(trace_context: nil)
    @trace_context = trace_context
  end

  def process(item)
    # Use explicit parent context if provided
    with_tracing(:process, parent_component: @trace_context) do
      # Processing logic
    end
  end
end
```

## Troubleshooting

### Common Issues

#### 1. Spans Not Appearing in Traces

**Symptoms**: No spans showing up in OpenAI dashboard or console output

**Solutions**:
```ruby
# Check if tracing is enabled
puts RAAF::Tracing.disabled?

# Verify processors are configured
puts RAAF::Tracing.tracer.processors.size

# Enable debug output
ENV['RAAF_DEBUG_CATEGORIES'] = 'tracing'

# Force flush traces
RAAF::Tracing.force_flush
sleep(1) # Allow time for network requests
```

#### 2. Incorrect Parent-Child Relationships

**Symptoms**: Spans appear flat instead of hierarchical

**Solutions**:
```ruby
# Verify parent_component is set
class MyAgent
  def initialize(parent_component: nil)
    @parent_component = parent_component  # Must set this
  end
end

# Check parent span exists during execution
agent.with_tracing(:run) do
  puts "Parent span: #{agent.current_span[:parent_id]}"
end

# Use explicit parent in nested calls
child_agent.with_tracing(:run, parent_component: parent_agent) do
  # Processing
end
```

#### 3. Duplicate Spans

**Symptoms**: Multiple spans with same operation appearing

**Solutions**:
```ruby
# Check span reuse logic
class MyComponent
  def should_create_span?(method_name, context = {})
    # Custom logic to prevent duplicates
    return false if already_processing_same_method?
    super
  end
end

# Use span reuse context
with_tracing(:operation, reuse_span: true) do
  # Won't create new span if compatible one exists
end
```

#### 4. Missing Span Attributes

**Symptoms**: Spans created but missing expected metadata

**Solutions**:
```ruby
# Verify collect_span_attributes is implemented
def collect_span_attributes
  super.merge({
    "my.custom.attribute" => @some_value
  })
end

# Check for exceptions in attribute collection
def collect_span_attributes
  begin
    super.merge(my_custom_attributes)
  rescue => e
    puts "Error collecting attributes: #{e.message}"
    super
  end
end
```

### Debug Mode

```ruby
# Enable comprehensive debugging
ENV['RAAF_LOG_LEVEL'] = 'debug'
ENV['RAAF_DEBUG_CATEGORIES'] = 'tracing,http'

# Add debug processor
RAAF::Tracing.add_trace_processor(
  RAAF::Tracing::ConsoleProcessor.new(detailed: true)
)

# Custom debug output
class DebugProcessor
  def on_span_start(span)
    puts "🔄 Span started: #{span.name}"
    puts "   Parent: #{span.parent_id}"
    puts "   Trace: #{span.trace_id}"
  end

  def on_span_end(span)
    puts "✅ Span completed: #{span.name}"
    puts "   Duration: #{span.duration}ms"
    puts "   Success: #{span.attributes['success']}"
    puts "   Attributes: #{span.attributes.keys.join(', ')}"
  end
end

RAAF::Tracing.add_trace_processor(DebugProcessor.new)
```

### Performance Debugging

```ruby
# Monitor span creation performance
class PerformanceProcessor
  def initialize
    @span_times = {}
  end

  def on_span_start(span)
    @span_times[span.span_id] = Time.now
  end

  def on_span_end(span)
    start_time = @span_times.delete(span.span_id)
    overhead = Time.now - start_time - (span.duration / 1000.0)

    if overhead > 0.01 # More than 10ms overhead
      puts "⚠️  High tracing overhead: #{overhead * 1000}ms for #{span.name}"
    end
  end
end

RAAF::Tracing.add_trace_processor(PerformanceProcessor.new)
```

## Performance Considerations

### Memory Management

```ruby
# Configure memory limits
ENV['RAAF_TRACE_MAX_SPANS'] = '1000'     # Limit spans in memory
ENV['RAAF_TRACE_CLEANUP_INTERVAL'] = '60' # Cleanup old spans every 60s

# Manual cleanup
RAAF::Tracing.force_flush  # Send all pending spans
RAAF::Tracing.cleanup      # Clean up old spans
```

### Batching and Buffering

```ruby
# Optimize for high-throughput scenarios
ENV['RAAF_TRACE_BATCH_SIZE'] = '100'      # Larger batches
ENV['RAAF_TRACE_FLUSH_INTERVAL'] = '10'   # Less frequent flushes

# Custom batching processor
class HighThroughputProcessor
  def initialize(batch_size: 1000, flush_interval: 30)
    @batch_size = batch_size
    @flush_interval = flush_interval
    @buffer = []
  end

  def on_span_end(span)
    @buffer << span
    flush_if_needed
  end

  private

  def flush_if_needed
    if @buffer.size >= @batch_size
      send_batch(@buffer)
      @buffer.clear
    end
  end
end
```

### Selective Tracing

```ruby
# Trace only important operations
class SelectiveAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def run(message, trace_level: :normal)
    case trace_level
    when :none
      process_message(message)
    when :basic
      with_tracing(:run) { process_message(message) }
    when :detailed
      with_detailed_tracing(message)
    end
  end

  private

  def with_detailed_tracing(message)
    with_tracing(:run, message_length: message.length) do
      with_tracing(:preprocessing) { preprocess(message) }
      with_tracing(:processing) { process_message(message) }
      with_tracing(:postprocessing) { postprocess(result) }
    end
  end
end
```

## Migration Guide

### From Manual Span Creation

**Before**:
```ruby
class OldAgent
  def run(message)
    span = tracer.start_span("agent.run")
    span.set_attribute("agent.name", @name)

    begin
      result = process_message(message)
      span.set_attribute("success", true)
      result
    rescue => e
      span.set_attribute("error", e.message)
      span.set_status(:error)
      raise
    ensure
      span.finish
    end
  end
end
```

**After**:
```ruby
class NewAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def run(message)
    with_tracing(:run) do
      process_message(message)
    end
  end

  def collect_span_attributes
    super.merge({
      "agent.name" => @name
    })
  end
end
```

### From Custom Tracing Systems

**Before**:
```ruby
class OldPipeline
  def execute
    trace_id = generate_trace_id
    parent_span = create_span("pipeline.execute", trace_id)

    @agents.each do |agent|
      agent_span = create_span("agent.run", trace_id, parent_span.id)
      agent.run_with_span(agent_span)
      agent_span.finish
    end

    parent_span.finish
  end
end
```

**After**:
```ruby
class NewPipeline
  include RAAF::Tracing::Traceable
  trace_as :pipeline

  def execute
    with_tracing(:execute) do
      @agents.each do |agent|
        agent.run  # Automatic span creation and hierarchy
      end
    end
  end
end

class NewAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def initialize(parent_component: nil)
    @parent_component = parent_component
  end

  def run
    with_tracing(:run) do
      # Agent logic
    end
  end
end
```

### Backwards Compatibility

The coherent tracing system maintains compatibility with existing RAAF tracing:

```ruby
# Old style still works
tracer = RAAF::Tracing.tracer
tracer.agent_span("my_agent") do |span|
  span.set_attribute("custom", "value")
  # Your code
end

# New style is recommended
class MyAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def run
    with_tracing(:run) do
      # Your code
    end
  end
end
```

## Best Practices

1. **Always set `parent_component`** when creating child components
2. **Use `trace_as`** to define component types clearly
3. **Override `collect_span_attributes`** to add meaningful metadata
4. **Use descriptive method names** in `with_tracing` calls
5. **Configure appropriate processors** for your environment
6. **Monitor performance impact** in high-throughput scenarios
7. **Use debug mode** during development and troubleshooting
8. **Test trace hierarchies** with integration tests

## Summary

RAAF Coherent Tracing provides a robust, intelligent tracing system that automatically handles the complexities of distributed agent workflows. By including the `Traceable` module and following the patterns in this guide, you get:

- ✅ Automatic span hierarchy management
- ✅ Duplicate span prevention
- ✅ Thread-safe operation
- ✅ Rich metadata collection
- ✅ Easy debugging and monitoring
- ✅ Performance optimization options

The system grows with your needs, from simple single-agent operations to complex multi-pipeline workflows with hundreds of components.