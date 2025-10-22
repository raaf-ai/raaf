# RAAF DSL - Claude Code Guide

This gem provides a Ruby DSL for building agents with a more declarative syntax, comprehensive debugging tools, flexible prompt resolution, and **automatic hash indifferent access** for seamless data handling.

## Important: Prompt Format Preference

**PREFER RUBY PROMPTS**: When creating prompts for RAAF agents, prefer using Ruby Phlex-style prompt classes over Markdown files. Ruby prompts provide:
- Type safety and validation
- IDE support and autocomplete
- Testability with RSpec
- Dynamic behavior with Ruby logic
- Better integration with the DSL

## Quick Start

```ruby
require 'raaf-dsl'

# Define agent using DSL
agent = RAAF::DSL::AgentBuilder.build do
  name "WebSearchAgent"
  instructions "You help users search the web"
  model "gpt-4o"
  
  # Add a custom web search tool
  tool :web_search do
    description "Search the web for information"
    parameter :query, type: :string, required: true
    
    execute do |query:|
      # Web search implementation
      { results: ["Result 1", "Result 2"] }
    end
  end
end

# Run the agent with a runner
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Search for Ruby programming tutorials")
```

## Core Components

- **AgentBuilder** - DSL for defining agents
- **ToolBuilder** - DSL for creating tools
- **ContextVariables** - Dynamic context management with **indifferent hash access**
- **Prompt Resolution** - Flexible prompt loading system
- **WebSearch** - Built-in web search tool
- **DebugUtils** - Enhanced debugging capabilities
- **Indifferent Access** - All data structures support both string and symbol keys seamlessly

## Thread Safety and Data Storage Patterns (CRITICAL)

**IMPORTANT**: When designing data storage for agent configuration, always consider whether data needs to be:

1. **Class-level configuration (shared across all threads)** - Use class instance variables
2. **Thread-local data (unique per thread)** - Use Thread.current

### Class-Level Configuration (Preferred for Stateless Data)

Use **class instance variables** (`@variable`) for agent configuration that:
- **Defined at class definition time** (e.g., via DSL methods like `tool`, `schema`, `instructions`)
- **Persist unchanged across runtime** (not modified per-instance)
- **Must be accessible in background jobs** (ActiveJob workers run in different threads)
- **Are shared by all agent instances** (memory efficient)

**Examples:**
- Tool definitions (`_tools_config`)
- Schema configurations (`_schema_config`)
- Prompt configurations (`_prompt_config`)
- Auto-discovery configurations (`_auto_discovery_config`)

```ruby
# ✅ CORRECT: Class instance variables for configuration
class Agent
  class << self
    def _tools_config
      @_tools_config ||= []  # Shared across all threads
    end

    def _tools_config=(value)
      @_tools_config = value
    end
  end
end
```

### Thread-Local Data (For Runtime State)

Use `Thread.current` ONLY for data that:
- **Changes per thread** (execution context specific)
- **Must not leak between threads** (security/isolation)
- **Is temporary** (discarded after thread completes)

**Potential candidates (if needed):**
- Active execution state
- Request-specific context
- Transient caching

**DO NOT use Thread.current for:**
- ❌ Class definitions and configuration (persists beyond single run)
- ❌ Tool definitions (needed in background jobs)
- ❌ Agent metadata (should be accessible anywhere)

### Known Issue: Thread-Local with object_id (ANTIPATTERN)

**NEVER use:** `Thread.current["key_#{object_id}"]`

This pattern breaks in background jobs:
```ruby
# ❌ BROKEN in background jobs
def _tools_config
  Thread.current["raaf_dsl_tools_config_#{object_id}"] ||= []
end

# Problem: Thread.current changes in background job workers
# → New thread has empty Thread.current
# → Configuration is lost
# → Agent has 0 tools
```

### Why This Worked in Development but Failed in Acceptance

The thread-local antipattern appears to work in **development** (with `eager_load: false`) but fails in **acceptance/production** (with `eager_load: true`):

**Development (eager_load: false) - APPEARS TO WORK:**
```
Main Thread (development server)
├─ Class definition (lazy load when first used)
├─ Tool registration → Thread.current["key_#{object_id}"] stored in Main Thread
└─ Background job runs in Main Thread (or reuses Thread.current)
   → Data still in Thread.current → Works ✅ (misleading!)
```

**Acceptance/Production (eager_load: true) - FAILS:**
```
Main Thread (Rails boot)
├─ Class definition (eager loaded during boot)
├─ Tool registration → Thread.current["key_#{object_id}"] stored in Main Thread
└─ Background job runs in WORKER THREAD (different thread)
   → Thread.current is empty in worker thread → Data lost ❌
   → Agent has 0 tools
```

**The fix works in ALL environments:**
```ruby
# ✅ WORKS EVERYWHERE
def _tools_config
  @_tools_config ||= []  # Shared class variable, not thread-local
end
```

Class instance variables are **not bound to threads**, so they're accessible regardless of which thread accesses them.

### Testing Across Thread Boundaries

When testing agents that run in background jobs:

```ruby
# Test thread-safe configuration access
it "has tools in background job thread" do
  original_thread = Thread.current

  agent_config = nil
  job_thread = Thread.new do
    # Different thread
    assert_not_equal Thread.current, original_thread

    # Configuration still accessible
    agent_config = Ai::Agents::Prospect::Scoring._tools_config
  end

  job_thread.join

  # Class-level config available in both threads
  assert_equal agent_config.length, Ai::Agents::Prospect::Scoring._tools_config.length
end
```

### Migration Checklist

When refactoring to use class instance variables:

- [ ] Replace `Thread.current["key_#{object_id}"]` with `@key ||= ...`
- [ ] Replace setter with direct assignment `@key = value`
- [ ] Verify configuration loads during class definition (eager loading)
- [ ] Test in background job context (different thread)
- [ ] Verify memory efficiency (shared class variables, not per-instance)
- [ ] Update RAAF tests for thread safety

## Agent DSL

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "ResearchAgent"
  instructions "Research and analyze topics"
  model "gpt-4o"

  # Add built-in tools
  use_web_search
  use_file_search

  # Custom tool
  tool :analyze_sentiment do |text|
    # Sentiment analysis logic
    { sentiment: "positive", confidence: 0.85 }
  end

  # Configuration
  config do
    max_tokens 1000
    temperature 0.7
  end
end
```

## Agent Lifecycle Hooks

**NEW:** RAAF DSL agents support lifecycle hooks for wrapper-level interception, enabling preprocessing and postprocessing logic that works consistently across all pipeline wrapper types.

### Overview

Lifecycle hooks allow agents to execute custom logic before and after wrapper execution:

- **`before_execute`** - Runs before the wrapper executes (preprocessing)
- **`after_execute`** - Runs after the wrapper executes (postprocessing)

Hooks receive rich context about the wrapper execution including wrapper type, configuration, timing information, and can modify the context/result for downstream processing.

### Hook Registration

```ruby
class MyAgent < RAAF::DSL::Agent
  include RAAF::DSL::Hooks::AgentHooks

  agent_name "MyAgent"
  model "gpt-4o"

  # Register before_execute hook
  before_execute do |context:, wrapper_type:, wrapper_config:, timestamp:, **|
    # Preprocessing logic
    Rails.logger.info "🔍 [#{self.class.name}] Starting #{wrapper_type} execution"

    # Modify context (mutable)
    context[:preprocessing_complete] = true
    context[:started_at] = timestamp
  end

  # Register after_execute hook
  after_execute do |context:, result:, wrapper_type:, wrapper_config:, duration_ms:, timestamp:, **|
    # Postprocessing logic
    Rails.logger.info "✅ [#{self.class.name}] Completed in #{duration_ms}ms"

    # Modify result (mutable)
    context[:execution_time] = duration_ms
    context[:completed_at] = timestamp
  end
end
```

### Hook Parameters

#### before_execute Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `context` | ContextVariables | Pipeline context (mutable - modifications persist) |
| `wrapper_type` | Symbol | Type of wrapper executing (`:batched`, `:chained`, `:parallel`, `:remapped`, `:configured`, `:iterating`) |
| `wrapper_config` | Hash | Wrapper-specific configuration (e.g., `{chunk_size: 10, input_field: :items}` for BatchedAgent) |
| `timestamp` | Time | Execution start time |

#### after_execute Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `context` | ContextVariables | Result context (mutable - modifications persist in returned result) |
| `result` | ContextVariables | Execution result (same as context in after_execute) |
| `wrapper_type` | Symbol | Type of wrapper that executed |
| `wrapper_config` | Hash | Wrapper-specific configuration |
| `duration_ms` | Numeric | Execution duration in milliseconds |
| `timestamp` | Time | Execution completion time |

### Wrapper Types

Hooks receive `wrapper_type` parameter indicating which wrapper is executing:

- `:batched` - BatchedAgent (processes items in chunks)
- `:chained` - ChainedAgent (sequential agent execution)
- `:parallel` - ParallelAgents (concurrent agent execution)
- `:remapped` - RemappedAgent (field name remapping)
- `:configured` - ConfiguredAgent (inline configuration)
- `:iterating` - IteratingAgent (iteration over data entries)

### Wrapper Configuration

Each wrapper type provides specific configuration in `wrapper_config`:

```ruby
# BatchedAgent
{ chunk_size: 10, input_field: :items, output_field: :items }

# ChainedAgent
{ first_agent: AgentClass1, second_agent: AgentClass2 }

# ParallelAgents
{ agent_count: 3 }

# RemappedAgent
{ input_mapping: { target: :source }, output_mapping: { result: :output } }

# ConfiguredAgent
{ options: { max_retries: 3, timeout: 30 } }

# IteratingAgent
{ field: :items }
```

### Context Mutability

**IMPORTANT:** Context modifications in hooks persist:

```ruby
class PreprocessingAgent < RAAF::DSL::Agent
  include RAAF::DSL::Hooks::AgentHooks

  before_execute do |context:, **|
    # Direct mutation using []= operator
    context[:preprocessed] = true
    context[:metadata] = { source: "preprocessing", timestamp: Time.current }
  end

  after_execute do |context:, duration_ms:, **|
    # Result modifications persist in returned value
    context[:execution_metadata] = {
      duration_ms: duration_ms,
      processed_at: Time.current
    }
  end
end

# Usage
agent = PreprocessingAgent.new
result = agent.run

# Hook modifications are present in result
puts result[:preprocessed]         # true
puts result[:execution_metadata]   # { duration_ms: 245.67, processed_at: ... }
```

### Guard Clauses

Use guard clauses to conditionally execute hooks based on wrapper type:

```ruby
class SelectiveAgent < RAAF::DSL::Agent
  include RAAF::DSL::Hooks::AgentHooks

  before_execute do |context:, wrapper_type:, wrapper_config:, **|
    # Only run for batched execution
    next unless wrapper_type == :batched

    batch_size = wrapper_config[:chunk_size]
    Rails.logger.info "🔄 Processing in batches of #{batch_size}"

    # Batched-specific preprocessing
    context[:batch_processing] = true
    context[:expected_chunks] = (context[:items].size.to_f / batch_size).ceil
  end
end
```

### Multiple Hooks

Register multiple hooks - they execute in registration order:

```ruby
class MultiHookAgent < RAAF::DSL::Agent
  include RAAF::DSL::Hooks::AgentHooks

  before_execute do |context:, **|
    context[:hook_1_executed] = true
  end

  before_execute do |context:, **|
    context[:hook_2_executed] = true
  end

  after_execute do |context:, **|
    context[:post_hook_1_executed] = true
  end

  after_execute do |context:, **|
    context[:post_hook_2_executed] = true
  end
end

# Execution order: hook_1 → hook_2 → agent execution → post_hook_1 → post_hook_2
```

### Common Use Cases

#### 1. Logging and Monitoring

```ruby
class MonitoredAgent < RAAF::DSL::Agent
  include RAAF::DSL::Hooks::AgentHooks

  before_execute do |context:, wrapper_type:, **|
    Rails.logger.info "🔍 [#{self.class.name}] Starting #{wrapper_type} execution"
    Rails.logger.info "📄 Context: #{context.keys.inspect}"
  end

  after_execute do |context:, duration_ms:, **|
    Rails.logger.info "✅ [#{self.class.name}] Completed in #{duration_ms}ms"

    # Record metrics
    MetricsRecorder.record(
      agent: self.class.name,
      duration_ms: duration_ms,
      success: context[:success]
    )
  end
end
```

#### 2. Error Recovery

```ruby
class ResilientAgent < RAAF::DSL::Agent
  include RAAF::DSL::Hooks::AgentHooks

  after_execute do |context:, duration_ms:, **|
    if context[:error] && duration_ms < 1000
      # Fast failure - might be transient
      context[:should_retry] = true
      Rails.logger.warn "⚠️ Fast failure detected - marking for retry"
    end
  end
end
```

#### 3. Data Enrichment

```ruby
class EnrichingAgent < RAAF::DSL::Agent
  include RAAF::DSL::Hooks::AgentHooks

  before_execute do |context:, **|
    # Add metadata before processing
    context[:execution_id] = SecureRandom.uuid
    context[:environment] = Rails.env
  end

  after_execute do |context:, duration_ms:, wrapper_type:, **|
    # Enrich results with execution metadata
    context[:_metadata] = {
      execution_id: context[:execution_id],
      duration_ms: duration_ms,
      wrapper_type: wrapper_type,
      timestamp: Time.current.iso8601
    }
  end
end
```

#### 4. Pipeline Context Preparation

```ruby
class PipelineAgent < RAAF::DSL::Agent
  include RAAF::DSL::Hooks::AgentHooks

  before_execute do |context:, wrapper_type:, **|
    # Prepare context for downstream agents in pipeline
    if wrapper_type == :chained
      context[:pipeline_stage] = "preprocessing"
      context[:pipeline_metadata] = {
        started_at: Time.current,
        agent_sequence: [self.class.name]
      }
    end
  end

  after_execute do |context:, **|
    # Add this agent to the sequence
    metadata = context[:pipeline_metadata] || {}
    sequence = metadata[:agent_sequence] || []
    sequence << self.class.name

    context[:pipeline_metadata] = metadata.merge(
      agent_sequence: sequence,
      completed_at: Time.current
    )
  end
end
```

### Testing Hooks

```ruby
RSpec.describe MyAgent do
  let(:agent) { described_class.new }

  it "executes before_execute hook" do
    context = { input_data: "test" }

    # Before execute hook adds preprocessing flag
    expect(context).to receive(:[]=).with(:preprocessed, true)

    agent.execute_with_hooks(context, :chained, {}) do
      # Wrapper execution logic
    end
  end

  it "executes after_execute hook with timing" do
    result = agent.execute_with_hooks({}, :batched, { chunk_size: 10 }) do
      { success: true }
    end

    # After execute hook adds execution metadata
    expect(result[:execution_metadata]).to be_present
    expect(result[:execution_metadata][:duration_ms]).to be_a(Numeric)
  end
end
```

### Best Practices

1. **Keep hooks focused** - Single responsibility per hook
2. **Use guard clauses** - Conditionally execute based on wrapper_type
3. **Log consistently** - Use emojis and structured logging
4. **Modify context judiciously** - Only add necessary data
5. **Handle errors gracefully** - Don't let hook errors break pipelines
6. **Document hook behavior** - Explain what hooks do and why
7. **Test hook logic** - Verify preprocessing and postprocessing work correctly

## Provider Configuration

**NEW:** RAAF DSL agents now support automatic provider detection and configuration using short names:

```ruby
# Automatic provider detection from model name (default)
class GPTAgent < RAAF::DSL::Agent
  agent_name "Assistant"
  model "gpt-4o"  # Auto-detects :openai provider (ResponsesProvider)
  static_instructions "You are a helpful assistant"
end

# Explicit provider with short name
class ClaudeAgent < RAAF::DSL::Agent
  agent_name "Claude Assistant"
  model "claude-3-5-sonnet-20241022"
  provider :anthropic  # Explicit provider specification
  static_instructions "You are Claude, an AI assistant"
end

# Provider with custom options
class CustomAgent < RAAF::DSL::Agent
  agent_name "Custom Assistant"
  provider :anthropic
  provider_options api_key: ENV['CUSTOM_ANTHROPIC_KEY'], max_tokens: 4000
end

# Disable auto-detection (use Runner's default provider)
class NoProviderAgent < RAAF::DSL::Agent
  agent_name "Default Provider Agent"
  model "gpt-4o"
  auto_detect_provider false  # Won't auto-detect provider
end

# Usage - provider is automatically used
agent = ClaudeAgent.new
runner = RAAF::Runner.new(agent: agent)  # Uses AnthropicProvider automatically
result = runner.run("Hello!")
```

### Provider Short Names

- `:openai` - OpenAI ResponsesProvider (auto-detected for gpt-*, o1-*, o3-*)
- `:anthropic` - Anthropic Claude (auto-detected for claude-*)
- `:cohere` - Cohere (auto-detected for command-*)
- `:groq` - Groq (auto-detected for mixtral-*, llama-*, gemma-*)
- `:perplexity` - Perplexity (auto-detected for sonar-*)
- `:together` - Together AI
- `:litellm` - LiteLLM (universal provider)

### Provider Precedence

1. **Explicit provider at Runner level** (highest priority)
2. **Agent's explicit provider** (via `provider :name`)
3. **Auto-detected provider** (from model name)
4. **Runner's default provider** (ResponsesProvider)

```ruby
agent = ClaudeAgent.new  # Has :anthropic provider

# Agent's provider used
runner1 = RAAF::Runner.new(agent: agent)
# Uses AnthropicProvider from agent

# Explicit provider overrides agent's provider
runner2 = RAAF::Runner.new(agent: agent, provider: RAAF::Models::GroqProvider.new)
# Uses GroqProvider (explicit override)
```

## Tool Execution Interceptor (NEW - October 2025)

**RAAF DSL now includes automatic tool execution conveniences** via an interceptor that eliminates the need for DSL wrapper classes:

### Overview

The tool execution interceptor provides automatic:
- **Parameter validation** - Validates against tool definition before execution
- **Execution logging** - Logs tool start/end with duration tracking
- **Metadata injection** - Adds `_execution_metadata` to Hash results
- **Error handling** - Catches and logs errors with context
- **Performance** - < 1ms overhead verified by benchmarks

### Using Core Tools Directly

```ruby
# NEW: Use raw core tools directly (no wrapper needed)
class MyAgent < RAAF::DSL::Agent
  agent_name "WebSearchAgent"
  model "gpt-4o"

  # Use core tool - interceptor adds conveniences automatically
  uses_tool RAAF::Tools::PerplexityTool, as: :perplexity_search

  # Optional: Configure interceptor behavior
  tool_execution do
    enable_validation true   # Default: true
    enable_logging true      # Default: true
    enable_metadata true     # Default: true
    log_arguments true       # Default: true
    truncate_logs 100        # Default: 100
  end
end

# Execute tool - automatic conveniences applied
agent = MyAgent.new
result = agent.run("Search for Ruby AI frameworks")

# Result includes automatic metadata
result[:_execution_metadata]
# => {
#   duration_ms: 245.67,
#   tool_name: "perplexity_search",
#   timestamp: "2025-10-10T12:34:56Z",
#   agent_name: "WebSearchAgent"
# }
```

### Configuration Options

```ruby
class ConfiguredAgent < RAAF::DSL::Agent
  # Disable specific features
  tool_execution do
    enable_validation false  # Skip parameter validation
    enable_logging false     # Skip execution logging
    enable_metadata false    # Skip metadata injection
    log_arguments false      # Don't log arguments
    truncate_logs 200        # Longer truncation
  end
end

# Instance-level override
agent = ConfiguredAgent.new
agent.tool_execution do
  enable_logging true  # Re-enable for this instance
end
```

### Backward Compatibility

Existing DSL wrappers continue to work - they're marked with `dsl_wrapped?` to skip double-processing:

```ruby
# OLD: DSL wrapper (still works)
class MyAgent < RAAF::DSL::Agent
  uses_tool :perplexity_search  # Uses RAAF::DSL::Tools::PerplexitySearch
end

# DSL wrappers inherit from Base which has:
# def dsl_wrapped?
#   true  # Tells interceptor to skip this tool
# end
```

### Benefits

| Aspect | Before (Wrapper) | After (Interceptor) |
|--------|------------------|---------------------|
| **Code** | 200+ lines per wrapper | 3 lines per agent declaration |
| **Updates** | Change each wrapper | Change interceptor once |
| **Consistency** | Varies per wrapper | Identical for all tools |
| **Performance** | Varies | < 1ms overhead |

### Migration Guide

See the comprehensive migration guide for step-by-step instructions:
`.agent-os/specs/2025-10-10-agent-level-tool-execution-conveniences/DSL_WRAPPER_MIGRATION_GUIDE.md`

## Tool Registration (v2.0.0+)

### Unified Tool API

RAAF DSL 2.0.0 introduces a unified tool registration API with lazy loading, providing **6.25x faster initialization** while simplifying the developer experience:

```ruby
class MyAgent < RAAF::DSL::Agent
  agent_name "ToolDemoAgent"
  model "gpt-4o"

  # All tool registration now uses 'tool' or 'tools'
  tool :web_search                          # Symbol identifier
  tool RAAF::Tools::PerplexityTool         # Class reference
  tool :calculator, precision: :high        # With options
  tool :search, as: :internet_search       # With alias
  tools :file_search, :database_query      # Multiple at once
end
```

### All 7 Registration Patterns

#### 1. Symbol Identifier (Most Common)
```ruby
tool :web_search
tool :calculator
```

#### 2. Multiple Tools
```ruby
tools :web_search, :file_search, :calculator
```

#### 3. Native Tool Class
```ruby
tool RAAF::Tools::PerplexityTool
tool MyCustomToolClass
```

#### 4. With Options
```ruby
tool :web_search, max_results: 10, timeout: 30
tool :database_query, connection: :primary
```

#### 5. With Alias
```ruby
tool :web_search, as: :internet_search
tool RAAF::Tools::PerplexityTool, as: :perplexity
```

#### 6. Conditional Loading
```ruby
tool :premium_tool if Rails.env.production?
tool :expensive_tool if respond_to?(:costly?) && costly?
```

#### 7. Inline Definition with Block
```ruby
tool :custom_calculator do
  description "Performs safe calculations"
  parameter :expression, type: :string, required: true

  execute do |expression:|
    # Implementation here
  end
end
```

### Lazy Loading Benefits

Tools are now loaded **only when needed**, not at agent initialization:

```ruby
# Before: All tools loaded immediately (slow)
agent = MyAgent.new  # 37.50ms for 100 initializations

# After: Tools loaded on first use (fast)
agent = MyAgent.new  # 6.00ms for 100 initializations (6.25x faster!)
```

### Tool Resolution

Tools are automatically resolved from multiple namespaces:

1. `RAAF::DSL::Tools::[Identifier]` - DSL-specific tools
2. `RAAF::Tools::[Identifier]` - Core RAAF tools
3. `Ai::Tools::[Identifier]` - Application tools
4. Direct constant lookup for custom classes

### Enhanced Error Messages

If a tool cannot be found, you'll get helpful error messages:

```ruby
class MyAgent < RAAF::DSL::Agent
  tool :unknown_tool
end

# Raises ToolResolutionError with:
# 🔍 Tool Resolution Failed: 'unknown_tool'
#
# Searched namespaces:
#   ❌ RAAF::DSL::Tools::UnknownTool
#   ❌ RAAF::Tools::UnknownTool
#   ❌ Ai::Tools::UnknownTool
#   ❌ UnknownTool
#
# 💡 Suggestions:
#   • Check the tool identifier spelling
#   • Ensure the tool gem is installed
#   • Try using the full class name
#
# Available tools: web_search, calculator, file_search
```

### Migration from Old Syntax

If you're upgrading from an older version, see [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md) for detailed instructions on migrating from the deprecated `uses_*` methods.

## Tool DSL

```ruby
# Define reusable tools
calculator = RAAF::DSL::ToolBuilder.build do
  name "calculator"
  description "Perform mathematical calculations"

  parameter :expression, type: :string, required: true

  execute do |expression:|
    # Use a safe math evaluator instead of eval
    # Example: Dentaku.evaluate(expression)
    raise "Calculator not implemented - use a safe math library"
  end
end

# Create an agent and add the tool
agent = RAAF::DSL::AgentBuilder.build do
  name "MathAgent"
  instructions "You help with mathematical calculations"
  model "gpt-4o"
end

agent.add_tool(calculator)
```

## Prompt Resolution System

The DSL includes a powerful prompt resolution framework:

```ruby
# Configure prompt resolution
RAAF::DSL.configure_prompts do |config|
  config.add_path "prompts"        # Add search paths
  config.add_path "app/prompts"    # Rails-style paths
  
  # File resolver handles .md and .md.erb automatically
  config.enable_resolver :file, priority: 100
  config.enable_resolver :phlex, priority: 50
end

# PREFERRED: Ruby prompt classes (Phlex-style)
class ResearchPrompt < RAAF::DSL::Prompts::Base
  def system
    <<~SYSTEM
      You are a research assistant specializing in #{topic}.
      Provide #{depth} analysis in #{language || 'English'}.
    SYSTEM
  end
  
  def user
    "Research the latest developments in #{topic}."
  end
end

# Use prompts in agents via a custom agent class
class ResearchAgent < RAAF::DSL::Agent
  
  agent_name "researcher"
  prompt_class ResearchPrompt  # Preferred: Ruby class
  # prompt_class "research.md"  # Alternative: Markdown file
  # prompt_class "analysis.md.erb"  # Alternative: ERB template
end

# Or with simple instructions
agent = RAAF::DSL::AgentBuilder.build do
  name "Researcher"
  instructions "You are a research assistant"
  model "gpt-4o"
end
```

### Prompt Formats Supported

1. **Ruby Classes (PREFERRED)** - Type-safe, testable, dynamic
2. **Markdown Files** - Simple with `{{variable}}` interpolation
3. **ERB Templates** - Full Ruby logic with helper methods

### Why Prefer Ruby Prompts?

- **Automatic Context**: Variables are automatically accessible via method_missing
- **Testing**: Easy to test with RSpec
- **IDE Support**: Autocomplete and refactoring support
- **Dynamic**: Can use Ruby logic and conditionals
- **Clean Errors**: Clear Ruby NameError messages for missing variables
- **Reusable**: Inherit from base classes

## Context Variables with Deep Indifferent Access

Context variables in RAAF DSL use **deep** `ActiveSupport::HashWithIndifferentAccess` for seamless key handling throughout all nested structures:

```ruby
# Context variables support both string and symbol key access at ALL levels
result = agent.run("Research AI trends") do
  # Set context variables with nested data
  context_variable :search_config, {
    depth: "deep",
    sources: ["academic", "industry"],
    filters: { date_range: "2024", topics: ["AI", "ML"] }
  }
  context_variable :users, [
    { name: "John", profile: { role: "researcher", active: true } },
    { name: "Jane", profile: { role: "analyst", active: false } }
  ]
end

# Top-level access works with both key types
puts result.context[:search_config]   # ✅ Works  
puts result.context["search_config"]  # ✅ Also works

# NESTED hash access now works with both key types too!
config = result.context[:search_config]
puts config[:depth]           # ✅ Works
puts config["depth"]          # ✅ Also works  
puts config[:filters][:date_range]    # ✅ Works
puts config["filters"]["date_range"]  # ✅ Also works
puts config[:filters]["topics"]      # ✅ Mixed access works too

# Arrays containing hashes also support indifferent access
first_user = result.context[:users].first
puts first_user[:name]              # ✅ Works
puts first_user["name"]             # ✅ Also works
puts first_user[:profile][:role]    # ✅ Works  
puts first_user["profile"]["role"]  # ✅ Also works

# No more defensive programming patterns needed at ANY level:
# OLD: config[:filters][:key] || config["filters"]["key"]  ❌ Error-prone
# NEW: config[:filters][:key]                              ✅ Always works
```

### Deep Indifferent Access Benefits

- **Consistent behavior**: Works the same at every nesting level
- **No surprises**: LLM responses with mixed key types "just work"  
- **Reduced errors**: Eliminates symbol/string key confusion bugs
- **Better DX**: Use whatever key style feels natural

## Web Search Tool

```ruby
# Built-in web search with Tavily
agent = RAAF::DSL::AgentBuilder.build do
  name "SearchAgent"
  instructions "Search and summarize web content"
  
  use_web_search do
    api_key ENV['TAVILY_API_KEY']
    max_results 5
    include_raw_content true
  end
end
```

## Debug Tools

```ruby
# Enhanced debugging
RAAF::DSL::DebugUtils.inspect_agent(agent) do
  show_tools true
  show_context true
  show_configuration true
end

# Prompt inspection
RAAF::DSL::DebugUtils.inspect_prompts(result) do
  show_system_prompt true
  show_tool_calls true
  highlight_handoffs true
end
```

## RSpec Integration

```ruby
# Example RSpec test file (e.g., spec/agent_spec.rb)
# This shows how to use RAAF DSL in RSpec tests

# require 'spec_helper'
# require 'raaf-testing' # For RSpec matchers
# 
# RSpec.describe "Agent behavior" do
#   it "should handle web search" do
#     agent = RAAF::DSL::AgentBuilder.build do
#       name "TestAgent"
#       instructions "You search the web"
#       model "gpt-4o"
#       
#       tool :web_search do
#         description "Search the web"
#         parameter :query, type: :string, required: true
#         execute { |query:| { results: ["Result 1", "Result 2"] } }
#       end
#     end
#     
#     runner = RAAF::Runner.new(agent: agent)
#     # Test agent behavior here
#   end
# end
```

### Schema Validation with Smart Key Mapping

RAAF DSL includes powerful schema validation that automatically handles LLM field name variations:

```ruby
# Define agents with flexible schema validation
class CompanyAnalyzer < RAAF::DSL::Agent
  agent_name "CompanyAnalyzer"
  model "gpt-4o"
  
  # Define schema with Ruby naming conventions
  schema do
    field :company_name, type: :string, required: true
    field :market_sector, type: :string, required: true
    field :employee_count, type: :integer
    field :annual_revenue, type: :number
    field :headquarters_location, type: :string
    
    # Choose validation mode
    validate_mode :tolerant  # :strict, :tolerant, or :partial
  end
  
  instructions "Analyze company information and extract key details"
end

# LLMs can use natural language field names - they get automatically mapped
agent = CompanyAnalyzer.new
result = agent.run("Tesla Inc is an automotive company with 127,000 employees...")

# Even if LLM returns:
# {
#   "Company Name": "Tesla Inc",
#   "Market Sector": "automotive", 
#   "Employee Count": 127000,
#   "HQ Location": "Austin, Texas"
# }
#
# You get normalized output with indifferent access:
puts result[:company_name]           # "Tesla Inc"
puts result["company_name"]          # "Tesla Inc" (same result)
puts result[:market_sector]          # "automotive"  
puts result["market_sector"]         # "automotive" (same result)
puts result[:employee_count]         # 127000
puts result["employee_count"]        # 127000 (same result)
puts result[:headquarters_location]  # "Austin, Texas"
puts result["headquarters_location"] # "Austin, Texas" (same result)
```

### OpenAI Responses API Schema Requirements

**CRITICAL**: When using OpenAI Responses API (RAAF's default provider), nested array object schemas have stricter validation requirements:

```ruby
# ❌ INCORRECT: OpenAI validation will fail
schema do
  field :companies, type: :array, required: true do
    field :id, type: :integer, required: true
    field :name, type: :string, required: true
    field :description, type: :string, required: false  # ❌ Causes error
    field :location, type: :string, required: false     # ❌ Causes error
  end
end

# ✅ CORRECT: All nested array fields must be required: true
schema do
  field :companies, type: :array, required: true do
    field :id, type: :integer, required: true
    field :name, type: :string, required: true
    field :description, type: :string, required: true  # ✅ Must be true
    field :location, type: :string, required: true     # ✅ Must be true
  end
end
```

**Why This Happens:**
- OpenAI Responses API requires ALL properties in nested objects to be in the required array
- This applies even to logically optional fields
- Standard JSON Schema allows partial required arrays, but OpenAI does not

**Common Error Messages:**
```
"Invalid schema for response_format 'agent_response':
In context=('properties', 'companies', 'items'),
'required' is required to be supplied and to be an array
including every key in properties. Missing 'description'"
```

**Solution**: Mark ALL nested array object fields as `required: true` when using OpenAI, regardless of logical necessity.

### JSON Repair and Error Handling

```ruby
# RAAF automatically handles malformed JSON from LLMs
class DataExtractor < RAAF::DSL::Agent
  agent_name "DataExtractor"
  model "gpt-4o"
  
  schema do
    field :extracted_data, type: :object
    field :confidence, type: :number
    validate_mode :partial  # Most forgiving mode
  end
end

# These problematic responses are automatically fixed:
# 1. '{"name": "John",}' → {"name": "John"}  (trailing comma removed)
# 2. '```json\n{"valid": true}\n```' → {"valid": true}  (markdown extracted)
# 3. "{'key': 'value'}" → {"key": "value"}  (single quotes fixed)
# 4. Mixed text with embedded JSON gets extracted automatically

agent = DataExtractor.new
result = agent.run("Extract the user data from this messy text...")

# Always get clean, parsed data with indifferent key access regardless of LLM output quality
puts result[:extracted_data]    # ✅ Works
puts result["extracted_data"]   # ✅ Also works  
puts result[:confidence]        # ✅ Works
puts result["confidence"]       # ✅ Also works
```

### Validation Mode Comparison

```ruby
# :strict mode (default) - All fields must match exactly
schema do
  field :name, type: :string, required: true
  validate_mode :strict
end
# LLM must return exactly {"name": "value"} or validation fails

# :tolerant mode - Required fields strict, others flexible  
schema do
  field :name, type: :string, required: true
  field :age, type: :integer
  validate_mode :tolerant
end
# LLM can return {"Name": "John", "Age": 25, "ExtraField": "ignored"}
# Gets normalized with indifferent access: both result[:name] and result["name"] work

# :partial mode - Use whatever validates, ignore the rest
schema do
  field :name, type: :string, required: true
  field :age, type: :integer  
  validate_mode :partial
end
# Even {"Name": "John", "InvalidAge": "not a number"} gets normalized with indifferent access
# Both result[:name] and result["name"] return "John"
```

## Environment Variables

```bash
export TAVILY_API_KEY="your-tavily-key"
export OPENAI_API_KEY="your-openai-key"
export RAAF_DEBUG_TOOLS="true"
```