# RAAF Core

[![Gem Version](https://badge.fury.io/rb/raaf-core.svg)](https://badge.fury.io/rb/raaf-core)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Core** gem provides the foundational components for the Ruby AI Agents Factory (RAAF) ecosystem. This gem contains the essential building blocks that all other RAAF gems depend on, including base classes, interfaces, utilities, and core abstractions.

## Overview

RAAF (Ruby AI Agents Factory) Core serves as the foundation layer for the entire Ruby AI Agents Factory mono-repo. It provides:

- **Base Agent Classes** - Abstract base classes for all AI agents
- **Core Interfaces** - Standard interfaces for providers, tools, and components
- **Utility Classes** - Common utilities used across the ecosystem
- **Configuration Management** - Base configuration handling
- **Error Handling** - Standardized exception classes
- **Type System** - Ruby type definitions and validation

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-core'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install raaf-core
```

## Quick Start

```ruby
require 'raaf-core'

# Create an agent
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant",
  model: "gpt-4o"
)

# Run the agent
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Hello, how can you help me?")

# Get the response
puts result.messages.last[:content]
```

## Core Components

### Agent
The main class for creating AI agents with specific instructions and capabilities.

```ruby
agent = RAAF::Agent.new(
  name: "Customer Support",
  instructions: "You help customers with their questions",
  model: "gpt-4o",
  max_turns: 10
)
```

### Runner  
The execution engine that handles agent conversations, tool calls, and response processing.

```ruby
runner = RAAF::Runner.new(agent: agent)
result = runner.run("What services do you offer?")
```

### FunctionTool
Framework for integrating custom tools and functions into agents.

```ruby
def get_weather(city)
  "The weather in #{city} is sunny and 22°C"
end

agent.add_tool(method(:get_weather))
```

### Default Providers
RAAF Core includes two OpenAI providers:

- **ResponsesProvider** (default) - Modern OpenAI Responses API
- **OpenAIProvider** - Legacy Chat Completions API

```ruby
# Using default ResponsesProvider
runner = RAAF::Runner.new(agent: agent)

# Using legacy OpenAIProvider explicitly
runner = RAAF::Runner.new(
  agent: agent,
  provider: RAAF::Models::OpenAIProvider.new
)
```

## Configuration

Set your OpenAI API key:

```bash
export OPENAI_API_KEY="your-openai-api-key"
```

## Relationship with Other Gems

### Direct Dependencies

RAAF Core is the foundation that **all other gems** depend on:

- **raaf-logging** - Extends core logging capabilities
- **raaf-configuration** - Builds on core config management
- **raaf-providers** - Implements provider interfaces
- **raaf-dsl** - Uses core agent classes for DSL
- **raaf-tools-basic** - Extends core tool system
- **raaf-tools-advanced** - Advanced tools using core interfaces

### Core Abstractions Used By

- **raaf-tracing** - Uses core agent lifecycle hooks
- **raaf-memory** - Implements memory interfaces defined in core
- **raaf-rails** - Integrates core agents with Rails
- **raaf-guardrails** - Validates using core validation system
- **raaf-testing** - Tests core agent functionality
- **raaf-streaming** - Extends core response handling

### Enterprise Integration

- **raaf-compliance** - Uses core audit interfaces
- **raaf-security** - Implements core security abstractions
- **raaf-monitoring** - Monitors core agent metrics
- **raaf-analytics** - Analyzes core agent performance
- **raaf-deployment** - Deploys core agent systems

## Architecture

### Core Classes

```
RAAF::Core::
├── Agent                    # Base agent class
├── Provider                 # LLM provider interface
├── Tool                     # Agent tool interface
├── Message                  # Message handling
├── Response                 # Response objects
├── Configuration            # Configuration management
├── Logger                   # Logging interface
├── Error                    # Exception hierarchy
└── Utils                    # Common utilities
```

### Extension Points

The core gem provides several extension points:

1. **Agent Lifecycle Hooks** - Before/after execution callbacks
2. **Provider Interface** - Custom LLM provider implementations
3. **Tool Interface** - Custom agent tools
4. **Middleware System** - Request/response processing
5. **Configuration Extensions** - Custom configuration options

## Advanced Features

### Middleware System

```ruby
# Custom middleware for request processing
class LoggingMiddleware < RAAF::Core::Middleware
  def call(request, response)
    logger.info "Processing: #{request.input}"
    yield
    logger.info "Response: #{response.content}"
  end
end

agent.use(LoggingMiddleware)
```

### Plugin Architecture

```ruby
# Register custom plugins
RAAF::Core::PluginManager.register(:custom_feature) do |agent|
  agent.extend(CustomFeature)
end
```

## Development

After checking out the repo, run:

```bash
bundle install
bundle exec rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/raaf-ai/ruby-ai-agents-factory.

## License

This gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).