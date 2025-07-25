# RAAF Core

[![🚀 Core CI](https://github.com/raaf-ai/raaf/actions/workflows/core-ci.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/core-ci.yml)
[![⚡ Quick Check](https://github.com/raaf-ai/raaf/actions/workflows/core-quick-check.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/core-quick-check.yml)
[![🌙 Nightly](https://github.com/raaf-ai/raaf/actions/workflows/core-nightly.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/core-nightly.yml)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%203.2-ruby.svg)](https://www.ruby-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Core** gem provides the foundational agent implementation and execution engine for the Ruby AI Agents Factory (RAAF). This is the core gem that enables creating and running AI agents with multi-agent handoffs, tool integration, and structured output capabilities.

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

# Create an agent with default ResponsesProvider
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
  name: "CustomerSupport",
  instructions: "You help customers with their questions",
  model: "gpt-4o"
)
```

### Runner  
The execution engine that handles agent conversations, tool calls, and multi-agent handoffs.

```ruby
runner = RAAF::Runner.new(agent: agent)
result = runner.run("What services do you offer?")
```

### FunctionTool
Framework for integrating custom tools and functions into agents.

```ruby
def get_weather(city:)
  "The weather in #{city} is sunny and 22°C"
end

agent.add_tool(method(:get_weather))
```

### Built-in Retry Logic
All providers inherit robust retry logic from ModelInterface with exponential backoff.

```ruby
# Retry is built-in - no wrapper needed
agent = RAAF::Agent.new(name: "Assistant", model: "gpt-4o")
runner = RAAF::Runner.new(agent: agent)

# Customize retry behavior
provider = RAAF::Models::ResponsesProvider.new
provider.configure_retry(max_attempts: 5, base_delay: 2.0, max_delay: 60.0)
runner = RAAF::Runner.new(agent: agent, provider: provider)
```

### Default Providers
RAAF Core includes OpenAI providers with built-in retry:

- **ResponsesProvider** (default) - Modern OpenAI Responses API with retry
- **OpenAIProvider** (deprecated) - Legacy Chat Completions API

```ruby
# Using default ResponsesProvider (recommended)
runner = RAAF::Runner.new(agent: agent)

# Using legacy OpenAIProvider (deprecated)
runner = RAAF::Runner.new(
  agent: agent,
  provider: RAAF::Models::OpenAIProvider.new
)
```

## Multi-Agent Handoffs

Create specialized agents that can hand off conversations to each other:

```ruby
# Create specialized agents
research_agent = RAAF::Agent.new(
  name: "Researcher",
  instructions: "Research topics thoroughly",
  model: "gpt-4o"
)

writer_agent = RAAF::Agent.new(
  name: "Writer",
  instructions: "Write compelling content", 
  model: "gpt-4o"
)

# Enable handoffs between agents
research_agent.add_handoff(writer_agent)

# Run with multiple agents
runner = RAAF::Runner.new(
  agent: research_agent,
  agents: [research_agent, writer_agent]
)

result = runner.run("Research and write about Ruby programming")
```

## Structured Output

Define and validate structured responses using JSON schemas:

```ruby
# Define a schema
schema = RAAF::StructuredOutput::ObjectSchema.build do
  string :name, required: true
  number :price, minimum: 0
  array :features, items: { type: "string" }
  boolean :in_stock, required: true
end

# Use with agent (requires API key)
agent = RAAF::Agent.new(
  name: "ProductAgent",
  instructions: "Generate product information",
  model: "gpt-4o"
)

# Schema validation happens automatically
result = runner.run("Create product info for iPhone", schema: schema)
```

## Configuration

### Environment Variables

```bash
export OPENAI_API_KEY="your-openai-api-key"
export RAAF_LOG_LEVEL="info"
export RAAF_DEBUG_CATEGORIES="api,tracing"
```

### Production Configuration

```ruby
# Create a configuration management system
class ProductionConfig
  def openai_api_key
    ENV.fetch('OPENAI_API_KEY')
  end
  
  def retry_max_attempts
    ENV.fetch('RETRY_MAX_ATTEMPTS', '5').to_i
  end
end

config = ProductionConfig.new

# Configure provider
provider = RAAF::Models::ResponsesProvider.new(api_key: config.openai_api_key)
provider.configure_retry(max_attempts: config.retry_max_attempts)

agent = RAAF::Agent.new(name: "Production", model: "gpt-4o")
runner = RAAF::Runner.new(agent: agent, provider: provider)
```

## Architecture

### Key Classes

- **`RAAF::Agent`** - Main agent class with tools and handoffs
- **`RAAF::Runner`** - Execution engine (uses ResponsesProvider by default)
- **`RAAF::Models::ModelInterface`** - Base class with built-in retry logic
- **`RAAF::Models::ResponsesProvider`** - Modern OpenAI Responses API with retry
- **`RAAF::FunctionTool`** - Tool wrapper for Ruby methods
- **`RAAF::StructuredOutput`** - JSON schema validation system

### Provider Architecture

All providers inherit from `ModelInterface` which provides:

- ✅ **Built-in retry logic** with exponential backoff
- ✅ **Automatic error handling** for common network issues  
- ✅ **Responses API compatibility** for Python SDK parity
- ✅ **Tool calling support** for multi-agent handoffs
- ✅ **Configurable retry behavior**

### Agent Lifecycle

1. **Agent Creation** - Define name, instructions, model
2. **Tool Registration** - Add custom functions via `add_tool`
3. **Handoff Configuration** - Enable agent-to-agent transfers
4. **Execution** - Runner orchestrates conversation flow
5. **Response Processing** - Extract messages, handle tool calls

## Examples

See the `examples/` directory for comprehensive examples:

- **`basic_example.rb`** - Simple agent setup and conversation
- **`multi_agent_example.rb`** - Multi-agent collaboration with handoffs
- **`structured_output_example.rb`** - JSON schema validation
- **`configuration_example.rb`** - Production configuration patterns

Run examples:

```bash
# Set API key
export OPENAI_API_KEY="your-key"

# Run examples
ruby examples/basic_example.rb
ruby examples/multi_agent_example.rb
```

## Development

After checking out the repo:

```bash
bundle install
bundle exec rspec
```

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test categories  
bundle exec rspec spec/models/
bundle exec rspec --tag integration
```

### Validation

Examples are automatically validated in CI:

```bash
# Validate all examples
ruby scripts/validate_examples.rb

# Test mode (no API key needed)
RAAF_TEST_MODE=true ruby scripts/validate_examples.rb
```

## Documentation

- **[LLM Compatibility](LLM_COMPATIBILITY_MATRIX.md)** - Supported models and provider information
- **[Handoff Implementation](UNIVERSAL_HANDOFF_IMPLEMENTATION_PLAN.md)** - Technical details on agent handoffs
- **[Unified Processing](UNIFIED_PROCESSING.md)** - Internal step processing system
- **[CI Testing](CI_TESTING.md)** - Example validation and testing without API keys
- **[Contributing](CONTRIBUTING.md)** - Guidelines for contributing to the project

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/raaf-ai/ruby-ai-agents-factory.

## License

This gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).