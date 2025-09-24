# RAAF Tracing

[![Gem Version](https://badge.fury.io/rb/raaf-tracing.svg)](https://badge.fury.io/rb/raaf-tracing)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Tracing** gem provides comprehensive distributed tracing and observability for the Ruby AI Agents Factory (RAAF) ecosystem. It offers span-based monitoring, performance analytics, and seamless integration with popular tracing and monitoring platforms.

## Overview

RAAF (Ruby AI Agents Factory) Tracing extends the core tracing capabilities from `raaf-core` to provide distributed tracing and monitoring for Ruby AI Agents Factory (RAAF). This gem provides comprehensive observability for AI agent workflows with support for multiple monitoring platforms.

## Features

- **🧠 Coherent Tracing System** - Intelligent span lifecycle management with automatic hierarchy creation
- **🌳 Smart Span Hierarchy** - Proper parent-child relationships across complex multi-agent workflows
- **🔄 Duplicate Prevention** - Automatic detection and prevention of duplicate spans
- **🔒 Thread Safety** - Independent trace contexts per thread with no shared mutable state
- **🎯 Component-Specific Attributes** - Rich metadata collection controlled by each component type
- **📊 Python SDK Compatibility** - Maintains exact structural alignment with OpenAI Agents Python SDK
- **🔌 Multiple Processors** - Send traces to OpenAI, Datadog, files, console, and more
- **📈 OpenTelemetry Integration** - Full OpenTelemetry support for enterprise monitoring
- **⚡ Performance Metrics** - Token usage, response times, and error tracking
- **🛠️ Custom Processors** - Easy to extend with your own monitoring solutions

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

### Coherent Tracing (Recommended)

The **Coherent Tracing System** provides automatic span management with smart hierarchy creation:

```ruby
require 'raaf-tracing'

# 1. Include Traceable in your components
class MyAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def initialize(name, parent_component: nil)
    @name = name
    @parent_component = parent_component
  end

  def run(message)
    with_tracing(:run) do
      process_message(message)
    end
  end

  # Define what data goes into spans
  def collect_span_attributes
    super.merge({
      "agent.name" => @name,
      "agent.model" => "gpt-4"
    })
  end
end

# 2. Create components with proper hierarchy
pipeline = MyPipeline.new(name: "DataPipeline")
agent = MyAgent.new("Assistant", parent_component: pipeline)

# 3. Execute - spans are automatically created with proper hierarchy
pipeline.execute do
  agent.run("Process this data")
end

# Traces are automatically sent to OpenAI dashboard
# View at: https://platform.openai.com/traces
```

### Traditional Usage

```ruby
require 'raaf-tracing'

# Create a tracer
tracer = RAAF::Tracing::SpanTracer.new

# Add processors
tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)
tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new)

# Use with agent
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are helpful"
)

runner = RAAF::Runner.new(agent: agent, tracer: tracer)
result = runner.run("Hello, world!")
```

### OpenTelemetry Integration

```ruby
require 'raaf-tracing'

# Setup OpenTelemetry
otel = RAAF::Tracing::OpenTelemetryIntegration.new(
  service_name: "my-ai-service",
  service_version: "1.0.0"
)
otel.setup_instrumentation

# Use with agent
agent = RAAF::Agent.new(name: "Assistant")
runner = RAAF::Runner.new(agent: agent, tracer: otel)
```

## Processors

### OpenAI Processor

Sends traces to OpenAI's monitoring dashboard:

```ruby
processor = RAAF::Tracing::OpenAIProcessor.new
tracer.add_processor(processor)
```

### Datadog Processor

Integrates with Datadog APM:

```ruby
processor = RAAF::Tracing::DatadogProcessor.new(
  service_name: "ai-agents-production",
  env: "production",
  version: "1.0.0"
)
tracer.add_processor(processor)
```

### Console Processor

Outputs traces to console for debugging:

```ruby
processor = RAAF::Tracing::ConsoleProcessor.new
tracer.add_processor(processor)
```

### File Processor

Saves traces to JSON files:

```ruby
processor = RAAF::Tracing::FileProcessor.new("traces.json")
tracer.add_processor(processor)
```

## Configuration

### Global Configuration

```ruby
RAAF::Tracing.configure do |config|
  config.enabled = true
  config.sample_rate = 0.1  # Sample 10% of traces
  config.max_spans_per_trace = 1000
  config.processors = [
    RAAF::Tracing::OpenAIProcessor.new,
    RAAF::Tracing::ConsoleProcessor.new
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

## Coherent Tracing Documentation

The coherent tracing system is extensively documented:

- **[Coherent Tracing Guide](COHERENT_TRACING_GUIDE.md)** - Complete guide to the coherent tracing system
- **[Coherent Tracing Examples](examples/coherent_tracing_examples.rb)** - Working examples of proper span hierarchies
- **[Troubleshooting Guide](TROUBLESHOOTING_TRACING.md)** - Debug common tracing issues
- **[Integration Tests](spec/raaf/tracing/coherent_tracing_integration_spec.rb)** - Comprehensive test suite

### Key Documentation Sections

- **Getting Started**: Basic setup and component integration
- **Span Hierarchy Examples**: Pipeline → Agent → Tool hierarchies
- **Component Integration**: Custom components, RAAF DSL agents, tools
- **Configuration**: Environment variables, processors, advanced options
- **Troubleshooting**: Common issues, debug tools, performance monitoring
- **Migration Guide**: Upgrading from manual span creation

### Example Hierarchies

The documentation includes real-world examples:
- Basic three-level hierarchy (Pipeline → Agent → Tool)
- Multi-agent parallel execution
- Nested pipeline architecture
- Complex multi-tool agents
- Error handling and recovery patterns

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/new-feature`)
3. Make your changes
4. Add tests for your changes
5. Ensure all tests pass (`bundle exec rspec`)
6. Commit your changes (`git commit -am 'Add new feature'`)
7. Push to the branch (`git push origin feature/new-feature`)
8. Open a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).