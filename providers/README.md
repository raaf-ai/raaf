# RAAF Providers

[![Gem Version](https://badge.fury.io/rb/raaf-providers.svg)](https://badge.fury.io/rb/raaf-providers)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Providers** gem provides comprehensive multi-provider LLM support for the Ruby AI Agents Factory (RAAF) ecosystem. It offers a unified interface for multiple Large Language Model providers, enabling seamless switching between different AI services.

## Overview

RAAF (Ruby AI Agents Factory) Providers extends the provider interfaces from `raaf-core` to provide:

- **Multi-Provider Support** - OpenAI, Anthropic, Cohere, Groq, Mistral, and more
- **Unified Interface** - Consistent API across all providers
- **Provider Switching** - Easy switching between providers without code changes
- **Load Balancing** - Automatic failover and load distribution
- **Rate Limiting** - Built-in rate limiting and retry logic
- **Cost Optimization** - Automatic provider selection based on cost and performance

## Supported Providers

### OpenAI
- **Models**: GPT-4, GPT-4 Turbo, GPT-3.5 Turbo, GPT-4o
- **Features**: Chat completions, function calling, streaming, vision
- **API**: Both Chat Completions and Responses API

### Anthropic
- **Models**: Claude 3 Opus, Claude 3 Sonnet, Claude 3 Haiku
- **Features**: Chat completions, function calling, streaming, vision
- **API**: Messages API

### Cohere
- **Models**: Command, Command-R, Command-R+
- **Features**: Chat completions, function calling, streaming
- **API**: Chat API

### Groq
- **Models**: Llama 3, Mixtral, Gemma
- **Features**: High-speed inference, streaming
- **API**: Chat Completions API

### Perplexity
- **Models**: Sonar, Sonar Pro, Sonar Reasoning Pro, Sonar Deep Research
- **Features**: Web-grounded search, citations, JSON schema support
- **API**: Chat Completions API with web search

### Mistral
- **Models**: Mistral 7B, Mistral 8x7B, Mistral Large
- **Features**: Chat completions, function calling
- **API**: Chat Completions API

### Google AI
- **Models**: Gemini Pro, Gemini Pro Vision
- **Features**: Chat completions, multimodal, streaming
- **API**: GenerativeAI API

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-providers', '~> 1.0'
```

And then execute:

```bash
bundle install
```

## Usage

### Basic Provider Usage

```ruby
require 'raaf-providers'

# OpenAI Provider
openai = RAAF::Models::OpenAIProvider.new(
  api_key: ENV['OPENAI_API_KEY']
)

# Anthropic Provider
anthropic = RAAF::Models::AnthropicProvider.new(
  api_key: ENV['ANTHROPIC_API_KEY']
)

# Use with agents
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant",
  model: "gpt-4o"
)

runner = RAAF::Runner.new(
  agent: agent,
  provider: openai  # or anthropic, cohere, etc.
)
```

### Multi-Provider Support

```ruby
# Automatic provider selection based on model
provider = RAAF::Models::MultiProvider.auto_provider(model: "claude-3-sonnet")
provider = RAAF::Models::MultiProvider.auto_provider(model: "gpt-4o")

# Create specific provider with custom options
anthropic = RAAF::Models::MultiProvider.create_provider("anthropic", api_key: "custom-key")
groq = RAAF::Models::MultiProvider.create_provider("groq", timeout: 30)

# List available providers
puts "Available providers: #{RAAF::Models::MultiProvider.supported_providers}"
```

### Using Different Providers

```ruby
# Create different providers
anthropic = RAAF::Models::AnthropicProvider.new(
  api_key: ENV['ANTHROPIC_API_KEY']
)

cohere = RAAF::Models::CohereProvider.new(
  api_key: ENV['COHERE_API_KEY']
)

groq = RAAF::Models::GroqProvider.new(
  api_key: ENV['GROQ_API_KEY']
)

# Use with agents
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant",
  model: "claude-3-sonnet"  # or "command-r", "llama3-8b-8192", etc.
)

runner = RAAF::Runner.new(
  agent: agent,
  provider: anthropic  # or cohere, groq, etc.
)
```

### Provider Switching

```ruby
# Switch providers at runtime
openai = RAAF::Models::OpenAIProvider.new
anthropic = RAAF::Models::AnthropicProvider.new

runner = RAAF::Runner.new(agent: agent)

# Use OpenAI
runner.provider = openai
result1 = runner.run("Hello")

# Switch to Anthropic  
runner.provider = anthropic
result2 = runner.run("Hello")
```

### Retry Logic

```ruby
# Add retry logic to any provider
base_provider = RAAF::Models::OpenAIProvider.new
retryable_provider = RAAF::Models::RetryableProviderWrapper.new(base_provider) do |config|
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

runner = RAAF::Runner.new(
  agent: agent,
  provider: retryable_provider
)
```

## Provider-Specific Features

### OpenAI Features

```ruby
openai = RAAF::Models::OpenAIProvider.new do |config|
  config.api_key = ENV['OPENAI_API_KEY']
  config.organization = ENV['OPENAI_ORG_ID']
  config.use_responses_api = true  # Use new Responses API
  config.streaming = true
  config.function_calling = true
end

# Vision capabilities
result = openai.chat_completion(
  messages: [
    { role: "user", content: [
      { type: "text", text: "What's in this image?" },
      { type: "image_url", image_url: { url: "data:image/jpeg;base64,..." } }
    ]}
  ],
  model: "gpt-4o"
)
```

### Anthropic Features

```ruby
anthropic = RAAF::Models::AnthropicProvider.new do |config|
  config.api_key = ENV['ANTHROPIC_API_KEY']
  config.max_tokens = 4000
  config.streaming = true
end

# System message handling
result = anthropic.chat_completion(
  messages: [
    { role: "user", content: "Hello" }
  ],
  model: "claude-3-opus-20240229",
  system: "You are a helpful assistant"
)
```

### Cohere Features

```ruby
cohere = RAAF::Models::CohereProvider.new do |config|
  config.api_key = ENV['COHERE_API_KEY']
  config.temperature = 0.7
  config.max_tokens = 4000
end

# Command-R+ with RAG
result = cohere.chat_completion(
  messages: [{ role: "user", content: "Search for information about AI" }],
  model: "command-r-plus",
  documents: [
    { text: "AI is transforming industries...", title: "AI Overview" }
  ]
)
```

### Perplexity Features

Perplexity AI provides **web-grounded search** with automatic citations, making it ideal for research tasks requiring real-time information and source attribution.

#### Basic Usage

```ruby
perplexity = RAAF::Models::PerplexityProvider.new(
  api_key: ENV['PERPLEXITY_API_KEY']
)

# Web-grounded search with citations
result = perplexity.chat_completion(
  messages: [{ role: "user", content: "Latest Ruby news" }],
  model: "sonar-pro"
)

# Access citations and sources
puts "Citations: #{result['citations']}"
puts "Web results: #{result['web_results']}"
```

#### Available Models

```ruby
# sonar - Fast web search (best for quick queries)
perplexity.chat_completion(
  messages: [{ role: "user", content: "Ruby 3.4 features" }],
  model: "sonar"
)

# sonar-pro - Advanced search with structured output support
perplexity.chat_completion(
  messages: [{ role: "user", content: "Compare Ruby vs Python performance" }],
  model: "sonar-pro"
)

# sonar-reasoning - Deep reasoning with web search
perplexity.chat_completion(
  messages: [{ role: "user", content: "Analyze trends in Ruby development" }],
  model: "sonar-reasoning"
)

# sonar-reasoning-pro - Premium reasoning with structured output
perplexity.chat_completion(
  messages: [{ role: "user", content: "Technical analysis of Rails 8" }],
  model: "sonar-reasoning-pro"
)
```

#### Structured Output with JSON Schema

**Only available on `sonar-pro` and `sonar-reasoning-pro` models:**

```ruby
# Define structured schema
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

result = perplexity.chat_completion(
  messages: [{ role: "user", content: "Find top 3 Ruby news items from this month" }],
  model: "sonar-pro",
  response_format: schema
)

# Result automatically parsed to match schema
puts result[:news_items].first[:title]
puts result[:total]
```

#### Web Search Filtering

```ruby
# Domain filtering - restrict to specific websites
result = perplexity.chat_completion(
  messages: [{ role: "user", content: "Ruby updates" }],
  model: "sonar",
  web_search_options: {
    search_domain_filter: ["ruby-lang.org", "github.com/rails"],
    search_recency_filter: "week"
  }
)

# Recency filtering options:
# - "hour" - Last hour
# - "day" - Last 24 hours
# - "week" - Last 7 days
# - "month" - Last 30 days
# - "year" - Last 365 days

# Combine filters for precise results
result = perplexity.chat_completion(
  messages: [{ role: "user", content: "Ruby security advisories" }],
  model: "sonar-pro",
  web_search_options: {
    search_domain_filter: ["ruby-lang.org", "github.com"],
    search_recency_filter: "month"
  }
)
```

#### RAAF DSL Integration

```ruby
# Use Perplexity in DSL agents
class RubyNewsAgent < RAAF::DSL::Agent
  instructions "Search for recent Ruby programming news"
  model "sonar-pro"
  provider :perplexity

  schema do
    field :news_items, type: :array, required: true do
      field :title, type: :string, required: true
      field :summary, type: :string, required: true
      field :url, type: :string, required: true
    end
    field :total, type: :integer, required: true
  end
end

# Run with automatic provider
agent = RubyNewsAgent.new
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Find latest Ruby 3.4 news")

# Access structured results
result[:news_items].each do |item|
  puts "#{item[:title]}: #{item[:url]}"
end
```

#### Prompt Engineering for Perplexity

Perplexity works best with **search-optimized prompts**. Follow these best practices:

##### 1. Be Specific and Contextual

```ruby
# ❌ BAD: Too generic
result = perplexity.chat_completion(
  messages: [{ role: "user", content: "Tell me about climate models" }],
  model: "sonar"
)

# ✅ GOOD: Specific with context
result = perplexity.chat_completion(
  messages: [{
    role: "user",
    content: "Explain recent advances in climate prediction models for urban planning"
  }],
  model: "sonar"
)
```

##### 2. Structure Prompts Like Web Searches

```ruby
# ✅ Think like a search user
prompts = [
  "Latest Ruby on Rails security vulnerabilities 2024",
  "Best practices Ruby microservices architecture",
  "Compare Rails 7 vs Rails 8 performance benchmarks"
]

prompts.each do |prompt|
  result = perplexity.chat_completion(
    messages: [{ role: "user", content: prompt }],
    model: "sonar"
  )
  puts result[:content]
end
```

##### 3. Use System Prompts for Style/Tone

```ruby
# Set style with system prompt
result = perplexity.chat_completion(
  messages: [
    { role: "system", content: "Provide clear, concise, expert-level technical information" },
    { role: "user", content: "Ruby 3.4 performance improvements" }
  ],
  model: "sonar-pro"
)
```

##### 4. Prevent Hallucinations

```ruby
# Include explicit instructions about limitations
result = perplexity.chat_completion(
  messages: [{
    role: "user",
    content: <<~PROMPT
      Find information about Ruby 4.0 roadmap.

      If information is not available or uncertain, clearly state that.
      Only use publicly accessible sources.
      Acknowledge when information is limited or unavailable.
    PROMPT
  }],
  model: "sonar-pro"
)
```

##### 5. Single-Topic Focus

```ruby
# ❌ BAD: Multiple unrelated topics
result = perplexity.chat_completion(
  messages: [{
    role: "user",
    content: "Tell me about Ruby performance, Rails security, and Python comparisons"
  }],
  model: "sonar"
)

# ✅ GOOD: One focused topic
result = perplexity.chat_completion(
  messages: [{
    role: "user",
    content: "Ruby vs Python performance benchmarks for web applications"
  }],
  model: "sonar"
)
```

##### 6. Never Request URLs in Prompts

```ruby
# ❌ BAD: Requesting URLs directly
result = perplexity.chat_completion(
  messages: [{
    role: "user",
    content: "Find URLs for Ruby documentation"
  }],
  model: "sonar"
)

# ✅ GOOD: Use search_results field for source information
result = perplexity.chat_completion(
  messages: [{
    role: "user",
    content: "Ruby 3.4 documentation and guides"
  }],
  model: "sonar"
)

# Access sources programmatically
result[:web_results].each do |source|
  puts "#{source[:title]}: #{source[:url]}"
end
```

##### 7. Use Built-in Parameters Instead of Prompt Instructions

```ruby
# ❌ BAD: Using prompt to filter
result = perplexity.chat_completion(
  messages: [{
    role: "user",
    content: "Search only ruby-lang.org for Ruby news from this week"
  }],
  model: "sonar"
)

# ✅ GOOD: Use API parameters
result = perplexity.chat_completion(
  messages: [{ role: "user", content: "Ruby news" }],
  model: "sonar",
  web_search_options: {
    search_domain_filter: ["ruby-lang.org"],
    search_recency_filter: "week"
  }
)
```

#### Advanced Perplexity Patterns

##### Research Pipeline

```ruby
# Multi-stage research with Perplexity
class ResearchPipeline
  def initialize
    @perplexity = RAAF::Models::PerplexityProvider.new(
      api_key: ENV['PERPLEXITY_API_KEY']
    )
  end

  def research(topic)
    # Stage 1: Broad search
    overview = search("#{topic} overview recent developments")

    # Stage 2: Specific details from top sources
    details = search(
      "#{topic} technical details implementation",
      recency: "month"
    )

    # Stage 3: Expert opinions
    opinions = search(
      "#{topic} expert analysis best practices",
      domains: ["thoughtworks.com", "martinfowler.com"]
    )

    {
      overview: overview,
      details: details,
      opinions: opinions
    }
  end

  private

  def search(query, recency: "week", domains: nil)
    options = { search_recency_filter: recency }
    options[:search_domain_filter] = domains if domains

    @perplexity.chat_completion(
      messages: [{ role: "user", content: query }],
      model: "sonar-pro",
      web_search_options: options
    )
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
  PROMPT

  model "sonar-reasoning-pro"
  provider :perplexity

  schema do
    field :claim, type: :string, required: true
    field :verdict, type: :string, required: true  # "True", "False", "Uncertain"
    field :confidence, type: :string, required: true  # "High", "Medium", "Low"
    field :evidence, type: :array, required: true do
      field :source, type: :string, required: true
      field :quote, type: :string, required: true
    end
  end
end

# Verify technical claims
agent = FactCheckAgent.new
result = agent.run("Ruby 3.4 has 40% faster performance than Ruby 3.3")

puts "Verdict: #{result[:verdict]} (#{result[:confidence]} confidence)"
result[:evidence].each do |e|
  puts "- #{e[:source]}: #{e[:quote]}"
end
```

**Perplexity Capabilities:**
- ✅ Web-grounded search with real-time information
- ✅ Automatic citations and source tracking
- ✅ JSON schema support (sonar-pro, sonar-reasoning-pro)
- ✅ Web search filtering (domain and recency)
- ✅ RAAF DSL agent compatibility
- ✅ Multi-stage research workflows

**Perplexity Limitations:**
- ❌ No function/tool calling support (cannot participate in multi-agent handoffs)
- ❌ Streaming not yet implemented
- ❌ JSON schema limited to specific models (sonar-pro, sonar-reasoning-pro)
- ⚠️ Real-time search may not always follow system prompt precisely
- ⚠️ Avoid traditional LLM techniques like few-shot prompting

## Relationship with Other Gems

### Foundation Dependencies

- **raaf-core** - Implements provider interfaces and base classes
- **raaf-logging** - Uses logging for provider operations and debugging
- **raaf-configuration** - Uses configuration for provider settings

### Used By Agent Features

- **raaf-dsl** - Provides DSL syntax for provider configuration
- **raaf-tracing** - Traces provider API calls and performance metrics
- **raaf-memory** - Uses providers for embedding generation
- **raaf-tools-basic** - Integrates with provider function calling
- **raaf-tools-advanced** - Uses providers for advanced tool capabilities

### Integration with Infrastructure

- **raaf-rails** - Provides Rails integration for provider management
- **raaf-streaming** - Uses providers for streaming responses
- **raaf-testing** - Provides mocking and testing utilities for providers

### Enterprise Features

- **raaf-guardrails** - Validates provider responses for safety
- **raaf-compliance** - Ensures provider usage meets compliance requirements
- **raaf-security** - Secures provider API keys and communications
- **raaf-monitoring** - Monitors provider performance and costs

### Operations Support

- **raaf-debug** - Provides debugging tools for provider interactions
- **raaf-analytics** - Analyzes provider usage and performance
- **raaf-deployment** - Manages provider configurations in deployment
- **raaf-cli** - Provides CLI commands for provider management

## Architecture

### Core Components

```
RAAF::Models::
├── ModelInterface           # Base provider interface (from raaf-core)
├── OpenAIProvider          # OpenAI provider implementation
├── AnthropicProvider       # Anthropic provider implementation
├── CohereProvider          # Cohere provider implementation
├── GroqProvider            # Groq provider implementation
├── TogetherProvider        # Together AI provider implementation
├── LitellmProvider         # LiteLLM provider implementation
├── MultiProvider           # Multi-provider support with auto-selection
└── RetryableProviderWrapper # Retry wrapper (from raaf-core)
```

### Provider Interface

```ruby
class CustomProvider < RAAF::Models::ModelInterface
  def chat_completion(messages:, model:, **options)
    # Implementation
  end
  
  def stream_completion(messages:, model:, **options)
    # Streaming implementation
  end
  
  def available_models
    # Return list of available models
  end
  
  def supports_function_calling?
    # Return true if provider supports function calling
  end
end
```

## Advanced Features

### Custom Provider Development

```ruby
# Create custom provider
class MyCustomProvider < RAAF::Models::ModelInterface
  def initialize(api_key:, base_url:)
    @api_key = api_key
    @base_url = base_url
    super()
  end
  
  def chat_completion(messages:, model:, **options)
    # Custom implementation
    response = http_client.post("#{@base_url}/chat/completions", {
      model: model,
      messages: messages,
      **options
    })
    
    parse_response(response)
  end
  
  private
  
  def parse_response(response)
    # Parse provider-specific response format
  end
end

# Use custom provider
custom_provider = MyCustomProvider.new(
  api_key: ENV['CUSTOM_API_KEY'],
  base_url: "https://api.custom-llm.com/v1"
)

runner = RAAF::Runner.new(agent: agent, provider: custom_provider)
```

### Cost Optimization Strategy

```ruby
# Route requests based on cost and capability
class CostOptimizedProvider
  def initialize
    @providers = {
      cheap: RAAF::Models::GroqProvider.new,       # Fast, cheap
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

# Usage
optimizer = CostOptimizedProvider.new
provider = optimizer.route_request(task_complexity)
runner = RAAF::Runner.new(agent: agent, provider: provider)
```

## Best Practices

1. **Use Environment Variables** - Store API keys securely
2. **Implement Failover** - Configure backup providers
3. **Monitor Usage** - Track costs and performance
4. **Rate Limiting** - Implement appropriate rate limits
5. **Model Selection** - Choose appropriate models for tasks

## Development

### Running Tests

```bash
cd providers/
bundle exec rspec
```

### Testing Providers

```ruby
# Test provider implementations
RSpec.describe RAAF::Models::OpenAIProvider do
  include RAAF::Testing::ProviderMatchers
  
  it "supports chat completion" do
    expect(provider).to support_chat_completion
  end
  
  it "handles rate limiting" do
    expect { provider.chat_completion(messages: messages) }
      .to handle_rate_limiting
  end
end
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This gem is available as open source under the terms of the [MIT License](LICENSE).

## Support

- **Documentation**: [Ruby AI Agents Factory Docs](https://raaf-ai.github.io/ruby-ai-agents-factory/)
- **Issues**: [GitHub Issues](https://github.com/raaf-ai/ruby-ai-agents-factory/issues)
- **Discussions**: [GitHub Discussions](https://github.com/raaf-ai/ruby-ai-agents-factory/discussions)
- **Email**: bert.hajee@enterprisemodules.com

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a list of changes and version history.