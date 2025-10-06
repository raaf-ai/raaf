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

##### Multi-Stage Research Pipeline

```ruby
class ResearchPipeline
  def initialize
    @perplexity = RAAF::Models::PerplexityProvider.new(
      api_key: ENV['PERPLEXITY_API_KEY']
    )
    @agent = RAAF::Agent.new(
      name: "Researcher",
      instructions: "Provide comprehensive research with citations",
      model: "sonar-pro"
    )
  end

  def research(topic)
    runner = RAAF::Runner.new(agent: @agent, provider: @perplexity)

    # Stage 1: Broad overview
    overview = runner.run("#{topic} overview recent developments")

    # Stage 2: Technical details from authoritative sources
    details = runner.run(
      "#{topic} technical details implementation",
      web_search_options: { search_recency_filter: "month" }
    )

    # Stage 3: Expert opinions from specific domains
    opinions = runner.run(
      "#{topic} expert analysis best practices",
      web_search_options: {
        search_domain_filter: ["thoughtworks.com", "martinfowler.com"]
      }
    )

    {
      overview: overview,
      details: details,
      opinions: opinions
    }
  end
end

# Usage
pipeline = ResearchPipeline.new
results = pipeline.research("Ruby 3.4 YJIT improvements")
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