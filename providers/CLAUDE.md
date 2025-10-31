# RAAF Providers - Claude Code Guide

This gem provides multiple AI provider integrations for RAAF agents, supporting OpenAI, Anthropic, Cohere, Groq, Together, and more.

## Quick Start

```ruby
require 'raaf-providers'

# Use different providers
agent = RAAF::Agent.new(
  name: "MultiProviderAgent",
  instructions: "You are helpful",
  model: "claude-3-sonnet"
)

# Anthropic provider
anthropic_provider = RAAF::Models::AnthropicProvider.new do |config|
  config.api_key = ENV['ANTHROPIC_API_KEY']
  config.max_tokens = 4000
  config.temperature = 0.7
end

runner = RAAF::Runner.new(agent: agent, provider: anthropic_provider)
```

## Available Providers

### OpenAI Provider
```ruby
openai_provider = RAAF::Models::OpenAIProvider.new do |config|
  config.api_key = ENV['OPENAI_API_KEY']
  config.organization = ENV['OPENAI_ORG_ID']  # optional
  config.base_url = "https://api.openai.com/v1"  # custom endpoint
end

# Supports all OpenAI models
runner = RAAF::Runner.new(agent: agent, provider: openai_provider)
```

### Anthropic Provider
```ruby
anthropic_provider = RAAF::Models::AnthropicProvider.new do |config|
  config.api_key = ENV['ANTHROPIC_API_KEY']
  config.version = "2023-06-01"
  config.max_tokens = 4000
end

# Use Claude models
agent.model = "claude-3-sonnet-20240229"
runner = RAAF::Runner.new(agent: agent, provider: anthropic_provider)
```

### Cohere Provider
```ruby
cohere_provider = RAAF::Models::CohereProvider.new do |config|
  config.api_key = ENV['COHERE_API_KEY']
  config.model = "command-r-plus"
  config.temperature = 0.7
  config.max_tokens = 2000
end

runner = RAAF::Runner.new(agent: agent, provider: cohere_provider)
```

### Groq Provider
```ruby
groq_provider = RAAF::Models::GroqProvider.new do |config|
  config.api_key = ENV['GROQ_API_KEY']
  config.model = "mixtral-8x7b-32768"
  config.temperature = 0.5
end

runner = RAAF::Runner.new(agent: agent, provider: groq_provider)
```

### Gemini Provider

**Google Gemini** provides powerful multimodal AI models with support for text, vision, and function calling. Gemini excels at complex reasoning tasks and offers competitive pricing. **NEW: Automatic continuation support** for handling truncated responses.

#### Basic Usage

```ruby
# Initialize Gemini provider
gemini_provider = RAAF::Models::GeminiProvider.new(
  api_key: ENV['GEMINI_API_KEY']
)

agent = RAAF::Agent.new(
  name: "Gemini Assistant",
  instructions: "You are a helpful AI assistant",
  model: "gemini-2.0-flash-exp"
)

runner = RAAF::Runner.new(agent: agent, provider: gemini_provider)
result = runner.run("Explain quantum computing")
```

#### Automatic Continuation Support (NEW)

Gemini provider now supports **automatic continuation** using Gemini's multi-turn conversation pattern:

```ruby
# Automatic continuation when response is truncated (MAX_TOKENS)
result = runner.run(
  "Generate a comprehensive list of 200 companies",
  max_tokens: 8000,           # May hit token limit
  auto_continuation: true,     # Default: true - automatically continues
  max_continuation_attempts: 10  # Default: 10 - max continuation rounds
)

# Check how many continuation chunks were used
puts "Continuation chunks: #{result['continuation_chunks']}"
# => "Continuation chunks: 3" (if response was truncated twice)

# Disable continuation if needed
result = runner.run(
  "Generate list",
  auto_continuation: false  # Stop after first truncation
)
```

**How it works:**
1. Detects `finishReason: "MAX_TOKENS"` (mapped to `"length"` in OpenAI format)
2. Appends assistant's response to conversation history
3. Adds continuation prompt: "Continue from where you left off..."
4. Makes additional API call with full conversation context
5. Accumulates content and usage across all chunks
6. Returns complete response with `continuation_chunks` count

#### Available Models

```ruby
# gemini-2.0-flash-exp - Latest experimental (fastest, most capable)
# gemini-1.5-pro-latest - Stable production (best quality)
# gemini-1.5-flash-latest - Stable production (fast, efficient)
# gemini-1.0-pro - Legacy (still supported)

agent.model = "gemini-2.0-flash-exp"  # Recommended for most use cases
agent.model = "gemini-1.5-pro-latest" # For production stability
agent.model = "gemini-1.5-flash-latest" # For cost optimization
```

#### Function Calling

Gemini has **native function calling** support:

```ruby
# Define tools
def get_weather(location:)
  "Weather in #{location}: sunny, 72°F"
end

agent = RAAF::Agent.new(
  name: "Tool Agent",
  instructions: "Help users with weather information",
  model: "gemini-2.0-flash-exp"
)

agent.add_tool(method(:get_weather))

gemini_provider = RAAF::Models::GeminiProvider.new
runner = RAAF::Runner.new(agent: agent, provider: gemini_provider)

result = runner.run("What's the weather in Tokyo?")
# Gemini will call get_weather function automatically
```

#### RAAF DSL Integration

```ruby
# Use Gemini in DSL agents with automatic provider detection
class ResearchAgent < RAAF::DSL::Agent
  instructions "Conduct thorough research on technical topics"
  model "gemini-2.0-flash-exp"
  provider :gemini  # Automatic provider detection

  schema do
    field :summary, type: :string, required: true
    field :key_points, type: :array, required: true
  end
end

# Run with automatic provider instantiation
dsl_agent = ResearchAgent.new
dsl_runner = RAAF::Runner.new(agent: dsl_agent)
result = dsl_runner.run("Research Ruby 3.4 YJIT improvements")

# Access structured results
puts result[:summary]
result[:key_points].each { |point| puts "- #{point}" }
```

#### Advanced Configuration

```ruby
# Custom generation parameters
result = runner.run(
  "Write a poem",
  temperature: 0.9,        # Higher creativity
  top_p: 0.95,            # Nucleus sampling
  top_k: 40,              # Top-k sampling
  max_tokens: 1024,       # Max output length
  stop: ["END"]           # Stop sequences
)

# Custom API endpoint
custom_provider = RAAF::Models::GeminiProvider.new(
  api_key: ENV['GEMINI_API_KEY'],
  api_base: "https://custom-gemini-endpoint.com"
)
```

#### Streaming Support

```ruby
# Stream responses in real-time
agent = RAAF::Agent.new(
  name: "Streaming Assistant",
  model: "gemini-2.0-flash-exp"
)

gemini_provider = RAAF::Models::GeminiProvider.new
runner = RAAF::Runner.new(agent: agent, provider: gemini_provider)

runner.stream("Write a long story about Ruby") do |chunk|
  case chunk[:type]
  when "content"
    print chunk[:content]  # Print each chunk as it arrives
  when "finish"
    puts "\n\nFinished! Reason: #{chunk[:finish_reason]}"
  end
end
```

#### Best Practices

1. **Model Selection**
   - Use `gemini-2.0-flash-exp` for cutting-edge features
   - Use `gemini-1.5-pro-latest` for production stability
   - Use `gemini-1.5-flash-latest` for cost-sensitive applications

2. **Function Calling**
   - Gemini supports OpenAI-compatible function calling
   - Function parameters must use JSON schema format
   - System instructions can guide when to use functions

3. **Safety and Content Filtering**
   - Gemini includes built-in safety filters
   - Responses may be blocked for safety reasons (finish_reason: "content_filter")
   - Configure safety settings if needed (contact Google for details)

4. **Token Management**
   - Use `max_tokens` to control output length
   - Monitor usage via `result["usage"]` field
   - Gemini 1.5 models have larger context windows (up to 2M tokens)

**Gemini Capabilities:**
- ✅ Native function/tool calling
- ✅ Streaming responses
- ✅ Multi-turn conversations
- ✅ System instructions
- ✅ RAAF DSL compatibility
- ✅ Multi-agent handoffs

**Gemini Limitations:**
- ⚠️ Rate limits vary by tier (free tier has lower limits)
- ⚠️ Safety filters may block some content
- ⚠️ API is in beta (v1beta endpoint)

**When to Use Gemini:**
- ✅ Complex reasoning tasks
- ✅ Multimodal applications (text + vision)
- ✅ Cost-effective alternative to GPT-4
- ✅ Long context windows needed
- ✅ Google Cloud integration preferred

### Hugging Face Inference Providers

**Hugging Face** provides access to hundreds of models through a unified inference routing system. The API is OpenAI-compatible with support for function calling and streaming, making it easy to experiment with different open-source models.

#### Basic Usage

```ruby
# Initialize Hugging Face provider
hf_provider = RAAF::Models::HuggingFaceProvider.new(
  api_key: ENV['HUGGINGFACE_API_KEY']  # or HF_TOKEN
)

agent = RAAF::Agent.new(
  name: "HF Assistant",
  instructions: "You are a helpful AI assistant",
  model: "deepseek-ai/DeepSeek-R1-0528"
)

runner = RAAF::Runner.new(agent: agent, provider: hf_provider)
result = runner.run("Explain quantum computing")
```

#### Available Models

Hugging Face supports 100+ models via automatic provider routing. Models must use `org/model` format:

```ruby
# Verified models (tested with RAAF)
"deepseek-ai/DeepSeek-R1-0528"        # Latest reasoning model
"meta-llama/Llama-3-70B-Instruct"     # Meta's Llama 3
"mistralai/Mixtral-8x7B-Instruct-v0.1" # Mixtral MoE
"microsoft/phi-4"                      # Microsoft Phi-4

# Use any model from Hugging Face Hub
agent.model = "your-org/your-model"
```

**Important**: The provider will log warnings for unverified models, as capabilities may vary.

#### Function Calling

Function calling is supported on select models:

```ruby
def get_weather(location:)
  "Weather in #{location}: sunny, 72°F"
end

agent = RAAF::Agent.new(
  name: "Tool Agent",
  instructions: "Help users with weather information",
  model: "deepseek-ai/DeepSeek-R1-0528"
)

agent.add_tool(method(:get_weather))

hf_provider = RAAF::Models::HuggingFaceProvider.new
runner = RAAF::Runner.new(agent: agent, provider: hf_provider)

result = runner.run("What's the weather in Tokyo?")
# Hugging Face will call get_weather function automatically
```

**Model Support**: The provider logs warnings when using tools with models that haven't been verified for function calling. Confirmed function-calling models:
- `deepseek-ai/DeepSeek-R1-0528`

#### Provider Selection

Hugging Face automatically routes requests to available providers (Cerebras, Groq, Nebius, etc.). You can optionally specify a provider:

```ruby
# Automatic routing (recommended)
model: "deepseek-ai/DeepSeek-R1-0528"

# Explicit provider (advanced)
model: "deepseek-ai/DeepSeek-R1-0528:nebius"  # Force Nebius provider
model: "meta-llama/Llama-3-70B-Instruct:groq" # Force Groq provider
```

#### Streaming Support

```ruby
# Stream responses in real-time
agent = RAAF::Agent.new(
  name: "Streaming Assistant",
  model: "deepseek-ai/DeepSeek-R1-0528"
)

hf_provider = RAAF::Models::HuggingFaceProvider.new
runner = RAAF::Runner.new(agent: agent, provider: hf_provider)

runner.stream("Write a long story about Ruby") do |chunk|
  case chunk[:type]
  when "content"
    print chunk[:content]  # Print each chunk as it arrives
  when "finish"
    puts "\n\nFinished! Reason: #{chunk[:finish_reason]}"
  end
end
```

#### RAAF DSL Integration

```ruby
# Use Hugging Face in DSL agents with automatic provider detection
class ResearchAgent < RAAF::DSL::Agent
  instructions "Conduct research on technical topics"
  model "deepseek-ai/DeepSeek-R1-0528"
  provider :huggingface  # Automatic provider detection

  schema do
    field :summary, type: :string, required: true
    field :key_points, type: :array, required: true
  end
end

# Run with automatic provider instantiation
dsl_agent = ResearchAgent.new
dsl_runner = RAAF::Runner.new(agent: dsl_agent)
result = dsl_runner.run("Research Ruby 3.4 YJIT improvements")

# Access structured results
puts result[:summary]
result[:key_points].each { |point| puts "- #{point}" }
```

#### Advanced Configuration

```ruby
# Custom generation parameters
result = runner.run(
  "Write a poem",
  temperature: 0.9,        # Higher creativity
  top_p: 0.95,            # Nucleus sampling
  max_tokens: 1024,       # Max output length
  stop: ["END"]           # Stop sequences
)

# Custom API endpoint
custom_provider = RAAF::Models::HuggingFaceProvider.new(
  api_key: ENV['HUGGINGFACE_API_KEY'],
  api_base: "https://custom-hf-endpoint.com/v1"
)

# Custom timeout
long_timeout_provider = RAAF::Models::HuggingFaceProvider.new(
  api_key: ENV['HUGGINGFACE_API_KEY'],
  timeout: 300  # 5 minutes
)
```

#### Best Practices

1. **Model Selection**
   - Start with verified models for guaranteed compatibility
   - Test unverified models thoroughly before production use
   - Check model documentation for function calling support

2. **Function Calling**
   - Only use function calling with verified models
   - Monitor logs for unsupported model warnings
   - Test tool execution before deploying

3. **Rate Limiting**
   - Use automatic retry (built into ModelInterface)
   - Monitor rate limit errors in logs
   - Consider PRO tier for production applications

4. **Provider Routing**
   - Use automatic routing for best availability
   - Specify provider suffix only when needed
   - Test with multiple providers for redundancy

**Hugging Face Capabilities:**
- ✅ Function/tool calling (model-dependent)
- ✅ Streaming responses
- ✅ Multi-turn conversations
- ✅ RAAF DSL compatibility
- ✅ Multi-agent handoffs (with function-calling models)
- ✅ Access to 100+ models
- ✅ OpenAI-compatible API (minimal conversion)

**Hugging Face Limitations:**
- ⚠️ Model capabilities vary significantly
- ⚠️ Not all models support function calling
- ⚠️ Provider availability varies by model
- ⚠️ Rate limits depend on account tier
- ⚠️ Unverified models may have unexpected behavior

**When to Use Hugging Face:**
- ✅ Access to latest open-source models
- ✅ Cost-effective inference
- ✅ Specialized models (coding, reasoning, etc.)
- ✅ Multi-provider redundancy
- ✅ Experimentation with different models
- ✅ Avoiding vendor lock-in
- ❌ Production systems requiring guaranteed capabilities
- ❌ Applications requiring all models to support tools

### Perplexity Provider

**Perplexity AI** provides web-grounded search with automatic citations, ideal for research tasks requiring real-time information and source attribution.

#### Basic Usage

```ruby
# Initialize Perplexity provider
perplexity_provider = RAAF::Models::PerplexityProvider.new(
  api_key: ENV['PERPLEXITY_API_KEY']
)

agent = RAAF::Agent.new(
  name: "Search Assistant",
  instructions: "Provide factual information with citations",
  model: "sonar-pro"
)

runner = RAAF::Runner.new(agent: agent, provider: perplexity_provider)
result = runner.run("Latest Ruby developments")

# Access citations and web results
puts "Citations: #{result[:citations]}"
puts "Web results: #{result[:web_results]}"
result[:web_results].each do |source|
  puts "#{source[:title]}: #{source[:url]}"
end
```

#### Available Models

```ruby
# sonar - Fast web search (best for quick queries)
# sonar-pro - Advanced search with JSON schema support
# sonar-reasoning - Deep reasoning with web search
# sonar-reasoning-pro - Premium reasoning with JSON schema support

agent.model = "sonar"          # Fast search
agent.model = "sonar-pro"      # Advanced with structured output
agent.model = "sonar-reasoning"     # Deep reasoning
agent.model = "sonar-reasoning-pro" # Premium reasoning + structured output
```

#### Structured Output with JSON Schema

**Only available on `sonar-pro` and `sonar-reasoning-pro` models:**

```ruby
# Define detailed schema for structured output
schema = {
  type: "object",
  properties: {
    news_items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          summary: { type: "string" },
          url: { type: "string" },
          date: { type: "string" }
        },
        required: ["title", "summary"]
      }
    },
    total: { type: "integer" },
    sources: { type: "array" }
  },
  required: ["news_items", "total"]
}

result = runner.run(
  "Find top 3 Ruby news items from this month",
  response_format: schema
)

# Access structured data
puts "Found #{result[:total]} items"
result[:news_items].each do |item|
  puts "#{item[:title]}: #{item[:url]}"
end
```

#### Web Search Filtering

```ruby
# Domain filtering - restrict to specific websites
result = runner.run(
  "Ruby updates",
  web_search_options: {
    search_domain_filter: ["ruby-lang.org", "github.com"],
    search_recency_filter: "week"
  }
)

# Recency options: "hour", "day", "week", "month", "year"

# Combine filters for precise results
result = runner.run(
  "Ruby security advisories",
  web_search_options: {
    search_domain_filter: ["ruby-lang.org", "cve.org"],
    search_recency_filter: "month"
  }
)
```

#### RAAF DSL Integration

```ruby
# Use Perplexity in DSL agents with automatic provider detection
class RubyNewsAgent < RAAF::DSL::Agent
  instructions "Search for recent Ruby programming news"
  model "sonar-pro"
  provider :perplexity  # Automatic provider detection

  schema do
    field :news_items, type: :array, required: true do
      field :title, type: :string, required: true
      field :summary, type: :string, required: true
      field :url, type: :string, required: true
    end
    field :total, type: :integer, required: true
  end
end

# Run with automatic provider instantiation
dsl_agent = RubyNewsAgent.new
dsl_runner = RAAF::Runner.new(agent: dsl_agent)
result = dsl_runner.run("Latest Ruby 3.4 news")

# Access structured results
result[:news_items].each do |item|
  puts "#{item[:title]}: #{item[:url]}"
end
```

#### Prompt Engineering Best Practices for Perplexity

Perplexity works best with **search-optimized prompts**. Follow these guidelines:

##### 1. Be Specific and Contextual

```ruby
# ❌ BAD: Too generic
result = runner.run("Tell me about climate models")

# ✅ GOOD: Specific with context (add 2-3 extra words)
result = runner.run("Explain recent advances in climate prediction models for urban planning")
```

##### 2. Structure Prompts Like Web Searches

```ruby
# Think like a search engine user
good_prompts = [
  "Latest Ruby on Rails security vulnerabilities 2024",
  "Best practices Ruby microservices architecture",
  "Compare Rails 7 vs Rails 8 performance benchmarks"
]

good_prompts.each do |prompt|
  result = runner.run(prompt)
  puts result[:content]
end
```

##### 3. Use System Prompts for Style/Tone

```ruby
agent = RAAF::Agent.new(
  name: "Expert Assistant",
  instructions: "Provide clear, concise, expert-level technical information",
  model: "sonar-pro"
)

# System prompt guides style, user prompt is search-focused
result = runner.run("Ruby 3.4 performance improvements")
```

##### 4. Prevent Hallucinations

```ruby
# Include explicit instructions about information limitations
result = runner.run(<<~PROMPT)
  Find information about Ruby 4.0 roadmap.

  If information is not available or uncertain, clearly state that.
  Only use publicly accessible sources.
  Acknowledge when information is limited or unavailable.
PROMPT
```

##### 5. Single-Topic Focus

```ruby
# ❌ BAD: Multiple unrelated topics
result = runner.run("Tell me about Ruby performance, Rails security, and Python comparisons")

# ✅ GOOD: One focused topic per query
result = runner.run("Ruby vs Python performance benchmarks for web applications")
```

##### 6. Never Request URLs in Prompts

```ruby
# ❌ BAD: Requesting URLs directly
result = runner.run("Find URLs for Ruby documentation")

# ✅ GOOD: Use web_results field for source information
result = runner.run("Ruby 3.4 documentation and guides")

# Access sources programmatically
result[:web_results].each do |source|
  puts "#{source[:title]}: #{source[:url]}"
end
```

##### 7. Use Built-in Parameters Instead of Prompt Instructions

```ruby
# ❌ BAD: Using prompt to specify filters
result = runner.run("Search only ruby-lang.org for Ruby news from this week")

# ✅ GOOD: Use API parameters
result = runner.run(
  "Ruby news",
  web_search_options: {
    search_domain_filter: ["ruby-lang.org"],
    search_recency_filter: "week"
  }
)
```

#### Advanced Perplexity Patterns

##### Multi-Stage Research Pipeline with DSL

```ruby
# Three specialized agents for comprehensive research
class ResearchPipeline
  # Stage 1: Overview agent
  class OverviewAgent < RAAF::DSL::Agent
    instructions "Search for overview and recent developments"
    model "sonar-pro"
    provider :perplexity

    provider_options(
      web_search_options: { search_recency_filter: "week" }
    )

    schema do
      field :overview, type: :string, required: true
      field :key_points, type: :array, required: true
      field :sources, type: :array, required: true
    end
  end

  # Stage 2: Technical details agent
  class TechnicalAgent < RAAF::DSL::Agent
    instructions "Search for technical details and implementation"
    model "sonar-pro"
    provider :perplexity

    provider_options(
      web_search_options: { search_recency_filter: "month" }
    )

    schema do
      field :technical_details, type: :string, required: true
      field :implementation_notes, type: :array, required: true
    end
  end

  # Stage 3: Expert opinions agent
  class ExpertOpinionAgent < RAAF::DSL::Agent
    instructions "Search expert analysis and best practices"
    model "sonar-pro"
    provider :perplexity

    provider_options(
      web_search_options: {
        search_domain_filter: ["thoughtworks.com", "martinfowler.com", "ruby-lang.org"],
        search_recency_filter: "month"
      }
    )

    schema do
      field :expert_opinions, type: :array, required: true do
        field :source, type: :string, required: true
        field :opinion, type: :string, required: true
        field :url, type: :string, required: true
      end
    end
  end

  def research(topic)
    # Execute three specialized agents
    overview = OverviewAgent.new.run("#{topic} overview recent developments")
    details = TechnicalAgent.new.run("#{topic} technical details implementation")
    opinions = ExpertOpinionAgent.new.run("#{topic} expert analysis best practices")

    {
      overview: overview,
      technical_details: details,
      expert_opinions: opinions
    }
  end
end

# Usage
pipeline = ResearchPipeline.new
results = pipeline.research("Ruby 3.4 YJIT improvements")

# Access structured results
puts "Overview: #{results[:overview][:overview]}"
results[:overview][:key_points].each { |point| puts "- #{point}" }

puts "\nTechnical: #{results[:technical_details][:technical_details]}"

puts "\nExpert Opinions:"
results[:expert_opinions][:expert_opinions].each do |op|
  puts "#{op[:source]}: #{op[:opinion]}"
  puts "  URL: #{op[:url]}"
end
```

##### Fact-Checking Agent

```ruby
class FactCheckAgent < RAAF::DSL::Agent
  instructions <<~PROMPT
    You are a fact-checking assistant.
    Verify claims using recent, authoritative sources.
    Always acknowledge uncertainty when sources conflict.
    Provide evidence with specific quotes from sources.
  PROMPT

  model "sonar-reasoning-pro"
  provider :perplexity

  schema do
    field :claim, type: :string, required: true
    field :verdict, type: :string, required: true  # "True", "False", "Uncertain"
    field :confidence, type: :string, required: true  # "High", "Medium", "Low"
    field :explanation, type: :string, required: true
    field :evidence, type: :array, required: true do
      field :source, type: :string, required: true
      field :quote, type: :string, required: true
      field :url, type: :string, required: true
    end
  end
end

# Verify technical claims with sources
agent = FactCheckAgent.new
result = agent.run("Ruby 3.4 has 40% faster performance than Ruby 3.3")

puts "Claim: #{result[:claim]}"
puts "Verdict: #{result[:verdict]} (#{result[:confidence]} confidence)"
puts "Explanation: #{result[:explanation]}"
puts "\nEvidence:"
result[:evidence].each do |e|
  puts "- #{e[:source]}: #{e[:quote]}"
  puts "  Source: #{e[:url]}"
end
```

##### Competitive Intelligence Agent

```ruby
class CompetitiveIntelligenceAgent < RAAF::DSL::Agent
  instructions <<~PROMPT
    Analyze competitive landscape for technology topics.
    Focus on recent developments, market position, and technical capabilities.
    Use authoritative tech news and company sources.
  PROMPT

  model "sonar-pro"
  provider :perplexity

  schema do
    field :competitors, type: :array, required: true do
      field :name, type: :string, required: true
      field :strengths, type: :array, required: true
      field :weaknesses, type: :array, required: true
      field :recent_news, type: :string, required: true
    end
    field :market_trends, type: :array, required: true
  end
end

# Analyze competitive landscape
agent = CompetitiveIntelligenceAgent.new
result = agent.run(
  "Compare Ruby on Rails vs Django vs Laravel frameworks",
  web_search_options: { search_recency_filter: "month" }
)

result[:competitors].each do |competitor|
  puts "\n#{competitor[:name]}"
  puts "Strengths: #{competitor[:strengths].join(', ')}"
  puts "Recent: #{competitor[:recent_news]}"
end
```

**Perplexity Capabilities:**
- ✅ Web-grounded search with real-time information
- ✅ Automatic citations and source tracking
- ✅ JSON schema support (sonar-pro, sonar-reasoning-pro)
- ✅ Web search filtering (domain and recency)
- ✅ RAAF DSL agent compatibility
- ✅ Multi-stage research workflows
- ✅ Fact-checking and verification
- ✅ Competitive intelligence gathering

**Perplexity Limitations:**
- ❌ No function/tool calling (cannot participate in multi-agent handoffs)
- ❌ Streaming not yet implemented
- ❌ JSON schema limited to specific models (sonar-pro, sonar-reasoning-pro)
- ⚠️ Real-time search may not always follow system prompt precisely
- ⚠️ Avoid traditional LLM techniques like few-shot prompting
- ⚠️ Best suited for research/search tasks, not general conversation

**When to Use Perplexity:**
- ✅ Research requiring current information
- ✅ Fact-checking and verification
- ✅ Competitive analysis
- ✅ Technical documentation search
- ✅ News and trend monitoring
- ❌ Multi-agent workflows (no tool calling)
- ❌ General conversational tasks
- ❌ Streaming real-time responses

### Perplexity Common Code Integration

**PerplexityProvider uses common code from RAAF Core** for consistent behavior with PerplexityTool.

#### Common Modules Used

```ruby
require 'raaf/perplexity/common'
require 'raaf/perplexity/search_options'
require 'raaf/perplexity/result_parser'

class PerplexityProvider < ModelInterface
  def chat_completion(messages:, model:, **kwargs)
    # 1. Validate model using common code
    RAAF::Perplexity::Common.validate_model(model)

    # 2. Validate schema support (for sonar-pro, sonar-reasoning-pro)
    if kwargs[:response_format]
      RAAF::Perplexity::Common.validate_schema_support(model)
    end

    # 3. Build search options using common code
    if kwargs[:web_search_options]
      options = RAAF::Perplexity::SearchOptions.build(
        domain_filter: kwargs[:web_search_options][:search_domain_filter],
        recency_filter: kwargs[:web_search_options][:search_recency_filter]
      )
      body[:search_domain_filter] = options[:search_domain_filter] if options
      body[:search_recency_filter] = options[:search_recency_filter] if options
    end

    # 4. Make API call
    response = make_api_call(body)

    # 5. Format response using common code
    RAAF::Perplexity::ResultParser.format_search_result(response)
  end
end
```

#### Single Source of Truth

All Perplexity constants and validation logic live in RAAF Core:

```ruby
# Model constants - single source of truth
RAAF::Perplexity::Common::SUPPORTED_MODELS
# => ["sonar", "sonar-pro", "sonar-reasoning", "sonar-reasoning-pro", "sonar-deep-research"]

RAAF::Perplexity::Common::SCHEMA_CAPABLE_MODELS
# => ["sonar-pro", "sonar-reasoning-pro"]

# Recency filters - single source of truth
RAAF::Perplexity::Common::RECENCY_FILTERS
# => ["hour", "day", "week", "month", "year"]

# Validation methods used by provider
RAAF::Perplexity::Common.validate_model("sonar-pro")          # => true
RAAF::Perplexity::Common.validate_schema_support("sonar-pro") # => true
```

#### Result Formatting

Both provider and tool use identical result formatting:

```ruby
# Provider response structure (formatted by ResultParser)
{
  success: true,
  content: "Search result text...",
  citations: ["https://source1.com", "https://source2.com"],
  web_results: [
    {
      "title" => "Article Title",
      "url" => "https://article.com",
      "snippet" => "Article preview..."
    }
  ],
  model: "sonar-pro"
}

# Tool response structure (same format via ResultParser)
{
  success: true,
  content: "Search result text...",
  citations: [...],
  web_results: [...],
  model: "sonar-pro"
}
```

#### Benefits of Common Code

1. **Consistent Validation**: Same model and filter validation across provider and tool
2. **Single Source of Truth**: Constants defined once in RAAF Core
3. **Identical Response Format**: Provider and tool return same structure
4. **Easy Maintenance**: Update validation/formatting logic in one place
5. **No Code Duplication**: SearchOptions and ResultParser shared between both

**See also:** `@raaf/core/CLAUDE.md` for detailed common code documentation.

### Together AI Provider
```ruby
together_provider = RAAF::Models::TogetherProvider.new do |config|
  config.api_key = ENV['TOGETHER_API_KEY']
  config.model = "meta-llama/Llama-2-70b-chat-hf"
  config.max_tokens = 2000
end

runner = RAAF::Runner.new(agent: agent, provider: together_provider)
```

### LiteLLM Provider (Universal)
```ruby
# Use LiteLLM for unified access to 100+ models
litellm_provider = RAAF::Models::LiteLLMProvider.new do |config|
  config.model = "gpt-4"  # or any supported model
  config.api_key = ENV['OPENAI_API_KEY']
  config.provider = "openai"  # auto-detected from model name
end

# Works with any model supported by LiteLLM
runner = RAAF::Runner.new(agent: agent, provider: litellm_provider)
```

## Multi-Provider Support

```ruby
# Use different providers for different tasks
class MultiProviderAgent
  def initialize
    @providers = {
      reasoning: RAAF::Models::AnthropicProvider.new(model: "claude-3-sonnet"),
      coding: RAAF::Models::OpenAIProvider.new(model: "gpt-4"),
      speed: RAAF::Models::GroqProvider.new(model: "mixtral-8x7b")
    }
  end
  
  def run_task(message, task_type: :reasoning)
    provider = @providers[task_type]
    runner = RAAF::Runner.new(agent: create_agent, provider: provider)
    runner.run(message)
  end
end

# Usage
agent = MultiProviderAgent.new
result = agent.run_task("Explain quantum computing", task_type: :reasoning)
code_result = agent.run_task("Write a Ruby method", task_type: :coding)
```

## Retryable Provider

```ruby
# Add retry logic to any provider
base_provider = RAAF::Models::OpenAIProvider.new
retryable_provider = RAAF::Models::RetryableProvider.new(base_provider) do |config|
  config.max_retries = 3
  config.initial_delay = 1.0
  config.backoff_multiplier = 2.0
  config.max_delay = 60.0
  config.retry_on = [
    RAAF::Errors::RateLimitError,
    RAAF::Errors::ServiceUnavailableError,
    Net::TimeoutError
  ]
end

runner = RAAF::Runner.new(agent: agent, provider: retryable_provider)
```

## Custom Provider

```ruby
class CustomProvider < RAAF::Models::Interface
  def initialize(config = {})
    @api_key = config[:api_key]
    @base_url = config[:base_url]
  end
  
  def complete(messages, options = {})
    # Implement your provider logic
    response = call_custom_api(messages, options)
    
    # Return standardized response
    {
      content: response[:text],
      usage: {
        input_tokens: response[:input_tokens],
        output_tokens: response[:output_tokens],
        total_tokens: response[:total_tokens]
      },
      model: options[:model],
      finish_reason: response[:finish_reason]
    }
  end
  
  private
  
  def call_custom_api(messages, options)
    # Your API implementation
    HTTP.auth("Bearer #{@api_key}")
        .post("#{@base_url}/chat/completions", json: {
          messages: messages,
          model: options[:model],
          max_tokens: options[:max_tokens]
        })
  end
end

# Use custom provider
custom_provider = CustomProvider.new(
  api_key: ENV['CUSTOM_API_KEY'],
  base_url: "https://api.custom-llm.com/v1"
)

runner = RAAF::Runner.new(agent: agent, provider: custom_provider)
```

## Provider Configuration

### Global Configuration
```ruby
RAAF::Providers.configure do |config|
  config.default_timeout = 30
  config.default_retries = 3
  config.rate_limit_handling = :wait
  config.log_requests = true
end
```

### Provider-Specific Settings
```ruby
# Different settings per provider
providers_config = {
  openai: {
    timeout: 60,
    max_retries: 5,
    temperature: 0.7
  },
  anthropic: {
    timeout: 90,
    max_retries: 3,
    temperature: 0.5
  }
}
```

## Cost Optimization

```ruby
# Route requests based on cost and capability
class CostOptimizedProvider
  def initialize
    @providers = {
      cheap: RAAF::Models::GroqProvider.new,      # Fast, cheap
      balanced: RAAF::Models::OpenAIProvider.new,  # Good balance
      premium: RAAF::Models::AnthropicProvider.new # Best quality
    }
  end
  
  def route_request(complexity_score)
    case complexity_score
    when 0..3 then @providers[:cheap]
    when 4..7 then @providers[:balanced]
    else @providers[:premium]
    end
  end
end
```

## Environment Variables

```bash
# Provider API keys
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-anthropic-key"
export COHERE_API_KEY="your-cohere-key"
export GROQ_API_KEY="your-groq-key"
export TOGETHER_API_KEY="your-together-key"

# Configuration
export RAAF_DEFAULT_PROVIDER="openai"
export RAAF_PROVIDER_TIMEOUT="30"
export RAAF_PROVIDER_RETRIES="3"
```