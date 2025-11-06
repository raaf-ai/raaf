# Ruby AI Agents Factory (RAAF) - Claude Code Guide

**RAAF** is a comprehensive Ruby implementation of AI Agents with 100% Python OpenAI Agents SDK feature parity, plus enterprise-grade capabilities for building sophisticated multi-agent workflows. **RAAF eliminates hash key confusion** with indifferent access throughout the entire system.

## Quick Start

```ruby
require 'raaf'

agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant",
  model: "gpt-4o"  # Also supports: gpt-5, o1-preview, o1-mini (reasoning models)
)

runner = RAAF::Runner.new(agent: agent)
result = runner.run("Hello!")

# Access with either key type - no more symbol/string confusion!
puts result.messages.last[:content]  # Symbol key access
puts result.messages.last["content"] # String key access (same result)
```

**NEW:** Full support for GPT-5 and reasoning models (`gpt-5`, `o1-preview`, `o1-mini`).
- Reasoning items processed automatically with proper token tracking
- **Control reasoning costs** with `reasoning_effort` DSL method (see [DSL docs](dsl/CLAUDE.md#reasoning-effort-configuration-new))
- Track reasoning tokens via `result.usage[:output_tokens_details][:reasoning_tokens]`

See **[Reasoning Support](core/CLAUDE.md#reasoning-support-gpt-5-o1-preview-o1-mini)** for complete details.

## Unified Context System with Indifferent Access

**RAAF provides a harmonized context system** that eliminates string vs symbol key confusion across all 12 context classes:

```ruby
# All RAAF contexts now support deep indifferent access
run_context = RAAF::RunContext.new
run_context.set(:user, { profile: { name: "John" } })

# These all work identically at every nesting level:
run_context[:user][:profile][:name]      # ✅ Works
run_context["user"]["profile"]["name"]   # ✅ Works
run_context[:user]["profile"][:name]     # ✅ Mixed works!

# No more defensive programming patterns needed:
# OLD: context[:key] || context["key"]  ❌ Error-prone
# NEW: context[:key]                     ✅ Always works

# Unified interface across all contexts:
run_context.set(:key, "value")     # RunContext
tool_context.set(:key, "value")    # ToolContext (same method!)
handoff_context.set(:key, "value") # HandoffContext (consistent!)
```

**Complete Context Harmonization Guide:** See **[CONTEXT_HARMONIZATION.md](core/CONTEXT_HARMONIZATION.md)** for:
- Unified interface specification
- Two-tier mutable/immutable pattern
- Migration guide from old patterns
- Deep dive into all 12 context classes

## Provider Requirements

**All providers used with RAAF must support tool/function calling.** Providers that don't support tool calling (like Ollama) have been removed to ensure consistent handoff behavior across all deployments.

### OpenAI Responses API Schema Requirements

**CRITICAL**: When using OpenAI Responses API (default provider), schemas for nested array objects have stricter validation requirements than standard JSON Schema:

- **ALL properties in nested objects MUST be listed in the required array**
- **This applies even to fields that are logically optional**
- **Standard JSON Schema allows partial required arrays, but OpenAI does not**

```ruby
# ❌ INCORRECT: Will fail OpenAI validation
schema do
  field :companies, type: :array, required: true do
    field :id, type: :integer, required: true
    field :name, type: :string, required: true
    field :description, type: :string, required: false  # ❌ Causes validation error
  end
end

# ✅ CORRECT: All fields in required array for OpenAI compatibility
schema do
  field :companies, type: :array, required: true do
    field :id, type: :integer, required: true
    field :name, type: :string, required: true
    field :description, type: :string, required: true  # ✅ Must be true for OpenAI
  end
end
```

**Error Symptoms:**
- `"Invalid schema for response_format '..._response': Missing '[field_name]'"`
- `"'required' is required to be supplied and to be an array including every key in properties"`

**Solution**: Mark ALL nested array object fields as `required: true` when using OpenAI Responses API, regardless of logical requirement.

## Provider Configuration (NEW)

**RAAF now supports automatic provider detection and configuration** using short symbolic names:

```ruby
require 'raaf-dsl'

# Automatic provider detection from model name
class GPTAgent < RAAF::DSL::Agent
  agent_name "Assistant"
  model "gpt-4o"  # Auto-detects :openai provider
  static_instructions "You are a helpful assistant"
end

# Explicit provider with short name
class ClaudeAgent < RAAF::DSL::Agent
  agent_name "Claude"
  model "claude-3-5-sonnet-20241022"
  provider :anthropic  # Explicit provider
end

# Run without specifying provider - automatically used
agent = ClaudeAgent.new
runner = RAAF::Runner.new(agent: agent)  # Uses AnthropicProvider
result = runner.run("Hello!")
```

### Provider Short Names

- `:openai` / `:responses` → ResponsesProvider (gpt-*, o1-*, o3-*)
- `:anthropic` → AnthropicProvider (claude-*)
- `:cohere` → CohereProvider (command-*)
- `:groq` → GroqProvider (mixtral-*, llama-*, gemma-*)
- `:xai` → XAIProvider (grok-*)
- `:gemini` → GeminiProvider (gemini-*)
- `:huggingface` → HuggingFaceProvider (org/model format)
- `:perplexity` → PerplexityProvider (sonar-*)
- `:moonshot` → MoonshotProvider (kimi-*, moonshot-*)
- `:together` → TogetherProvider
- `:litellm` → LiteLLMProvider
- `:openrouter` → OpenRouterProvider (provider/model format)

### Provider Precedence

1. Explicit provider at Runner level (highest)
2. Agent's explicit provider (`provider :name`)
3. Auto-detected from model name
4. Runner's default (ResponsesProvider)

**See**: `dsl/CLAUDE.md` for complete provider configuration documentation.

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

### Tool Execution Interceptor (NEW)

**RAAF DSL now includes an automatic tool execution interceptor** that provides validation, logging, and metadata injection for all tools without requiring wrapper classes:

```ruby
# Use raw core tools directly - interceptor adds conveniences automatically
class MyAgent < RAAF::DSL::Agent
  agent_name "WebSearchAgent"
  model "gpt-4o"

  # Use core tool directly (no wrapper needed)
  uses_tool RAAF::Tools::PerplexityTool, as: :perplexity_search

  # Optional: Configure interceptor behavior
  tool_execution do
    enable_validation true   # Validate parameters before execution
    enable_logging true      # Log execution start/end with duration
    enable_metadata true     # Add _execution_metadata to results
    log_arguments true       # Include arguments in logs
    truncate_logs 100        # Truncate long values in logs
  end
end

# The interceptor automatically provides:
# - Parameter validation against tool definition
# - Execution logging with duration tracking
# - Metadata injection ({ _execution_metadata: { duration_ms, tool_name, timestamp } })
# - Error handling and logging

# Tools execute with < 1ms overhead
agent = MyAgent.new
result = agent.run("Search for Ruby AI tools")

# Result includes automatic metadata
result[:_execution_metadata]
# => { duration_ms: 245.67, tool_name: "perplexity_search", timestamp: "2025-10-10T...", agent_name: "WebSearchAgent" }
```

**Benefits:**
- **Code Reduction:** Eliminates 200+ line DSL wrapper boilerplate
- **Single Update Point:** Change logging/validation once, applies to all tools
- **Consistent Behavior:** All tools get same conveniences automatically
- **Performance:** < 1ms overhead verified by benchmarks
- **Backward Compatible:** Existing DSL wrappers marked with `dsl_wrapped?` to skip double-processing

**Migration Guide:** See `.agent-os/specs/2025-10-10-agent-level-tool-execution-conveniences/DSL_WRAPPER_MIGRATION_GUIDE.md` for step-by-step wrapper migration instructions.

### DSL Usage with Automatic Context

RAAF DSL agents now provide automatic context access, eliminating manual context building:

```ruby
# Modern DSL agent with automatic context and schema validation
class WebSearchAgent < RAAF::DSL::Agent
  instructions "Help users search the web for #{query}"
  model "gpt-4o"
  
  # Define schema with smart key normalization
  schema do
    field :search_results, type: :array, required: true
    field :result_count, type: :integer
    field :search_query, type: :string
    
    # Use tolerant mode for flexible field mapping
    validate_mode :tolerant  # Automatically maps "Search Results" → :search_results
  end
  
  # Automatic access to context variables like :query
  def search_results
    "Searching for: #{query}"  # Direct context access
  end
end

# Usage with automatic context injection and schema validation
agent = WebSearchAgent.new(query: "Ruby news")
result = agent.run

# Even if LLM returns fields like "Search Results", "Result Count"
# They get automatically normalized to :search_results, :result_count
puts result[:search_results]  # Array of search results  
puts result[:result_count]    # Integer count
```

## Why JSON Repair and Schema Normalization?

**The Problem**: LLMs frequently return inconsistent JSON output that breaks applications:

- **Field Name Variations**: LLMs use natural language like "Company Name" instead of `company_name`
- **Malformed JSON**: Trailing commas, single quotes, markdown wrapping are common  
- **Inconsistent Structure**: Same data returned in different formats across requests
- **Developer Friction**: Constant manual parsing and error handling

**Our Solution**: RAAF's automatic JSON repair and schema normalization eliminates these issues:

1. **Smart Key Mapping**: Automatically converts `"Company Name"` → `:company_name`  
2. **JSON Repair**: Fixes malformed JSON (trailing commas, markdown blocks, etc.)
3. **Validation Modes**: Choose between strict, tolerant, or partial validation
4. **Zero Configuration**: Works automatically with DSL agents
5. **Comprehensive Coverage**: Handles nested objects, arrays, and complex structures

**Result**: Developers get consistent, clean data structures regardless of LLM output quality, enabling reliable applications with minimal code.

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

## RAAF Eval - Agent Evaluation Framework

**RAAF Eval** provides systematic testing and validation of AI agent behavior across different LLM configurations, parameters, and prompts.

### Quick Access
- **[Complete Documentation](RAAF_EVAL.md)** - Master guide with full feature overview
- **[Quick Start](eval/README.md)** - 5-minute introduction
- **[Tutorial](eval/GETTING_STARTED.md)** - Comprehensive guide with examples
- **[RSpec Testing](eval/RSPEC_INTEGRATION.md)** - 40+ matchers for automated testing
- **[Web UI](eval-ui/README.md)** - Interactive evaluation interface

### Two Complementary Interfaces

**Core Engine (raaf-eval):**
- Span serialization from production
- Evaluation execution engine
- RSpec integration with 40+ matchers
- Comprehensive metrics system

**Web UI (raaf-eval-ui):**
- Interactive span browser
- Monaco-based prompt editor
- Real-time execution tracking
- Side-by-side results comparison

### 5-Second Example

```ruby
# Compare models
baseline = find_span(agent: "HelpfulAssistant")

result = evaluate_span(baseline) do |config|
  config.model = "claude-3-5-sonnet-20241022"
  config.provider = "anthropic"
end

expect(result).to maintain_semantic_similarity(threshold: 0.85)
expect(result).not_to regress_from_baseline
```

See **[RAAF_EVAL.md](RAAF_EVAL.md)** for complete documentation.

## Agent OS Documentation

### Product Context
- **Mission & Vision:** @.agent-os/product/mission.md
- **Technical Architecture:** @.agent-os/product/tech-stack.md
- **Development Roadmap:** @.agent-os/product/roadmap.md
- **Decision History:** @.agent-os/product/decisions.md

### Development Standards
- **Code Style:** @~/.agent-os/standards/code-style.md
- **Best Practices:** @~/.agent-os/standards/best-practices.md

### Project Management
- **Active Specs:** @.agent-os/specs/
- **Spec Planning:** Use `@~/.agent-os/instructions/create-spec.md`
- **Tasks Execution:** Use `@~/.agent-os/instructions/execute-tasks.md`

## Workflow Instructions

When asked to work on this codebase:

1. **First**, check @.agent-os/product/roadmap.md for current priorities
2. **Then**, follow the appropriate instruction file:
   - For new features: @.agent-os/instructions/create-spec.md
   - For tasks execution: @.agent-os/instructions/execute-tasks.md
3. **Always**, adhere to the standards in the files listed above

## Important Notes

- Product-specific files in `.agent-os/product/` override any global standards
- User's specific instructions override (or amend) instructions found in `.agent-os/specs/...`
- Always adhere to established patterns, code style, and best practices documented above.