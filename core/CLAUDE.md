# RAAF Core - Claude Code Guide

This is the **core gem** of the Ruby AI Agents Factory (RAAF), providing the fundamental agent implementation and execution engine.

## Quick Start

```ruby
require 'raaf-core'

# Create agent with default ResponsesProvider
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o"
)

# Or create with JSON repair and key normalization enabled
agent = RAAF::Agent.new(
  name: "FlexibleAssistant",
  instructions: "Extract data from user input.",
  model: "gpt-4o",
  json_repair: true,          # Handle malformed JSON automatically
  normalize_keys: true,       # Map "Full Name" to :full_name  
  validation_mode: :tolerant  # Flexible validation
)

# Run conversation
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Hello!")
puts result.messages.last[:content]
```

## Core Components

- **Agent** (`lib/raaf/agent.rb`) - Main agent class with tools and handoffs
- **Runner** (`lib/raaf/runner.rb`) - Execution engine (uses ResponsesProvider by default)
- **JsonRepair** (`lib/raaf/json_repair.rb`) - Fault-tolerant JSON parsing for LLM responses
- **SchemaValidator** (`lib/raaf/schema_validator.rb`) - Schema validation with key normalization
- **AgentOutputSchema** (`lib/raaf/agent_output.rb`) - Output validation with JSON repair integration
- **ModelInterface** (`lib/raaf/models/interface.rb`) - Base class with built-in retry logic
- **ResponsesProvider** (`lib/raaf/models/responses_provider.rb`) - **DEFAULT** - OpenAI Responses API with retry
- **OpenAIProvider** (`lib/raaf/models/openai_provider.rb`) - **DEPRECATED** - Legacy Chat Completions API
- **FunctionTool** (`lib/raaf/function_tool.rb`) - Tool wrapper for Ruby methods

## Key Patterns

### Agent with Tools
```ruby
def get_weather(location)
  "Weather in #{location}: sunny, 72°F"
end

agent.add_tool(method(:get_weather))
```

### Multi-Agent Handoff
```ruby
research_agent = RAAF::Agent.new(name: "Researcher", instructions: "Research topics")
writer_agent = RAAF::Agent.new(name: "Writer", instructions: "Write content")

# Handoff between agents
result = runner.run("Research and write about Ruby", agents: [research_agent, writer_agent])
```

### Built-in Retry Logic

All providers inherit robust retry logic from ModelInterface with exponential backoff:

```ruby
# Retry is built-in - no wrapper needed
agent = RAAF::Agent.new(name: "Assistant", model: "gpt-4o")
runner = RAAF::Runner.new(agent: agent)  # Uses ResponsesProvider with built-in retry

# Customize retry behavior
provider = RAAF::Models::ResponsesProvider.new
provider.configure_retry(max_attempts: 5, base_delay: 2.0, max_delay: 60.0)
runner = RAAF::Runner.new(agent: agent, provider: provider)
```

### Flexible Agent Identification

The core runner automatically normalizes agent identifiers:

```ruby
# Both Agent objects and string names work
research_agent.add_handoff(writer_agent)     # Agent object
research_agent.add_handoff("Writer")         # String name

# System handles conversion automatically - no type errors
```

## Environment Variables

```bash
export OPENAI_API_KEY="your-key"
export RAAF_LOG_LEVEL="info"
export RAAF_DEBUG_CATEGORIES="api,tracing"
```

## Development Commands

```bash
# Run tests
bundle exec rspec

# Run examples
ruby examples/basic_usage.rb

# Debug with detailed logging
RAAF_LOG_LEVEL=debug ruby your_script.rb
```

## Provider Selection Guide

**ResponsesProvider (Default)**: Automatically selected for OpenAI API compatibility with Python SDK features.

```ruby
# RECOMMENDED: Default behavior (no provider needed)
runner = RAAF::Runner.new(agent: agent)

# EXPLICIT: Manual ResponsesProvider configuration
provider = RAAF::Models::ResponsesProvider.new(
  api_key: ENV['OPENAI_API_KEY'],
  api_base: ENV['OPENAI_API_BASE']
)
runner = RAAF::Runner.new(agent: agent, provider: provider)
```

**Built-in Retry Logic**: All providers include robust retry handling through `ModelInterface`.

```ruby
# Retry is automatic - no additional configuration needed
agent = RAAF::Agent.new(name: "Assistant", model: "gpt-4o")
runner = RAAF::Runner.new(agent: agent)

# Customize retry behavior if needed
provider = RAAF::Models::ResponsesProvider.new
provider.configure_retry(max_attempts: 5, base_delay: 2.0)
runner = RAAF::Runner.new(agent: agent, provider: provider)
```