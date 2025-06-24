# OpenAI Agents Ruby

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
<!-- [![Gem Version](https://badge.fury.io/rb/openai_agents.svg)](https://badge.fury.io/rb/openai_agents) -->
<!-- [![Documentation](https://img.shields.io/badge/docs-available-brightgreen.svg)](https://rubydoc.info/gems/openai_agents) -->

A comprehensive Ruby implementation of OpenAI Agents for building sophisticated multi-agent AI workflows. This gem provides a production-ready framework for creating, managing, and monitoring AI agents with advanced capabilities including tool integration, intelligent handoffs, voice interactions, and enterprise-grade safety features.

> 🤖 **Built with AI**: This codebase was generated and developed using AI assistance, demonstrating AI-assisted software development at scale.

## 🌟 Features

### Core Framework
- **🤖 Multi-Agent Workflows** - Specialized agents with intelligent routing
- **🔧 Advanced Tool Integration** - File search, web search, computer automation, code interpreter
- **↔️ Smart Agent Handoffs** - Context-aware routing with capability matching
- **📡 Real-time Streaming** - Live response streaming with event handling
- **📊 Comprehensive Tracing** - Span-based monitoring and visualization
- **🎯 Provider Agnostic** - Support for OpenAI, Anthropic, Gemini, Cohere, Groq, Ollama, Together AI, and 100+ LLMs
- **🔌 MCP Support** - Model Context Protocol integration for tools and resources

### Advanced Capabilities
- **🎤 Voice Workflows** - Complete speech-to-text and text-to-speech pipeline
- **🛡️ Enterprise Guardrails** - Safety, validation, compliance, and tripwire systems
- **📋 Structured Outputs** - Schema validation and formatted responses
- **🔌 Extensions Framework** - Plugin architecture for custom functionality
- **📈 Usage Analytics** - Resource monitoring and cost tracking
- **⚙️ Configuration Management** - Environment-based configuration system
- **🔄 Tool Context Management** - State persistence and execution tracking
- **🔁 Retry Logic** - Automatic retry with exponential backoff
- **🖥️ Code Execution** - Safe sandboxed Python/Ruby code interpreter
- **🔧 Shell Commands** - Controlled local shell tool with safety features

### Developer Experience
- **💻 Interactive REPL** - Real-time agent development and testing
- **🐛 Advanced Debugging** - Breakpoints, step mode, and performance profiling
- **📊 Visualization Tools** - Workflow diagrams and trace visualization
- **🎯 Comprehensive Documentation** - Detailed examples and API reference
- **🧪 Production Ready** - Enterprise-grade architecture and monitoring

## 🚀 Quick Start

### Installation

Add this line to your application's Gemfile:

```ruby
gem 'openai_agents'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install openai_agents
```

### Environment Setup

```bash
# Set up API keys
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-anthropic-key"
export GEMINI_API_KEY="your-gemini-key"
```

### Basic Agent

```ruby
require 'openai_agents'

# Define a tool
def get_weather(city)
  "The weather in #{city} is sunny with 22°C"
end

# Create an agent (now uses ResponsesProvider by default, matching Python)
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant that can get weather information.",
  model: "gpt-4o"  # Recommended model for Responses API
)

# Add tools
agent.add_tool(method(:get_weather))

# Create and run (automatically uses ResponsesProvider matching Python)
runner = OpenAIAgents::Runner.new(agent: agent)
result = runner.run("What's the weather in Paris?")

puts result.messages.last[:content]
```

### Python-Compatible Tracing

```ruby
require 'openai_agents'

# Enable tracing that matches Python structure exactly
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o"
)

runner = OpenAIAgents::Runner.new(agent: agent)
result = runner.run("Hello, world!")

# Generates identical traces to Python:
# - Agent span as root (parent_id: null)
# - Response span as child of agent span
# - Uses POST /v1/responses endpoint
# - Identical field structure and types
```

## 🏗️ Core Concepts

Understanding these fundamental concepts will help you build powerful AI-driven applications that solve real-world business challenges.

### AI Agents

**What they are**: AI Agents are specialized AI systems designed to perform specific tasks autonomously. Unlike simple chatbots, agents can use tools, make decisions, access external data, and collaborate with other agents to complete complex workflows.

**Problems they solve**:
- **Task Automation**: Replace repetitive manual processes with intelligent automation
- **24/7 Availability**: Provide consistent service without human intervention
- **Scalability**: Handle multiple concurrent conversations without performance degradation
- **Expertise Distribution**: Make specialized knowledge available across your organization
- **Consistency**: Ensure uniform responses and adherence to business policies

**Key capabilities**:
- Execute functions and access external APIs
- Maintain conversation context and memory
- Make decisions based on conversation flow
- Hand off to other specialized agents when needed

Learn more about [AI Agents](https://platform.openai.com/docs/assistants/overview) in the OpenAI documentation.

### Function Calling & Tool Integration

**What it is**: Function calling allows agents to execute specific functions based on the conversation context. This bridges the gap between AI reasoning and real-world actions.

**Problems it solves**:
- **Data Access**: Retrieve real-time information from databases, APIs, and files
- **Action Execution**: Perform operations like sending emails, updating records, or processing payments
- **Integration**: Connect AI agents with existing business systems and workflows
- **Dynamic Responses**: Provide up-to-date, contextual information rather than static responses

**Common use cases**:
- Customer service agents accessing order systems
- Research assistants searching through documentation
- Technical support agents running diagnostic tools
- Sales agents checking inventory and pricing

See the [Function Calling Guide](https://platform.openai.com/docs/guides/function-calling) for more details.

### Multi-Agent Workflows

**What they are**: Multi-agent workflows involve multiple specialized AI agents working together, each with distinct capabilities and expertise. Agents can intelligently route conversations to the most appropriate specialist based on context, user needs, and conversation history.

**Problems they solve**:
- **Expertise Silos**: Break down knowledge barriers by connecting specialists
- **Complex Problem Solving**: Handle multi-step processes that require different skills
- **Load Distribution**: Distribute workload across specialized agents for better performance
- **Escalation Management**: Automatically route complex issues to appropriate experts
- **Quality Assurance**: Ensure the right specialist handles each type of inquiry

**Real-world applications**:
- Customer service: General support → Technical support → Billing specialist
- Healthcare: Triage → Specialist consultation → Treatment planning
- Sales: Lead qualification → Product specialist → Closing agent
- IT Support: Initial diagnosis → System specialist → Security expert

Create specialized agents that can hand off to each other based on context and capabilities:

```ruby
# Create specialized agents
support_agent = OpenAIAgents::Agent.new(
  name: "CustomerSupport",
  instructions: "Handle general customer inquiries. Escalate technical issues to TechnicalSupport.",
  model: "gpt-4"
)

tech_agent = OpenAIAgents::Agent.new(
  name: "TechnicalSupport", 
  instructions: "Handle complex technical issues and troubleshooting.",
  model: "gpt-4"
)

# Set up intelligent handoffs
handoff_manager = OpenAIAgents::Handoffs::AdvancedHandoff.new

handoff_manager.add_agent(support_agent, capabilities: [:general_support, :billing])
handoff_manager.add_agent(tech_agent, capabilities: [:technical_support, :debugging])

# Execute context-aware handoff
result = handoff_manager.execute_handoff(
  from_agent: support_agent,
  context: { topic: "technical_issue", user_sentiment: "frustrated" },
  reason: "Customer needs technical assistance"
)
```

### Advanced Tool Integration

**What it is**: Advanced tool integration provides agents with sophisticated capabilities beyond simple text processing. These tools enable agents to interact with files, search the web, control computers, and integrate with external systems.

**Problems they solve**:
- **Information Access**: Search through large codebases, documentation, and files instantly
- **Real-time Data**: Access current information from the web and APIs
- **System Integration**: Interact with existing software and automate computer tasks
- **Workflow Automation**: Complete complex multi-step processes automatically
- **Knowledge Discovery**: Find relevant information across diverse data sources

**Available tools**:
- **File Search**: Search through codebases, documentation, and file systems
- **Web Search**: Access real-time information from the internet
- **Computer Control**: Automate UI interactions, take screenshots, control applications
- **API Integration**: Connect with databases, CRMs, and external services

Extend agent capabilities with powerful built-in tools. Function calling enables agents to use tools effectively. See the [Tools documentation](https://platform.openai.com/docs/assistants/tools) for more information.

```ruby
# File search across your codebase
file_search = OpenAIAgents::Tools::FileSearchTool.new(
  search_paths: ["./src", "./docs"],
  file_extensions: [".rb", ".md", ".txt"],
  max_results: 10
)

# Web search for real-time information
web_search = OpenAIAgents::Tools::WebSearchTool.new(
  search_engine: "duckduckgo",
  max_results: 5
)

# Computer automation (screenshots, mouse, keyboard)
computer_tool = OpenAIAgents::Tools::ComputerTool.new(
  allowed_actions: [:screenshot, :click, :type]
)

# Add tools to your agent
agent.add_tool(file_search)
agent.add_tool(web_search)
agent.add_tool(computer_tool)
```

### Voice Workflows

**What they are**: Voice workflows enable agents to process spoken input and respond with synthesized speech, creating natural voice-based interactions. This includes speech-to-text transcription, agent processing, and text-to-speech synthesis.

**Problems they solve**:
- **Accessibility**: Make AI agents accessible to users who prefer voice interaction
- **Hands-free Operation**: Enable use in situations where typing is impractical
- **Natural Interaction**: Provide more intuitive, conversational experiences
- **Mobile Integration**: Better suited for mobile and IoT devices
- **Multilingual Support**: Support global audiences with voice in multiple languages

**Use cases**:
- Voice assistants for customer service
- Hands-free technical support
- Voice-controlled automation systems
- Accessibility tools for visually impaired users
- Drive-through or kiosk applications

Complete speech-to-text and text-to-speech pipeline using OpenAI's [Speech to Text](https://platform.openai.com/docs/guides/speech-to-text) and [Text to Speech](https://platform.openai.com/docs/guides/text-to-speech) APIs:

```ruby
# Create voice workflow
voice = OpenAIAgents::Voice::VoiceWorkflow.new(
  transcription_model: "whisper-1",
  tts_model: "tts-1-hd",
  voice: "nova"
)

# Process audio file through agent
result = voice.process_audio_file("user_input.wav", agent)
puts "User said: #{result.transcription}"
puts "Agent replied: #{result.text_response}"

# Play synthesized response
voice.play_audio(result.audio_file)

# Real-time voice session
voice.start_streaming_session(agent) do |session|
  session.on_transcription { |text| puts "User: #{text}" }
  session.on_response { |text| puts "Agent: #{text}" }
  session.on_audio { |audio_file| voice.play_audio(audio_file) }
end
```

### Streaming

**What it is**: Real-time streaming delivers agent responses as they're generated, rather than waiting for complete responses. This provides immediate feedback and improved user experience during longer processing tasks.

**Problems it solves**:
- **Perceived Performance**: Users see immediate progress instead of waiting
- **User Engagement**: Maintain user attention during longer responses
- **Timeout Prevention**: Avoid connection timeouts for complex queries
- **Progressive Information**: Deliver information as it becomes available
- **Resource Efficiency**: Better memory management for long responses

**Benefits**:
- Faster perceived response times
- Better user experience for complex queries
- Real-time feedback during tool execution
- Improved scalability for concurrent users

Stream responses in real-time for better user experience:

```ruby
# Create streaming runner
streaming_runner = OpenAIAgents::StreamingRunner.new(agent: agent)

# Stream responses
streaming_runner.run_streaming(messages) do |chunk|
  case chunk[:type]
  when "content"
    print chunk[:content]
  when "tool_call"
    puts "\nCalling tool: #{chunk[:tool_call]}"
  end
end
```

## 🛡️ Enterprise Features

Enterprise features address the critical requirements for deploying AI agents in production environments, including safety, compliance, monitoring, and governance.

### Guardrails and Safety

**What they are**: Guardrails are safety and validation systems that ensure AI agents operate within defined boundaries, protecting both users and systems from harmful or inappropriate content and behaviors.

**Critical problems they solve**:
- **Security Risks**: Prevent injection attacks, data leaks, and unauthorized access
- **Content Safety**: Block harmful, inappropriate, or offensive content
- **Compliance Requirements**: Meet regulatory standards (GDPR, HIPAA, SOX, etc.)
- **Resource Protection**: Prevent abuse and excessive resource consumption
- **Quality Assurance**: Ensure consistent, accurate responses
- **Legal Liability**: Reduce risk of legal issues from AI behavior

**Enterprise benefits**:
- **Risk Mitigation**: Protect your organization from AI-related risks
- **Regulatory Compliance**: Meet industry standards and regulations
- **Brand Protection**: Maintain consistent brand voice and values
- **Cost Control**: Prevent unexpected usage spikes and costs
- **Audit Trail**: Complete logging for compliance and debugging

**Types of guardrails**:
- Content safety filters for harmful material
- Rate limiting to prevent abuse
- Input/output validation and sanitization
- Schema validation for structured data
- Custom business rule enforcement

Implement comprehensive safety and validation systems:

```ruby
# Create guardrail manager
guardrails = OpenAIAgents::Guardrails::GuardrailManager.new

# Content safety (blocks harmful content)
guardrails.add_guardrail(
  OpenAIAgents::Guardrails::ContentSafetyGuardrail.new
)

# Rate limiting (prevent abuse)
guardrails.add_guardrail(
  OpenAIAgents::Guardrails::RateLimitGuardrail.new(
    max_requests_per_minute: 60
  )
)

# Input/output length validation
guardrails.add_guardrail(
  OpenAIAgents::Guardrails::LengthGuardrail.new(
    max_input_length: 10000,
    max_output_length: 5000
  )
)

# Schema validation for structured data
user_schema = {
  type: "object",
  properties: {
    query: { type: "string", maxLength: 1000 }
  },
  required: ["query"]
}

guardrails.add_guardrail(
  OpenAIAgents::Guardrails::SchemaGuardrail.new(input_schema: user_schema)
)

# Validate input before processing
begin
  guardrails.validate_input(user_input)
  # Process with agent...
rescue OpenAIAgents::Guardrails::GuardrailError => e
  puts "Input blocked: #{e.message}"
end
```

### Usage Tracking and Analytics

**What it is**: Comprehensive monitoring and analytics system that tracks AI agent usage, costs, performance metrics, and user interactions to provide business insights and operational control.

**Critical business problems it solves**:
- **Cost Management**: Track and control AI API costs and resource usage
- **Performance Optimization**: Identify bottlenecks and optimization opportunities
- **Business Intelligence**: Understand user behavior and agent effectiveness
- **Capacity Planning**: Predict resource needs and scale appropriately
- **ROI Measurement**: Demonstrate value and return on AI investment

**Key metrics tracked**:
- **Financial**: API costs, token usage, cost per interaction
- **Performance**: Response times, error rates, throughput
- **Quality**: User satisfaction, resolution rates, handoff frequency
- **Usage**: Active users, conversation volume, feature adoption
- **Business**: Conversion rates, customer lifetime value impact

**Enterprise value**:
- **Budget Control**: Prevent cost overruns with real-time alerts
- **Operational Insights**: Data-driven decisions for agent optimization
- **Compliance Reporting**: Generate reports for audits and stakeholders
- **Trend Analysis**: Identify patterns and predict future needs
- **Performance SLAs**: Monitor and maintain service level agreements

Monitor resource usage, costs, and performance with comprehensive analytics:

```ruby
# Create usage tracker
tracker = OpenAIAgents::UsageTracking::UsageTracker.new

# Set up alerts
tracker.add_alert(:high_cost) do |usage|
  usage[:total_cost_today] > 100.0
end

tracker.add_alert(:token_limit) do |usage|
  usage[:tokens_today] > 1_000_000
end

# Track API usage automatically
tracker.track_api_call(
  provider: "openai",
  model: "gpt-4",
  tokens_used: { prompt_tokens: 150, completion_tokens: 75, total_tokens: 225 },
  cost: 0.0135,
  duration: 2.3
)

# Track agent interactions
tracker.track_agent_interaction(
  agent_name: "CustomerSupport",
  user_id: "user123",
  session_id: "session456",
  duration: 120.5,
  satisfaction_score: 4.2,
  outcome: :resolved
)

# Get comprehensive analytics
analytics = tracker.analytics(:today)
puts "API calls: #{analytics[:api_calls][:count]}"
puts "Total cost: $#{analytics[:costs][:total]}"
puts "Avg satisfaction: #{analytics[:agent_interactions][:average_satisfaction]}"

# Generate reports
report = tracker.generate_report(:month, include_charts: true)
report.save_to_file("monthly_report.html")
```

### Configuration Management

**What it is**: Centralized configuration system that manages settings across different environments (development, staging, production) with validation, change tracking, and hot-reloading capabilities.

**Enterprise problems it solves**:
- **Environment Consistency**: Ensure consistent behavior across dev, staging, and production
- **Change Management**: Track and audit configuration changes
- **Security**: Secure handling of API keys and sensitive configuration
- **Operational Efficiency**: Reduce deployment errors and configuration drift
- **Compliance**: Maintain audit trails for configuration changes

**Key capabilities**:
- Environment-specific configurations
- Real-time configuration validation
- Hot-reloading without service restart
- Configuration versioning and rollback
- Secure secret management

Environment-based configuration with validation:

```ruby
# Load configuration
config = OpenAIAgents::Configuration.new(environment: "production")

# Access nested configuration
puts config.openai.api_key
puts config.agent.max_turns
puts config.logging.level

# Set values programmatically
config.set("agent.default_model", "gpt-4")
config.set("guardrails.rate_limiting.max_requests_per_minute", 120)

# Watch for changes
config.watch do |updated_config|
  puts "Configuration updated!"
end

# Validate configuration
errors = config.validate
if errors.any?
  puts "Configuration issues: #{errors.join(', ')}"
end

# Export configuration
config.save_to_file("config/production.yml", format: :yaml)
```

## 🔧 Advanced Features

Advanced features provide sophisticated capabilities for complex use cases, including structured data handling, extensibility, debugging, and multi-provider support.

### Structured Outputs

**What they are**: Structured outputs ensure AI agent responses conform to predefined schemas and formats, enabling reliable integration with downstream systems and databases.

**Technical problems they solve**:
- **Data Consistency**: Ensure predictable response formats for system integration
- **API Integration**: Reliable data structures for connecting with other services
- **Validation**: Catch and handle malformed responses before they cause errors
- **Type Safety**: Provide strong typing for AI responses in typed languages
- **Database Integration**: Direct insertion into databases with schema validation

**Business benefits**:
- **System Reliability**: Reduce integration failures and data corruption
- **Development Speed**: Faster integration with predictable data formats
- **Quality Assurance**: Automated validation of AI responses
- **Error Reduction**: Catch data issues before they reach production systems

**Common use cases**:
- CRM data entry and updates
- Form processing and validation
- API response formatting
- Database record creation
- Structured reporting and analytics

Define and validate response schemas using [Structured Outputs](https://platform.openai.com/docs/guides/structured-outputs):

```ruby
# Create response schema
response_schema = OpenAIAgents::StructuredOutput::ObjectSchema.build do
  string :response_type, required: true, enum: ["answer", "question", "action"]
  string :content, required: true, min_length: 1, max_length: 1000
  number :confidence, required: true, minimum: 0.0, maximum: 1.0
  array :suggestions, items: { type: "string" }
  boolean :requires_followup, required: true
end

# Validate response
begin
  validated = response_schema.validate(agent_response)
  puts "Response type: #{validated[:response_type]}"
  puts "Confidence: #{(validated[:confidence] * 100).round(1)}%"
rescue OpenAIAgents::StructuredOutput::ValidationError => e
  puts "Invalid response format: #{e.message}"
end
```

### Extensions Framework

**What it is**: A plugin architecture that allows developers to extend the framework with custom tools, processors, and functionality without modifying the core codebase.

**Development problems it solves**:
- **Extensibility**: Add custom functionality without forking the framework
- **Modularity**: Keep custom code separate and maintainable
- **Reusability**: Share extensions across projects and teams
- **Version Management**: Manage dependencies and compatibility
- **Integration**: Seamlessly integrate third-party tools and services

**Extension types**:
- **Tools**: Custom agent capabilities (APIs, databases, services)
- **Processors**: Custom data processing and transformation
- **Authenticators**: Custom authentication mechanisms
- **Validators**: Custom validation and safety checks
- **Visualizers**: Custom reporting and visualization tools

**Benefits for teams**:
- **Faster Development**: Reuse existing extensions
- **Code Organization**: Keep custom logic modular
- **Team Collaboration**: Share extensions across projects
- **Maintenance**: Independent updates and versioning

Create and load custom extensions:

```ruby
# Define custom extension
class CustomToolExtension < OpenAIAgents::Extensions::BaseExtension
  def self.extension_info
    {
      name: :custom_tool,
      type: :tool,
      version: "1.0.0",
      dependencies: []
    }
  end
  
  def setup(config)
    # Extension setup logic
  end
  
  def activate
    # Extension activation logic
  end
end

# Load and activate extension
OpenAIAgents::Extensions.load_extension(CustomToolExtension)
OpenAIAgents::Extensions.activate(:custom_tool, config)

# Register inline extensions
OpenAIAgents::Extensions.register(:weather_tool) do |ext|
  ext.name = "Weather Tool"
  ext.type = :tool
  ext.setup { |config| puts "Weather tool configured" }
end
```

### Enhanced Tracing and Debugging

**What they are**: Advanced monitoring and debugging tools that provide detailed insights into agent behavior, performance, and decision-making processes through distributed tracing and debugging capabilities.

**Development problems they solve**:
- **Debugging Complexity**: Understand multi-agent interactions and decision flows
- **Performance Issues**: Identify bottlenecks and optimization opportunities
- **Error Diagnosis**: Quickly locate and understand failures in complex workflows
- **Behavior Analysis**: Understand why agents make specific decisions
- **Production Monitoring**: Real-time visibility into agent performance

**Key debugging features**:
- **Distributed Tracing**: Track requests across multiple agents and systems
- **Span Visualization**: See hierarchical execution flows
- **Performance Profiling**: Identify slow operations and bottlenecks
- **Error Tracking**: Capture and analyze exceptions and failures
- **Decision Logging**: Record agent reasoning and tool selections

**Production benefits**:
- **Faster Troubleshooting**: Quickly identify and resolve issues
- **Performance Optimization**: Data-driven performance improvements
- **Quality Assurance**: Monitor agent behavior in production
- **Capacity Planning**: Understand resource usage patterns

Comprehensive monitoring and debugging capabilities:

```ruby
# Create enhanced tracer
tracer = OpenAIAgents::Tracing::SpanTracer.new
tracer.add_processor(OpenAIAgents::Tracing::ConsoleSpanProcessor.new)
tracer.add_processor(OpenAIAgents::Tracing::FileSpanProcessor.new("trace.log"))

# Create nested spans
tracer.agent_span("CustomerSupport") do |span|
  span.set_attribute("user.id", "user123")
  
  tracer.tool_span("web_search") do |tool_span|
    tool_span.set_attribute("query", "customer billing")
    # Tool execution...
  end
  
  tracer.llm_span("gpt-4") do |llm_span|
    llm_span.set_attribute("tokens", 245)
    # LLM call...
  end
end

# Advanced debugging
debugger = OpenAIAgents::Debugging::Debugger.new
debugger.set_breakpoint("agent_run_start")
debugger.enable_step_mode

# Debug-enabled runner
debug_runner = OpenAIAgents::Debugging::DebugRunner.new(
  agent: agent,
  debugger: debugger
)
```

### Visualization

Generate workflow diagrams and trace visualizations:

```ruby
# Workflow visualization
workflow_viz = OpenAIAgents::Visualization::WorkflowVisualizer.new([
  support_agent, tech_agent, billing_agent
])

# ASCII diagram for terminal
puts workflow_viz.render_ascii

# Mermaid diagram for web
mermaid_code = workflow_viz.generate_mermaid

# Trace visualization
trace_viz = OpenAIAgents::Visualization::TraceVisualizer.new(spans)
puts trace_viz.render_timeline

# HTML report
html_report = OpenAIAgents::Visualization::HTMLVisualizer.generate(
  spans, trace_summary
)
File.write("trace_report.html", html_report)
```

## 🎯 Interactive Development

### REPL Interface

Interactive development and testing environment:

```ruby
# Start REPL with agent
repl = OpenAIAgents::REPL.new(agent: agent, tracer: tracer)
repl.start

# Available REPL commands:
# /help          - Show help
# /agents        - List agents  
# /current       - Show current agent
# /switch <name> - Switch agent
# /tools         - List tools
# /trace         - Show trace summary
# /debug         - Toggle debug mode
# /export        - Export conversation
```

## 🌐 Multi-Provider Support

Use different LLM providers seamlessly. See the [Models documentation](https://platform.openai.com/docs/models) for available models:

```ruby
# OpenAI
openai_agent = OpenAIAgents::Agent.new(
  name: "OpenAI_Assistant",
  model: "gpt-4",
  instructions: "You use OpenAI's GPT-4"
)

# Anthropic Claude
claude_agent = OpenAIAgents::Agent.new(
  name: "Claude_Assistant",
  model: "claude-3-sonnet-20240229", 
  instructions: "You use Anthropic's Claude"
)

# Google Gemini
gemini_agent = OpenAIAgents::Agent.new(
  name: "Gemini_Assistant",
  model: "gemini-1.5-pro",
  instructions: "You use Google's Gemini"
)

# Automatic provider selection
provider = OpenAIAgents::Models::MultiProvider.auto_provider(model: "gpt-4")
```

## 📚 Complete API Reference

### Agent Class

```ruby
# Create agent
agent = OpenAIAgents::Agent.new(
  name: "AgentName",              # Required: Unique agent identifier
  instructions: "Instructions",   # Optional: System prompt/behavior
  model: "gpt-4",                # Optional: LLM model (default: "gpt-4")
  max_turns: 10,                 # Optional: Max conversation turns
  tools: [],                     # Optional: Pre-configured tools
  handoffs: []                   # Optional: Pre-configured handoff agents
)

# Methods
agent.add_tool(tool)                    # Add tool (Method, Proc, or FunctionTool)
agent.add_handoff(other_agent)          # Add handoff target
agent.can_handoff_to?(agent_name)       # Check handoff availability
agent.find_handoff(agent_name)          # Get handoff target by name
agent.has_tools?                        # Check if agent has tools
agent.execute_tool(name, **args)        # Execute tool directly
agent.to_h                             # Convert to hash
```

### Runner Class

```ruby
# Create runner
runner = OpenAIAgents::Runner.new(
  agent: agent,        # Required: Primary agent
  tracer: tracer       # Optional: Tracer for monitoring
)

# Methods
result = runner.run(messages, stream: false)      # Synchronous execution
future = runner.run_async(messages)               # Asynchronous execution
```

### Enhanced Tracing

```ruby
# Create tracer
tracer = OpenAIAgents::Tracing::SpanTracer.new

# Add processors
tracer.add_processor(OpenAIAgents::Tracing::ConsoleSpanProcessor.new)
tracer.add_processor(OpenAIAgents::Tracing::FileSpanProcessor.new("trace.log"))

# Create spans
tracer.start_span("operation") do |span|
  span.set_attribute("key", "value")
  span.add_event("event_name")
  # Your code here
end

# Convenience methods
tracer.agent_span("agent_name") { }     # Agent operation span
tracer.tool_span("tool_name") { }       # Tool execution span
tracer.llm_span("model_name") { }       # LLM call span
```

### Advanced Tools

```ruby
# File Search Tool
file_search = OpenAIAgents::Tools::FileSearchTool.new(
  search_paths: ["./src"],              # Directories to search
  file_extensions: [".rb", ".md"],      # File types to include
  max_results: 10                       # Maximum results to return
)

# Web Search Tool
web_search = OpenAIAgents::Tools::WebSearchTool.new(
  search_engine: "duckduckgo",          # Search engine to use
  max_results: 5,                       # Maximum results
  api_key: "optional_api_key"           # For Google/Bing APIs
)

# Computer Control Tool
computer_tool = OpenAIAgents::Tools::ComputerTool.new(
  allowed_actions: [:screenshot, :click, :type],  # Permitted actions
  screen_size: { width: 1920, height: 1080 }      # Screen dimensions
)
```

## 🎮 Examples

For comprehensive examples covering all features, see **[EXAMPLES.md](EXAMPLES.md)**.

### Quick Examples

#### Customer Service Bot
```ruby
# Multi-agent customer service with handoffs
support_agent = OpenAIAgents::Agent.new(
  name: "CustomerSupport",
  instructions: "Help customers and escalate complex issues.",
  model: "gpt-4"
)

billing_agent = OpenAIAgents::Agent.new(
  name: "BillingSpecialist", 
  instructions: "Handle billing inquiries and refunds.",
  model: "claude-3-sonnet-20240229"
)

# Set up intelligent handoffs
handoff_manager = OpenAIAgents::Handoffs::AdvancedHandoff.new
handoff_manager.add_agent(support_agent, capabilities: [:general_support])
handoff_manager.add_agent(billing_agent, capabilities: [:billing, :refunds])

# Process customer inquiry with automatic handoff
response = handle_customer_inquiry("I need a refund for order #12345")
```

#### Research Assistant
```ruby
# Research assistant with file and web search
research_agent = OpenAIAgents::Agent.new(
  name: "ResearchAssistant",
  instructions: "Research topics using files and web search.",
  model: "gpt-4"
)

# Add advanced tools
research_agent.add_tool(OpenAIAgents::Tools::FileSearchTool.new(
  search_paths: ["./docs", "./research"],
  file_extensions: [".md", ".txt", ".pdf"]
))

research_agent.add_tool(OpenAIAgents::Tools::WebSearchTool.new(
  search_engine: "duckduckgo",
  max_results: 5
))

# Conduct research with structured output
result = conduct_research("Ruby programming best practices", research_agent)
```

#### Voice-Enabled Agent
```ruby
# Voice workflow with speech-to-text and text-to-speech
voice = OpenAIAgents::Voice::VoiceWorkflow.new(
  transcription_model: "whisper-1",
  tts_model: "tts-1-hd",
  voice: "nova"
)

# Process audio through agent
result = voice.process_audio_file("user_input.wav", agent)
voice.play_audio(result.audio_file)
```

**👀 See [EXAMPLES.md](EXAMPLES.md) for complete examples including:**
- Multi-agent workflows with handoffs
- Voice-enabled agents 
- Enterprise guardrails and safety
- Usage tracking and analytics
- Structured outputs and validation
- Advanced tool integration
- Configuration management
- Production deployment examples

## 🔍 Testing

```ruby
# spec/spec_helper.rb
require 'openai_agents'

RSpec.configure do |config|
  config.before(:each) do
    # Set up test environment
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test-key")
  end
end

# spec/agent_spec.rb
RSpec.describe OpenAIAgents::Agent do
  let(:agent) do
    OpenAIAgents::Agent.new(
      name: "TestAgent",
      instructions: "You are a test agent",
      model: "gpt-4"
    )
  end
  
  describe "#add_tool" do
    it "adds a method as a tool" do
      def test_tool(input)
        "Test result: #{input}"
      end
      
      agent.add_tool(method(:test_tool))
      
      expect(agent.tools.length).to eq(1)
      expect(agent.tools.first.name).to eq("test_tool")
    end
  end
  
  describe "#execute_tool" do
    it "executes a tool with arguments" do
      agent.add_tool(proc { |x| x * 2 })
      
      result = agent.execute_tool("anonymous_function", x: 5)
      expect(result).to eq(10)
    end
  end
end
```

## 🚀 Deployment

### Production Configuration

```yaml
# config/openai_agents.production.yml
environment: production

openai:
  api_key: <%= ENV['OPENAI_API_KEY'] %>
  timeout: 30
  max_retries: 3

agent:
  default_model: "gpt-4"
  max_turns: 20

guardrails:
  content_safety:
    enabled: true
    strict_mode: true
  rate_limiting:
    enabled: true
    max_requests_per_minute: 120

tracing:
  enabled: true
  processors: ["file", "console"]
  export_format: "json"

logging:
  level: "info"
  output: "file"
  file: "/var/log/openai_agents.log"

cache:
  enabled: true
  ttl: 3600
  storage: "redis"
```

### Docker Deployment

```dockerfile
# Dockerfile
FROM ruby:3.2

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

ENV OPENAI_AGENTS_ENVIRONMENT=production
ENV OPENAI_AGENTS_LOG_LEVEL=info

CMD ["ruby", "app.rb"]
```

## 📖 Additional Resources

- **[OpenAI Platform Documentation](https://platform.openai.com/docs)** - Official OpenAI API documentation
- **[Assistants API Guide](https://platform.openai.com/docs/assistants/overview)** - Learn about AI assistants and agents
- **[Function Calling Guide](https://platform.openai.com/docs/guides/function-calling)** - Tool integration documentation
- **[Structured Outputs Guide](https://platform.openai.com/docs/guides/structured-outputs)** - Schema validation and structured responses
- **[Speech to Text API](https://platform.openai.com/docs/guides/speech-to-text)** - Voice transcription capabilities
- **[Text to Speech API](https://platform.openai.com/docs/guides/text-to-speech)** - Voice synthesis capabilities
- **[API Documentation](lib/)** - Complete Ruby API reference in source code
- **[EXAMPLES.md](./EXAMPLES.md)** - Comprehensive code examples and tutorials
- **[Examples Directory](./examples/)** - Runnable example files
- **[Contributing Guide](./CONTRIBUTING.md)** - How to contribute
- **[Changelog](./CHANGELOG.md)** - Version history and updates
- **[Security](./SECURITY.md)** - Security considerations and best practices

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](./CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by the [OpenAI Agents Python SDK](https://github.com/openai/openai-agents-python)
- Built with ❤️ for the Ruby community
- Thanks to all contributors and users

---

**Built with 🚀 by the Enterprise Modules Team**