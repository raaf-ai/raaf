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

## Provider Requirements

**All providers used with RAAF must support tool/function calling.** Providers that don't support tool calling (like Ollama) have been removed to ensure consistent handoff behavior across all deployments.

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

**Important**: RAAF uses tool-based handoffs exclusively. Handoffs are implemented as function calls (tools) that the LLM must explicitly invoke. Text-based or JSON-based handoff detection in message content is not supported.

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
# This automatically creates transfer_to_<agent_name> tools
research_agent.add_handoff(writer_agent)

runner = RAAF::Runner.new(
  agent: research_agent,
  agents: [research_agent, writer_agent]
)

result = runner.run("Research and write about Ruby programming")
```

When you add a handoff target, RAAF automatically creates a tool like `transfer_to_writer` that the agent can call to transfer control. The LLM must explicitly call this tool - simply mentioning a transfer in text will not trigger a handoff.

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

### DSL Usage with Automatic Context

RAAF DSL agents now provide automatic context access, eliminating manual context building:

```ruby
# Modern DSL agent with automatic context
class WebSearchAgent < RAAF::DSL::Agent
  instructions "Help users search the web for #{query}"
  model "gpt-4o"
  
  # Automatic access to context variables like :query
  def search_results
    "Searching for: #{query}"  # Direct context access
  end
end

# Usage with automatic context injection
agent = WebSearchAgent.new(query: "Ruby news")
result = agent.run
```

### Pipeline DSL for Agent Chaining

Use the elegant Pipeline DSL for chaining agents with `>>` (sequential) and `|` (parallel):

```ruby
class DataProcessingPipeline < RAAF::Pipeline
  flow DataAnalyzer >> ReportGenerator
  
  context do
    default :format_type, "json"
  end
end

# 3-line pipeline replaces 66+ line traditional approaches
pipeline = DataProcessingPipeline.new(data: raw_data)
result = pipeline.run
```

### Modern Agent and Service Architecture

RAAF now uses a unified Agent and Service pattern with automatic context handling:

```ruby
# Modern service with automatic context
class ResearchService < RAAF::DSL::Service
  def call
    case action
    when :analyze then analyze_research
    when :summarize then create_summary
    end
  end
  
  private
  
  def analyze_research
    # Direct access to context variables without manual building
    success_result(analysis: "Research on #{topic} completed")
  end
end

# Agent using the new architecture
class ResearchAgent < RAAF::DSL::Agent
  instructions "Research #{topic} with #{depth} analysis"
  model "gpt-4o"
  
  # Context automatically available, no manual context.set() calls needed
  def research_prompt
    "Analyze #{topic} at #{depth} level in #{language || 'English'}"
  end
end

# Usage with automatic context injection
agent = ResearchAgent.new(topic: "AI", depth: "comprehensive")
result = agent.run
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
require 'raaf'
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

## Best Practices and Current Standards

**Default Provider**: RAAF automatically uses `ResponsesProvider` for OpenAI API compatibility with the Python SDK.

```ruby
# RECOMMENDED: Let RAAF use the default ResponsesProvider
runner = RAAF::Runner.new(agent: agent)  # Uses ResponsesProvider automatically

# EXPLICIT: Specify ResponsesProvider if needed
provider = RAAF::Models::ResponsesProvider.new(api_key: ENV['OPENAI_API_KEY'])
runner = RAAF::Runner.new(agent: agent, provider: provider)

# LEGACY: OpenAIProvider (still supported but not recommended)
# provider = RAAF::Models::OpenAIProvider.new
# runner = RAAF::Runner.new(agent: agent, provider: provider)
```

For detailed gem-specific documentation, see the individual `CLAUDE.md` files in each gem directory.