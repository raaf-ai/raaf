# Ruby AI Agents Factory (RAAF) 🤖

[![Gem Version](https://badge.fury.io/rb/raaf.svg)](https://badge.fury.io/rb/raaf)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ruby Version](https://img.shields.io/badge/Ruby-3.0%2B-red.svg)](https://www.ruby-lang.org/)

**Ruby AI Agents Factory** is a comprehensive Ruby framework for building sophisticated multi-agent AI workflows with enterprise-grade features. This main gem includes all components needed to create, deploy, and manage AI agents at scale.

## 🚀 Quick Start

### Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install raaf
```

### Basic Usage

```ruby
require 'raaf'

# Create an agent
agent = RubyAIAgentsFactory::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o"
)

# Run the agent
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("Hello, how are you?")
puts result.messages.last[:content]
```

### With Tools

```ruby
require 'raaf'

# Define a custom tool
def get_weather(location)
  "The weather in #{location} is sunny and 72°F"
end

# Create agent with tools
agent = RubyAIAgentsFactory::Agent.new(
  name: "WeatherBot",
  instructions: "You are a weather assistant.",
  model: "gpt-4o",
  tools: [method(:get_weather)]
)

runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("What's the weather in Tokyo?")
```

## 📦 What's Included

This main `raaf` gem includes all the following components:

### Core Components
- **[raaf-core](../core)** - Core agent framework and execution engine
- **[raaf-providers](../providers)** - Multiple LLM provider integrations (OpenAI, Anthropic, Cohere, etc.)
- **[raaf-tools-basic](../tools-basic)** - Basic tools (math, text processing)
- **[raaf-tools-advanced](../tools-advanced)** - Advanced tools (web search, file operations, computer control)

### Enterprise Features
- **[raaf-guardrails](../guardrails)** - Safety and security guardrails
- **[raaf-tracing](../tracing)** - Comprehensive monitoring and observability
- **[raaf-streaming](../streaming)** - Real-time streaming capabilities
- **[raaf-memory](../memory)** - Memory management and vector storage
- **[raaf-compliance](../compliance)** - Enterprise compliance and audit logging

### Development & Integration
- **[raaf-dsl](../dsl)** - Domain-specific language for agent building
- **[raaf-debug](../debug)** - Debugging tools and REPL
- **[raaf-testing](../testing)** - Testing utilities and mocks
- **[raaf-visualization](../visualization)** - Workflow visualization and reporting
- **[raaf-extensions](../extensions)** - Plugin architecture and extensions
- **[raaf-rails](../rails)** - Rails integration and web interface

## 🎯 Key Features

### 🧠 Multi-Agent Workflows
- **Agent Handoffs**: Seamless delegation between specialized agents
- **Conversation Management**: Persistent conversation state and context
- **Parallel Processing**: Execute multiple agents concurrently

### 🔧 Comprehensive Tooling
- **Built-in Tools**: Math, text processing, web search, file operations
- **Custom Tools**: Easy integration of your own functions
- **Tool Context**: Stateful tool execution with shared context

### 🛡️ Enterprise Security
- **Guardrails**: Input/output filtering and safety checks
- **PII Detection**: Automatic detection and masking of sensitive data
- **Compliance**: GDPR, HIPAA, SOX audit logging

### 📊 Monitoring & Observability
- **Distributed Tracing**: Full execution tracing with OpenTelemetry
- **Performance Metrics**: Response times, token usage, cost tracking
- **Real-time Dashboard**: Web-based monitoring interface

### 🔄 Streaming & Real-time
- **Streaming Responses**: Real-time response streaming
- **WebSocket Support**: Live agent interactions
- **Event-driven Architecture**: Reactive agent workflows

### 💾 Memory & Context
- **Vector Storage**: Semantic memory with vector embeddings
- **Context Management**: Automatic context window management
- **Persistent Memory**: Long-term memory across conversations

## 🔌 Provider Support

RAAF supports multiple LLM providers out of the box:

- **OpenAI** (GPT-4, GPT-3.5, etc.)
- **Anthropic** (Claude 3, Claude 2, etc.)
- **Cohere** (Command, Generate, etc.)
- **Groq** (Llama, Mixtral, etc.)
- **Ollama** (Local models)
- **LiteLLM** (Unified interface to 100+ models)
- **Together AI** (Open source models)

## 🎨 DSL Usage

Use the intuitive DSL for rapid agent development:

```ruby
require 'raaf'

# Use the DSL
RubyAIAgentsFactory::DSL.define_agent :weather_bot do
  name "WeatherBot"
  instructions "You are a helpful weather assistant"
  model "gpt-4o"
  
  tool :get_weather do |location|
    "The weather in #{location} is sunny and 72°F"
  end
  
  guardrail :input do |input|
    input.length < 1000
  end
end

# Run the agent
agent = RubyAIAgentsFactory::DSL.agents[:weather_bot]
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("What's the weather in Tokyo?")
```

## 🚂 Rails Integration

RAAF provides seamless Rails integration:

```ruby
# In your Rails application
class ChatController < ApplicationController
  def create
    agent = RubyAIAgentsFactory::Agent.new(
      name: "ChatBot",
      instructions: "You are a helpful customer service agent.",
      model: "gpt-4o"
    )
    
    runner = RubyAIAgentsFactory::Runner.new(agent: agent)
    result = runner.run(params[:message])
    
    render json: { response: result.messages.last[:content] }
  end
end
```

Mount the web dashboard:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount RubyAIAgentsFactory::Rails::Engine => "/agents"
end
```

## 📈 Monitoring & Tracing

Enable comprehensive monitoring:

```ruby
require 'raaf'

# Set up tracing
tracer = RubyAIAgentsFactory::Tracing::SpanTracer.new
tracer.add_processor(RubyAIAgentsFactory::Tracing::OpenAIProcessor.new)

# Create agent with tracing
agent = RubyAIAgentsFactory::Agent.new(
  name: "TracedAgent",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o"
)

runner = RubyAIAgentsFactory::Runner.new(agent: agent, tracer: tracer)
result = runner.run("Explain quantum computing")
```

## 🧪 Testing

RAAF includes comprehensive testing utilities:

```ruby
require 'raaf'

# Use test helpers
RSpec.describe "My Agent" do
  include RubyAIAgentsFactory::Testing::Helpers
  
  let(:agent) { create_test_agent }
  
  it "responds correctly" do
    response = run_agent(agent, "Hello")
    expect(response).to include("Hello")
  end
end
```

## 📊 Performance

RAAF is designed for high performance:

- **Concurrent Execution**: Process multiple agents in parallel
- **Streaming Responses**: Real-time response streaming
- **Connection Pooling**: Efficient HTTP connection management
- **Caching**: Intelligent caching of responses and embeddings
- **Rate Limiting**: Built-in rate limiting and retry logic

## 🌐 Community & Support

- **Documentation**: [https://docs.raaf.ai](https://docs.raaf.ai)
- **GitHub**: [https://github.com/raaf-ai/ruby-ai-agents-factory](https://github.com/raaf-ai/ruby-ai-agents-factory)
- **Issues**: [GitHub Issues](https://github.com/raaf-ai/ruby-ai-agents-factory/issues)
- **Discussions**: [GitHub Discussions](https://github.com/raaf-ai/ruby-ai-agents-factory/discussions)

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](../CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

## 🙏 Acknowledgments

Built with ❤️ by the RAAF team and contributors. Special thanks to the Ruby and AI communities for their support and inspiration.

---

**Ruby AI Agents Factory** - Building the future of AI agents in Ruby 🚀