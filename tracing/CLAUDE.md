# RAAF Tracing - Claude Code Guide

This gem provides comprehensive tracing and monitoring for RAAF agents, with **exact Python SDK compatibility**.

## Quick Start

```ruby
require 'raaf-tracing'

# Create tracer
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)

# Add to runner
runner = RAAF::Runner.new(agent: agent, tracer: tracer)
result = runner.run("Hello!")
```

## Core Components

- **SpanTracer** - Main tracing coordinator
- **OpenAIProcessor** - Sends traces to OpenAI dashboard (Python format)
- **ConsoleProcessor** - Debug output to console
- **FileProcessor** - Save traces to file
- **ActiveRecordProcessor** - Rails database integration

## Trace Structure (Python-Compatible)

```json
{
  "trace": {
    "run_id": "run_abc123",
    "workflow": { "name": "Assistant", "version": "1.0.0" }
  },
  "spans": [
    {
      "span_id": "span_123",
      "parent_id": null,
      "name": "run.workflow.agent",
      "type": "agent",
      "error": null,
      "start_time": "2024-01-01T00:00:00.000000+00:00",
      "end_time": "2024-01-01T00:00:01.500000+00:00"
    }
  ]
}
```

## Processors

### OpenAI Dashboard
```ruby
tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)
```

### Console Debug
```ruby
tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new)
```

### File Storage
```ruby
tracer.add_processor(RAAF::Tracing::FileProcessor.new("traces.json"))
```

### Custom Processor
```ruby
class CustomProcessor
  def process(span)
    MyMonitoringService.send_span(span.to_h)
  end
end

tracer.add_processor(CustomProcessor.new)
```

## Rails Integration

```ruby
# In Rails application
class AgentController < ApplicationController
  def create
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(RAAF::Tracing::ActiveRecordProcessor.new)
    
    runner = RAAF::Runner.new(agent: agent, tracer: tracer)
    result = runner.run(params[:message])
  end
end
```

## Debug Categories

```bash
export RAAF_DEBUG_CATEGORIES="tracing,api"
```

Available categories:
- `tracing` - Span lifecycle, trace processing
- `api` - API calls and responses
- `tools` - Tool execution
- `handoff` - Agent handoffs
- `context` - Context management

## Comprehensive Documentation

**RAAF Tracing** includes extensive documentation for the coherent tracing system:

- **[Coherent Tracing Guide](COHERENT_TRACING_GUIDE.md)** - Complete guide with examples and integration patterns
- **[Troubleshooting Guide](TROUBLESHOOTING_TRACING.md)** - Debug common tracing issues and problems
- **[Performance Guide](PERFORMANCE_GUIDE.md)** - Optimization strategies for production environments
- **[Working Examples](examples/coherent_tracing_examples.rb)** - Real-world span hierarchy examples
- **[Integration Tests](spec/raaf/tracing/coherent_tracing_integration_spec.rb)** - Comprehensive test coverage

The coherent tracing system provides automatic span lifecycle management, proper hierarchy creation, duplicate prevention, and thread safety for production AI agent workflows.