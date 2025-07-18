# RAAF Providers - Claude Code Guide

This gem provides multiple AI provider integrations for RAAF agents, supporting OpenAI, Anthropic, Cohere, Groq, Ollama, and more.

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

### Ollama Provider (Local)
```ruby
ollama_provider = RAAF::Models::OllamaProvider.new do |config|
  config.base_url = "http://localhost:11434"
  config.model = "llama2"
  config.temperature = 0.7
  config.timeout = 60
end

runner = RAAF::Runner.new(agent: agent, provider: ollama_provider)
```

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
      speed: RAAF::Models::GroqProvider.new(model: "mixtral-8x7b"),
      local: RAAF::Models::OllamaProvider.new(model: "llama2")
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
  },
  local: {
    timeout: 120,
    max_retries: 1,
    temperature: 0.8
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