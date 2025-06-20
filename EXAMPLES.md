# OpenAI Agents Ruby - Examples

A comprehensive collection of examples demonstrating all features of the OpenAI Agents Ruby gem.

## Table of Contents

1. [Basic Examples](#basic-examples)
2. [Multi-Agent Workflows](#multi-agent-workflows)
3. [Advanced Tool Integration](#advanced-tool-integration)
4. [Voice Workflows](#voice-workflows)
5. [Enterprise Features](#enterprise-features)
6. [Configuration Management](#configuration-management)
7. [Complete Feature Showcase](#complete-feature-showcase)

---

## Basic Examples

### Simple Agent with Tools

```ruby
require 'openai_agents'

# Define a tool
def get_weather(city)
  "The weather in #{city} is sunny with 22°C"
end

# Create an agent
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant that can get weather information.",
  model: "gpt-4"
)

# Add tools
agent.add_tool(method(:get_weather))

# Create and run
runner = OpenAIAgents::Runner.new(agent: agent)
messages = [{ role: "user", content: "What's the weather in Paris?" }]

result = runner.run(messages)
puts result[:messages].last[:content]
```

### Agent with Multiple Tools

```ruby
# Define tools
def lookup_order(order_id)
  "Order #{order_id}: Status - Shipped, ETA - 2 days"
end

def process_refund(order_id, amount)
  "Refund of $#{amount} processed for order #{order_id}"
end

# Create agent
support_agent = OpenAIAgents::Agent.new(
  name: "CustomerSupport",
  instructions: "You are a customer support agent. Help with orders and refunds.",
  model: "gpt-4"
)

# Add multiple tools
support_agent.add_tool(method(:lookup_order))
support_agent.add_tool(method(:process_refund))

runner = OpenAIAgents::Runner.new(agent: support_agent)
messages = [{ role: "user", content: "I need a refund for order #12345" }]

result = runner.run(messages)
puts result[:messages].last[:content]
```

---

## Multi-Agent Workflows

### Basic Agent Handoffs

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

# Set up handoffs
support_agent.add_handoff(tech_agent)

runner = OpenAIAgents::Runner.new(agent: support_agent)
```

### Advanced Handoff System

```ruby
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

### Customer Service Bot

```ruby
require 'openai_agents'

# Create configuration
config = OpenAIAgents::Configuration.new
config.set("agent.max_turns", 15)

# Create usage tracker
tracker = OpenAIAgents::UsageTracking::UsageTracker.new

# Create agents
support_agent = OpenAIAgents::Agent.new(
  name: "CustomerSupport",
  instructions: "You are a friendly customer support agent. Help customers with their questions and escalate complex issues.",
  model: "gpt-4"
)

billing_agent = OpenAIAgents::Agent.new(
  name: "BillingSpecialist",
  instructions: "You handle billing inquiries, refunds, and payment issues.",
  model: "claude-3-sonnet-20240229"
)

# Add tools
def lookup_order(order_id)
  "Order #{order_id}: Status - Shipped, ETA - 2 days"
end

def process_refund(order_id, amount)
  "Refund of $#{amount} processed for order #{order_id}"
end

support_agent.add_tool(method(:lookup_order))
billing_agent.add_tool(method(:lookup_order))
billing_agent.add_tool(method(:process_refund))

# Set up handoffs
handoff_manager = OpenAIAgents::Handoffs::AdvancedHandoff.new
handoff_manager.add_agent(support_agent, capabilities: [:general_support])
handoff_manager.add_agent(billing_agent, capabilities: [:billing, :refunds])

# Create guardrails
guardrails = OpenAIAgents::Guardrails::GuardrailManager.new
guardrails.add_guardrail(OpenAIAgents::Guardrails::ContentSafetyGuardrail.new)
guardrails.add_guardrail(
  OpenAIAgents::Guardrails::RateLimitGuardrail.new(max_requests_per_minute: 30)
)

# Enhanced tracing
tracer = OpenAIAgents::Tracing::SpanTracer.new
tracer.add_processor(OpenAIAgents::Tracing::ConsoleSpanProcessor.new)

# Process customer inquiry
def handle_customer_inquiry(inquiry, customer_id)
  # Validate input
  guardrails.validate_input({ query: inquiry })
  
  # Track interaction start
  session_id = "cs_#{Time.now.to_i}_#{customer_id}"
  start_time = Time.now
  
  tracer.agent_span("customer_service") do |span|
    span.set_attribute("customer.id", customer_id)
    span.set_attribute("session.id", session_id)
    
    # Start with support agent
    runner = OpenAIAgents::Runner.new(agent: support_agent, tracer: tracer)
    messages = [{ role: "user", content: inquiry }]
    
    result = runner.run(messages)
    
    # Check if handoff needed
    if inquiry.downcase.include?("billing") || inquiry.downcase.include?("refund")
      handoff_result = handoff_manager.execute_handoff(
        from_agent: support_agent,
        context: { 
          messages: messages,
          topic: "billing",
          customer_id: customer_id
        },
        reason: "Billing inquiry requires specialist"
      )
      
      if handoff_result.success?
        billing_runner = OpenAIAgents::Runner.new(agent: billing_agent, tracer: tracer)
        result = billing_runner.run(result[:messages])
      end
    end
    
    # Track interaction
    duration = Time.now - start_time
    tracker.track_agent_interaction(
      agent_name: result[:agent].name,
      user_id: customer_id,
      session_id: session_id,
      duration: duration,
      message_count: result[:messages].length,
      outcome: :completed
    )
    
    result[:messages].last[:content]
  end
end

# Example usage
response = handle_customer_inquiry(
  "I need a refund for my order #12345", 
  "customer_001"
)
puts response
```

---

## Advanced Tool Integration

### File Search Tool

```ruby
# File search across your codebase
file_search = OpenAIAgents::Tools::FileSearchTool.new(
  search_paths: ["./src", "./docs"],
  file_extensions: [".rb", ".md", ".txt"],
  max_results: 10
)

agent.add_tool(file_search)
```

### Web Search Tool

```ruby
# Web search for real-time information
web_search = OpenAIAgents::Tools::WebSearchTool.new(
  search_engine: "duckduckgo",
  max_results: 5
)

agent.add_tool(web_search)
```

### Computer Automation Tool

```ruby
# Computer automation (screenshots, mouse, keyboard)
computer_tool = OpenAIAgents::Tools::ComputerTool.new(
  allowed_actions: [:screenshot, :click, :type]
)

agent.add_tool(computer_tool)
```

### Research Assistant

```ruby
require 'openai_agents'

# Create research assistant with advanced tools
research_agent = OpenAIAgents::Agent.new(
  name: "ResearchAssistant",
  instructions: "You are a research assistant that can search files, web, and analyze information.",
  model: "gpt-4"
)

# Add advanced tools
file_search = OpenAIAgents::Tools::FileSearchTool.new(
  search_paths: ["./docs", "./research"],
  file_extensions: [".md", ".txt", ".pdf"],
  max_results: 10
)

web_search = OpenAIAgents::Tools::WebSearchTool.new(
  search_engine: "duckduckgo",
  max_results: 5
)

research_agent.add_tool(file_search)
research_agent.add_tool(web_search)

# Create structured output schema for research results
research_schema = OpenAIAgents::StructuredOutput::ObjectSchema.build do
  string :research_topic, required: true
  array :key_findings, required: true, items: { type: "string" }
  array :sources, required: true, items: {
    type: "object",
    properties: {
      title: { type: "string" },
      url: { type: "string" },
      type: { type: "string", enum: ["file", "web", "document"] }
    }
  }
  string :summary, required: true, min_length: 50
  number :confidence_score, required: true, minimum: 0.0, maximum: 1.0
end

# Enhanced tracing for research operations
tracer = OpenAIAgents::Tracing::SpanTracer.new
tracer.add_processor(OpenAIAgents::Tracing::FileSpanProcessor.new("research_trace.log"))

# Research function
def conduct_research(topic, research_agent, schema, tracer)
  tracer.start_span("research_session") do |span|
    span.set_attribute("research.topic", topic)
    
    runner = OpenAIAgents::Runner.new(agent: research_agent, tracer: tracer)
    
    messages = [{
      role: "user",
      content: "Research the topic: #{topic}. Provide key findings, sources, and a summary."
    }]
    
    result = runner.run(messages)
    response_content = result[:messages].last[:content]
    
    # Parse and validate response structure
    begin
      research_data = extract_research_data(response_content, topic)
      validated_result = schema.validate(research_data)
      
      span.set_attribute("research.findings_count", validated_result[:key_findings].length)
      span.set_attribute("research.sources_count", validated_result[:sources].length)
      span.set_attribute("research.confidence", validated_result[:confidence_score])
      
      validated_result
    rescue => e
      span.set_status(:error, description: e.message)
      raise
    end
  end
end

# Example usage
begin
  research_result = conduct_research(
    "Ruby programming best practices",
    research_agent,
    research_schema,
    tracer
  )
  
  puts "Research Topic: #{research_result[:research_topic]}"
  puts "Key Findings:"
  research_result[:key_findings].each_with_index do |finding, i|
    puts "  #{i + 1}. #{finding}"
  end
  puts "Confidence: #{(research_result[:confidence_score] * 100).round(1)}%"
  
rescue OpenAIAgents::StructuredOutput::ValidationError => e
  puts "Research result validation failed: #{e.message}"
end
```

---

## Voice Workflows

### Basic Voice Workflow

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
```

### Streaming Voice Session

```ruby
# Real-time voice session
voice.start_streaming_session(agent) do |session|
  session.on_transcription { |text| puts "User: #{text}" }
  session.on_response { |text| puts "Agent: #{text}" }
  session.on_audio { |audio_file| voice.play_audio(audio_file) }
end
```

---

## Enterprise Features

### Guardrails and Safety

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

### Structured Outputs

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

---

## Configuration Management

### Environment-based Configuration

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

---

## Streaming and Real-time Features

### Basic Streaming

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

### Enhanced Tracing and Debugging

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

### Interactive REPL

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

---

## Multi-Provider Support

### Different LLM Providers

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

---

## Complete Feature Showcase

The complete feature showcase demonstrates all capabilities in a single comprehensive example. See the full implementation in [`examples/complete_features_showcase.rb`](examples/complete_features_showcase.rb).

### Running the Complete Showcase

```bash
# Set up environment
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-anthropic-key"
export GEMINI_API_KEY="your-gemini-key"

# Run the complete demonstration
ruby examples/complete_features_showcase.rb
```

This showcase includes:
- Configuration Management
- Usage Tracking and Analytics
- Extensions Framework
- Advanced Agent Creation
- Advanced Tools Integration
- Advanced Handoff System
- Voice Workflow System
- Enhanced Tracing and Visualization
- Guardrails and Safety Systems
- Structured Output and Schema Validation
- Comprehensive Analytics and Reporting
- Interactive REPL Demo Setup

---

## Testing Examples

### Basic Agent Testing

```ruby
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

---

## Deployment Examples

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

### Production Setup

```ruby
# config/production.rb
require 'openai_agents'

# Load production configuration
config = OpenAIAgents::Configuration.new(environment: 'production')

# Set up comprehensive monitoring
tracker = OpenAIAgents::UsageTracking::UsageTracker.new
tracker.add_alert(:cost_limit) { |usage| usage[:total_cost_today] > 1000.0 }
tracker.add_alert(:error_rate) { |usage| usage[:error_rate] > 0.05 }

# Create production-ready tracer
tracer = OpenAIAgents::Tracing::SpanTracer.new
tracer.add_processor(OpenAIAgents::Tracing::FileSpanProcessor.new("/var/log/traces.log"))

# Set up guardrails
guardrails = OpenAIAgents::Guardrails::GuardrailManager.new
guardrails.add_guardrail(OpenAIAgents::Guardrails::ContentSafetyGuardrail.new)
guardrails.add_guardrail(OpenAIAgents::Guardrails::RateLimitGuardrail.new(
  max_requests_per_minute: 300
))

# Your production agents and workflows...
```

---

## Additional Resources

- **[Complete Features Showcase](examples/complete_features_showcase.rb)** - Comprehensive demonstration
<!-- [API Documentation](https://rubydoc.info/gems/openai_agents) - Complete Ruby API reference -->
- **[API Documentation](lib/)** - Complete Ruby API reference in source code
- **[README.md](README.md)** - Quick start guide
- **[Contributing Guide](CONTRIBUTING.md)** - How to contribute
- **[Security Guide](SECURITY.md)** - Security best practices

For more examples and advanced use cases, explore the `examples/` directory in the repository.