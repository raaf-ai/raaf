# Claude Code Guide for Ruby AI Agents Factory

This repository contains a comprehensive Ruby implementation of AI Agents for building sophisticated multi-agent AI workflows. This guide will help you understand the codebase structure, common development patterns, and useful commands.

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
- **ResponsesProvider (`lib/openai_agents/models/responses_provider.rb`)** - **RECOMMENDED DEFAULT** - Uses OpenAI Responses API matching Python
- **OpenAIProvider (`lib/openai_agents/models/openai_provider.rb`)** - **DEPRECATED** - Legacy Chat Completions API provider (do not modify)
- **FunctionTool (`lib/openai_agents/function_tool.rb`)** - Wraps Ruby methods/procs as agent tools
- **Tracing (`lib/openai_agents/tracing/`)** - Comprehensive span-based monitoring **exactly matching Python**
- **Logging (`lib/openai_agents/logging.rb`)** - Unified logging system with Rails integration and debug categories

### Key Development Patterns

### 1. Agent Creation Pattern (Updated)
```ruby
# WHAT: Creating an OpenAI Agent with ResponsesProvider (recommended)
# WHY: The Ruby implementation now defaults to ResponsesProvider for Python compatibility
# HOW: Agent instances are created with name, instructions, and model parameters

# ✅ RECOMMENDED: Default pattern uses ResponsesProvider (matching Python implementation)
# This is the recommended approach for all new applications
agent = RubyAIAgentsFactory::Agent.new(
  name: "Assistant",                               # Agent identifier for handoffs and tracing
  instructions: "You are a helpful assistant.",    # System prompt defining agent behavior
  model: "gpt-4o"                                 # OpenAI model (defaults to ResponsesProvider)
)

# ✅ RECOMMENDED: Explicit ResponsesProvider (same as default)
# ResponsesProvider: Modern API, better features, Python-compatible, WITH usage data
runner = RubyAIAgentsFactory::Runner.new(
  agent: agent,
  provider: RubyAIAgentsFactory::Models::ResponsesProvider.new  # Explicitly set (though it's default)
)

# ✅ RECOMMENDED: Token usage tracking with ResponsesProvider
# ResponsesProvider: Default provider with detailed usage data
# Provides: {input_tokens, output_tokens, total_tokens, input_tokens_details, output_tokens_details}
runner = RubyAIAgentsFactory::Runner.new(agent: agent)  # Default ResponsesProvider includes usage data

# ⚠️ DEPRECATED: OpenAIProvider - Legacy Chat Completions API 
# DEPRECATED: Use ResponsesProvider instead (it's the default)
# Only kept for backwards compatibility and streaming support
# Provides: {prompt_tokens, completion_tokens, total_tokens}
runner = RubyAIAgentsFactory::Runner.new(
  agent: agent,
  provider: RubyAIAgentsFactory::Models::OpenAIProvider.new  # DEPRECATED - will show warning
)
```

### 2. Basic Usage Example
```ruby
# WHAT: Complete example showing how to create and run a basic agent conversation
# WHY: Demonstrates the simplest way to get started with OpenAI Agents in Ruby
# HOW: Load library, create agent, run conversation, and display response

# Load the OpenAI Agents library
# Use require 'openai_agents' if installed as a gem
require_relative 'lib/openai_agents'

# Create an agent instance with basic configuration
# The agent encapsulates the AI's personality and capabilities
agent = RubyAIAgentsFactory::Agent.new(
  name: "Assistant",                             # Used in multi-agent scenarios for identification
  instructions: "You are a helpful assistant.",  # Defines the agent's behavior and personality
  model: "gpt-4o"                               # Latest GPT-4 model with optimized performance
)

# Create a runner to execute conversations
# Runner handles the conversation loop, tool calls, and response streaming
# By default, uses ResponsesProvider for Python compatibility
runner = RubyAIAgentsFactory::Runner.new(agent: agent)

# Execute a single conversation turn
# Returns a Result object containing messages and metadata
result = runner.run("Hello, tell me about Ruby programming.")

# Extract and display the assistant's response
# result.messages is an array of message hashes with :role and :content
puts result.messages.last[:content]

# The result object also contains:
# - result.messages: Full conversation history
# - result.usage: Token usage data (available with both providers)
# - result.metadata: Additional response metadata
```

### 3. Tool Integration Pattern
```ruby
# WHAT: Adding custom tools (functions) to agents for extended capabilities
# WHY: Tools allow agents to perform actions beyond text generation (API calls, calculations, etc.)
# HOW: Define Ruby methods and add them to agents using FunctionTool wrapper

# Define a tool as a regular Ruby method
# The method signature and parameter names are automatically extracted
def get_weather(location)
  # In production, this would call a real weather API
  # For demo purposes, we return mock data
  "The weather in #{location} is sunny and 72°F"
end

# Method 1: Add tool using Ruby's method() function
# This automatically creates a FunctionTool with proper metadata
agent.add_tool(method(:get_weather))

# Method 2: Define tools with more control using FunctionTool directly
weather_tool = RubyAIAgentsFactory::FunctionTool.new(
  name: "get_weather",                                    # Tool name the AI will use
  description: "Get current weather for a location",      # Helps AI understand when to use it
  parameters: {                                           # JSON Schema for parameters
    type: "object",
    properties: {
      location: {
        type: "string",
        description: "City name or location"
      }
    },
    required: ["location"]
    
  }
) do |location:|                                          # Block receives named parameters
  # Tool implementation
  "The weather in #{location} is sunny and 72°F"
end

agent.add_tool(weather_tool)

# Method 3: Add multiple tools at once
def calculate_distance(from:, to:)
  # Mock calculation
  "Distance from #{from} to #{to} is 150 miles"
end

def search_web(query:)
  # Mock web search
  "Search results for '#{query}': [Result 1, Result 2, Result 3]"
end

# Add multiple tools efficiently
agent.add_tool(method(:calculate_distance))
agent.add_tool(method(:search_web))

# Now the agent can use these tools in conversations:
# User: "What's the weather in Tokyo?"
# Agent: [Calls get_weather(location: "Tokyo")]
# Agent: "The weather in Tokyo is sunny and 72°F"
```

### 4. Tracing Pattern (Updated)
```ruby
# WHAT: Implementing distributed tracing for agent execution monitoring
# WHY: Track performance, debug issues, and maintain Python SDK compatibility
# HOW: Use SpanTracer with processors to collect and send trace data

# Create a span tracer instance
# This collects timing and execution data for each agent interaction
tracer = RubyAIAgentsFactory::Tracing::SpanTracer.new

# Add OpenAI processor to send traces to OpenAI's monitoring dashboard
# This enables viewing agent performance in the OpenAI platform
tracer.add_processor(RubyAIAgentsFactory::Tracing::OpenAIProcessor.new)

# Attach tracer to runner for automatic span creation
runner = RubyAIAgentsFactory::Runner.new(agent: agent, tracer: tracer)

# Advanced: Add multiple processors for different destinations
console_processor = RubyAIAgentsFactory::Tracing::ConsoleProcessor.new    # Logs to console
file_processor = RubyAIAgentsFactory::Tracing::FileProcessor.new("traces.json")  # Saves to file

tracer.add_processor(console_processor)
tracer.add_processor(file_processor)

# Custom processor example for your own monitoring system
class CustomProcessor
  def process(span)
    # Send to your monitoring service (e.g., DataDog, New Relic)
    MyMonitoringService.send_span(
      name: span.name,
      duration: span.duration_ms,
      metadata: span.metadata
    )
  end
end

tracer.add_processor(CustomProcessor.new)

# Trace structure matches Python SDK exactly:
# {
#   "trace": {
#     "run_id": "run_abc123",
#     "workflow": { "name": "Assistant", "version": "1.0.0" }
#   },
#   "spans": [
#     {
#       "span_id": "span_123",
#       "parent_id": null,              # Agent spans are always root (null parent)
#       "name": "run.workflow.agent",
#       "type": "agent",
#       "error": null,                  # Always included for Python compatibility
#       "start_time": "2024-01-01T00:00:00.000000+00:00",  # Microsecond precision
#       "end_time": "2024-01-01T00:00:01.500000+00:00"
#     },
#     {
#       "span_id": "span_456",
#       "parent_id": "span_123",        # Response spans are children of agent spans
#       "name": "run.workflow.agent.response",
#       "type": "response",
#       "model": "gpt-4o",
#       "provider": "responses"         # Uses POST /v1/responses endpoint
#     }
#   ]
# }
```

### 5. Logging Pattern (New)
```ruby
# WHAT: Unified logging system with Rails integration and debug categories
# WHY: Provides consistent logging across the gem with fine-grained control
# HOW: Use Logger mixin for convenience methods or Logging module directly

# Method 1: Include Logger mixin in your classes for convenience methods
class MyAgent
  include RubyAIAgentsFactory::Logger  # Provides log_* instance methods
  
  def process
    # log_info: General information messages
    log_info("Processing started", agent: "MyAgent", task_id: 123)
    
    # log_debug_*: Category-specific debug messages (only shown when category enabled)
    log_debug_api("API call details", url: "https://api.openai.com", method: "POST")
    log_debug_tracing("Span created", span_id: "abc123", parent_id: "xyz789")
    log_debug_tools("Tool executed", tool: "get_weather", result: "success")
    
    # log_error: Error messages with exception details
    begin
      risky_operation
    rescue => e
      log_error("Processing failed", error: e, agent: "MyAgent")
    end
  end
end

# Method 2: Direct logging using the Logging module
# Use when you don't want to include the mixin
RubyAIAgentsFactory::Logging.info("Agent started", agent: "GPT-4", run_id: "123")
RubyAIAgentsFactory::Logging.debug("Tool called", tool: "search", category: :tools)
RubyAIAgentsFactory::Logging.warn("Rate limit approaching", requests_remaining: 10)
RubyAIAgentsFactory::Logging.error("API error", status: 429, message: "Rate limited")

# Configure logging programmatically
RubyAIAgentsFactory::Logging.configure do |config|
  config.log_level = :debug                        # :debug, :info, :warn, :error, :fatal
  config.log_format = :json                        # :text or :json
  config.log_output = :rails                       # :console, :file, :rails, :auto
  config.debug_categories = [:api, :tracing]       # Enable specific debug categories
end

# Debug categories control which debug messages are shown:
# - :tracing - Span lifecycle, trace processing
# - :api - API calls, responses, HTTP details  
# - :tools - Tool execution, function calls
# - :handoff - Agent handoffs, delegation
# - :context - Context management, memory
# - :http - HTTP debug output
# - :general - General debug messages
# - :all - Enable all categories
# - :none - Disable all debug output

# Rails integration example
# When Rails is detected, logs automatically go to Rails.logger
class AgentController < ApplicationController
  include RubyAIAgentsFactory::Logger
  
  def create
    log_info("Creating agent", params: agent_params)
    agent = RubyAIAgentsFactory::Agent.new(agent_params)
    log_debug_api("Agent created", agent_id: agent.id)
  end
end

# Structured logging with JSON format produces:
# {
#   "timestamp": "2024-01-01T00:00:00.000Z",
#   "level": "INFO",
#   "message": "Processing started",
#   "context": {
#     "agent": "MyAgent",
#     "task_id": 123
#   }
# }
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
agent = RubyAIAgentsFactory::Agent.new(name: 'Assistant', instructions: 'Be helpful', model: 'gpt-4o')
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
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
6. **Usage Data**: Now available from both providers (ResponsesProvider is recommended)

### 🔄 Migration Guide
```ruby
# OLD (Legacy - DEPRECATED)
runner = RubyAIAgentsFactory::Runner.new(
  agent: agent,
  provider: RubyAIAgentsFactory::Models::OpenAIProvider.new  # DEPRECATED - will show warning
)

# ✅ NEW (Python-aligned, recommended)
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
# Automatically uses ResponsesProvider with usage data
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
RubyAIAgentsFactory::Logging.configure do |config|
  config.log_level = :debug
  config.log_format = :json
  config.debug_categories = [:api, :tracing]
end

# Use in your classes
class MyProcessor
  include RubyAIAgentsFactory::Logger
  
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