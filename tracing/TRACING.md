# Tracing and Monitoring

Comprehensive observability for RAAF (Ruby AI Agents Factory) with automatic instrumentation, OpenAI dashboard integration, and flexible export options.

## Overview

The tracing system provides complete visibility into agent execution, automatically capturing:

- **Agent Operations** - Complete conversation flows and handoffs
- **LLM Interactions** - API calls, token usage, and response times  
- **Tool Executions** - Function calls and results
- **Performance Metrics** - Duration, costs, and error rates
- **Custom Events** - Application-specific monitoring points

All traces are sent to the OpenAI platform dashboard for visualization and analysis.

## Quick Start

Tracing is enabled by default when you have an OpenAI API key set:

```ruby
# Tracing happens automatically
agent = RAAF::Agent.new(name: "Assistant", model: "gpt-4")
runner = RAAF::Runner.new(agent: agent)
result = runner.run(messages)  # This creates traces!
```

## Configuration

### Global Configuration

```ruby
RAAF.configure_tracing do |config|
  # Add console output for development
  config.add_processor(RAAF::Tracing::ConsoleSpanProcessor.new)
  
  # Save traces to a file
  config.add_processor(RAAF::Tracing::FileSpanProcessor.new("traces.jsonl"))
  
  # Add custom processor
  config.add_processor(MyCustomProcessor.new)
end
```

### Environment Variables

- `RAAF_DISABLE_TRACING=true` - Disable all tracing
- `RAAF_TRACE_CONSOLE=true` - Enable console output
- `RAAF_TRACE_BATCH_SIZE=100` - Batch size for OpenAI export (default: 50)
- `RAAF_TRACE_FLUSH_INTERVAL=10` - Flush interval in seconds (default: 5)
- `RAAF_DEBUG_CATEGORIES=http,tracing` - Enable detailed HTTP and tracing debug output

### Disabling Tracing

```ruby
# Disable globally
ENV["RAAF_DISABLE_TRACING"] = "true"

# Disable for specific runner
runner = RAAF::Runner.new(agent: agent, disabled_tracing: true)

# Disable programmatically
RAAF::Tracing::TraceProvider.disable!
```

## Trace Structure

### Automatic Spans

The following spans are automatically created:

1. **Agent Span** (`agent.<name>`)
   - Wraps entire agent execution
   - Attributes: model, max_turns, tools_count, handoffs_count

2. **LLM Span** (`llm.completion`)
   - Wraps each LLM API call
   - Attributes: model, messages, usage (tokens)
   - Events: request.start, request.complete

3. **Tool Span** (`tool.<name>`)
   - Wraps each tool execution
   - Attributes: arguments, result
   - Events: execution.start, execution.complete

4. **Handoff Span** (`handoff`)
   - Created when agents hand off to each other
   - Attributes: from_agent, to_agent
   - Events: handoff.initiated

### Manual Tracing

```ruby
tracer = RAAF.tracer

# Basic span
tracer.span("operation_name") do |span|
  span.set_attribute("key", "value")
  span.add_event("checkpoint")
  # Your code here
end

# Typed spans
tracer.agent_span("agent_name") do |span|
  # Agent-specific logic
end

tracer.tool_span("tool_name", arguments: {x: 1}) do |span|
  # Tool execution
end

tracer.llm_span("gpt-4", messages: messages) do |span|
  # LLM call
end
```

## OpenAI Platform Integration

Traces are automatically sent to OpenAI's platform when `OPENAI_API_KEY` is set. View them at:
https://platform.openai.com/traces

The integration includes:
- Automatic batching (default: 50 spans)
- Background processing with configurable flush interval
- Proper span type mapping for OpenAI's UI
- SDK metadata inclusion

## OpenTelemetry Integration

### Using OTLP Exporter

```ruby
# Requires: gem install opentelemetry-exporter-otlp
RAAF::Tracing::OTelBridge.configure_otlp(
  endpoint: "http://localhost:4318/v1/traces",
  headers: { "x-api-key" => "your-key" }
)
```

### Using Jaeger

```ruby
# Requires: gem install opentelemetry-exporter-jaeger
RAAF::Tracing::OTelBridge.configure_jaeger(
  endpoint: "localhost:6831"
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

Create custom processors to handle traces your way:

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
  end
  
  def shutdown
    # Called on shutdown
  end
end

RAAF::Tracing::TraceProvider.add_processor(MyCustomProcessor.new)
```

## Trace Data Format

Spans include the following data:

```ruby
{
  span_id: "span_abc123...",
  trace_id: "trace_def456...",
  parent_id: "span_parent123...",
  name: "tool.calculator",
  kind: :tool,
  start_time: "2024-01-15T10:00:00Z",
  end_time: "2024-01-15T10:00:01Z",
  duration_ms: 1000.5,
  attributes: {
    "tool.name" => "calculator",
    "tool.arguments" => { expression: "2+2" },
    "tool.result" => "4"
  },
  events: [
    {
      name: "execution.start",
      timestamp: "2024-01-15T10:00:00Z",
      attributes: {}
    }
  ],
  status: :ok
}
```

## Performance Considerations

- Tracing adds minimal overhead (~1-2ms per span)
- Batching reduces API calls to external services
- Background processing doesn't block main execution
- Automatic sampling can be configured for high-volume scenarios

## Debugging

### Unified Logging System

The tracing system now uses a unified logging system with granular debug categories:

```ruby
# Configure logging for tracing
RAAF.logger.configure do |config|
  config.log_level = :debug
  config.debug_categories = [:tracing, :http]
end

# Use in your classes
class MyTraceProcessor
  include RAAF::Logger
  
  def process_span(span)
    log_debug_tracing("Processing span", span_id: span.id)
    log_debug_http("Sending to OpenAI", url: "https://api.openai.com")
  end
end
```

### Environment Variables

```bash
# Enable tracing debug output
export RAAF_DEBUG_CATEGORIES=tracing,http

# Set overall log level
export RAAF_LOG_LEVEL=debug

# Choose output format
export RAAF_LOG_FORMAT=json
```

### Trace Management

Standard tracing operations:

```ruby
# Add console output processor
RAAF.configure_tracing do |config|
  config.add_processor(RAAF::Tracing::ConsoleSpanProcessor.new)
end

# Check if tracing is active
puts RAAF::Tracing::TraceProvider.disabled?

# Force flush all pending traces
RAAF::Tracing::TraceProvider.force_flush

# Get trace summary
tracer = RAAF.tracer
summary = tracer.trace_summary if tracer.respond_to?(:trace_summary)
```

### HTTP Debug Mode

To troubleshoot trace export to OpenAI platform:

```bash
# Enable detailed HTTP debugging
export RAAF_DEBUG_CATEGORIES=http,tracing

# Run your code
ruby your_script.rb
```

This will output:
- Full HTTP request details (URL, headers, payload structure)
- HTTP response details (status, headers, body)
- Batch processor queuing and flushing information
- Detailed error messages with stack traces

Example debug output:
```
[BatchTraceProcessor] Added span 'agent.MathAssistant' to queue (1/50)
[BatchTraceProcessor] Flushing batch of 1 spans (0 remaining in queue)
[OpenAI Processor] === DEBUG: HTTP Request Details ===
URL: https://api.openai.com/v1/traces/ingest
Headers:
  authorization: Bearer sk-proj-1234...
  content-type: application/json
  user-agent: raaf/0.1.0
  openai-beta: traces=v1

Payload Structure:
  - Trace ID: trace_abc123...
  - Workflow: raaf
  - Spans: 1
    [0] agent - agent.MathAssistant
```

## Examples

See `examples/tracing_example.rb` for a complete working example demonstrating:
- Automatic tracing of agent execution
- Manual span creation
- Multiple processor configuration
- OpenTelemetry integration