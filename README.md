# OpenAI Agents Ruby

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-0.1.0-blue.svg)](https://rubygems.org/gems/openai_agents)
[![Ruby](https://img.shields.io/badge/Ruby-3.0%2B-red.svg)](https://www.ruby-lang.org/)

A comprehensive Ruby implementation of OpenAI Agents for building sophisticated multi-agent AI workflows. This gem provides 100% feature parity with the Python OpenAI Agents library, plus additional enterprise-grade capabilities.

> 🤖 **Built with AI**: This codebase was developed using AI assistance, demonstrating AI-assisted software development at scale.

## 🌟 Key Features

- **🤖 Multi-Agent Workflows** - Specialized agents with intelligent routing
- **🔧 Advanced Tool Integration** - File search, web search, computer automation, code interpreter
- **📡 Real-time Streaming** - Live response streaming with event handling
- **📊 Comprehensive Tracing** - OpenAI dashboard integration with span-based monitoring
- **🎯 Multi-Provider Support** - OpenAI, Anthropic, Gemini, Cohere, Groq, Ollama, and 100+ LLMs
- **🛡️ Enterprise Guardrails** - Safety, validation, compliance, and cost controls
- **🎤 Voice Workflows** - Complete speech-to-text and text-to-speech pipeline
- **📈 Usage Analytics** - Resource monitoring, cost tracking, and business insights
- **💻 Developer Tools** - Interactive REPL, debugging, and visualization

## 🚀 Quick Start

### Installation

```bash
gem install openai_agents
```

Or add to your Gemfile:
```ruby
gem 'openai_agents'
```

### Basic Example

```ruby
require 'openai_agents'

# Set your API key
ENV['OPENAI_API_KEY'] = 'your-api-key'

# Define a tool
def get_weather(city)
  "The weather in #{city} is sunny with 22°C"
end

# Create an agent
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o"
)

# Add tools
agent.add_tool(method(:get_weather))

# Run conversation
runner = OpenAIAgents::Runner.new(agent: agent)
result = runner.run("What's the weather in Paris?")

puts result.messages.last[:content]
```

### Multi-Agent Example

```ruby
# Create specialized agents
support_agent = OpenAIAgents::Agent.new(
  name: "CustomerSupport",
  instructions: "Handle general inquiries, escalate complex issues.",
  model: "gpt-4"
)

tech_agent = OpenAIAgents::Agent.new(
  name: "TechnicalSupport", 
  instructions: "Handle technical troubleshooting.",
  model: "gpt-4"
)

# Set up handoffs
support_agent.add_handoff(tech_agent)

# Automatic handoff based on conversation context
runner = OpenAIAgents::Runner.new(agent: support_agent)
result = runner.run("My API integration is failing with 500 errors")
```

## 📚 Documentation

### Getting Started
- **[Getting Started Guide](GETTING_STARTED.md)** - Detailed tutorials and core concepts
- **[Examples](EXAMPLES.md)** - Comprehensive code examples for all features
- **[API Reference](API_REFERENCE.md)** - Complete API documentation

### Production
- **[Deployment Guide](DEPLOYMENT.md)** - Production setup, Docker, configuration
- **[Security Guide](SECURITY.md)** - Security best practices and guidelines
- **[Tracing Guide](TRACING.md)** - Monitoring and observability

### Development
- **[Contributing Guide](CONTRIBUTING.md)** - How to contribute to the project
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
- **[Changelog](CHANGELOG.md)** - Version history and updates

## 🏗️ Core Architecture

### Agents
AI systems that can use tools, make decisions, and collaborate with other agents to complete complex workflows.

### Tools
Functions that extend agent capabilities:
- **File Search** - Search through codebases and documentation
- **Web Search** - Access real-time information
- **Computer Control** - Automate UI interactions
- **Code Interpreter** - Execute code safely

### Multi-Agent Workflows
Specialized agents working together with intelligent handoffs based on context and capabilities.

### Tracing & Monitoring
Comprehensive observability with OpenAI dashboard integration for debugging and optimization.

## 🎯 Use Cases

- **Customer Service** - Automated support with specialist handoffs
- **Research & Analysis** - Information gathering and synthesis
- **Code Assistance** - Development help and code review
- **Data Processing** - Automated analysis and reporting
- **Voice Interfaces** - Speech-enabled applications

## 🌐 Provider Support

- **OpenAI** - GPT-4, GPT-3.5, and other OpenAI models
- **Anthropic** - Claude 3.5 Sonnet, Claude 3 Opus, and Haiku
- **Google** - Gemini 1.5 Pro and Flash
- **Cohere** - Command and Chat models
- **Groq** - High-speed inference
- **Ollama** - Local model serving
- **100+ More** - Via compatible APIs

## 🛡️ Enterprise Features

- **Safety Guardrails** - Content filtering and input validation
- **Rate Limiting** - Prevent abuse and control costs
- **Usage Tracking** - Comprehensive analytics and reporting
- **Cost Controls** - Budget limits and alerts
- **Audit Logging** - Complete activity trails
- **Configuration Management** - Environment-based settings

## 💻 Development Experience

```ruby
# Ruby-idiomatic agent configuration
agent = OpenAIAgents::Agent.new(name: "Assistant") do |config|
  config.instructions = "You are a helpful assistant"
  config.model = "gpt-4o"
  config.add_tool(calculator_tool)
end

# Dynamic tool execution
result = agent.get_weather(city: "Tokyo")  # Direct method calls

# Comprehensive tracing
tracer = OpenAIAgents.tracer
runner = OpenAIAgents::Runner.new(agent: agent, tracer: tracer)
```

## 🤝 Community & Support

- **GitHub Issues** - Bug reports and feature requests
- **Documentation** - Comprehensive guides and examples
- **Contributing** - Join our growing community

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by the [OpenAI Agents Python SDK](https://github.com/openai/openai-agents-python)
- Built with ❤️ for the Ruby community
- Thanks to all contributors and users

---

**Ready to build intelligent AI workflows?** Start with our [Getting Started Guide](GETTING_STARTED.md) or explore the [Examples](EXAMPLES.md).