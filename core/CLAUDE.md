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
- **ModelInterface** (`lib/raaf/models/interface.rb`) - Base class with built-in retry, throttling, and rate limiting
- **RateLimiter** (`lib/raaf/rate_limiter.rb`) - **NEW** - Shared rate limiting across concurrent agents with pluggable storage
- **Throttler** (`lib/raaf/throttler.rb`) - **NEW** - Token bucket rate limiting for providers and tools
- **ThrottleConfig** (`lib/raaf/throttle_config.rb`) - **NEW** - Provider default RPM limits registry
- **ResponsesProvider** (`lib/raaf/models/responses_provider.rb`) - **DEFAULT** - OpenAI Responses API with retry and throttling
- **OpenAIProvider** (`lib/raaf/models/openai_provider.rb`) - **DEPRECATED** - Legacy Chat Completions API
- **FunctionTool** (`lib/raaf/function_tool.rb`) - Tool wrapper for Ruby methods with throttling support
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

## Usage Tracking and Token Field Naming

**RAAF uses canonical token field names** aligned with modern LLM APIs for consistent usage tracking across all providers.

### Canonical Field Names

RAAF standardizes on these token field names:

```ruby
# ✅ CANONICAL RAAF FORMAT (use these)
result.usage[:input_tokens]              # Input/prompt tokens
result.usage[:output_tokens]             # Output/completion tokens
result.usage[:total_tokens]              # Total tokens used
result.usage[:cache_read_input_tokens]   # Cached tokens (if supported)

# ❌ OLD CHAT COMPLETIONS FORMAT (deprecated)
result.usage[:prompt_tokens]             # Legacy name
result.usage[:completion_tokens]         # Legacy name
```

**Why canonical names?** Modern LLM APIs (Anthropic Claude, Google Gemini, etc.) use `input_tokens` and `output_tokens` as standard field names. RAAF aligns with this industry convention for consistency.

### Architecture Pattern

All providers follow a standardized pattern using `RAAF::Usage::Normalizer`:

```ruby
# Provider Implementation Pattern
class MyProvider < RAAF::Models::Interface
  def perform_chat_completion(messages:, model:, **kwargs)
    # 1. Make API call (returns native provider format)
    response = make_api_call(messages, model, kwargs)

    # 2. Normalize to canonical RAAF format
    if response["usage"]
      normalized_usage = RAAF::Usage::Normalizer.normalize(
        response,
        provider_name: "my_provider",
        model: model
      )
      response["usage"] = normalized_usage if normalized_usage
    end

    # 3. Return standardized response
    response
  end
end
```

**Key Benefits:**

1. **Single Source of Truth**: `Usage::Normalizer` handles all token field conversions
2. **Provider Independence**: Downstream code doesn't need provider-specific logic
3. **Automatic Conversion**: Normalizer reads both old and canonical formats
4. **Future-Proof**: New providers automatically get canonical format

### Provider-Specific Metadata

Providers can preserve provider-specific metadata alongside canonical fields:

```ruby
# Example: Ollama provider preserves timing metadata
{
  "input_tokens" => 100,     # Canonical RAAF format
  "output_tokens" => 50,     # Canonical RAAF format
  "total_tokens" => 150,     # Canonical RAAF format
  "total_duration" => 1234,  # Ollama-specific metadata
  "load_duration" => 234     # Ollama-specific metadata
}
```

### Usage::Normalizer Implementation

The normalizer handles conversion from various provider formats:

```ruby
# Normalizer reads multiple formats and returns canonical format
normalized = RAAF::Usage::Normalizer.normalize(
  {
    "usage" => {
      "prompt_tokens" => 100,      # Old format
      "completion_tokens" => 50    # Old format
    },
    "model" => "gpt-4o"
  },
  provider_name: "openai",
  model: "gpt-4o"
)

# Returns canonical format
normalized
# => {
#   "input_tokens" => 100,
#   "output_tokens" => 50,
#   "total_tokens" => 150
# }
```

### Backward Compatibility

Runner includes defensive fallbacks for old code:

```ruby
# Runner supports both formats (line 1522-1523)
input_tokens = completion.usage[:input_tokens] || completion.usage[:prompt_tokens] || 0
output_tokens = completion.usage[:output_tokens] || completion.usage[:completion_tokens] || 0

# But all providers MUST return canonical format
```

### Migration Guide for Providers

If you're implementing a custom provider, follow this pattern:

```ruby
# ✅ CORRECT: Use Usage::Normalizer
def parse_response(api_response)
  # Build intermediate structure
  usage_body = {
    "usage" => {
      "prompt_tokens" => api_response["input_count"],
      "completion_tokens" => api_response["output_count"]
    },
    "model" => api_response["model"]
  }

  # Normalize to canonical format
  normalized_usage = RAAF::Usage::Normalizer.normalize(
    usage_body,
    provider_name: "my_provider",
    model: api_response["model"]
  )

  {
    "content" => api_response["text"],
    "usage" => normalized_usage,
    "model" => api_response["model"]
  }
end

# ❌ WRONG: Explicit conversion (bypasses normalizer)
def parse_response(api_response)
  {
    "content" => api_response["text"],
    "usage" => {
      "prompt_tokens" => api_response["input_count"],    # Don't do this!
      "completion_tokens" => api_response["output_count"] # Don't do this!
    }
  }
end
```

### Historical Context

RAAF originally used the Chat Completions API format (`prompt_tokens`, `completion_tokens`) but migrated to the Responses API format (`input_tokens`, `output_tokens`) for:

1. **Industry Alignment**: Match modern LLM APIs (Anthropic, Gemini, etc.)
2. **Python SDK Compatibility**: Align with OpenAI Python SDK conventions
3. **Clarity**: "input" and "output" are more intuitive than "prompt" and "completion"

All 13 RAAF providers now use canonical field names exclusively.

## Rate Limiting and Throttling - Quick Start

**RAAF provides two complementary rate limiting mechanisms** to prevent API quota exhaustion:

### Quick Decision Matrix

```
┌─────────────────────────────────────────────────────────────┐
│              When to Use Rate Limiting Features             │
└─────────────────────────────────────────────────────────────┘

YOUR SCENARIO                          USE THIS
─────────────────────────────────────  ────────────────────────
Single agent, simple rate control      → Throttler only
Multiple concurrent agents (threads)   → RateLimiter only
Production multi-threaded app          → RateLimiter + Retry
Development/testing single agent       → Throttler + Retry
Distributed deployment (multi-server)  → RateLimiter (Redis) + Retry
Need per-method isolation              → Throttler
Need cross-process coordination        → RateLimiter (Redis)
Want burst capacity                    → Both (Throttler for bursts)
```

### The Three-Layer Defense

```ruby
# RECOMMENDED: Complete protection pattern
provider = RAAF::Models::GeminiProvider.new

# Layer 1: RateLimiter - Coordinate across all agent instances
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 15  # Gemini free tier
)

# Layer 2: Throttler - Smooth bursts within single instance (optional)
provider.configure_throttle(
  rpm: 15,
  enabled: true
)

# Layer 3: Retry - Handle transient failures (built-in, always active)
provider.configure_retry(max_attempts: 3)

# Result: Production-ready multi-agent deployment
# - RateLimiter prevents concurrent agents from exceeding 15 RPM
# - Throttler smooths burst traffic within each agent
# - Retry handles network errors and other transient issues
```

### 30-Second Guide: Most Common Patterns

**Pattern 1: Single-Threaded Development**
```ruby
# Simple case: One agent at a time
provider = RAAF::Models::GeminiProvider.new
provider.configure_throttle(rpm: 10, enabled: true)
runner = RAAF::Runner.new(agent: agent, provider: provider)
```

**Pattern 2: Multi-Threaded Production (RECOMMENDED)**
```ruby
# Production case: Multiple concurrent agents
provider = RAAF::Models::GeminiProvider.new
provider.configure_rate_limiting(enabled: true, requests_per_minute: 15)
runner = RAAF::Runner.new(agent: agent, provider: provider)

# Deploy 20 concurrent agents - all coordinate to stay within 15 RPM
20.times.map { Thread.new { runner.run("Task") } }.each(&:join)
```

**Pattern 3: Distributed Production (Redis)**
```ruby
# Multi-server deployment: Coordinate across servers
redis_storage = RAAF::RateLimiter::RedisStorage.new(
  redis: Redis.new(url: ENV['REDIS_URL'])
)

provider = RAAF::Models::GeminiProvider.new
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 15,
  storage: redis_storage
)

# Now all servers share the same rate limit bucket
```

### Core Differences at a Glance

| Feature | RateLimiter | Throttler |
|---------|-------------|-----------|
| **Best For** | Concurrent agents (production) | Single agent (development) |
| **Coordination** | Shared across all instances | Per-instance only |
| **Storage** | Pluggable (Memory/Redis/Rails.cache) | In-memory only |
| **Thread-Safe** | ✅ Yes (Concurrent::Map) | ✅ Yes (Monitor) |
| **Window** | Minute-boundary (resets at :00) | Continuous refill |
| **Burst Handling** | First N requests immediate | Configurable burst capacity |
| **Use Case** | 20 concurrent agents → 15 RPM total | 1 agent with burst capacity |

### Complete Documentation

For deep dive into each mechanism, see sections below:
- **Throttler Deep Dive** - Token bucket, burst capacity, per-method isolation
- **RateLimiter Deep Dive** - Shared coordination, storage backends, minute windows
- **Performance Characteristics** - Overhead, timing, thread-safety guarantees
- **Production Deployment** - Configuration, monitoring, troubleshooting

---

## Rate Limiting with Throttler

**RAAF includes built-in proactive rate limiting** to prevent API quota exhaustion and rate limit errors. The Throttler module uses a token bucket algorithm to enforce requests-per-minute (RPM) limits before making API calls.

### Key Concepts

- **Proactive vs Reactive**: Throttling prevents rate limits (proactive) while retry logic handles them (reactive)
- **Token Bucket Algorithm**: Tokens refill continuously at the configured RPM rate, with a burst capacity for traffic spikes
- **Opt-In Design**: Throttling is disabled by default - must be explicitly enabled
- **Per-Method Isolation**: Separate token buckets per method prevent different operations from blocking each other
- **Thread-Safe**: Uses Monitor for concurrent request handling

### Automatic Configuration

All providers are automatically configured with default RPM limits based on their type:

```ruby
# Provider throttling is auto-configured but disabled by default
provider = RAAF::Models::GeminiProvider.new

# Default limits loaded from ThrottleConfig:
# - Gemini: 10 RPM (free tier)
# - OpenAI: 500 RPM (tier 1)
# - Anthropic: 1000 RPM (tier 1)
# - Groq: 30 RPM (free tier)
# - Perplexity: 20 RPM (standard)

# Enable throttling to enforce limits
provider.configure_throttle(enabled: true)

# Now requests will be rate-limited to 10 RPM for Gemini
runner = RAAF::Runner.new(agent: agent, provider: provider)
```

### Environment Variable Overrides

Override default RPM limits using environment variables:

```bash
# Override Gemini's default 10 RPM to 60 RPM (paid tier)
export RAAF_THROTTLE_GEMINI_RPM=60

# Override OpenAI's default 500 RPM
export RAAF_THROTTLE_OPENAI_RPM=5000

# Override Perplexity's default 20 RPM
export RAAF_THROTTLE_PERPLEXITY_RPM=100
```

```ruby
# Environment variable is automatically applied
provider = RAAF::Models::GeminiProvider.new
provider.configure_throttle(enabled: true)

# Now uses 60 RPM from RAAF_THROTTLE_GEMINI_RPM instead of 10 RPM default
```

### Provider Throttling Configuration

```ruby
# Enable with default RPM (auto-detected from provider type)
provider = RAAF::Models::GeminiProvider.new
provider.configure_throttle(enabled: true)

# Custom RPM and burst capacity
provider.configure_throttle(
  rpm: 60,        # Requests per minute
  burst: 10,      # Burst capacity (defaults to rpm/10)
  timeout: 30,    # Max wait time in seconds (default: 30)
  enabled: true   # Enable throttling
)

# Disable throttling
provider.configure_throttle(enabled: false)
```

### Tool Throttling Configuration

```ruby
# Enable throttling for expensive API tool
expensive_tool = FunctionTool.new(
  method(:call_expensive_api),
  throttle: { rpm: 10, enabled: true }
)

# Add to agent
agent.add_tool(expensive_tool)

# Tool calls will be rate-limited to 10 RPM
```

### Throttle Statistics

Monitor throttling behavior with statistics tracking:

```ruby
provider = RAAF::Models::GeminiProvider.new
provider.configure_throttle(rpm: 60, enabled: true)

# Make requests
10.times { runner.run("Hello") }

# Check statistics
stats = provider.throttle_stats
# => {
#   requests_throttled: 4,        # Requests that waited for tokens
#   total_wait_time: 2.3,         # Total seconds spent waiting
#   timeout_failures: 0           # Requests that timed out
# }

# Reset statistics
provider.reset_throttle_stats
```

### Real-World Example: Gemini Rate Limit

**Problem:** Gemini free tier has a 10 RPM limit, causing frequent rate limit errors.

**Solution without throttling (reactive retry):**
```ruby
# Without throttling - hits rate limit, retries 5 times, all fail
# Total cost: 6 failed API calls, 15+ seconds wasted on retries
provider = RAAF::Models::GeminiProvider.new
runner = RAAF::Runner.new(agent: agent, provider: provider)

# Rapid requests exceed 10 RPM
20.times { runner.run("Analyze this...") }
# ❌ ERROR: Rate limit exceeded (15/10 RPM)
# ❌ Retry 1 failed... Retry 2 failed... Retry 3 failed... (all within same 60s window)
```

**Solution with throttling (proactive prevention):**
```ruby
# With throttling - prevents rate limit, distributes requests evenly
provider = RAAF::Models::GeminiProvider.new
provider.configure_throttle(rpm: 10, enabled: true)
runner = RAAF::Runner.new(agent: agent, provider: provider)

# Requests automatically distributed to respect 10 RPM limit
20.times { runner.run("Analyze this...") }
# ✅ Success: All 20 requests complete without errors
# ✅ Time: ~2 minutes (distributed evenly at 10 RPM)
# ✅ Cost: 20 successful API calls, zero wasted retries
```

### Throttling + Retry Pattern

**Throttling and retry work together** for robust API handling:

```ruby
provider = RAAF::Models::GeminiProvider.new

# Configure both throttling (proactive) and retry (reactive)
provider.configure_throttle(rpm: 10, enabled: true)  # Prevent rate limits
provider.configure_retry(max_attempts: 3)            # Handle transient errors

# Throttling runs BEFORE retry
# 1. Throttle enforces 10 RPM limit
# 2. If request still fails (network error, etc.), retry kicks in
# 3. Result: Fewer retries, better success rate
```

### Default RPM Limits by Provider

| Provider | Default RPM | Tier | Environment Variable |
|----------|-------------|------|---------------------|
| Gemini | 10 | Free | `RAAF_THROTTLE_GEMINI_RPM` |
| Perplexity | 20 | Standard | `RAAF_THROTTLE_PERPLEXITY_RPM` |
| Groq | 30 | Free | `RAAF_THROTTLE_GROQ_RPM` |
| Cohere | 100 | Trial | `RAAF_THROTTLE_COHERE_RPM` |
| xAI | 60 | Standard | `RAAF_THROTTLE_XAI_RPM` |
| Moonshot | 60 | Standard | `RAAF_THROTTLE_MOONSHOT_RPM` |
| OpenAI | 500 | Tier 1 | `RAAF_THROTTLE_OPENAI_RPM` |
| Responses | 500 | Tier 1 | `RAAF_THROTTLE_RESPONSES_RPM` |
| Anthropic | 1000 | Tier 1 | `RAAF_THROTTLE_ANTHROPIC_RPM` |
| HuggingFace | 1000 | Inference API | `RAAF_THROTTLE_HUGGINGFACE_RPM` |
| Together | 600 | Standard | `RAAF_THROTTLE_TOGETHER_RPM` |
| LiteLLM | nil | Backend-dependent | `RAAF_THROTTLE_LITELLM_RPM` |
| OpenRouter | nil | Model-dependent | `RAAF_THROTTLE_OPENROUTER_RPM` |

**Note:** Paid tiers typically have higher limits. Use environment variables or `configure_throttle(rpm: ...)` to override defaults.

### Per-Method Token Buckets

Each method gets its own token bucket to prevent cross-method blocking:

```ruby
class MyProvider < RAAF::Models::ModelInterface
  def chat_completion(...)
    with_throttle(:chat_completion) do
      # Has its own token bucket
    end
  end

  def stream_completion(...)
    with_throttle(:stream_completion) do
      # Different token bucket - won't block chat_completion
    end
  end
end
```

### Timeout Handling

When throttle timeout is exceeded, `ThrottleTimeoutError` is raised:

```ruby
provider = RAAF::Models::GeminiProvider.new
provider.configure_throttle(rpm: 1, timeout: 5, enabled: true)

begin
  # First request succeeds immediately
  runner.run("First request")

  # Second request needs to wait 60 seconds for next token
  # But timeout is only 5 seconds
  runner.run("Second request")
rescue RAAF::ThrottleTimeoutError => e
  puts "Throttle timeout exceeded: #{e.message}"
  # => "Throttle timeout exceeded (5s) for GeminiProvider#chat_completion"
end
```

## Rate Limiting with RateLimiter

**NEW:** RAAF now includes a dedicated RateLimiter class that provides shared rate limiting across multiple concurrent agent instances, solving the problem of concurrent agents overwhelming provider rate limits.

### Problem: Concurrent Agents Exceeding Rate Limits

Even with retry logic and throttling, multiple concurrent agents can exceed provider RPM limits:

```ruby
# Problem: 20 concurrent agents × 1 request each = 20 RPM
# But Gemini free tier only allows 15 RPM
20.times.map do |i|
  Thread.new do
    agent = ProspectScoringAgent.new(prospect: prospects[i])
    agent.run  # Each makes 1 request
  end
end.each(&:join)

# Result: 5 agents hit rate limit, retries fail (all in same 60s window)
# ❌ 5 failed agents, wasted API calls, delayed results
```

### Solution: Shared RateLimiter Coordination

The RateLimiter uses a token bucket algorithm with shared storage to coordinate across all agent instances:

```ruby
# Enable rate limiting on provider
provider = RAAF::Models::GeminiProvider.new
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 15  # Gemini free tier limit
)

runner = RAAF::Runner.new(agent: agent, provider: provider)

# Now 20 concurrent agents coordinate to stay within 15 RPM limit
20.times.map do |i|
  Thread.new do
    agent = ProspectScoringAgent.new(prospect: prospects[i])
    runner.run("Score this prospect")  # Waits for token if needed
  end
end.each(&:join)

# Result: First 15 agents run immediately, remaining 5 wait for next window
# ✅ All 20 complete successfully, zero wasted API calls
```

### Basic Configuration

```ruby
# Enable with default RPM (auto-detected from provider type)
provider = RAAF::Models::GeminiProvider.new
provider.configure_rate_limiting(enabled: true)

# Custom RPM limit
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 60  # Override default
)

# Disable rate limiting
provider.configure_rate_limiting(enabled: false)
```

### Storage Backends

RateLimiter supports three storage backends for different deployment scenarios:

```ruby
# 1. Memory Storage (default) - Single process
provider.configure_rate_limiting(
  enabled: true,
  storage: RAAF::RateLimiter::MemoryStorage.new
)

# 2. Redis Storage - Distributed coordination across servers
redis_storage = RAAF::RateLimiter::RedisStorage.new(
  redis: Redis.new(url: ENV['REDIS_URL'])
)
provider.configure_rate_limiting(
  enabled: true,
  storage: redis_storage
)

# 3. Rails.cache Storage - Uses Rails caching backend
rails_storage = RAAF::RateLimiter::RailsCacheStorage.new
provider.configure_rate_limiting(
  enabled: true,
  storage: rails_storage
)
```

### Rate Limiter Status

Monitor rate limiter state in real-time:

```ruby
provider = RAAF::Models::GeminiProvider.new
provider.configure_rate_limiting(enabled: true, requests_per_minute: 15)

# Check status
status = provider.rate_limiter_status
# => {
#   provider: "gemini",
#   current_requests: 12,
#   limit: 15,
#   window_start: 2025-01-12 13:45:00 UTC,
#   available: true,
#   tokens_per_minute: 1000000
# }

# Reset rate limiter (useful for testing)
provider.reset_rate_limiter
```

### Default RPM Limits

RateLimiter uses the same provider defaults as Throttler:

| Provider | Default RPM | Storage Backend |
|----------|-------------|----------------|
| Gemini | 15 | Memory (single process) |
| Perplexity | 50 | Memory (single process) |
| Groq | 30 | Memory (single process) |
| OpenAI | 3 (free) / 500 (tier 1) | Memory (single process) |
| Anthropic | 5 (free) / 1000 (tier 1) | Memory (single process) |

**Note:** For distributed deployments, use Redis or Rails.cache storage for cross-server coordination.

### RateLimiter vs Throttler

Both implement token bucket algorithms but serve different use cases:

| Feature | RateLimiter | Throttler |
|---------|-------------|-----------|
| **Scope** | Shared across all instances | Per-provider instance |
| **Use Case** | Concurrent agents (threads/processes) | Single agent rate limiting |
| **Storage** | Pluggable (Memory/Redis/Rails.cache) | In-memory only |
| **Coordination** | Multi-agent coordination | Single-agent throttling |
| **Best For** | Production multi-threaded apps | Development/testing |

**Recommendation:** Use RateLimiter for production applications with concurrent agents. Use Throttler for single-agent scenarios or development.

### Rate Limiting + Throttling + Retry Pattern

All three can work together for maximum reliability:

```ruby
provider = RAAF::Models::GeminiProvider.new

# 1. Rate limiting - Coordinate across concurrent agents
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 15
)

# 2. Throttling - Additional per-instance smoothing
provider.configure_throttle(
  rpm: 15,
  enabled: true
)

# 3. Retry - Handle transient failures
provider.configure_retry(max_attempts: 3)

# Execution order:
# 1. RateLimiter enforces shared RPM limit (waits if bucket empty)
# 2. Throttler smooths bursts within single instance
# 3. Retry handles any remaining transient errors
```

---

## Rate Limiting Deep Dive

### Architecture and Design Decisions

**RateLimiter** was designed specifically for multi-agent production environments where multiple concurrent agents can overwhelm provider rate limits. It uses a shared token bucket algorithm with pluggable storage backends.

#### Why Minute-Boundary Windows?

RateLimiter uses minute-boundary windows (resets at :00 seconds) instead of continuous rolling windows:

```ruby
# Example: Current time is 13:45:37

current_window_start = Time.new(now.year, now.month, now.day, now.hour, now.min, 0)
# => 2025-01-12 13:45:00

# Window resets at 13:46:00 regardless of when requests were made
```

**Rationale:**
1. **Provider Alignment**: Most AI providers (OpenAI, Anthropic, Gemini) use minute-boundary rate limits
2. **Predictability**: Window reset timing is deterministic (always at :00 seconds)
3. **Simplicity**: No complex sliding window calculations needed
4. **Storage Efficiency**: Only need to store count and window_start timestamp

**Trade-off**: Near minute boundaries (13:45:58, 13:46:01), requests may experience variable wait times:
- At 13:45:58: Window about to reset, wait ~2 seconds
- At 13:46:01: Fresh window, immediate execution

This is acceptable because:
- Average wait time is still correct (distributed evenly over 60 seconds)
- Total throughput matches configured RPM limit
- Simpler implementation is more reliable

#### Storage Backend Design

RateLimiter supports three storage backends for different deployment scenarios:

**1. MemoryStorage (Default)**
```ruby
# Uses Concurrent::Map for thread-safety
class MemoryStorage
  def initialize
    @cache = Concurrent::Map.new  # Thread-safe hash
  end

  def fetch(key)
    @cache[key] || yield
  end
end

# Single process coordination
provider.configure_rate_limiting(enabled: true)
```

**Characteristics:**
- ✅ Zero external dependencies
- ✅ Fastest performance (in-memory)
- ❌ Only coordinates within single process
- ❌ Lost on process restart

**Best for**: Development, testing, single-server deployments

**2. RedisStorage (Distributed)**
```ruby
# Uses Redis for cross-process coordination
class RedisStorage
  def initialize(redis: nil)
    @redis = redis || Redis.new
  end

  def fetch(key)
    value = @redis.get(key)
    value ? JSON.parse(value, symbolize_names: true) : yield
  end
end

# Multi-server coordination
redis_storage = RAAF::RateLimiter::RedisStorage.new(
  redis: Redis.new(url: ENV['REDIS_URL'])
)
provider.configure_rate_limiting(
  enabled: true,
  storage: redis_storage
)
```

**Characteristics:**
- ✅ Coordinates across multiple servers
- ✅ Survives process restarts
- ✅ Scales horizontally
- ❌ Requires Redis server
- ❌ Network latency (1-5ms)

**Best for**: Multi-server production deployments, Kubernetes clusters

**3. RailsCacheStorage (Rails Integration)**
```ruby
# Uses Rails.cache backend (Redis, Memcached, etc.)
class RailsCacheStorage
  def initialize(cache: nil)
    @cache = cache || Rails.cache
  end

  def fetch(key)
    @cache.fetch(key) { yield }
  end
end

# Rails application
rails_storage = RAAF::RateLimiter::RailsCacheStorage.new
provider.configure_rate_limiting(
  enabled: true,
  storage: rails_storage
)
```

**Characteristics:**
- ✅ Uses existing Rails cache infrastructure
- ✅ No additional Redis setup needed
- ✅ Coordinates based on cache backend (Redis, Memcached, etc.)
- ❌ Requires Rails
- ❌ Performance depends on cache backend

**Best for**: Rails applications with existing cache infrastructure

#### Thread-Safety Guarantees

**RateLimiter uses `Concurrent::Map`** (not Mutex) for thread-safe storage access:

```ruby
class MemoryStorage
  def initialize
    @cache = Concurrent::Map.new  # Lock-free data structure
  end

  def fetch(key)
    @cache[key] || yield  # Atomic read
  end

  def write(key, value, expires_in: nil)
    @cache[key] = value  # Atomic write
  end
end
```

**Why Concurrent::Map over Mutex?**

1. **Lock-Free Performance**: No mutex contention, faster under high concurrency
2. **Non-Blocking Reads**: Multiple threads can read simultaneously
3. **Atomic Operations**: CAS (Compare-And-Swap) guarantees consistency

**Concurrent::Map Guarantees:**
- ✅ Atomic reads and writes
- ✅ Thread-safe enumeration
- ✅ No deadlocks
- ✅ Scales with CPU cores (lock-free)

**Trade-off**: Concurrent::Map can temporarily use more memory than Mutex-protected Hash due to internal lock-free structures. This is acceptable because:
- Memory overhead is minimal (~32 bytes per key)
- Performance gain under concurrency is significant (10-50x faster)
- Most deployments have < 100 providers (< 3.2 KB overhead)

### Performance Characteristics

#### RateLimiter Performance

**Overhead per acquire():**
- Memory storage: 0.01-0.05ms (10-50 microseconds)
- Redis storage: 1-5ms (network round-trip)
- Rails.cache storage: Depends on backend (Redis: 1-5ms, Memcached: 0.5-2ms)

**Compared to API call:**
- Typical AI API call: 100-2000ms
- RateLimiter overhead: 0.01-5ms (0.01% - 5% of total time)

**Throughput capacity:**
- Memory storage: 100,000+ acquires/second (single process)
- Redis storage: 1,000-10,000+ acquires/second (depends on Redis latency)

**Benchmark results:**
```ruby
# Memory storage benchmark
Benchmark.measure do
  10_000.times { rate_limiter.acquire { "work" } }
end
# => 0.3 seconds (33,000 acquires/second)

# Redis storage benchmark (localhost Redis)
Benchmark.measure do
  10_000.times { rate_limiter.acquire { "work" } }
end
# => 15 seconds (667 acquires/second)
```

#### Throttler Performance

**Overhead per with_throttle():**
- Token bucket check: 0.005-0.01ms (5-10 microseconds)
- Monitor synchronization: 0.001ms (1 microsecond)
- Total overhead: < 0.02ms (20 microseconds)

**Compared to API call:**
- Typical AI API call: 100-2000ms
- Throttler overhead: 0.02ms (0.001% - 0.02% of total time)

**Throughput capacity:**
- 50,000+ checks/second per provider instance

### When to Use Which Feature

#### Use RateLimiter When:

1. **Multiple concurrent agents** (threads or processes)
   ```ruby
   # 20 agents running simultaneously
   20.times.map do
     Thread.new do
       agent = MyAgent.new
       agent.run  # All coordinate via RateLimiter
     end
   end.each(&:join)
   ```

2. **Distributed deployment** (multiple servers)
   ```ruby
   # Kubernetes with 5 pods, each running 10 threads
   # All 50 threads share rate limit via Redis
   redis_storage = RAAF::RateLimiter::RedisStorage.new(
     redis: Redis.new(url: ENV['REDIS_URL'])
   )
   provider.configure_rate_limiting(enabled: true, storage: redis_storage)
   ```

3. **Strict rate limit enforcement** (must never exceed provider limits)
   ```ruby
   # Gemini free tier: exactly 15 RPM, no exceptions
   provider.configure_rate_limiting(enabled: true, requests_per_minute: 15)
   ```

#### Use Throttler When:

1. **Single agent development** (no concurrency)
   ```ruby
   # Development/testing: one agent at a time
   provider.configure_throttle(rpm: 10, enabled: true)
   agent.run("Task")
   ```

2. **Need burst capacity** (handle traffic spikes)
   ```ruby
   # Allow 10 immediate requests, then throttle to 60 RPM
   provider.configure_throttle(rpm: 60, burst: 10, enabled: true)
   ```

3. **Per-method rate limiting** (different limits for different operations)
   ```ruby
   class CustomProvider < RAAF::Models::ModelInterface
     def chat_completion(...)
       with_throttle(:chat_completion) { ... }  # 60 RPM
     end

     def embeddings(...)
       with_throttle(:embeddings) { ... }  # Different limit
     end
   end
   ```

#### Use Both When:

1. **Production multi-agent deployment with burst handling**
   ```ruby
   # RateLimiter: coordinate across agents
   provider.configure_rate_limiting(enabled: true, requests_per_minute: 60)

   # Throttler: smooth bursts within each agent
   provider.configure_throttle(rpm: 60, burst: 10, enabled: true)

   # Result: 20 agents coordinate to 60 RPM total,
   # but each can burst up to 10 requests when available
   ```

2. **Cost optimization** (reduce wasted retry attempts)
   ```ruby
   # Three-layer defense
   provider.configure_rate_limiting(enabled: true, requests_per_minute: 15)  # Layer 1: Global coordination
   provider.configure_throttle(rpm: 15, enabled: true)  # Layer 2: Per-instance smoothing
   provider.configure_retry(max_attempts: 3)  # Layer 3: Handle transient errors
   ```

### Common Pitfalls and Solutions

#### Pitfall 1: Timeout Too Short

**Problem:**
```ruby
# Timeout set too short for rate limit
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 1,  # 1 request per minute
  max_wait_seconds: 5      # But timeout is only 5 seconds
)

provider.acquire { API.call }  # First request: success
sleep(1)
provider.acquire { API.call }  # Second request: timeout! (needs to wait 59 seconds)
# => RuntimeError: Rate limit acquisition timeout after 5s
```

**Solution:** Set timeout >= 60 seconds for low RPM limits:
```ruby
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 1,
  max_wait_seconds: 65  # Allow full minute wait + buffer
)
```

#### Pitfall 2: Wrong Storage Backend for Deployment

**Problem:**
```ruby
# Kubernetes with 5 pods, each using MemoryStorage
# Each pod has its own rate limit bucket
# Result: 5 pods × 15 RPM = 75 RPM total (exceeds Gemini's 15 RPM limit!)
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 15  # Per pod, not total!
)
```

**Solution:** Use Redis storage for distributed coordination:
```ruby
redis_storage = RAAF::RateLimiter::RedisStorage.new(
  redis: Redis.new(url: ENV['REDIS_URL'])
)

provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 15,  # Total across all pods
  storage: redis_storage
)
```

#### Pitfall 3: Minute-Boundary Timing Issues

**Problem:**
```ruby
# At 13:45:58 (2 seconds before window reset)
# 15 requests already made this minute
provider.acquire { API.call }

# Waits 2 seconds for window reset (acceptable)
# But user expects immediate execution because "bucket not full yet"
```

**Understanding:** This is expected behavior with minute-boundary windows:
- Window: 13:45:00 to 13:45:59 (15 requests allowed)
- At 13:45:58: Window almost full, must wait for 13:46:00 reset
- At 13:46:00: Fresh window starts, immediate execution

**Solution:** This is not a bug, it's how minute-boundary windows work. Average wait time is still correct over many requests. If you need sub-minute precision, use Throttler instead:

```ruby
# Throttler uses continuous token refill (no minute boundaries)
provider.configure_throttle(rpm: 15, enabled: true)
```

#### Pitfall 4: Not Disabling Default Configuration

**Problem:**
```ruby
# Provider has default RPM configuration from ThrottleConfig
provider = RAAF::Models::GeminiProvider.new
# Gemini default: 10 RPM

# But you have paid tier with 60 RPM
# Still limited to 10 RPM unless you override!
```

**Solution:** Always explicitly configure rate limiting for production:
```ruby
# Override default with actual tier limit
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 60  # Paid tier limit
)

# Or use environment variable
# export RAAF_RATE_LIMIT_GEMINI_RPM=60
provider.configure_rate_limiting(enabled: true)
```

### Monitoring and Debugging

#### RateLimiter Status Monitoring

```ruby
provider = RAAF::Models::GeminiProvider.new
provider.configure_rate_limiting(enabled: true, requests_per_minute: 15)

# Make some requests
5.times { runner.run("Task") }

# Check current status
status = provider.rate_limiter_status
# => {
#   provider: "gemini",
#   current_requests: 5,      # Requests made in current window
#   limit: 15,                # RPM limit
#   window_start: 2025-01-12 13:45:00 UTC,  # Current window start
#   available: true,          # Can make more requests?
#   tokens_per_minute: 1000000  # Token limit (if applicable)
# }

puts "Used #{status[:current_requests]}/#{status[:limit]} requests"
puts "Window resets at #{status[:window_start] + 60} (#{(status[:window_start] + 60 - Time.now).to_i}s)"
```

#### Throttler Statistics Monitoring

```ruby
provider = RAAF::Models::GeminiProvider.new
provider.configure_throttle(rpm: 10, enabled: true)

# Make requests
20.times { runner.run("Task") }

# Check statistics
stats = provider.throttle_stats
# => {
#   requests_throttled: 10,   # Requests that had to wait
#   total_wait_time: 60.5,    # Total seconds spent waiting
#   timeout_failures: 0       # Requests that timed out
# }

puts "Throttled #{stats[:requests_throttled]} requests"
puts "Average wait: #{stats[:total_wait_time] / stats[:requests_throttled]}s"
puts "Efficiency: #{((1 - stats[:requests_throttled].to_f / 20) * 100).round(1)}%"
```

#### Debug Logging

Enable debug logging to see rate limiting decisions:

```bash
export RAAF_LOG_LEVEL=debug
export RAAF_DEBUG_CATEGORIES=rate_limiting,throttling
```

```ruby
# Debug output
# ✅ [RateLimiter] Acquired token (provider: gemini, rpm: 15)
# ⏱️  [RateLimiter] Rate limit reached (provider: gemini, current: 15, limit: 15, wait: 42.3s)
# ✅ [RateLimiter] Acquired token (provider: gemini, rpm: 15)
```

### Production Deployment Guide

#### Step 1: Determine Your Deployment Type

**Single-Server Deployment:**
```ruby
# Use default MemoryStorage
provider.configure_rate_limiting(enabled: true, requests_per_minute: 15)
```

**Multi-Server Deployment (Kubernetes, Docker Swarm, etc.):**
```ruby
# Use Redis storage for cross-server coordination
redis_storage = RAAF::RateLimiter::RedisStorage.new(
  redis: Redis.new(url: ENV['REDIS_URL'])
)
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 15,
  storage: redis_storage
)
```

**Rails Application:**
```ruby
# Use Rails.cache (automatically uses your cache backend)
rails_storage = RAAF::RateLimiter::RailsCacheStorage.new
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 15,
  storage: rails_storage
)
```

#### Step 2: Configure Rate Limits

**Use environment variables for easy tier changes:**
```bash
# .env or config/secrets
RAAF_RATE_LIMIT_GEMINI_RPM=60
RAAF_RATE_LIMIT_OPENAI_RPM=500
RAAF_RATE_LIMIT_ANTHROPIC_RPM=1000
```

```ruby
# Application code reads from ENV automatically
provider.configure_rate_limiting(enabled: true)
# Uses environment variable if set, otherwise uses default
```

#### Step 3: Add Monitoring

```ruby
# config/initializers/raaf_monitoring.rb
module RAAF
  module RateLimiting
    class Monitor
      def self.start
        Thread.new do
          loop do
            sleep(60)  # Check every minute
            log_rate_limiter_stats
          end
        end
      end

      def self.log_rate_limiter_stats
        providers = [
          RAAF::Models::GeminiProvider.new,
          RAAF::Models::OpenAIProvider.new,
          # ... other providers
        ]

        providers.each do |provider|
          next unless provider.rate_limiting_enabled?

          status = provider.rate_limiter_status
          Rails.logger.info(
            "Rate Limiter Status",
            provider: status[:provider],
            used: status[:current_requests],
            limit: status[:limit],
            utilization: "#{(status[:current_requests].to_f / status[:limit] * 100).round(1)}%"
          )
        end
      end
    end
  end
end

# Start monitoring
RAAF::RateLimiting::Monitor.start
```

#### Step 4: Set Up Alerts

```ruby
# config/initializers/raaf_alerts.rb
module RAAF
  module RateLimiting
    class Alerting
      def self.check_high_utilization
        providers.each do |provider|
          status = provider.rate_limiter_status
          utilization = status[:current_requests].to_f / status[:limit]

          if utilization > 0.9  # 90% utilization
            alert_high_utilization(provider, utilization)
          end
        end
      end

      def self.alert_high_utilization(provider, utilization)
        # Send alert to monitoring system
        Sentry.capture_message(
          "High rate limit utilization",
          level: :warning,
          extra: {
            provider: provider.class.name,
            utilization: "#{(utilization * 100).round(1)}%"
          }
        )
      end
    end
  end
end
```

#### Step 5: Test Under Load

```ruby
# test/integration/rate_limiting_test.rb
class RateLimitingTest < ActiveSupport::TestCase
  test "rate limiting handles concurrent agents" do
    provider = RAAF::Models::GeminiProvider.new
    provider.configure_rate_limiting(enabled: true, requests_per_minute: 15)
    runner = RAAF::Runner.new(agent: agent, provider: provider)

    # Spawn 20 concurrent threads
    threads = 20.times.map do
      Thread.new { runner.run("Test task") }
    end

    # All should complete without rate limit errors
    results = threads.map(&:value)
    assert_equal 20, results.count
    assert results.all? { |r| r.success? }
  end
end
```

### Cost Optimization

#### Calculate Cost Savings

**Without rate limiting** (reactive retry):
```ruby
# 20 concurrent agents × 1 request = 20 RPM
# But Gemini limit is 15 RPM
# 5 agents hit rate limit, retry 5 times each
# Total API calls: 15 (success) + 5 × 5 (failures) = 40 calls
# Cost: 40 × $0.01 = $0.40
# Time: ~5 minutes (multiple retry cycles)
```

**With rate limiting** (proactive prevention):
```ruby
# RateLimiter coordinates agents to 15 RPM
# First 15 agents execute immediately
# Remaining 5 wait for next window
# Total API calls: 20 (all success)
# Cost: 20 × $0.01 = $0.20
# Time: ~2 minutes (20 requests at 15 RPM)

# Savings: 50% cost reduction, 60% time reduction
```

#### Optimize RPM Settings

**Match your tier exactly:**
```ruby
# ❌ BAD: Using default free tier limit when you have paid tier
provider.configure_rate_limiting(enabled: true)  # Uses 10 RPM default
# Result: Leaving money on the table, slower execution

# ✅ GOOD: Use your actual tier limit
provider.configure_rate_limiting(enabled: true, requests_per_minute: 60)
# Result: Full utilization of paid tier, faster execution
```

**Use environment variables for easy tier upgrades:**
```bash
# Free tier
export RAAF_RATE_LIMIT_GEMINI_RPM=10

# Upgrade to paid tier - just change environment variable
export RAAF_RATE_LIMIT_GEMINI_RPM=60

# No code changes needed!
```

### Troubleshooting Guide

#### Problem: "Rate limit acquisition timeout"

**Symptoms:**
```ruby
RuntimeError: Rate limit acquisition timeout after 30s for gemini
```

**Diagnosis:**
1. Check current RPM setting: `provider.rate_limiter_status[:limit]`
2. Check number of concurrent agents
3. Check timeout setting

**Solutions:**

1. **Increase timeout** for low RPM limits:
   ```ruby
   provider.configure_rate_limiting(
     enabled: true,
     requests_per_minute: 1,
     max_wait_seconds: 65  # Must be > 60 for 1 RPM
   )
   ```

2. **Increase RPM** if you have higher tier:
   ```ruby
   provider.configure_rate_limiting(
     enabled: true,
     requests_per_minute: 60  # Use your actual tier limit
   )
   ```

3. **Reduce concurrent agents** if RPM limit is too low:
   ```ruby
   # Instead of 20 concurrent agents with 10 RPM
   # Use 5 concurrent agents
   thread_pool = 5.times.map do
     Thread.new { ... }
   end
   ```

#### Problem: Requests still exceeding provider limits

**Symptoms:**
```ruby
# Despite rate limiting enabled, still getting 429 errors from provider
OpenAI::Error::RateLimitError: Rate limit exceeded
```

**Diagnosis:**
1. Check if rate limiting is actually enabled: `provider.rate_limiting_enabled?`
2. Check if using correct storage for deployment (Redis for multi-server)
3. Check if provider has multiple rate limits (RPM + TPM)

**Solutions:**

1. **Verify rate limiting is enabled:**
   ```ruby
   puts "Rate limiting enabled: #{provider.rate_limiting_enabled?}"
   puts "Current status: #{provider.rate_limiter_status}"
   ```

2. **Use Redis storage for multi-server deployments:**
   ```ruby
   # ❌ WRONG: Each server has its own bucket
   provider.configure_rate_limiting(enabled: true)  # MemoryStorage (default)

   # ✅ CORRECT: All servers share bucket
   redis_storage = RAAF::RateLimiter::RedisStorage.new(redis: Redis.new(...))
   provider.configure_rate_limiting(enabled: true, storage: redis_storage)
   ```

3. **Check provider's multiple limits:**
   ```ruby
   # Some providers have both RPM and TPM (tokens per minute) limits
   # RateLimiter only enforces RPM
   # You may need to add token counting separately
   ```

#### Problem: High latency with Redis storage

**Symptoms:**
```ruby
# Each request taking 5-10ms longer with Redis storage
Benchmark.measure { provider.acquire { API.call } }
# => Memory: 100ms, Redis: 110ms
```

**Diagnosis:**
1. Check Redis network latency: `redis.ping`
2. Check Redis is on same network/datacenter
3. Check Redis is not overloaded

**Solutions:**

1. **Use localhost Redis** for single-server deployments:
   ```ruby
   redis = Redis.new(host: 'localhost')  # Latency: 0.1-0.5ms
   ```

2. **Use connection pooling** for high-concurrency:
   ```ruby
   redis_pool = ConnectionPool.new(size: 25) { Redis.new(...) }
   redis_storage = RAAF::RateLimiter::RedisStorage.new(redis: redis_pool)
   ```

3. **Consider MemoryStorage** if multi-server coordination not needed:
   ```ruby
   # Single server? Use default MemoryStorage (10-50x faster)
   provider.configure_rate_limiting(enabled: true)
   ```

#### Problem: Tests failing due to minute-boundary windows

**Symptoms:**
```ruby
# Test fails randomly based on when it runs
it "should not wait" do
  provider.acquire { API.call }  # Success
  provider.acquire { API.call }  # Sometimes waits, sometimes doesn't
end
```

**Diagnosis:**
Test is running near minute boundary (:58, :59, :00, :01 seconds), causing variable behavior.

**Solution:** Use `reset_rate_limiter` in tests:
```ruby
it "should not wait" do
  provider.reset_rate_limiter  # Clear window
  provider.acquire { API.call }  # Fresh window, immediate
  provider.acquire { API.call }  # Still within limit
end
```

Or account for window reset timing:
```ruby
it "should enforce rate limit" do
  # Move to middle of minute to avoid boundary effects
  current_sec = Time.now.sec
  if current_sec < 10 || current_sec > 50
    sleep((70 - current_sec) % 60)
  end

  # Now test behavior
  provider.acquire { API.call }
end
```

---

## Summary: RateLimiter vs Throttler

### Quick Reference Table

| Aspect | RateLimiter | Throttler |
|--------|-------------|-----------|
| **Primary Use Case** | Multi-agent production | Single-agent development |
| **Coordination Scope** | Shared across all instances | Per-provider instance |
| **Storage** | Pluggable (Memory/Redis/Rails) | In-memory only |
| **Thread-Safety** | Concurrent::Map (lock-free) | Monitor (mutex) |
| **Window Type** | Minute-boundary (resets at :00) | Continuous token refill |
| **Burst Capacity** | First N requests immediate | Configurable (rpm/10 default) |
| **Overhead** | 0.01-5ms (depending on storage) | <0.02ms |
| **Best For** | 20 agents → 15 RPM total | 1 agent with burst handling |
| **Deployment** | Single or multi-server | Single server only |
| **Configuration** | `configure_rate_limiting()` | `configure_throttle()` |

### When to Use Each

**Use RateLimiter when:**
- Multiple concurrent agents (threads/processes)
- Distributed deployment (Kubernetes, multi-server)
- Need strict rate limit enforcement
- Production deployments

**Use Throttler when:**
- Single agent development/testing
- Need burst capacity (handle spikes)
- Per-method rate limiting
- Simple rate control needs

**Use Both when:**
- Production multi-agent deployment
- Want both coordination and burst handling
- Need defense-in-depth

### Production Recommendation

```ruby
# RECOMMENDED: Three-layer defense for production
provider = RAAF::Models::GeminiProvider.new

# Layer 1: RateLimiter (global coordination)
provider.configure_rate_limiting(
  enabled: true,
  requests_per_minute: 15,
  storage: redis_storage  # For multi-server
)

# Layer 2: Throttler (burst smoothing)
provider.configure_throttle(
  rpm: 15,
  burst: 5,
  enabled: true
)

# Layer 3: Retry (transient errors)
provider.configure_retry(max_attempts: 3)

# Result: Production-ready, cost-optimized, reliable
```

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

**Supported Parameters**:
- ✅ `response_format` - **FULLY SUPPORTED** for structured output/JSON schemas (sent as `text.format` parameter)
- ✅ `temperature` - For non-reasoning models
- ✅ `top_p` - For non-reasoning models
- ✅ `max_tokens` (as `max_output_tokens`)
- ✅ `tools` - Function calling
- ✅ `stream` - Streaming responses

**NOTE**: The Responses API uses `text.format` instead of `response_format` at the top level, but RAAF handles this conversion automatically.

**IMPORTANT**: The Responses API does NOT support these Chat Completions parameters:
- `frequency_penalty`
- `presence_penalty`
- `best_of`
- `logit_bias`

If you provide these unsupported parameters to `ResponsesProvider`, they will:
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