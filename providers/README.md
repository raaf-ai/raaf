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
openai = RAAF::Providers::OpenAI.new(
  api_key: ENV['OPENAI_API_KEY']
)

# Anthropic Provider
anthropic = RAAF::Providers::Anthropic.new(
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

### Provider Factory

```ruby
# Create provider from configuration
provider = RAAF::Providers::Factory.create(:openai) do |config|
  config.api_key = ENV['OPENAI_API_KEY']
  config.model = 'gpt-4o'
  config.max_tokens = 4000
end

# Create from string
provider = RAAF::Providers::Factory.from_string('openai://gpt-4o')

# Create from URL
provider = RAAF::Providers::Factory.from_url('https://api.openai.com/v1')
```

### Multi-Provider Configuration

```ruby
# Configure multiple providers
RAAF::Providers.configure do |config|
  config.register :openai do |openai|
    openai.api_key = ENV['OPENAI_API_KEY']
    openai.models = ['gpt-4o', 'gpt-4-turbo', 'gpt-3.5-turbo']
  end
  
  config.register :anthropic do |anthropic|
    anthropic.api_key = ENV['ANTHROPIC_API_KEY']
    anthropic.models = ['claude-3-opus', 'claude-3-sonnet']
  end
  
  config.register :cohere do |cohere|
    cohere.api_key = ENV['COHERE_API_KEY']
    cohere.models = ['command-r-plus', 'command-r']
  end
end
```

### Provider Switching

```ruby
# Switch providers at runtime
runner = RAAF::Runner.new(agent: agent)

# Use OpenAI
runner.provider = RAAF::Providers.get(:openai)
result1 = runner.run("Hello")

# Switch to Anthropic
runner.provider = RAAF::Providers.get(:anthropic)
result2 = runner.run("Hello")
```

### Load Balancing

```ruby
# Configure load balancing across providers
balancer = RAAF::Providers::LoadBalancer.new do |config|
  config.add_provider(:openai, weight: 70)
  config.add_provider(:anthropic, weight: 20)
  config.add_provider(:cohere, weight: 10)
  config.strategy = :weighted_round_robin
end

runner = RAAF::Runner.new(
  agent: agent,
  provider: balancer
)
```

### Failover Configuration

```ruby
# Configure automatic failover
failover = RAAF::Providers::Failover.new do |config|
  config.primary_provider = :openai
  config.fallback_providers = [:anthropic, :cohere]
  config.retry_attempts = 3
  config.retry_delay = 1.0
end

runner = RAAF::Runner.new(
  agent: agent,
  provider: failover
)
```

## Provider-Specific Features

### OpenAI Features

```ruby
openai = RAAF::Providers::OpenAI.new do |config|
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
anthropic = RAAF::Providers::Anthropic.new do |config|
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
cohere = RAAF::Providers::Cohere.new do |config|
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
RAAF::Providers::
├── Base                     # Base provider class
├── OpenAI                   # OpenAI provider implementation
├── Anthropic               # Anthropic provider implementation
├── Cohere                  # Cohere provider implementation
├── Groq                    # Groq provider implementation
├── Mistral                 # Mistral provider implementation
├── GoogleAI                # Google AI provider implementation
├── Factory                 # Provider factory
├── LoadBalancer           # Load balancing across providers
├── Failover               # Failover and retry logic
├── RateLimit              # Rate limiting and throttling
└── Registry               # Provider registry and management
```

### Provider Interface

```ruby
class CustomProvider < RAAF::Providers::Base
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
class MyCustomProvider < RAAF::Providers::Base
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

# Register custom provider
RAAF::Providers.register(:custom, MyCustomProvider)
```

### Provider Middleware

```ruby
# Add middleware to providers
class LoggingMiddleware < RAAF::Providers::Middleware
  def call(request, response)
    log_info("Provider request", provider: request.provider, model: request.model)
    yield
    log_info("Provider response", tokens: response.usage.total_tokens)
  end
end

provider.use(LoggingMiddleware)
```

### Cost Optimization

```ruby
# Configure cost-based provider selection
optimizer = RAAF::Providers::CostOptimizer.new do |config|
  config.budget_limit = 100.0  # $100 per day
  config.cost_per_token = {
    'gpt-4o' => 0.00003,
    'gpt-3.5-turbo' => 0.000002,
    'claude-3-sonnet' => 0.000015
  }
  config.optimization_strategy = :cost_performance_balance
end

runner = RAAF::Runner.new(
  agent: agent,
  provider: optimizer
)
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
RSpec.describe RAAF::Providers::OpenAI do
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