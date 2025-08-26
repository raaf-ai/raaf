# Ruby AI Agents Factory (RAAF)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-0.1.0-blue.svg)](https://rubygems.org/gems/ruby-ai-agents-factory)
[![Ruby](https://img.shields.io/badge/Ruby-3.0%2B-red.svg)](https://www.ruby-lang.org/)
 

A comprehensive Ruby framework for building sophisticated multi-agent AI workflows. Ruby AI Agents Factory (RAAF) is a Ruby implementation inspired by OpenAI's Swarm framework, providing 100% feature parity with the Python OpenAI Agents library, plus additional enterprise-grade capabilities.

> 🤖 **Built with AI**: This codebase was developed using AI assistance, demonstrating AI-assisted software development at scale.

## ✅ Build Status

CI:

[![Docs Link Check](https://github.com/raaf-ai/raaf/actions/workflows/docs-link-check.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/docs-link-check.yml)
[![Core CI](https://github.com/raaf-ai/raaf/actions/workflows/core-ci.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/core-ci.yml)
[![DSL CI](https://github.com/raaf-ai/raaf/actions/workflows/dsl-ci.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/dsl-ci.yml)
[![Providers CI](https://github.com/raaf-ai/raaf/actions/workflows/providers-ci.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/providers-ci.yml)
[![Guides Build & Deploy](https://github.com/raaf-ai/raaf/actions/workflows/guides-build-deploy.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/guides-build-deploy.yml)

Weekly:

[![Core Weekly](https://github.com/raaf-ai/raaf/actions/workflows/core-weekly.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/core-weekly.yml)
[![DSL Weekly](https://github.com/raaf-ai/raaf/actions/workflows/dsl-weekly.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/dsl-weekly.yml)
[![Providers Weekly](https://github.com/raaf-ai/raaf/actions/workflows/providers-weekly.yml/badge.svg)](https://github.com/raaf-ai/raaf/actions/workflows/providers-weekly.yml)

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
- **Multi-Provider Support**: Not just OpenAI, but Anthropic, Google, Cohere, and more.
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
- **🎯 Multi-Provider Support** - OpenAI, Anthropic, Gemini, Cohere, Groq, Ollama, and more
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

# Define a tool function with proper documentation
# @param city [String] The city to get weather for
# @return [String] Weather information for the city
def get_weather(city:)
  "The weather in #{city} is sunny with 22°C"
end

# Create an agent with comprehensive configuration
agent = RAAF::Agent.new(
  name: "WeatherAssistant",
  instructions: "You are a helpful weather assistant. Use tools when needed.",
  model: "gpt-4o"  # Uses ResponsesProvider by default for Python SDK compatibility
)

# Add tools to extend agent capabilities
agent.add_tool(method(:get_weather))

# Create runner (automatically uses ResponsesProvider with built-in retry)
runner = RAAF::Runner.new(agent: agent)

# Run conversation and get result
result = runner.run("What's the weather in Paris?")

# Access the assistant's response
puts result.messages.last[:content]
# => "I'll check the weather in Paris for you..."
```

### Structured Output Example

```ruby
# Universal structured output across ALL providers with smart field mapping
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

### Advanced Schema Validation with Smart Key Mapping

RAAF agents include powerful schema validation with automatic key normalization:

```ruby
# Create a DSL agent with flexible schema validation
class CompanyExtractor < RAAF::DSL::Agent
  agent_name "CompanyExtractor"
  model "gpt-4o"
  
  # Define schema with snake_case fields
  schema do
    field :company_name, type: :string, required: true
    field :market_sector, type: :string, required: true
    field :employee_count, type: :integer
    field :annual_revenue, type: :number
    
    # Configure validation mode for flexible field mapping
    validate_mode :tolerant  # :strict, :tolerant, or :partial
  end
  
  instructions "Extract company information from the text"
end

# LLM can use natural language field names that get automatically mapped
agent = CompanyExtractor.new
result = agent.run(<<~TEXT
  ACME Corporation is a technology company in the software sector.
  They have around 500 employees and $50M annual revenue.
TEXT)

# Even if LLM returns fields like "Company Name", "Market Sector", "Employee Count"
# They get automatically normalized to :company_name, :market_sector, :employee_count
puts result[:company_name]    # "ACME Corporation"
puts result[:market_sector]   # "software"
puts result[:employee_count]  # 500
```

**Key Features:**

- **Smart Key Normalization**: `"Company Name"` → `:company_name`, `"API-Key"` → `:api_key`
- **Three Validation Modes**:
  - `:strict` - All fields must match exactly (default)
  - `:tolerant` - Required fields strict, others flexible (recommended)
  - `:partial` - Use whatever validates, ignore invalid fields
- **JSON Repair**: Handles malformed JSON, markdown-wrapped responses, trailing commas
- **Nested Schema Support**: Works with complex nested objects and arrays
- **Comprehensive Metrics**: Track parsing success rates and common failures

### JSON Handling and Repair

RAAF agents automatically handle malformed JSON responses from LLMs:

```ruby
# The JsonRepair module handles common LLM output issues automatically
class DataProcessor < RAAF::DSL::Agent
  agent_name "DataProcessor"
  model "gpt-4o"
  
  schema do
    field :processed_data, type: :object
    field :summary, type: :string
    validate_mode :tolerant
  end
end

# These malformed responses are automatically repaired:

# 1. JSON with trailing commas
# LLM Output: '{"name": "John", "age": 25,}'
# Auto-repaired to: {"name": "John", "age": 25}

# 2. JSON wrapped in markdown
# LLM Output: '```json\n{"valid": true}\n```'  
# Auto-extracted: {"valid": true}

# 3. Mixed content with JSON
# LLM Output: 'Here is the data: {"name": "Alice"} as requested.'
# Auto-extracted: {"name": "Alice"}

# 4. Single quotes instead of double quotes  
# LLM Output: "{'name': 'Bob', 'active': true}"
# Auto-repaired to: {"name": "Bob", "active": true}

agent = DataProcessor.new
result = agent.run("Process this data and return as JSON")

# All repairs happen automatically - you always get clean, parsed data
puts result[:processed_data]  # Hash with symbolized keys
```

## Core vs DSL Agents: JSON Handling

**Great News**: JSON repair and schema validation features are now available in **both Core and DSL agents**!

### Core Agents (RAAF::Agent)
- **Configurable JSON parsing**: Enable fault-tolerant parsing with `json_repair: true`
- **Smart key normalization**: Enable with `normalize_keys: true`
- **Multiple validation modes**: Choose `:strict`, `:tolerant`, or `:partial`
- **Backward compatible**: Default behavior remains strict for existing code

```ruby
# Core agent with JSON repair and key normalization
agent = RAAF::Agent.new(
  name: "DataExtractor", 
  instructions: "Extract company data",
  model: "gpt-4o",
  json_repair: true,      # Enable fault-tolerant JSON parsing
  normalize_keys: true,   # Enable automatic key normalization
  validation_mode: :tolerant,  # Allow flexible validation
  response_format: { 
    type: "json_schema",
    json_schema: {
      properties: {
        company_name: { type: "string" },
        employee_count: { type: "integer" }
      }
    }
  }
)
```

### DSL Agents (RAAF::DSL::Agent)
- **Automatic JSON repair**: Enabled by default in DSL context
- **Built-in key normalization**: Seamlessly maps natural language field names
- **Schema DSL**: Declarative schema definition with validation modes
- **Best for**: Rapid development and complex data extraction workflows

```ruby
# DSL agent - enhanced with declarative syntax
class FlexibleExtractor < RAAF::DSL::Agent
  schema do
    field :company_name, type: :string, required: true
    field :employee_count, type: :integer
    validate_mode :tolerant  # Built into schema DSL
  end
end
```

**Choose Core agents** for maximum control and configuration flexibility.  
**Choose DSL agents** for rapid development with declarative schemas.

### Multi-Agent Example

```ruby
# Create specialized agents with clear roles and handoff logic
support_agent = RAAF::Agent.new(
  name: "CustomerSupport",
  instructions: "Handle general customer inquiries. Transfer technical issues to TechnicalSupport.",
  model: "gpt-4o"
)

tech_agent = RAAF::Agent.new(
  name: "TechnicalSupport", 
  instructions: "Handle technical troubleshooting and API integration issues.",
  model: "gpt-4o"
)

# Configure agent handoffs (creates transfer_to_TechnicalSupport tool automatically)
support_agent.add_handoff(tech_agent)

# Create runner with the initial agent
runner = RAAF::Runner.new(agent: support_agent)

# The agent will automatically handoff when detecting technical issues
result = runner.run("My API integration is failing with 500 errors")

# Check which agent handled the final response
puts "Final agent: #{result.last_agent.name}"
puts "Response: #{result.messages.last[:content]}"
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

### Pipeline DSL Example

Transform complex multi-step workflows from 66+ lines to just 3 lines:

```ruby
# Define agents using RAAF DSL
class DataAnalyzer < RAAF::DSL::Agent
  instructions "Analyze the provided data and extract key insights"
  model "gpt-4o"
  
  result_transform do
    field :insights
    field :summary
  end
end

class ReportGenerator < RAAF::DSL::Agent
  instructions "Generate a professional report from the analysis"
  model "gpt-4o"
  
  result_transform do
    field :report
  end
end

# Create elegant pipeline - just 3 lines!
class DataProcessingPipeline < RAAF::Pipeline
  flow DataAnalyzer >> ReportGenerator
end

# Run the pipeline
pipeline = DataProcessingPipeline.new(
  raw_data: "Sales data: Q1: $100k, Q2: $150k, Q3: $120k, Q4: $180k"
)
result = pipeline.run
puts result[:report]
```

**Parallel Processing:**
```ruby
# Execute multiple agents simultaneously
class ParallelAnalysisPipeline < RAAF::Pipeline
  flow DataInput >> 
       (SentimentAnalyzer | KeywordExtractor | EntityRecognizer) >> 
       ResultMerger
end
```

**Advanced Features:**
- **Automatic Field Mapping** - Context flows intelligently between agents
- **Error Handling** - Built-in retry and fallback mechanisms  
- **Performance Optimization** - Parallel execution where possible
- **Testing Support** - Comprehensive RSpec integration
- **Field Validation** - Compile-time compatibility checking

👉 **[Complete Pipeline DSL Guide](docs/PIPELINE_DSL_GUIDE.md)** - Comprehensive documentation with patterns, troubleshooting, and best practices

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
RAAF.logger.configure do |config|
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
- dsl/README.md — DSL quick start and core concepts
- examples/ — Example workflows and tool usage
- docs/PIPELINE_DSL_GUIDE.md — End-to-end Pipeline DSL guide

### API References
- dsl/API_REFERENCE.md — DSL classes, agents, pipeline APIs
- docs/TOOL_API_REFERENCE.md — Tool DSL and unified tool API
- tracing/API_REFERENCE.md — Tracing APIs and integrations
- memory/API_REFERENCE.md — Memory and vector store APIs
- guardrails/API_REFERENCE.md — Guardrails and safety APIs
- tools/API_REFERENCE.md — Toolkits and adapters
- analytics/API_REFERENCE.md — Analytics and usage tracking APIs

### Production
- SECURITY.md — Security practices and guidelines
- rails/ — Rails engine and integration (see gem README)

If you can’t find a doc at the root, look for it under the relevant gem folder (e.g., dsl/, tracing/, memory/) or in docs/.

### Development
- **[Contributing Guide](CONTRIBUTING.md)** - How to contribute to the project
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
- **[Changelog](CHANGELOG.md)** - Version history and updates

## 📦 Mono-repo Architecture

RAAF is organized as a mono-repo containing multiple independent gems, allowing you to use only the features you need:

### Core Gems
- raaf — Meta-gem that includes all components
- raaf-core — Essential agent runtime (see core/README.md)
- raaf-dsl — Declarative DSL for agents/pipelines (see dsl/README.md)
- raaf-providers — Multi-provider support (see providers/)

### Tool Ecosystems
- raaf-tools — Basic tools (see tools/)
- raaf-tools-advanced — Enterprise tools (see tools/)

### Safety & Compliance
- raaf-guardrails — Content filtering, PII detection (see guardrails/)
- raaf-compliance — Compliance and audit (see compliance/)

### Advanced Features
- raaf-memory — Memory/vector search (see memory/)
- raaf-streaming — Streaming and async (see core/ and tracing/)
- raaf-tracing — Monitoring/observability (see tracing/)
- raaf-rails — Rails integration and UI (see rails/)

### Development Tools
- raaf-debug — Debugger and REPL (see debug/)
- raaf-testing — RSpec matchers/test utils (see testing/)
- raaf-visualization — Workflow visualization (see analytics/)

### Quick Map
- Core runtime: core/
- DSL and pipelines: dsl/
- Providers: providers/
- Tools: tools/
- Guardrails: guardrails/
- Memory: memory/
- Tracing: tracing/
- Rails engine: rails/
- Testing helpers: testing/

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

The project includes a comprehensive RSpec test suite. Coverage is tracked in CI; see workflow summaries for current figures.

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

## ⚙️ Supported Ruby Versions

RAAF targets modern Ruby versions tested in CI. Current baseline: Ruby 3.2 and 3.3. Other versions may work but are not part of the official test matrix.

## ⚡ Concurrency Notes

Parallel pipeline steps and iterators use Ruby threads. For IO‑bound workloads this improves throughput. For very large data sets, consider adding concurrency limits or batching to avoid creating excessive threads. See docs/PIPELINE_DSL_GUIDE.md for patterns.

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

**Ready to build intelligent AI workflows?** Start with the DSL guide in dsl/README.md, dive deeper with docs/PIPELINE_DSL_GUIDE.md, or explore examples in examples/.
