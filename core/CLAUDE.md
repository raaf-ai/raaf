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
- **ProviderRegistry** (`lib/raaf/provider_registry.rb`) - **NEW** - Provider detection and instantiation from short names

## Provider Registry

The **ProviderRegistry** provides automatic provider detection and a clean DSL for provider configuration:

```ruby
# Automatic provider detection from model names
provider = RAAF::ProviderRegistry.detect("gpt-4o")        # => :openai
provider = RAAF::ProviderRegistry.detect("claude-3-5-sonnet")  # => :anthropic
provider = RAAF::ProviderRegistry.detect("sonar-pro")     # => :perplexity

# Create provider instances using short names
openai_provider = RAAF::ProviderRegistry.create(:openai)
anthropic_provider = RAAF::ProviderRegistry.create(:anthropic, api_key: ENV['ANTHROPIC_API_KEY'])

# Register custom providers
RAAF::ProviderRegistry.register(:custom, MyApp::CustomProvider)
custom_provider = RAAF::ProviderRegistry.create(:custom, api_key: "key")

# Check available providers
RAAF::ProviderRegistry.providers  # => [:openai, :responses, :anthropic, :cohere, :groq, ...]
RAAF::ProviderRegistry.registered?(:anthropic)  # => true
```

### Supported Provider Short Names

- `:openai` or `:responses` → `ResponsesProvider` (default for gpt-*, o1-*, o3-*)
- `:anthropic` → `AnthropicProvider` (default for claude-*)
- `:cohere` → `CohereProvider` (default for command-*)
- `:groq` → `GroqProvider` (default for mixtral-*, llama-*, gemma-*)
- `:perplexity` → `PerplexityProvider` (default for sonar-*)
- `:together` → `TogetherProvider`
- `:litellm` → `LiteLLMProvider`

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

### HTTP Timeout Configuration

Configure HTTP timeouts for long-running requests or slow network conditions:

```ruby
# Default timeout: 300 seconds (5 minutes)
agent = RAAF::Agent.new(name: "Assistant", model: "gpt-4o")
runner = RAAF::Runner.new(agent: agent)  # Uses default 300s timeout

# Custom timeout via provider
provider = RAAF::Models::ResponsesProvider.new(timeout: 600)  # 10 minutes
runner = RAAF::Runner.new(agent: agent, provider: provider)

# Or via environment variable
# export OPENAI_HTTP_TIMEOUT=600
runner = RAAF::Runner.new(agent: agent)  # Uses env var timeout
```

### Flexible Agent Identification

The core runner automatically normalizes agent identifiers:

```ruby
# Both Agent objects and string names work
research_agent.add_handoff(writer_agent)     # Agent object
research_agent.add_handoff("Writer")         # String name

# System handles conversion automatically - no type errors
```

### Reasoning Support (GPT-5, o1-preview, o1-mini)

RAAF provides full support for reasoning-capable models that show their "thinking" process:

```ruby
# Create agent with reasoning model
agent = RAAF::Agent.new(
  name: "ReasoningAssistant",
  instructions: "Think through problems step by step",
  model: "gpt-5"
)

runner = RAAF::Runner.new(agent: agent)
result = runner.run("What's the best approach to solve this problem?")

# Reasoning is processed automatically as ReasoningItem
# No warnings logged for reasoning response types
```

**Supported Models:**
- `gpt-5`, `gpt-5-mini`, `gpt-5-nano` (OpenAI GPT-5 family)
- `o1-preview`, `o1-mini` (OpenAI o1 models)
- `sonar-reasoning`, `sonar-reasoning-pro` (Perplexity)

**Parameter Restrictions:**
Reasoning models do not support parameter customization. The following parameters are automatically filtered out with warnings:
- `temperature` - Only default value (1) is supported
- `top_p` - Not supported
- `frequency_penalty` - Not supported
- `presence_penalty` - Not supported
- `logit_bias` - Not supported
- `best_of` - Not supported

```ruby
# These parameters are automatically filtered for reasoning models
agent = RAAF::Agent.new(name: "ReasoningAssistant", model: "gpt-5-nano")
runner = RAAF::Runner.new(agent: agent)

# ⚠️ Warning logged but request succeeds
result = runner.run("Task", temperature: 0.7)
# Parameter 'temperature' is not supported by reasoning model gpt-5-nano
# Suggestion: Remove this parameter - reasoning models only support default settings
```

**Token Tracking:**
Reasoning tokens are tracked separately in usage statistics:
```ruby
result = runner.run("Complex reasoning task...")

# Access reasoning token counts
reasoning_tokens = result.usage[:output_tokens_details][:reasoning_tokens] || 0
regular_tokens = result.usage[:output_tokens] - reasoning_tokens

puts "Reasoning tokens: #{reasoning_tokens} (billed at ~4x rate)"
puts "Regular tokens: #{regular_tokens}"
```

**Cost Considerations:**
- Reasoning tokens are typically **~4x more expensive** than regular tokens
- Use reasoning models for complex tasks requiring step-by-step thinking
- Monitor `output_tokens_details[:reasoning_tokens]` for cost tracking

**Streaming Support:**
Reasoning content streams via `ResponseReasoningDeltaEvent`:
```ruby
runner.stream("Solve this problem...") do |event|
  case event
  when RAAF::StreamingEvents::ResponseReasoningDeltaEvent
    print event.delta  # Stream reasoning content in real-time
  end
end
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

## Thread-Safety Best Practices

**RAAF is thread-safe for production multi-threaded deployments.** All class-level shared state is properly protected with mutex synchronization. Here are the guidelines for working with RAAF in multi-threaded environments:

### When to Use Thread.current (Thread-Local Storage)

Use `Thread.current` for context that should be **isolated per thread**:

```ruby
# ✅ GOOD: Thread-local tracer context
Thread.current[:raaf_tracer] = my_tracer

# ✅ GOOD: Thread-local trace/span context
Thread.current[:current_trace_id] = trace_id

# Usage pattern:
def with_tracer(tracer)
  previous_tracer = Thread.current[:raaf_tracer]

  begin
    Thread.current[:raaf_tracer] = tracer
    yield
  ensure
    Thread.current[:raaf_tracer] = previous_tracer  # Always restore!
  end
end
```

**When to use thread-local storage:**
- Request-scoped data (trace ID, current agent, user context)
- Per-thread logging configuration
- Execution context that should NOT be shared between threads
- Data that needs to survive across method calls in the same thread

**Example reference:** `RAAF::Tracing::TracingRegistry.with_tracer()` and `RAAF::Tracing::Trace::Context`

### When to Use Mutex (Shared State Protection)

Use `Mutex` for **shared class-level state** that must be accessed from multiple threads:

```ruby
# ✅ GOOD: Class-level shared state with mutex
class MyRegistry
  @shared_data = {}
  @data_mutex = Mutex.new

  def self.register(key, value)
    @data_mutex.synchronize do
      @shared_data[key] = value
    end
  end

  def self.get(key)
    @data_mutex.synchronize do
      @shared_data[key]
    end
  end
end
```

**When to use mutex:**
- Process-level configuration (shared across all threads)
- Custom provider registration
- Logging configuration
- Singleton registry patterns
- Lazy initialization of shared instances

**CRITICAL:** Always protect both reads AND writes:

```ruby
# ❌ WRONG: Only protecting writes
@config_mutex.synchronize do
  @configuration ||= Configuration.new
end

# But then reading without protection:
@configuration.log_level  # ❌ NOT protected!

# ✅ CORRECT: Protect reads and writes equally
@config_mutex.synchronize do
  @configuration ||= Configuration.new
  @configuration.log_level
end
```

**Example reference:** `RAAF::ProviderRegistry` (registers custom providers) and `RAAF::Logging.configure()` (configuration management)

### Instance-Level State (No Synchronization Needed)

Instance variables on non-shared objects are **automatically thread-safe**:

```ruby
# ✅ SAFE: Instance variables on per-request objects
class MyProcessor
  def initialize
    @results = []  # Each instance has its own array
  end

  def process(item)
    @results << item  # Safe because each processor instance is separate
  end
end

# Usage in multi-threaded environment:
thread1 = Thread.new { processor1 = MyProcessor.new; processor1.process("a") }
thread2 = Thread.new { processor2 = MyProcessor.new; processor2.process("b") }

# Each thread has its own processor instance with its own @results
```

**No synchronization needed when:**
- Each thread/request has its own instance
- Instance is not shared between threads
- Instances are created per-request (common in Rails)

**Example reference:** `RAAF::Tracing::Traceable` (per-span instance state)

### Lazy Initialization (||=) Pattern

**IMPORTANT:** The `||=` operator is **NOT atomic** in Ruby. Avoid for class-level shared state:

```ruby
# ❌ WRONG: Race condition in lazy initialization
@shared_instance ||= ExpensiveClass.new  # Not atomic!
# Two threads can both see nil, both call ExpensiveClass.new

# ✅ CORRECT: Use mutex for lazy initialization
@mutex.synchronize do
  @shared_instance ||= ExpensiveClass.new  # Atomic within mutex
end

# ✅ ALSO OK: Use for instance-level state (each instance is separate)
@instance_data ||= []  # Safe because each instance has its own @instance_data
```

### Testing Thread-Safety

RAAF includes comprehensive thread-safety tests. When adding new class-level state:

1. **Protect with mutex** if it's shared across threads
2. **Write tests** that verify concurrent access:

```ruby
# Test concurrent access
thread_count = 50
threads = thread_count.times.map do |i|
  Thread.new do
    MyRegistry.register("key_#{i}", "value_#{i}")
  end
end
threads.each(&:join)

# Verify no data loss
expect(MyRegistry.count).to eq(thread_count)
```

See `spec/provider_registry_spec.rb` and `spec/logging_spec.rb` for complete thread-safety test examples.

### Common Patterns by Component

| Component | Shared State | Protection | Thread-Safe |
|-----------|-------------|-----------|-----------|
| **TracingRegistry** | Process tracer | Mutex | ✅ YES |
| **ProviderRegistry** | Custom providers | Mutex | ✅ YES |
| **Logging.configure()** | Configuration | Mutex | ✅ YES |
| **Trace::Context** | Current trace | Thread.current | ✅ YES |
| **Traceable** | Sent spans | Instance vars | ✅ YES |
| **Processor instances** | Collected data | Instance vars | ✅ YES |

### Performance Considerations

**Mutex overhead is minimal:**
- Uncontended mutex acquisition: ~100 nanoseconds
- Most RAAF operations far exceed this (API calls: ~100+ milliseconds)
- Mutex contention only occurs at initialization/configuration time
- No performance penalty during normal request handling

**Optimization strategies:**
- Mutex lock only when necessary (don't hold locks during I/O)
- Read configuration once and cache in request context
- Use thread-local storage for request-scoped data (no mutex needed)

### Production Deployment Guidelines

✅ **Safe for production:**
- Multi-threaded app servers (Puma, Unicorn, etc.)
- Thread pooling and concurrent requests
- Multiple worker processes
- Distributed deployments

✅ **Verified by:**
- Comprehensive thread-safety tests with 100+ concurrent threads
- Stress tests with rapid concurrent operations
- Production deployments in multi-threaded Rails applications

## Perplexity Common Code

**RAAF Core provides shared Perplexity functionality** used by both PerplexityProvider and PerplexityTool for consistent behavior and single source of truth.

### Common Modules

Located in `lib/raaf/perplexity/`:

#### RAAF::Perplexity::Common

**Constants and validation methods:**

```ruby
require 'raaf/perplexity/common'

# Model constants
RAAF::Perplexity::Common::SUPPORTED_MODELS
# => ["sonar", "sonar-pro", "sonar-reasoning", "sonar-reasoning-pro", "sonar-deep-research"]

RAAF::Perplexity::Common::SCHEMA_CAPABLE_MODELS
# => ["sonar-pro", "sonar-reasoning-pro"]

RAAF::Perplexity::Common::RECENCY_FILTERS
# => ["hour", "day", "week", "month", "year"]

# Validation methods
RAAF::Perplexity::Common.validate_model("sonar")          # => true
RAAF::Perplexity::Common.validate_model("invalid")       # => raises ArgumentError

RAAF::Perplexity::Common.validate_schema_support("sonar-pro")  # => true
RAAF::Perplexity::Common.validate_schema_support("sonar")      # => raises ArgumentError
```

#### RAAF::Perplexity::SearchOptions

**Builds web_search_options hash with validation:**

```ruby
require 'raaf/perplexity/search_options'

# Build with domain filter
options = RAAF::Perplexity::SearchOptions.build(
  domain_filter: ["ruby-lang.org", "github.com"]
)
# => { search_domain_filter: ["ruby-lang.org", "github.com"] }

# Build with recency filter
options = RAAF::Perplexity::SearchOptions.build(
  recency_filter: "week"
)
# => { search_recency_filter: "week" }

# Build with both filters
options = RAAF::Perplexity::SearchOptions.build(
  domain_filter: ["ruby-lang.org"],
  recency_filter: "month"
)
# => { search_domain_filter: ["ruby-lang.org"], search_recency_filter: "month" }

# Returns nil if both filters are nil
options = RAAF::Perplexity::SearchOptions.build(
  domain_filter: nil,
  recency_filter: nil
)
# => nil
```

#### RAAF::Perplexity::ResultParser

**Formats API responses consistently:**

```ruby
require 'raaf/perplexity/result_parser'

# Parse provider response
api_response = {
  "choices" => [
    { "message" => { "content" => "Ruby 3.4 includes..." } }
  ],
  "citations" => ["https://ruby-lang.org/..."],
  "web_results" => [
    { "title" => "Ruby 3.4 Released", "url" => "..." }
  ],
  "model" => "sonar"
}

result = RAAF::Perplexity::ResultParser.format_search_result(api_response)
# => {
#   success: true,
#   content: "Ruby 3.4 includes...",
#   citations: ["https://ruby-lang.org/..."],
#   web_results: [...],
#   model: "sonar"
# }

# Handles missing citations/web_results gracefully
result = RAAF::Perplexity::ResultParser.format_search_result(response_without_citations)
# => { success: true, content: "...", citations: [], web_results: [], model: "sonar" }
```

### Usage Pattern

Both PerplexityProvider and PerplexityTool use these common modules:

```ruby
# In PerplexityProvider
class PerplexityProvider < ModelInterface
  def chat_completion(messages:, model:, **kwargs)
    # Validate model using common code
    RAAF::Perplexity::Common.validate_model(model)

    # Build search options using common code
    if kwargs[:web_search_options]
      options = RAAF::Perplexity::SearchOptions.build(
        domain_filter: kwargs[:web_search_options][:search_domain_filter],
        recency_filter: kwargs[:web_search_options][:search_recency_filter]
      )
    end

    # ... make API call ...

    # Format response using common code
    RAAF::Perplexity::ResultParser.format_search_result(response)
  end
end

# In PerplexityTool
class PerplexityTool
  def call(query:, model: "sonar", **kwargs)
    # Build search options using common code
    options = RAAF::Perplexity::SearchOptions.build(
      domain_filter: kwargs[:search_domain_filter],
      recency_filter: kwargs[:search_recency_filter]
    )

    # Call provider
    result = @provider.chat_completion(messages: messages, model: model, **kwargs)

    # Format result using common code
    RAAF::Perplexity::ResultParser.format_search_result(result)
  end
end
```

**Benefits:**
- Single source of truth for models, filters, and validation
- Consistent behavior between provider and tool
- Easy to maintain and extend
- No code duplication

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     RAAF Perplexity Stack                    │
└─────────────────────────────────────────────────────────────┘

┌──────────────────┐                        ┌──────────────────┐
│  Applications    │                        │  Applications    │
│   using RAAF     │                        │   using RAAF     │
└────────┬─────────┘                        └────────┬─────────┘
         │                                           │
         │ uses                                      │ uses
         ▼                                           ▼
┌─────────────────────────────────────────┬─────────────────────┐
│      raaf-providers gem                 │   raaf-tools gem    │
│  ┌────────────────────────────────┐    │ ┌─────────────────┐ │
│  │   PerplexityProvider           │    │ │ PerplexityTool  │ │
│  │  (lib/raaf/perplexity_provider)│    │ │ (lib/raaf/tools)│ │
│  │                                 │    │ │                 │ │
│  │  - chat_completion()            │    │ │ - call()        │ │
│  │  - validate model               │◄───┼─┤ - uses provider │ │
│  │  - build search options         │    │ │ - wraps in      │ │
│  │  - format response              │    │ │   FunctionTool  │ │
│  └────────────────────────────────┘    │ └─────────────────┘ │
│              │                          │         │           │
└──────────────┼──────────────────────────┴─────────┼───────────┘
               │                                    │
               │ imports                   imports  │
               ▼                                    ▼
┌──────────────────────────────────────────────────────────────┐
│                     raaf-core gem                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │            lib/raaf/perplexity/                      │   │
│  │                                                       │   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │  Common (common.rb)                         │    │   │
│  │  │  - SUPPORTED_MODELS constant                │    │   │
│  │  │  - SCHEMA_CAPABLE_MODELS constant           │    │   │
│  │  │  - RECENCY_FILTERS constant                 │    │   │
│  │  │  - validate_model(model)                    │    │   │
│  │  │  - validate_schema_support(model)           │    │   │
│  │  └─────────────────────────────────────────────┘    │   │
│  │                                                       │   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │  SearchOptions (search_options.rb)          │    │   │
│  │  │  - build(domain_filter:, recency_filter:)   │    │   │
│  │  │  - Returns { search_domain_filter: [...],   │    │   │
│  │  │             search_recency_filter: "..." }  │    │   │
│  │  └─────────────────────────────────────────────┘    │   │
│  │                                                       │   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │  ResultParser (result_parser.rb)            │    │   │
│  │  │  - format_search_result(response)           │    │   │
│  │  │  - Returns { success:, content:,            │    │   │
│  │  │             citations:, web_results:,       │    │   │
│  │  │             model: }                        │    │   │
│  │  └─────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘

Data Flow:
──────────

1. Application calls PerplexityProvider.chat_completion() or PerplexityTool.call()
2. Provider/Tool uses Common.validate_model() to check model name
3. Provider/Tool uses SearchOptions.build() to create web_search_options hash
4. Provider makes API call to Perplexity AI
5. Provider/Tool uses ResultParser.format_search_result() to format response
6. Formatted response returned to application

Key Relationships:
─────────────────

• Both PerplexityProvider and PerplexityTool depend on RAAF Core
• Both use identical validation, option building, and result formatting
• Common code lives in RAAF Core (lib/raaf/perplexity/)
• Single source of truth for constants and behavior
• No code duplication between provider and tool
```

### Benefits of Common Code Extraction

#### 1. Single Source of Truth

**Before**: Duplicate constants in provider and tool
```ruby
# In PerplexityProvider
SUPPORTED_MODELS = ["sonar", "sonar-pro", ...].freeze

# In PerplexityTool
SUPPORTED_MODELS = ["sonar", "sonar-pro", ...].freeze  # Duplicate!
```

**After**: Constants defined once in RAAF Core
```ruby
# In RAAF::Perplexity::Common (RAAF Core)
SUPPORTED_MODELS = ["sonar", "sonar-pro", ...].freeze

# Both provider and tool reference
RAAF::Perplexity::Common::SUPPORTED_MODELS
```

**Benefit**: Add new model once, available everywhere immediately.

#### 2. Consistent Validation

**Before**: Duplicate validation logic
```ruby
# In PerplexityProvider
def validate_model(model)
  unless SUPPORTED_MODELS.include?(model)
    raise ArgumentError, "Invalid model..."
  end
end

# In PerplexityTool
def validate_model(model)
  unless SUPPORTED_MODELS.include?(model)  # Duplicate logic
    raise ArgumentError, "Invalid model..."
  end
end
```

**After**: Validation in one place
```ruby
# In RAAF::Perplexity::Common (RAAF Core)
def self.validate_model(model)
  unless SUPPORTED_MODELS.include?(model)
    raise ArgumentError, "Invalid model..."
  end
end

# Both use same validation
RAAF::Perplexity::Common.validate_model(model)
```

**Benefit**: Fix validation bug once, fixed everywhere.

#### 3. Identical Response Format

**Before**: Different formatting logic in provider and tool
```ruby
# Provider formatting
def format_response(resp)
  {
    content: resp.dig("choices", 0, "message", "content"),
    citations: resp["citations"] || []
  }
end

# Tool formatting (slightly different!)
def format_result(resp)
  {
    success: true,
    content: resp.dig("choices", 0, "message", "content"),
    citations: resp["citations"] || [],
    web_results: resp["web_results"] || []  # Different fields!
  }
end
```

**After**: Single ResultParser used by both
```ruby
# In RAAF::Perplexity::ResultParser (RAAF Core)
def self.format_search_result(response)
  {
    success: true,
    content: response.dig("choices", 0, "message", "content") || "",
    citations: response["citations"] || [],
    web_results: response["web_results"] || [],
    model: response["model"]
  }
end

# Both use identical formatting
RAAF::Perplexity::ResultParser.format_search_result(response)
```

**Benefit**: Provider and tool return identical structure. No surprises.

#### 4. Simplified Testing

**Before**: Test validation, formatting, options in both provider and tool tests
```ruby
# providers/spec/perplexity_provider_spec.rb (44 tests)
describe "validation" do ... end
describe "search options" do ... end
describe "result formatting" do ... end

# tools/spec/perplexity_tool_spec.rb (27 tests)
describe "validation" do ... end  # Duplicate tests
describe "search options" do ... end  # Duplicate tests
describe "result formatting" do ... end  # Duplicate tests
```

**After**: Test common code once, test provider/tool integration separately
```ruby
# core/spec/perplexity/common_spec.rb (test once)
describe "validation" do ... end

# core/spec/perplexity/search_options_spec.rb (test once)
describe "option building" do ... end

# core/spec/perplexity/result_parser_spec.rb (test once)
describe "result formatting" do ... end

# providers/spec/perplexity_provider_spec.rb (integration tests only)
describe "uses common code correctly" do ... end

# tools/spec/perplexity_tool_spec.rb (integration tests only)
describe "uses common code correctly" do ... end
```

**Benefit**: Less test duplication. Faster test runs.

#### 5. Easy Maintenance

**Scenario**: Perplexity adds new model `"sonar-ultra"`

**Before**: Update in multiple places
```ruby
# 1. Update providers/lib/raaf/perplexity_provider.rb
SUPPORTED_MODELS = [..., "sonar-ultra"].freeze

# 2. Update tools/lib/raaf/tools/perplexity_tool.rb
SUPPORTED_MODELS = [..., "sonar-ultra"].freeze

# 3. Update both test suites
# 4. Risk: Easy to miss one location
```

**After**: Update in one place
```ruby
# Update core/lib/raaf/perplexity/common.rb
SUPPORTED_MODELS = [..., "sonar-ultra"].freeze

# Provider and tool immediately support new model
# All tests automatically cover new model
```

**Benefit**: One-line change. Zero risk of inconsistency.

#### 6. Clear Ownership

**Before**: Perplexity logic scattered across gems
```
raaf/
├── providers/
│   └── lib/raaf/perplexity_provider.rb (validation, formatting)
└── tools/
    └── lib/raaf/tools/perplexity_tool.rb (validation, formatting)
```

**After**: Clear ownership in RAAF Core
```
raaf/
├── core/
│   └── lib/raaf/perplexity/  ← Single source of truth
│       ├── common.rb
│       ├── search_options.rb
│       └── result_parser.rb
├── providers/
│   └── lib/raaf/perplexity_provider.rb (uses common code)
└── tools/
    └── lib/raaf/tools/perplexity_tool.rb (uses common code)
```

**Benefit**: Know exactly where to update Perplexity logic.

### Summary: Before vs After

| Aspect | Before (Duplicated) | After (Common Code) |
|--------|-------------------|-------------------|
| Model constants | 2 copies | 1 copy in Core |
| Validation logic | 2 copies | 1 copy in Core |
| Search option building | 2 copies | 1 copy in Core |
| Result formatting | 2 copies | 1 copy in Core |
| Adding new model | Update 2+ files | Update 1 file |
| Fixing validation bug | Fix 2+ places | Fix 1 place |
| Test coverage | Duplicate tests | Test once, integrate twice |
| Response consistency | Risk of drift | Always identical |
| Lines of code | ~400 duplicated | ~200 shared |
| Maintenance burden | High | Low |

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

### Parameter Compatibility

**IMPORTANT**: The Responses API does NOT support these Chat Completions parameters:
- `frequency_penalty`
- `presence_penalty`
- `best_of`
- `logit_bias`

If you provide these parameters to `ResponsesProvider`, they will:
1. **Log a warning** with the parameter name and suggested action
2. **Be silently filtered** from the API request (not sent to OpenAI)
3. **Not cause errors** - your request will succeed with other parameters

```ruby
# This will work but log warnings
provider.responses_completion(
  messages: [{ role: "user", content: "Hello" }],
  model: "gpt-4o",
  temperature: 0.7,           # ✅ Supported - will be used
  frequency_penalty: 0.5      # ⚠️ Warning logged - will be filtered
)

# Warning logged:
# ⚠️ Parameter 'frequency_penalty' is not supported by OpenAI Responses API
# Suggestion: Remove this parameter or use Chat Completions API (OpenAIProvider) instead
```

**If you need these parameters**, use `OpenAIProvider` (Chat Completions API) instead:

```ruby
provider = RAAF::Models::OpenAIProvider.new
runner = RAAF::Runner.new(agent: agent, provider: provider)

# Now frequency_penalty and presence_penalty are supported
result = runner.run("Hello", frequency_penalty: 0.5, presence_penalty: 0.3)
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