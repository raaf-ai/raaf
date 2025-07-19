# Ruby AI Agents Factory (RAAF) - Claude Code Guide

**RAAF** is a comprehensive Ruby implementation of AI Agents with 100% Python OpenAI Agents SDK feature parity, plus enterprise-grade capabilities for building sophisticated multi-agent workflows.

## Quick Start

```ruby
require 'raaf'

agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant",
  model: "gpt-4o"
)

runner = RAAF::Runner.new(agent: agent)
result = runner.run("Hello!")
puts result.messages.last[:content]
```

## Architecture Overview

RAAF is organized as a **mono-repo** with focused gems:

- **[core/](core/)** - Core agent implementation and execution engine
- **[tracing/](tracing/)** - Comprehensive monitoring with Python SDK compatibility  
- **[memory/](memory/)** - Context persistence and vector storage
- **[tools/](tools/)** - Pre-built tools (web search, files, code execution)
- **[guardrails/](guardrails/)** - Security and safety filters
- **[providers/](providers/)** - Multi-provider support (OpenAI, Anthropic, Groq, etc.)
- **[dsl/](dsl/)** - Ruby DSL for declarative agent building
- **[rails/](rails/)** - Rails integration with dashboard
- **[streaming/](streaming/)** - Real-time and async capabilities

## Critical Alignment Notes

**ALWAYS maintain Python SDK compatibility:**
- Uses OpenAI Responses API by default (not Chat Completions)
- Agent spans are root spans (`parent_id: null`)
- Response spans are children of agent spans
- Identical trace payloads and field structures
- Use `ResponsesProvider` as default (not `OpenAIProvider`)

## Development Patterns

### Basic Agent with Tools
```ruby
# Create agent
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant",
  model: "gpt-4o"
)

# Add tools
def get_weather(location)
  "Weather in #{location}: sunny, 72°F"
end

agent.add_tool(method(:get_weather))

# Run conversation
runner = RAAF::Runner.new(agent: agent)
result = runner.run("What's the weather in Tokyo?")
```

### Multi-Agent Handoff
```ruby
# Define specialized agents
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
runner = RAAF::Runner.new(
  agent: research_agent,
  agents: [research_agent, writer_agent]
)

result = runner.run("Research and write about Ruby programming")
```

### Flexible Agent Identification

RAAF automatically normalizes agent identifiers, accepting both Agent objects and string names:

```ruby
# Both approaches work seamlessly:
agent1 = RAAF::Agent.new(name: "SupportAgent")
agent2 = RAAF::Agent.new(name: "TechAgent")

# Add handoffs using Agent objects
agent1.add_handoff(agent2)

# Or using string names - both are equivalent
agent1.add_handoff("TechAgent")

# The system automatically converts Agent objects to names internally
# No need to worry about type mismatches
```

### Tracing and Monitoring
```ruby
# Set up comprehensive tracing
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)  # Send to OpenAI dashboard
tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new) # Debug output

runner = RAAF::Runner.new(agent: agent, tracer: tracer)
result = runner.run("Hello")

# Traces are automatically sent with Python SDK compatible format
```

### DSL Usage
```ruby
# Build agents declaratively
agent = RAAF::DSL::AgentBuilder.build do
  name "WebSearchAgent"
  instructions "Help users search the web"
  model "gpt-4o"
  
  use_web_search
  use_file_search
  
  tool :analyze_sentiment do |text|
    { sentiment: "positive", confidence: 0.85 }
  end
end

result = agent.run("Search for Ruby news")
```

### Prompt Management (PREFERRED: Ruby Prompts)

RAAF DSL provides a flexible prompt resolution system. **Always prefer Ruby prompt classes over Markdown files** for better type safety, testability, and IDE support:

```ruby
# PREFERRED: Ruby prompt class with validation
class ResearchPrompt < RAAF::DSL::Prompts::Base
  requires :topic, :depth
  optional :language, default: "English"
  
  def system
    "You are a research assistant specializing in #{@topic}."
  end
  
  def user
    "Provide #{@depth} analysis in #{@language}."
  end
end

# Use in agent
agent = RAAF::DSL::AgentBuilder.build do
  name "Researcher"
  prompt ResearchPrompt  # Type-safe, testable
  model "gpt-4o"
end

# Alternative formats (less preferred):
# prompt "research.md"      # Simple markdown
# prompt "analysis.md.erb"  # ERB template
```

## Environment Variables

```bash
export OPENAI_API_KEY="your-openai-key"
export RAAF_LOG_LEVEL="info"
export RAAF_DEBUG_CATEGORIES="api,tracing"
```

> 📋 **Complete Reference**: See **[ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md)** for a comprehensive list of all environment variables, their functions, formats, and examples.

## Development Commands

```bash
# Run basic example
ruby -e "
require_relative 'lib/raaf'
agent = RAAF::Agent.new(name: 'Assistant', instructions: 'Be helpful')
runner = RAAF::Runner.new(agent: agent)
puts runner.run('Hello').messages.last[:content]
"

# Run with debug logging
RAAF_LOG_LEVEL=debug ruby your_script.rb

# Run tests for specific gem
cd core && bundle exec rspec
cd tracing && bundle exec rspec
```

## Migration from Legacy

```ruby
# OLD (deprecated)
runner = RAAF::Runner.new(
  agent: agent,
  provider: RAAF::Models::OpenAIProvider.new  # DEPRECATED
)

# NEW (recommended)
runner = RAAF::Runner.new(agent: agent)  # Uses ResponsesProvider by default
```

For detailed gem-specific documentation, see the individual `CLAUDE.md` files in each gem directory.