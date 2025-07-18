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

# Run conversation
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Hello!")
puts result.messages.last[:content]
```

## Core Components

- **Agent** (`lib/raaf/agent.rb`) - Main agent class with tools and handoffs
- **Runner** (`lib/raaf/runner.rb`) - Execution engine (uses ResponsesProvider by default)
- **ResponsesProvider** (`lib/raaf/models/responses_provider.rb`) - **DEFAULT** - OpenAI Responses API
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

## Migration from Legacy

```ruby
# OLD (deprecated)
provider = RAAF::Models::OpenAIProvider.new
runner = RAAF::Runner.new(agent: agent, provider: provider)

# NEW (recommended)
runner = RAAF::Runner.new(agent: agent)  # Uses ResponsesProvider by default
```