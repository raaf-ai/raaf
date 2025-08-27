# RAAF Core - Claude Code Guide

This is the **core gem** of the Ruby AI Agents Factory (RAAF), providing the fundamental agent implementation and execution engine with **indifferent hash access** for seamless key handling.

## Quick Start

```ruby
require 'raaf-core'

# Create agent with default ResponsesProvider
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o"
)

# Run conversation - results support both string and symbol key access
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Hello!")

# Access with either key type - no more key confusion!
puts result.messages.last[:content]  # Symbol key access
puts result.messages.last["content"] # String key access (same result)
```

## Indifferent Hash Access

**RAAF Core eliminates string vs symbol key confusion** throughout the entire system:

```ruby
# All RAAF data structures support indifferent access
response = agent.run("Get weather data")

# These all work identically:
response[:output]         # ✅ Works
response["output"]        # ✅ Works  
response[:data][:weather] # ✅ Works
response["data"]["weather"] # ✅ Works

# No more dual access patterns needed:
# OLD: response[:key] || response["key"]  ❌ Error-prone
# NEW: response[:key]                     ✅ Always works
```

## Core Components

- **Agent** (`lib/raaf/agent.rb`) - Main agent class with tools and handoffs
- **Runner** (`lib/raaf/runner.rb`) - Execution engine (uses ResponsesProvider by default)  
- **IndifferentHash** (`lib/raaf/indifferent_hash.rb`) - **NEW** - Hash with flexible string/symbol key access
- **Utils** (`lib/raaf/utils.rb`) - **ENHANCED** - JSON parsing with indifferent access support
- **JsonRepair** (`lib/raaf/json_repair.rb`) - Fault-tolerant JSON parsing returning IndifferentHash
- **SchemaValidator** (`lib/raaf/schema_validator.rb`) - Schema validation with key normalization
- **AgentOutputSchema** (`lib/raaf/agent_output.rb`) - Output validation with indifferent access
- **ResponseProcessor** (`lib/raaf/response_processor.rb`) - **ENHANCED** - Processes responses with indifferent access
- **ModelInterface** (`lib/raaf/models/interface.rb`) - Base class with built-in retry logic
- **ResponsesProvider** (`lib/raaf/models/responses_provider.rb`) - **DEFAULT** - OpenAI Responses API with retry
- **OpenAIProvider** (`lib/raaf/models/openai_provider.rb`) - **DEPRECATED** - Legacy Chat Completions API
- **FunctionTool** (`lib/raaf/function_tool.rb`) - Tool wrapper for Ruby methods

## Key Patterns

### Indifferent Hash Access Patterns

```ruby
# JSON parsing returns IndifferentHash automatically
data = RAAF::Utils.parse_json('{"name": "John", "age": 30}')
data[:name]   # ✅ "John"
data["name"]  # ✅ "John"

# Tool arguments support both key types
def process_data(name:, age:, **options)
  "Processing #{name}, age #{age}"
end

agent.add_tool(method(:process_data))

# Agent responses have indifferent access
result = runner.run("Process data for John, age 30")
result[:output]         # ✅ Works
result["output"]        # ✅ Works
result.messages.last[:content]  # ✅ Works
result.messages.last["content"] # ✅ Works
```

### Converting Existing Hashes

```ruby
# Convert any hash to indifferent access
regular_hash = { "api_key" => "123", :model => "gpt-4o" }
indifferent = RAAF::Utils.indifferent_access(regular_hash)

indifferent[:api_key]   # ✅ "123" 
indifferent["api_key"]  # ✅ "123"
indifferent[:model]     # ✅ "gpt-4o"
indifferent["model"]    # ✅ "gpt-4o"
```

### Agent with Tools
```ruby
def get_weather(location)
  # Tool results automatically get indifferent access
  { 
    location: location,
    temperature: "72°F",
    "condition" => "sunny"  # Mixed keys work fine
  }
end

agent.add_tool(method(:get_weather))

# Both key types work in results
result = runner.run("What's the weather in Tokyo?")
weather = result[:tool_results].first
puts weather[:location]     # ✅ "Tokyo"
puts weather["condition"]   # ✅ "sunny"
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