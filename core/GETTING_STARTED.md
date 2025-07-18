# Getting Started with RAAF (Ruby AI Agents Factory)

This guide will walk you through building AI-powered applications with RAAF (Ruby AI Agents Factory), from basic concepts to advanced multi-agent workflows.

## Table of Contents

1. [Installation & Setup](#installation--setup)
2. [Core Concepts](#core-concepts)
3. [Building Your First Agent](#building-your-first-agent)
4. [Adding Tools](#adding-tools)
5. [Structured Output](#structured-output)
6. [Multi-Agent Workflows](#multi-agent-workflows)
7. [Enterprise Features](#enterprise-features)
8. [Next Steps](#next-steps)

## Installation & Setup

### Prerequisites

- Ruby 3.0 or higher
- OpenAI API key

### Installation

```bash
gem install raaf
```

Or add to your Gemfile:
```ruby
gem 'raaf'
```

### Environment Setup

```bash
# Required for OpenAI integration
export OPENAI_API_KEY="your-openai-api-key"

# Optional: Additional providers
export ANTHROPIC_API_KEY="your-anthropic-key"
export GEMINI_API_KEY="your-gemini-key"
```

## Core Concepts

### What are AI Agents?

AI Agents are specialized AI systems designed to perform tasks autonomously. Unlike simple chatbots, agents can:

- **Use Tools** - Execute functions and access external data
- **Make Decisions** - Choose appropriate actions based on context
- **Collaborate** - Work with other agents to solve complex problems
- **Learn Context** - Maintain conversation memory and state

**Business Benefits:**
- 24/7 automated customer service
- Intelligent task routing and escalation
- Consistent responses aligned with business policies
- Scalable expertise distribution

### Function Calling & Tools

Function calling allows agents to execute specific functions based on conversation context, bridging AI reasoning with real-world actions.

**Common Use Cases:**
- Customer service agents accessing order systems
- Research assistants searching documentation
- Technical support running diagnostics
- Sales agents checking inventory

### Multi-Agent Workflows

Multiple specialized agents working together, each with distinct capabilities. Agents intelligently route conversations based on context and expertise.

**Real-World Applications:**
- Customer service: General → Technical → Billing
- Healthcare: Triage → Specialist → Treatment
- Sales: Lead qualification → Product demo → Closing

## Building Your First Agent

### Basic Agent

```ruby
require 'raaf'

# Create a simple assistant
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o"
)

# Run a conversation
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Hello, tell me about Ruby programming")

puts result.messages.last[:content]
```

### Agent with Personality

```ruby
support_agent = RAAF::Agent.new(
  name: "CustomerSupport",
  instructions: "You are a friendly customer support agent. Always be helpful, 
                 patient, and professional. Ask clarifying questions when needed.",
  model: "gpt-4"
)
```

### Ruby-Idiomatic Agent Creation

The Ruby implementation supports idiomatic Ruby patterns:

```ruby
# Block-based configuration (Ruby-style)
agent = RAAF::Agent.new(name: "Assistant") do |config|
  config.instructions = "You are a helpful assistant"
  config.model = "gpt-4o"
  config.max_turns = 20
  config.add_tool(calculator_tool)
  config.add_handoff(other_agent)
end

# Dynamic tool execution (method_missing magic)
result = agent.get_weather(city: "Tokyo")  # Direct method calls

# Predicate methods for checking state
if agent.tools? && agent.handoffs?
  puts "Agent has tools and handoffs configured"
end

# Bang methods for destructive operations
agent.reset_tools!.reset_handoffs!  # Method chaining
```

### Understanding Agent Parameters

- **`name`** - Unique identifier for the agent
- **`instructions`** - System prompt defining behavior and personality
- **`model`** - LLM model (gpt-4o, claude-3-sonnet, etc.)
- **`max_turns`** - Maximum conversation turns (default: 10)

## Adding Tools

Tools extend agent capabilities beyond text generation.

### Simple Tool

```ruby
def get_weather(city)
  # In production, call a real weather API
  "The weather in #{city} is sunny with 22°C"
end

agent.add_tool(method(:get_weather))
```

### Tool with Parameters

```ruby
def calculate_discount(price, discount_percent)
  discounted = price * (1 - discount_percent / 100.0)
  "Original price: $#{price}, Discount: #{discount_percent}%, Final price: $#{discounted}"
end

agent.add_tool(method(:calculate_discount))
```

### Using FunctionTool for Advanced Tools

```ruby
lookup_order_tool = RAAF::FunctionTool.new(
  proc { |order_id| "Order #{order_id}: Status - Shipped, ETA - 2 days" },
  name: "lookup_order",
  description: "Look up order status by order ID",
  parameters: {
    type: "object",
    properties: {
      order_id: { type: "string", description: "Order ID to look up" }
    },
    required: ["order_id"]
  }
)

agent.add_tool(lookup_order_tool)

# Ruby-idiomatic tool usage
if agent.tool_exists?(:lookup_order)
  # Direct method call using method_missing
  result = agent.lookup_order(order_id: "12345")
  
  # Or traditional approach
  result = agent.execute_tool("lookup_order", order_id: "12345")
end
```

### Built-in Advanced Tools

```ruby
# File search across your codebase
file_search = RAAF::Tools::FileSearchTool.new(
  search_paths: ["./src", "./docs"],
  file_extensions: [".rb", ".md", ".txt"]
)

# Web search for real-time information
web_search = RAAF::Tools::WebSearchTool.new(
  search_engine: "duckduckgo",
  max_results: 5
)

# Computer automation
computer_tool = RAAF::Tools::ComputerTool.new(
  allowed_actions: [:screenshot, :click, :type]
)

agent.add_tool(file_search)
agent.add_tool(web_search)
agent.add_tool(computer_tool)
```

## Structured Output

OpenAI Agents Ruby provides **universal structured output** that works across ALL providers using the modern `response_format` parameter. This ensures your agents return data in a specific format that your application can reliably parse and use.

### Modern Response Format (Recommended)

```ruby
# Define structured output using response_format (works with ALL providers)
agent = RAAF::Agent.new(
  name: "UserExtractor", 
  instructions: "Extract user information from the input and return as JSON.",
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
          age: { type: "integer", minimum: 0, maximum: 150 },
          email: { type: "string" },
          city: { type: "string" }
        },
        required: ["name", "age", "city"],
        additionalProperties: false
      }
    }
  }
)

# Works with ANY provider - OpenAI, Anthropic, Cohere, Groq, etc.
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Hi, I'm Sarah, 28 years old from Seattle. Email: sarah@example.com")

# The response is guaranteed to match the schema across ALL providers
response = result.messages.last[:content]
# => '{"name":"Sarah","age":28,"email":"sarah@example.com","city":"Seattle"}'

user_data = JSON.parse(response)
puts "Welcome #{user_data['name']} from #{user_data['city']}!"
```

### Legacy Output Schema (Still Supported)

```ruby
# Legacy approach using output_schema (still works but response_format is preferred)
user_schema = {
  type: "object",
  properties: {
    name: { type: "string" },
    age: { type: "integer", minimum: 0, maximum: 150 },
    email: { type: "string" },
    city: { type: "string" }
  },
  required: ["name", "age", "city"],
  additionalProperties: false
}

agent = RAAF::Agent.new(
  name: "UserExtractor", 
  instructions: "Extract user information from the input and return as JSON.",
  model: "gpt-4o",
  output_schema: user_schema  # Legacy approach
)
```

### Cross-Provider Compatibility

The `response_format` feature works seamlessly across ALL providers with automatic adaptations:

```ruby
# Same schema definition works with any provider
user_schema = {
  type: "json_schema",
  json_schema: {
    name: "user_info",
    strict: true,
    schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        email: { type: "string" }
      },
      required: ["name"],
      additionalProperties: false
    }
  }
}

# OpenAI - Native JSON schema support
openai_agent = RAAF::Agent.new(
  name: "OpenAIExtractor",
  model: "gpt-4o",
  response_format: user_schema
)
openai_runner = RAAF::Runner.new(
  agent: openai_agent,
  provider: RAAF::Models::OpenAIProvider.new
)

# Anthropic - Enhanced system prompts with schema
anthropic_agent = RAAF::Agent.new(
  name: "AnthropicExtractor",
  model: "claude-3-5-sonnet-20241022",
  response_format: user_schema
)
anthropic_runner = RAAF::Runner.new(
  agent: anthropic_agent,
  provider: RAAF::Models::AnthropicProvider.new
)

# Cohere - JSON object format with schema instructions
cohere_agent = RAAF::Agent.new(
  name: "CohereExtractor",
  model: "command-r",
  response_format: user_schema
)
cohere_runner = RAAF::Runner.new(
  agent: cohere_agent,
  provider: RAAF::Models::CohereProvider.new
)

# All produce identical structured output!
input = "My name is John and email is john@example.com"
results = [
  openai_runner.run(input),
  anthropic_runner.run(input),
  cohere_runner.run(input)
].map { |r| JSON.parse(r.messages.last[:content]) }

# All results follow the same schema structure
results.each { |r| puts "Name: #{r['name']}, Email: #{r['email']}" }
```

### Provider-Specific Adaptations

- **OpenAI/Groq**: Native `response_format` support
- **Anthropic**: Automatic system message enhancement with schema instructions  
- **Cohere**: Conversion to `json_object` format with schema guidance
- **Others**: Intelligent prompt enhancement for structured output

### Using Schema Builder

For complex schemas, use the built-in schema builder:

```ruby
# Build schema programmatically
product_schema = RAAF::StructuredOutput::ObjectSchema.build do
  string :product_name, required: true, minLength: 1
  number :price, required: true, minimum: 0
  string :category, enum: %w[electronics clothing food other], required: true
  array :features, items: { type: "string" }, minItems: 1, required: true
  boolean :in_stock, required: true
end

# Use with agent
agent = RAAF::Agent.new(
  name: "ProductAnalyzer",
  instructions: "Analyze product information and structure it according to the schema.",
  model: "gpt-4o", 
  output_schema: product_schema.to_h
)
```

### Validation and Error Handling

```ruby
begin
  result = runner.run("Tell me about the MacBook Pro")
  response_json = result.messages.last[:content]
  
  # Parse and validate
  product_data = JSON.parse(response_json)
  
  # Additional validation using the schema
  validator = RAAF::StructuredOutput::BaseSchema.new(product_schema.to_h)
  validated_data = validator.validate(product_data)
  
  puts "Valid product data: #{validated_data}"
  
rescue JSON::ParserError => e
  puts "Invalid JSON returned: #{e.message}"
rescue RAAF::StructuredOutput::ValidationError => e
  puts "Schema validation failed: #{e.message}"
end
```

### Advanced Schema Features

```ruby
# Complex nested schema
order_schema = {
  type: "object",
  properties: {
    order_id: { type: "string" },
    customer: {
      type: "object",
      properties: {
        name: { type: "string" },
        email: { type: "string", pattern: ".*@.*" }
      },
      required: ["name", "email"]
    },
    items: {
      type: "array",
      items: {
        type: "object", 
        properties: {
          product: { type: "string" },
          quantity: { type: "integer", minimum: 1 },
          price: { type: "number", minimum: 0 }
        },
        required: ["product", "quantity", "price"]
      },
      minItems: 1
    },
    total: { type: "number", minimum: 0 }
  },
  required: ["order_id", "customer", "items", "total"],
  additionalProperties: false
}

# Agent will enforce this exact structure
order_agent = RAAF::Agent.new(
  name: "OrderProcessor",
  instructions: "Process order information into the required JSON format.",
  model: "gpt-4o",
  output_schema: order_schema
)
```

### Best Practices

1. **Keep schemas focused**: Design schemas for specific use cases rather than trying to handle everything
2. **Use clear property names**: Make field names descriptive and consistent
3. **Set appropriate constraints**: Use minimum/maximum values, string patterns, and enums to ensure data quality
4. **Handle validation errors**: Always include error handling for parsing and validation
5. **Test with edge cases**: Verify your schemas work with various input types

**Note**: Structured output is enforced at the API level, meaning the language model is constrained to return only valid JSON matching your schema. This is more reliable than post-processing validation alone.

## Multi-Agent Workflows

### Basic Handoffs

```ruby
# Create specialized agents
support_agent = RAAF::Agent.new(
  name: "CustomerSupport",
  instructions: "Handle general inquiries. Escalate technical issues to TechnicalSupport.",
  model: "gpt-4"
)

tech_agent = RAAF::Agent.new(
  name: "TechnicalSupport",
  instructions: "Handle complex technical issues and troubleshooting.",
  model: "gpt-4"
)

# Set up handoff capability
support_agent.add_handoff(tech_agent)

# Agent will automatically handoff when appropriate
runner = RAAF::Runner.new(agent: support_agent)
result = runner.run("My API is returning 500 errors")
```

### Advanced Handoff System

```ruby
# Create handoff manager
handoff_manager = RAAF::Handoffs::AdvancedHandoff.new

# Define agent capabilities
handoff_manager.add_agent(support_agent, capabilities: [:general_support, :billing])
handoff_manager.add_agent(tech_agent, capabilities: [:technical_support, :debugging])

# Context-aware handoff
result = handoff_manager.execute_handoff(
  from_agent: support_agent,
  context: { 
    topic: "technical_issue", 
    user_sentiment: "frustrated",
    complexity: "high"
  },
  reason: "Customer needs technical assistance"
)
```

## Enterprise Features

### Safety Guardrails

```ruby
# Create guardrail manager
guardrails = RAAF::Guardrails::GuardrailManager.new

# Content safety
guardrails.add_guardrail(
  RAAF::Guardrails::ContentSafetyGuardrail.new
)

# Rate limiting
guardrails.add_guardrail(
  RAAF::Guardrails::RateLimitGuardrail.new(
    max_requests_per_minute: 60
  )
)

# Input validation
guardrails.add_guardrail(
  RAAF::Guardrails::LengthGuardrail.new(
    max_input_length: 10000,
    max_output_length: 5000
  )
)

# Validate before processing
begin
  guardrails.validate_input(user_input)
  result = runner.run(user_input)
rescue RAAF::Guardrails::GuardrailError => e
  puts "Input blocked: #{e.message}"
end
```

### Usage Tracking

```ruby
# Create usage tracker
tracker = RAAF::UsageTracking::UsageTracker.new

# Set up cost alerts
tracker.add_alert(:high_cost) do |usage|
  usage[:total_cost_today] > 100.0
end

# Track interactions automatically
runner = RAAF::Runner.new(agent: agent, tracker: tracker)

# Get analytics
analytics = tracker.analytics(:today)
puts "API calls: #{analytics[:api_calls][:count]}"
puts "Total cost: $#{analytics[:costs][:total]}"
```

### Configuration Management

```ruby
# Environment-based configuration
config = RAAF::Configuration.new(environment: "production")

# Set values
config.set("agent.default_model", "gpt-4")
config.set("guardrails.rate_limiting.max_requests_per_minute", 120)

# Access configuration
puts config.openai.api_key
puts config.agent.max_turns
```

## Streaming Responses

For real-time user feedback:

```ruby
# Create streaming runner
streaming_runner = RAAF::StreamingRunner.new(agent: agent)

# Stream responses
streaming_runner.run_streaming(messages) do |chunk|
  case chunk[:type]
  when "content"
    print chunk[:content]  # Print as it arrives
  when "tool_call"
    puts "\n🔧 Using tool: #{chunk[:tool_call]}"
  end
end
```

## Tracing and Monitoring

Monitor agent behavior and performance:

```ruby
# Enable tracing
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(RAAF::Tracing::ConsoleSpanProcessor.new)

# Create traced runner
runner = RAAF::Runner.new(agent: agent, tracer: tracer)

# All operations are now traced
result = runner.run("Hello")

# View trace summary
summary = tracer.trace_summary
puts "Spans: #{summary[:total_spans]}"
puts "Duration: #{summary[:total_duration_ms]}ms"
```

## Voice Workflows

For speech-enabled applications:

```ruby
# Create voice workflow
voice = RAAF::Voice::VoiceWorkflow.new(
  transcription_model: "whisper-1",
  tts_model: "tts-1-hd",
  voice: "nova"
)

# Process audio file
result = voice.process_audio_file("user_input.wav", agent)
puts "User said: #{result.transcription}"
puts "Agent replied: #{result.text_response}"

# Play response audio
voice.play_audio(result.audio_file)
```

## Working with Multiple Providers

```ruby
# OpenAI (default)
openai_agent = RAAF::Agent.new(
  name: "OpenAI_Assistant",
  model: "gpt-4",
  instructions: "You use OpenAI's GPT-4"
)

# Anthropic Claude
claude_agent = RAAF::Agent.new(
  name: "Claude_Assistant",
  model: "claude-3-sonnet-20240229",
  instructions: "You use Anthropic's Claude"
)

# Google Gemini
gemini_agent = RAAF::Agent.new(
  name: "Gemini_Assistant",
  model: "gemini-1.5-pro",
  instructions: "You use Google's Gemini"
)
```

## Best Practices

### Agent Design
- Give agents clear, specific instructions
- Define their role and capabilities
- Set appropriate boundaries and escalation rules

### Tool Integration
- Keep tools focused on single responsibilities
- Provide clear parameter descriptions
- Handle errors gracefully

### Multi-Agent Systems
- Design clear handoff criteria
- Avoid circular handoffs
- Monitor agent interactions

### Production Considerations
- Implement comprehensive guardrails
- Monitor usage and costs
- Use appropriate rate limiting
- Enable tracing for debugging

## Common Patterns

### Customer Service Bot
```ruby
# Tier 1 Support
general_agent = RAAF::Agent.new(
  name: "GeneralSupport",
  instructions: "Handle common questions. Escalate complex technical issues.",
  model: "gpt-4"
)

# Tier 2 Support
technical_agent = RAAF::Agent.new(
  name: "TechnicalSupport",
  instructions: "Handle complex technical troubleshooting.",
  model: "gpt-4"
)

# Add tools and handoffs
general_agent.add_tool(method(:lookup_order))
general_agent.add_handoff(technical_agent)
technical_agent.add_tool(method(:run_diagnostics))
```

### Research Assistant
```ruby
research_agent = RAAF::Agent.new(
  name: "Researcher",
  instructions: "You are a research assistant. Search for information and provide comprehensive summaries.",
  model: "gpt-4"
)

# Add research tools
research_agent.add_tool(
  RAAF::Tools::FileSearchTool.new(search_paths: ["./docs", "./papers"])
)
research_agent.add_tool(
  RAAF::Tools::WebSearchTool.new(max_results: 10)
)
```

## Next Steps

1. **Explore Examples** - Check out [EXAMPLES.md](EXAMPLES.md) for comprehensive code examples
2. **API Reference** - See [API_REFERENCE.md](API_REFERENCE.md) for detailed API documentation
3. **Production Setup** - Read [DEPLOYMENT.md](DEPLOYMENT.md) for production deployment guide
4. **Advanced Features** - Learn about enterprise features and customization options

### Useful Resources

- [OpenAI Platform Documentation](https://platform.openai.com/docs)
- [Function Calling Guide](https://platform.openai.com/docs/guides/function-calling)
- [Assistants API Documentation](https://platform.openai.com/docs/assistants)

Ready to build more advanced workflows? Check out the [Examples](EXAMPLES.md) for detailed implementations of customer service bots, research assistants, and enterprise applications.