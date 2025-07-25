# Ruby AI Agents Factory (RAAF)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-0.1.0-blue.svg)](https://rubygems.org/gems/ruby-ai-agents-factory)
[![Ruby](https://img.shields.io/badge/Ruby-3.0%2B-red.svg)](https://www.ruby-lang.org/)

A comprehensive Ruby framework for building sophisticated multi-agent AI workflows. Ruby AI Agents Factory (RAAF) is a Ruby implementation inspired by OpenAI's Swarm framework, providing 100% feature parity with the Python OpenAI Agents library, plus additional enterprise-grade capabilities.

> 🤖 **Built with AI**: This codebase was developed using AI assistance, demonstrating AI-assisted software development at scale.

## 🎯 About RAAF and OpenAI Swarm

RAAF is a Ruby implementation of multi-agent orchestration patterns inspired by [OpenAI's Swarm framework](https://github.com/openai/swarm). While Swarm provides an experimental, educational framework for exploring ergonomic interfaces for multi-agent systems in Python, RAAF brings these concepts to the Ruby ecosystem with production-ready features and enterprise-grade capabilities.

### Key Concepts from Swarm

Like Swarm, RAAF implements:
- **Lightweight Agents**: Agents are simple, stateless entities defined by instructions and tools
- **Handoffs**: Agents can seamlessly transfer conversations to other specialized agents
- **Function Calling**: Natural integration of Ruby methods as agent tools
- **Context Variables**: Thread-safe context passing between agents and tool calls

### Beyond Swarm: Enterprise Features

RAAF extends the Swarm concepts with:
- **Multi-Provider Support**: Not just OpenAI, but Anthropic, Google, Cohere, and 100+ LLMs
- **Production Safety**: Advanced guardrails, PII detection, and security filtering
- **Memory Management**: Token-aware context management with vector search
- **Compliance**: GDPR/SOC2/HIPAA compliance tracking and audit trails
- **Rails Integration**: Full Rails engine with web UI and database persistence
- **Comprehensive Tracing**: OpenTelemetry support and AI-powered analytics

## 🌟 Key Features

### Core Agent Capabilities
- **🤖 Multi-Agent Workflows** - Specialized agents with intelligent routing and handoffs
- **🔧 Advanced Tool Integration** - 15+ built-in tools including file search, web search, computer automation, code interpreter, document generation, and more
- **📡 Real-time Streaming** - Live response streaming with comprehensive event handling
- **🎯 Multi-Provider Support** - OpenAI, Anthropic, Gemini, Cohere, Groq, Ollama, and 100+ LLMs
- **📋 Universal Structured Output** - JSON schema enforcement across ALL providers

### Memory & Intelligence
- **🧠 Memory Management** - Token-aware context management with auto-pruning and summarization
- **🔍 Vector Search** - Semantic search with PostgreSQL/pgvector, hybrid search, and query expansion
- **📚 Document Processing** - Generate PDFs, Word docs, Excel sheets, and reports
- **🤖 MCP Integration** - Model Context Protocol support for external tool servers

### Enterprise & Production
- **🛡️ Advanced Guardrails** - PII detection, security filtering, tripwire rules, parallel execution
- **📊 Compliance & Audit** - GDPR/SOC2/HIPAA compliance tracking with integrity hashing
- **🛤️ Rails Integration** - Complete mountable engine with database storage and web UI
- **📈 Comprehensive Tracing** - OpenAI dashboard integration, AI-powered analysis, anomaly detection
- **💰 Cost Management** - Token usage tracking, budget controls, and cost analytics
- **🔍 Advanced Debugging** - Interactive debugger with breakpoints, step-through, and performance profiling

### Communication & Integration
- **🎤 Voice Workflows** - Complete speech-to-text and text-to-speech pipeline
- **🌐 External Integrations** - Confluence, local shell, computer control tools
- **📊 Business Analytics** - Usage monitoring, resource tracking, and insights
- **💻 Developer Experience** - Interactive REPL, natural language queries, export capabilities

## 🚀 Quick Start

### Installation

```bash
gem install raaf
```

Or add to your Gemfile:
```ruby
gem 'raaf'
```

### Basic Example

```ruby
require 'raaf'

# Set your API key
ENV['OPENAI_API_KEY'] = 'your-api-key'

# Define a tool
def get_weather(city)
  "The weather in #{city} is sunny with 22°C"
end

# Create an agent
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o"
)

# Add tools
agent.add_tool(method(:get_weather))

# Run conversation
runner = RAAF::Runner.new(agent: agent)
result = runner.run("What's the weather in Paris?")

puts result.messages.last[:content]
```

### Structured Output Example

```ruby
# Universal structured output across ALL providers
agent = RAAF::Agent.new(
  name: "DataExtractor",
  instructions: "Extract user information as JSON.",
  model: "gpt-4o",
  response_format: {
    type: "json_schema",
    json_schema: {
      name: "user_info",
      strict: true,
      schema: {
        type: "object",
        properties: {
          name: { type: "string" },
          age: { type: "integer" },
          email: { type: "string" }
        },
        required: ["name", "age"],
        additionalProperties: false
      }
    }
  }
)

# Works with ANY provider - OpenAI, Anthropic, Cohere, Groq, etc.
runner = RAAF::Runner.new(agent: agent)
result = runner.run("I'm Alice, 25, alice@example.com")

# Guaranteed JSON output matching your schema
user_data = JSON.parse(result.messages.last[:content])
puts "Hello #{user_data['name']}, age #{user_data['age']}!"
```

### Multi-Agent Example

```ruby
# Create specialized agents
support_agent = RAAF::Agent.new(
  name: "CustomerSupport",
  instructions: "Handle general inquiries, escalate complex issues.",
  model: "gpt-4"
)

tech_agent = RAAF::Agent.new(
  name: "TechnicalSupport", 
  instructions: "Handle technical troubleshooting.",
  model: "gpt-4"
)

# Set up handoffs
support_agent.add_handoff(tech_agent)

# Automatic handoff based on conversation context
runner = RAAF::Runner.new(agent: support_agent)
result = runner.run("My API integration is failing with 500 errors")
```

### Memory Management Example

```ruby
# Create agent with memory
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant with memory.",
  model: "gpt-4o"
)

# Add memory manager with token limits
memory_manager = RAAF::Memory::MemoryManager.new(
  store: RAAF::Memory::VectorStore.new,
  token_limit: 4000,
  pruning_strategy: :sliding_window
)

# Run with memory context
runner = RAAF::Runner.new(
  agent: agent,
  memory_manager: memory_manager
)

# Conversations are automatically stored and retrieved
result = runner.run("Remember that my favorite color is blue")
# Later...
result = runner.run("What's my favorite color?")
# => "Your favorite color is blue"
```

### Vector Search Example

```ruby
# Create vector store for semantic search
vector_store = RAAF::VectorStore.new(
  adapter: :postgresql,  # or :in_memory for development
  connection_string: ENV['DATABASE_URL']
)

# Add documents
vector_store.add_documents([
  { content: "Ruby is a dynamic programming language", metadata: { topic: "languages" } },
  { content: "Rails is a web framework for Ruby", metadata: { topic: "frameworks" } }
])

# Create agent with vector search tool
agent = RAAF::Agent.new(
  name: "ResearchAssistant",
  instructions: "Help users find relevant information.",
  model: "gpt-4o"
)

# Add vector search capability
agent.add_tool(RAAF::Tools::VectorSearchTool.new(vector_store: vector_store))

runner = RAAF::Runner.new(agent: agent)
result = runner.run("Tell me about Ruby frameworks")
```

### Document Generation Example

```ruby
# Create agent with document generation tools
agent = RAAF::Agent.new(
  name: "ReportGenerator",
  instructions: "Generate professional reports and documents.",
  model: "gpt-4o"
)

# Add document generation capabilities
agent.add_tool(RAAF::Tools::DocumentTool.new)
agent.add_tool(RAAF::Tools::ReportTool.new)

runner = RAAF::Runner.new(agent: agent)

# Generate various document types
result = runner.run("Create a PDF report summarizing Q4 sales data")
result = runner.run("Generate an Excel spreadsheet with financial projections")
result = runner.run("Create a Word document with meeting minutes")
```

### Advanced Guardrails Example

```ruby
# Configure multiple guardrails with parallel execution
guardrails = RAAF::ParallelGuardrails.new([
  RAAF::Guardrails::PIIDetector.new(
    action: :redact,
    sensitivity: :high
  ),
  RAAF::Guardrails::SecurityGuardrail.new(
    block_patterns: [/password/, /api_key/],
    action: :block
  ),
  RAAF::Guardrails::Tripwire.new(
    patterns: [/delete.*production/, /drop.*table/],
    action: :terminate
  )
])

agent = RAAF::Agent.new(
  name: "SecureAssistant",
  instructions: "Process user requests safely.",
  model: "gpt-4o",
  guardrails: guardrails
)

# Guardrails automatically filter inputs and outputs
runner = RAAF::Runner.new(agent: agent)
result = runner.run("My SSN is 123-45-6789")  # PII will be redacted
```

### Debugging Example

```ruby
# Enable interactive debugging
debugger = RAAF::Debugging::Debugger.new
agent = RAAF::Agent.new(
  name: "DebugAssistant",
  instructions: "Help debug issues.",
  model: "gpt-4o"
)

# Run with debugging enabled
runner = RAAF::DebugRunner.new(
  agent: agent,
  debugger: debugger
)

# Set breakpoints and watch variables
debugger.set_breakpoint(:before_tool_call)
debugger.watch(:token_usage)

# Step through execution
result = runner.run("Debug this workflow")

# Export debug session
debugger.export_session("debug_session.json")
```

### Logging Configuration

```ruby
# Configure unified logging system
RAAF::Logging.configure do |config|
  config.log_level = :debug
  config.log_format = :json
  config.log_output = :rails  # or :console, :file, :auto
  config.debug_categories = [:api, :tracing, :http]
end

# Use in your classes
class MyAgent
  include RAAF::Logger
  
  def process
    log_info("Processing started", agent: "MyAgent", task_id: 123)
    log_debug_api("API call", url: "https://api.openai.com")
    log_debug_tracing("Span created", span_id: "abc123")
  end
end

# Environment configuration
ENV['RAAF_LOG_LEVEL'] = 'debug'
ENV['RAAF_LOG_FORMAT'] = 'json'
ENV['RAAF_DEBUG_CATEGORIES'] = 'api,tracing,http'
```

**Debug Categories:**
- `tracing` - Span lifecycle, trace processing
- `api` - API calls, responses, HTTP details  
- `tools` - Tool execution, function calls
- `handoff` - Agent handoffs, delegation
- `context` - Context management, memory
- `http` - HTTP debug output
- `general` - General debug messages

> 📋 **Complete Environment Variables Guide**: For a comprehensive list of all environment variables, their functions, formats, and examples, see **[ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md)**.

### Rails Integration Example

```bash
# Add to Gemfile and install
gem 'raaf'
bundle install

# Generate Rails integration
rails generate raaf:tracing:install
rails db:migrate

# Visit /tracing in your browser for web interface
```

```ruby
# config/initializers/raaf_tracing.rb
RAAF::Tracing.configure do |config|
  config.auto_configure = true  # Automatically store traces in database
  config.mount_path = '/tracing'
end

# app/jobs/application_job.rb
class ApplicationJob < ActiveJob::Base
  include RAAF::Tracing::RailsIntegrations::JobTracing
end

# Now all agent calls are automatically traced and visible at /tracing
agent = RAAF::Agent.new(name: "Assistant", model: "gpt-4o")
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Hello from Rails!")
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

### Rails Integration
- **[Rails Integration Guide](RAILS_INTEGRATION.md)** - Complete Rails integration with web UI
- **[Rails Tracing Engine](TRACING_RAILS.md)** - Database storage and analytics dashboard

### Development
- **[Contributing Guide](CONTRIBUTING.md)** - How to contribute to the project
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
- **[Changelog](CHANGELOG.md)** - Version history and updates

## 📦 Mono-repo Architecture

RAAF is organized as a mono-repo containing multiple independent gems, allowing you to use only the features you need:

### Core Gems
- **`raaf`** - Meta-gem that includes all components
- **`raaf-core`** - Essential agent runtime with OpenAI provider
- **`raaf-dsl`** - Declarative configuration DSL for elegant agent definitions
- **`raaf-providers`** - Multi-provider support (Anthropic, Cohere, Groq, Ollama, etc.)

### Tool Ecosystems
- **`raaf-tools`** - Basic tools (file search, web search)
- **`raaf-tools-advanced`** - Enterprise tools (code interpreter, document generation, computer control)

### Safety & Compliance
- **`raaf-guardrails`** - Content filtering, PII detection, security validation
- **`raaf-compliance`** - GDPR/SOC2/HIPAA compliance and audit trails

### Advanced Features
- **`raaf-memory`** - Memory management and vector search capabilities
- **`raaf-streaming`** - Real-time streaming and async processing
- **`raaf-tracing`** - Comprehensive monitoring and observability
- **`raaf-rails`** - Rails integration with web UI

### Development Tools
- **`raaf-debug`** - Interactive debugger and REPL
- **`raaf-testing`** - RSpec matchers and test utilities
- **`raaf-visualization`** - Workflow visualization and analytics

### Modular Installation

Install only what you need:

```ruby
# Minimal setup
gem 'raaf-core'

# Standard setup with tools
gem 'raaf-core'
gem 'raaf-tools'
gem 'raaf-guardrails'

# Full enterprise setup
gem 'raaf' # Includes everything
```

## 🏗️ Core Architecture

### Agents
AI systems that can use tools, make decisions, and collaborate with other agents to complete complex workflows.

### Tools
Extensive tool ecosystem extending agent capabilities:

**Search & Information**
- **File Search** - Search through codebases and documentation
- **Web Search** - Access real-time information with domain filtering
- **Vector Search** - Semantic search with hybrid capabilities

**Automation & Control**
- **Computer Control** - Automate UI interactions
- **Local Shell** - Execute system commands safely
- **Code Interpreter** - Execute code in sandboxed environment

**Document & Content**
- **Document Tool** - Generate PDFs, Word docs, Excel sheets
- **Report Tool** - Create professional reports with templates
- **Confluence Tool** - Integrate with Confluence wikis

**External Integration**
- **MCP Tool** - Connect to Model Context Protocol servers
- **Function Tool** - Wrap any Ruby method as a tool

### Memory System
- **Memory Manager** - Token-aware context management
- **Memory Stores** - In-memory, file-based, and vector storage
- **Auto-pruning** - Intelligent memory management strategies

### Multi-Agent Workflows
Specialized agents working together with intelligent handoffs based on context and capabilities.

### Guardrails System
- **PII Detection** - Automatic PII identification and redaction
- **Security Filtering** - Block sensitive patterns
- **Tripwire Rules** - Immediate termination on critical patterns
- **Parallel Execution** - High-performance guardrail processing

### Tracing & Monitoring
- **OpenAI Dashboard** - Native integration with OpenAI platform
- **Rails Web UI** - Full-featured analytics dashboard
- **AI Analysis** - Automatic trace analysis and insights
- **Anomaly Detection** - Identify unusual patterns
- **Cost Tracking** - Token usage and spend analytics

### Compliance & Audit
- **Audit Logger** - Comprehensive event tracking with integrity hashing
- **Policy Manager** - Enforce data retention and access policies
- **Compliance Monitor** - Real-time GDPR/SOC2/HIPAA compliance
- **Export Capabilities** - JSON, CSV, SIEM format exports

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
agent = RAAF::Agent.new(name: "Assistant") do |config|
  config.instructions = "You are a helpful assistant"
  config.model = "gpt-4o"
  config.add_tool(calculator_tool)
end

# Dynamic tool execution
result = agent.get_weather(city: "Tokyo")  # Direct method calls

# Comprehensive tracing
tracer = RAAF.tracer
runner = RAAF::Runner.new(agent: agent, tracer: tracer)

# Interactive debugging
debugger = RAAF::Debugging::Debugger.new
debugger.set_breakpoint(:before_tool_call)
debug_runner = RAAF::DebugRunner.new(agent: agent, debugger: debugger)

# Natural language trace queries
query = RAAF::Tracing::NaturalLanguageQuery.new(tracer)
results = query.search("Show me slow API calls from yesterday")

# Streaming with events
runner.run_streaming("Tell me a story") do |event|
  case event
  when RAAF::StreamingEvents::ResponseTextDeltaEvent
    print event.text_delta
  when RAAF::StreamingEvents::ResponseCompletedEvent
    puts "\nCompleted: #{event.response.status}"
  end
end
```

## 🧪 Testing

The gem includes a comprehensive RSpec test suite with 100% code coverage.

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/raaf/agent_spec.rb

# Run with coverage report
COVERAGE=true bundle exec rspec

# Run tests in parallel for speed
bundle exec parallel_rspec spec/
```

### Writing Tests for Your Agents

```ruby
# spec/agents/my_agent_spec.rb
require 'spec_helper'

RSpec.describe "MyAgent" do
  let(:agent) do
    RAAF::Agent.new(
      name: "TestAgent",
      instructions: "You are a test assistant.",
      model: "gpt-4o"
    )
  end
  
  let(:runner) { RAAF::Runner.new(agent: agent) }
  
  it "responds to basic queries" do
    VCR.use_cassette("agent_basic_query") do
      result = runner.run("Hello")
      expect(result.messages.last[:content]).to include("Hello")
    end
  end
  
  it "uses tools correctly" do
    agent.add_tool(method(:calculator_tool))
    
    VCR.use_cassette("agent_tool_use") do
      result = runner.run("What is 25 * 4?")
      expect(result.messages.last[:content]).to include("100")
    end
  end
  
  it "handles errors gracefully" do
    expect {
      runner.run("Trigger an error")
    }.to raise_error(RAAF::APIError)
  end
end
```

### Test Helpers

```ruby
# spec/support/agent_helpers.rb
module AgentHelpers
  def create_test_agent(name: "TestAgent", **options)
    RAAF::Agent.new(
      name: name,
      instructions: "Test agent",
      model: "gpt-4o",
      **options
    )
  end
  
  def stub_openai_response(content)
    allow_any_instance_of(RAAF::Runner)
      .to receive(:run)
      .and_return(double(messages: [{ role: "assistant", content: content }]))
  end
end

RSpec.configure do |config|
  config.include AgentHelpers
end
```

### Testing Best Practices

- Use VCR to record and replay API interactions
- Test both successful and error scenarios
- Mock external dependencies appropriately
- Test guardrails and security features
- Verify token usage and cost tracking
- Test streaming responses with proper event handling

## 🤝 Contributing

We welcome contributions from developers of all experience levels! Here's how to get involved:

### 🏷️ Find Work to Do

- **[Good First Issues](https://github.com/raaf-ai/raaf/labels/good%20first%20issue)** - Perfect for newcomers
- **[Help Wanted](https://github.com/raaf-ai/raaf/labels/help%20wanted)** - Issues where we need community help
- **[Documentation](https://github.com/raaf-ai/raaf/labels/documentation)** - Help improve our guides
- **[Bug Reports](https://github.com/raaf-ai/raaf/labels/bug)** - Fix issues and improve stability

### 🔍 Browse by Component

- **[Core](https://github.com/raaf-ai/raaf/labels/core)** - Agent execution and runners
- **[Tools](https://github.com/raaf-ai/raaf/labels/tools)** - Web search, files, and custom tools
- **[Providers](https://github.com/raaf-ai/raaf/labels/providers)** - AI provider integrations
- **[Memory](https://github.com/raaf-ai/raaf/labels/memory)** - Context persistence and vector storage
- **[Rails](https://github.com/raaf-ai/raaf/labels/rails)** - Rails integration and dashboard

### 📋 Contribution Resources

- **[Contributing Guide](CONTRIBUTING.md)** - Detailed contribution guidelines
- **[Project Boards](https://github.com/raaf-ai/raaf/projects)** - Current roadmap and priorities
- **[GitHub Discussions](https://github.com/raaf-ai/raaf/discussions)** - Ideas, questions, and collaboration

### 🚀 Quick Contribution Steps

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Make** your changes with tests
4. **Commit** with a descriptive message
5. **Push** to your branch (`git push origin feature/amazing-feature`)
6. **Open** a Pull Request

### 💡 Contribution Ideas

- **Add new tools** - Web scraping, databases, APIs
- **Improve documentation** - Examples, guides, API docs
- **Enhance testing** - Unit tests, integration tests, examples
- **Provider integrations** - New AI providers and models
- **Performance optimization** - Memory usage, speed improvements
- **Security enhancements** - Guardrails, compliance features

Every contribution makes RAAF better for the entire community!

## 🤝 Community & Support

- **GitHub Issues** - Bug reports and feature requests
- **Documentation** - Comprehensive guides and examples
- **GitHub Discussions** - Community conversations and support

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by [OpenAI's Swarm framework](https://github.com/openai/swarm) - An experimental framework for multi-agent orchestration
- Based on concepts from the [OpenAI Agents Python SDK](https://github.com/openai/openai-agents-python)
- Built with ❤️ for the Ruby community
- Thanks to all contributors and users

### Relationship to Swarm

RAAF began as a Ruby port of OpenAI's Swarm framework, maintaining the core philosophy of lightweight, composable agents while adding production-ready features. Where Swarm focuses on educational simplicity, RAAF provides the additional layers needed for enterprise deployment including compliance, monitoring, and multi-provider support.

---

**Ready to build intelligent AI workflows?** Start with our [Getting Started Guide](GETTING_STARTED.md) or explore the [Examples](EXAMPLES.md).