# RAAF Tracing

[![Gem Version](https://badge.fury.io/rb/raaf-tracing.svg)](https://badge.fury.io/rb/raaf-tracing)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Tracing** gem provides comprehensive distributed tracing and observability for the Ruby AI Agents Factory (RAAF) ecosystem. It offers span-based monitoring, performance analytics, and seamless integration with popular tracing and monitoring platforms.

## Overview

RAAF (Ruby AI Agents Factory) Tracing extends the core tracing capabilities from `raaf-core` to provide distributed tracing and monitoring for Ruby AI Agents Factory (RAAF). This gem provides comprehensive observability for AI agent workflows with support for multiple monitoring platforms.

## Features

- **Span-based tracing** - Track agent execution with detailed timing and metadata
- **Python SDK compatibility** - Maintains exact structural alignment with OpenAI Agents Python SDK
- **Multiple processors** - Send traces to OpenAI, Datadog, files, console, and more
- **OpenTelemetry integration** - Full OpenTelemetry support for enterprise monitoring
- **Performance metrics** - Token usage, response times, and error tracking
- **Custom processors** - Easy to extend with your own monitoring solutions

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-tracing'
```

And then execute:

```bash
bundle install
```

## Quick Start

### Basic Usage

```ruby
require 'raaf-tracing'

# Create a tracer
tracer = RubyAIAgentsFactory::Tracing::SpanTracer.new

# Add processors
tracer.add_processor(RubyAIAgentsFactory::Tracing::OpenAIProcessor.new)
tracer.add_processor(RubyAIAgentsFactory::Tracing::ConsoleProcessor.new)

# Use with agent
agent = RubyAIAgentsFactory::Agent.new(
  name: "Assistant",
  instructions: "You are helpful"
)

runner = RubyAIAgentsFactory::Runner.new(agent: agent, tracer: tracer)
result = runner.run("Hello, world!")
```

### OpenTelemetry Integration

```ruby
require 'raaf-tracing'

# Setup OpenTelemetry
otel = RubyAIAgentsFactory::Tracing::OpenTelemetryIntegration.new(
  service_name: "my-ai-service",
  service_version: "1.0.0"
)
otel.setup_instrumentation

# Use with agent
agent = RubyAIAgentsFactory::Agent.new(name: "Assistant")
runner = RubyAIAgentsFactory::Runner.new(agent: agent, tracer: otel)
```

## Processors

### OpenAI Processor

Sends traces to OpenAI's monitoring dashboard:

```ruby
processor = RubyAIAgentsFactory::Tracing::OpenAIProcessor.new
tracer.add_processor(processor)
```

### Datadog Processor

Integrates with Datadog APM:

```ruby
processor = RubyAIAgentsFactory::Tracing::DatadogProcessor.new(
  service_name: "ai-agents-production",
  env: "production",
  version: "1.0.0"
)
tracer.add_processor(processor)
```

### Console Processor

Outputs traces to console for debugging:

```ruby
processor = RubyAIAgentsFactory::Tracing::ConsoleProcessor.new
tracer.add_processor(processor)
```

### File Processor

Saves traces to JSON files:

```ruby
processor = RubyAIAgentsFactory::Tracing::FileProcessor.new("traces.json")
tracer.add_processor(processor)
```

## Configuration

### Global Configuration

```ruby
RubyAIAgentsFactory::Tracing.configure do |config|
  config.enabled = true
  config.sample_rate = 0.1  # Sample 10% of traces
  config.max_spans_per_trace = 1000
  config.processors = [
    RubyAIAgentsFactory::Tracing::OpenAIProcessor.new,
    RubyAIAgentsFactory::Tracing::ConsoleProcessor.new
  ]
end
```

### Environment Variables

```bash
# OpenTelemetry configuration
export OTEL_EXPORTER_OTLP_ENDPOINT="https://api.honeycomb.io"
export OTEL_EXPORTER_OTLP_HEADERS="x-honeycomb-team=YOUR_API_KEY"
export OTEL_SERVICE_NAME="ai-agents"
export OTEL_SERVICE_VERSION="1.0.0"

# Datadog configuration
export DD_AGENT_HOST="localhost"
export DD_AGENT_PORT="8126"
export DD_ENV="production"
export DD_SERVICE="ai-agents"
export DD_VERSION="1.0.0"
```

## Trace Structure

The trace format is compatible with Python OpenAI Agents SDK:

```json
{
  "trace": {
    "run_id": "run_abc123",
    "workflow": {
      "name": "Assistant",
      "version": "1.0.0"
    }
  },
  "spans": [
    {
      "span_id": "span_123",
      "parent_id": null,
      "name": "run.workflow.agent",
      "type": "agent",
      "error": null,
      "start_time": "2024-01-01T00:00:00.000000+00:00",
      "end_time": "2024-01-01T00:00:01.500000+00:00",
      "metadata": {
        "agent_name": "Assistant",
        "model": "gpt-4o",
        "provider": "responses"
      }
    },
    {
      "span_id": "span_456",
      "parent_id": "span_123",
      "name": "run.workflow.agent.response",
      "type": "response",
      "model": "gpt-4o",
      "provider": "responses",
      "usage": {
        "input_tokens": 10,
        "output_tokens": 25,
        "total_tokens": 35
      }
    }
  ]
}
```

## Custom Processors

Create your own processor by implementing the `process` method:

```ruby
class MyCustomProcessor
  def process(span)
    # Send to your monitoring service
    MyMonitoringService.send_span(
      name: span.name,
      duration: span.duration_ms,
      metadata: span.metadata
    )
  end
end

tracer.add_processor(MyCustomProcessor.new)
```

## Span Types

- **agent** - Root span for agent execution
- **response** - LLM response generation
- **tool** - Tool function execution
- **handoff** - Agent handoff operations

## Performance Considerations

- Use sampling for high-volume applications
- Configure appropriate batch sizes for exporters
- Monitor processor performance impact
- Use async processors for production

## Development

After checking out the repo, run:

```bash
bundle install
bundle exec rspec
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for your changes
5. Ensure all tests pass (`bundle exec rspec`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).