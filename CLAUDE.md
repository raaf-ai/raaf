# Claude Code Guide for OpenAI Agents Ruby

This repository contains a comprehensive Ruby implementation of OpenAI Agents for building sophisticated multi-agent AI workflows. This guide will help you understand the codebase structure, common development patterns, and useful commands.

## Repository Overview

This is a Ruby gem that provides 100% feature parity with the Python OpenAI Agents library, plus additional enterprise-grade capabilities. The gem enables building multi-agent AI workflows with advanced features like voice interactions, guardrails, usage tracking, and comprehensive monitoring.

**CRITICAL**: This Ruby implementation now maintains **exact structural alignment** with the Python OpenAI Agents SDK, using identical APIs, endpoints, and tracing formats.

## Development Memories

- **ALWAYS** look at the Python implementation and keep as close as possible
- Ruby now uses OpenAI Responses API by default (matching Python)
- Agent spans are root spans with `parent_id: null` (matching Python exactly)
- Response spans are children of agent spans (matching Python hierarchy)
- All trace payloads are structurally identical to Python
- Use `ResponsesProvider` by default instead of `OpenAIProvider`

## Architecture Overview

### Core Components

- **Agent (`lib/openai_agents/agent.rb`)** - Main agent class with tools and handoff capabilities
- **Runner (`lib/openai_agents/runner.rb`)** - Executes agent conversations using ResponsesProvider by default
- **ResponsesProvider (`lib/openai_agents/models/responses_provider.rb`)** - **NEW DEFAULT** - Uses OpenAI Responses API matching Python
- **OpenAIProvider (`lib/openai_agents/models/openai_provider.rb`)** - Legacy Chat Completions API provider
- **FunctionTool (`lib/openai_agents/function_tool.rb`)** - Wraps Ruby methods/procs as agent tools
- **Tracing (`lib/openai_agents/tracing/`)** - Comprehensive span-based monitoring **exactly matching Python**
- **Logging (`lib/openai_agents/logging.rb`)** - Unified logging system with Rails integration and debug categories

### Key Development Patterns

### 1. Agent Creation Pattern (Updated)
```ruby
# Default pattern now uses ResponsesProvider (matching Python)
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o"  # Uses ResponsesProvider by default
)

# Explicit provider specification if needed
runner = OpenAIAgents::Runner.new(
  agent: agent,
  provider: OpenAIAgents::Models::ResponsesProvider.new  # Default
)

# IMPORTANT: For token usage tracking and cost management, use OpenAIProvider
# The ResponsesProvider (Responses API) doesn't return usage data
runner = OpenAIAgents::Runner.new(
  agent: agent,
  provider: OpenAIAgents::Models::OpenAIProvider.new  # Use for token tracking
)
```

### 2. Basic Usage Example
```ruby
require_relative 'lib/openai_agents'

# Create agent
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o"
)

# Run conversation (uses ResponsesProvider automatically)
runner = OpenAIAgents::Runner.new(agent: agent)
result = runner.run("Hello, tell me about Ruby programming.")

puts result.messages.last[:content]
```

### 3. Tool Integration Pattern
```ruby
def get_weather(location)
  "The weather in #{location} is sunny and 72°F"
end

agent.add_tool(method(:get_weather))
```

### 4. Tracing Pattern (Updated)
```ruby
# Tracing now matches Python structure exactly
tracer = OpenAIAgents::Tracing::SpanTracer.new
tracer.add_processor(OpenAIAgents::Tracing::OpenAIProcessor.new)
runner = OpenAIAgents::Runner.new(agent: agent, tracer: tracer)

# Generates identical traces to Python:
# - Agent span with parent_id: null (root)
# - Response span as child of agent span
# - Uses POST /v1/responses endpoint
```

### 5. Logging Pattern (New)
```ruby
# Include in your classes for short logging methods
class MyAgent
  include OpenAIAgents::Logger
  
  def process
    log_info("Processing started", agent: "MyAgent", task_id: 123)
    log_debug_api("API call details", url: "https://api.openai.com")
    log_debug_tracing("Span created", span_id: "abc123")
  end
end

# Direct logging
OpenAIAgents::Logging.info("Agent started", agent: "GPT-4", run_id: "123")
OpenAIAgents::Logging.debug("Tool called", tool: "search", category: :tools)
```

## File Structure

```
lib/openai_agents/
├── agent.rb                    # Core agent implementation
├── runner.rb                   # Agent execution engine (uses ResponsesProvider)
├── logging.rb                  # Unified logging system with Rails integration
├── models/                     # Multi-provider support
│   ├── responses_provider.rb   # NEW DEFAULT - OpenAI Responses API
│   ├── openai_provider.rb      # Legacy Chat Completions API
│   └── interface.rb
├── tracing/                    # Monitoring system (Python-aligned)
│   ├── openai_processor.rb     # Sends traces to OpenAI (Python format)
│   └── spans.rb
└── ...
```

## Common Commands

### Development Commands
```bash
# Basic example
ruby -e "
require_relative 'lib/openai_agents'
agent = OpenAIAgents::Agent.new(name: 'Assistant', instructions: 'Be helpful', model: 'gpt-4o')
runner = OpenAIAgents::Runner.new(agent: agent)
result = runner.run('Hello')
puts result.messages.last[:content]
"

# With debug logging
export OPENAI_AGENTS_LOG_LEVEL=debug
export OPENAI_AGENTS_DEBUG_CATEGORIES=api,tracing
ruby your_script.rb
```

### Environment Setup
```bash
# Required API key
export OPENAI_API_KEY="your-openai-key"

# Unified logging configuration
export OPENAI_AGENTS_LOG_LEVEL="info"        # debug, info, warn, error, fatal
export OPENAI_AGENTS_LOG_FORMAT="text"       # text, json
export OPENAI_AGENTS_LOG_OUTPUT="auto"       # auto, console, file, rails
export OPENAI_AGENTS_DEBUG_CATEGORIES="all"  # all, none, or comma-separated categories

# Debug categories available: tracing, api, tools, handoff, context, http, general
export OPENAI_AGENTS_DEBUG_CATEGORIES="tracing,api,http"  # Enable specific categories
```

## Key Differences from Legacy Implementation

### ✅ What Changed (Python Alignment)
1. **Default Provider**: Now uses `ResponsesProvider` instead of `OpenAIProvider`
2. **API Endpoint**: Uses `POST /v1/responses` instead of `POST /v1/chat/completions`
3. **Trace Structure**: Agent spans are root spans (`parent_id: null`)
4. **Span Format**: Includes `error: null` field matching Python
5. **Timestamps**: Microsecond precision with timezone (`+00:00`)

### 🔄 Migration Guide
```ruby
# OLD (Legacy)
runner = OpenAIAgents::Runner.new(
  agent: agent,
  provider: OpenAIAgents::Models::OpenAIProvider.new
)

# NEW (Python-aligned, now default)
runner = OpenAIAgents::Runner.new(agent: agent)
# Automatically uses ResponsesProvider
```

## Debugging and Validation

### Compare with Python
```ruby
# Ruby implementation now generates identical trace structure to:
# - Python OpenAI Agents SDK
# - Same span hierarchy (agent -> response)
# - Same field names and types
# - Same API endpoints

# Enable debug output to verify
ENV["OPENAI_AGENTS_DEBUG_CATEGORIES"] = "tracing,http"
```

### Logging System

The unified logging system automatically integrates with Rails when available and provides category-based debug filtering:

```ruby
# Configure logging
OpenAIAgents::Logging.configure do |config|
  config.log_level = :debug
  config.log_format = :json
  config.debug_categories = [:api, :tracing]
end

# Use in your classes
class MyProcessor
  include OpenAIAgents::Logger
  
  def process
    log_info("Processing started", processor: "MyProcessor")
    log_debug_api("API request", url: "https://api.openai.com")
    log_debug_tracing("Span created", span_id: "abc123")
  end
end
```

### Debug Categories

- **tracing**: Span lifecycle, trace processing
- **api**: API calls, responses, HTTP details
- **tools**: Tool execution, function calls
- **handoff**: Agent handoffs, delegation
- **context**: Context management, memory
- **http**: HTTP debug output (replaces OPENAI_AGENTS_TRACE_DEBUG)
- **general**: General debug messages

### Debug Tasks

```bash
# Show current debug configuration
rake debug:config

# Test all logging levels
rake debug:test_logging

# Test specific categories
rake debug:test_tracing

# Benchmark logging performance
rake debug:benchmark
```

### Trace Verification
The Ruby traces now match Python exactly:
- Trace object with workflow metadata
- Agent span as root (`parent_id: null`)
- Response span as child of agent
- Identical field structure and types

This ensures both implementations appear identically in OpenAI dashboard.