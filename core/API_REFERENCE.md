# Core API Reference

Complete Ruby API documentation for RAAF Core components.

## Table of Contents

1. [Agent Class](#agent-class)
2. [Runner Classes](#runner-classes)
3. [FunctionTool](#functiontool)
4. [Structured Output](#structured-output)
5. [Configuration](#configuration)
6. [Models](#models)
7. [Error Handling](#error-handling)
8. [Return Types](#return-types)

## Agent Class

The core agent class for creating AI agents.

### Constructor

```ruby
RAAF::Agent.new(
  name: String,                    # Required: Unique agent identifier
  instructions: String,            # Optional: System prompt/behavior
  model: String,                   # Optional: LLM model (default: "gpt-4")
  max_turns: Integer,              # Optional: Max conversation turns (default: 10)
  tools: Array,                    # Optional: Pre-configured tools
  handoffs: Array,                 # Optional: Pre-configured handoff agents
  response_format: Hash,           # Optional: Modern structured output format (all providers)
  output_schema: Hash              # Optional: Legacy structured output (deprecated)
)
```

### Instance Methods

```ruby
# Tool Management
agent.add_tool(tool)                    # Add tool (Method, Proc, or FunctionTool)
agent.remove_tool(name)                 # Remove tool by name
agent.has_tools?                        # Check if agent has tools
agent.tools                            # Get all tools
agent.execute_tool(name, **args)        # Execute tool directly

# Handoff Management
agent.add_handoff(other_agent)          # Add handoff target
agent.remove_handoff(agent_name)        # Remove handoff by name
agent.can_handoff_to?(agent_name)       # Check handoff availability
agent.find_handoff(agent_name)          # Get handoff target by name
agent.handoffs                         # Get all handoff targets

# Utility
agent.to_h                             # Convert to hash representation
agent.inspect                         # Debugging information
```

### Examples

```ruby
# Basic agent
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4"
)

# Agent with tools and handoffs
agent = RAAF::Agent.new(
  name: "Support",
  instructions: "Handle customer support inquiries.",
  model: "gpt-4",
  max_turns: 15,
  tools: [lookup_order_tool],
  handoffs: [technical_agent]
)

# Agent with structured output (modern approach)
agent = RAAF::Agent.new(
  name: "DataExtractor",
  instructions: "Extract and structure data from user input.",
  model: "gpt-4o",
  response_format: {
    type: "json_schema",
    json_schema: {
      name: "user_data",
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
)
```

## Runner Classes

### Runner

Synchronous agent execution.

```ruby
# Constructor
RAAF::Runner.new(
  agent: Agent,                    # Required: Primary agent
  tracer: Tracer,                  # Optional: Tracer for monitoring
  provider: Provider               # Optional: Model provider
)

# Methods
runner.run(messages, stream: false, config: nil, **kwargs)  # Execute agent
runner.run_async(messages, **kwargs)                       # Async execution
```

### StreamingRunner

Real-time response streaming.

```ruby
# Constructor
RAAF::StreamingRunner.new(agent: agent)

# Methods
runner.run_streaming(messages) do |chunk|
  # Handle streaming chunks
end
```

### Examples

```ruby
# Basic execution
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Hello, help me with my order")

# With configuration
config = RAAF::RunConfig.new(
  max_turns: 5,
  trace_include_sensitive_data: false
)
result = runner.run(messages, config: config)

# Streaming
streaming_runner = RAAF::StreamingRunner.new(agent: agent)
streaming_runner.run_streaming(messages) do |chunk|
  case chunk[:type]
  when "content"
    print chunk[:content]
  when "tool_call"
    puts "\nTool: #{chunk[:tool_call]}"
  end
end
```

## FunctionTool

Wrapper for custom functions.

```ruby
# Constructor
RAAF::FunctionTool.new(
  callable,                       # Proc, Method, or callable object
  name: String,                   # Optional: Tool name
  description: String,            # Optional: Tool description
  parameters: Hash                # Optional: Parameter schema
)

# Methods
tool.call(**args)                # Execute the tool
tool.name                        # Get tool name
tool.description                 # Get tool description
tool.parameters                  # Get parameter schema
tool.to_tool_definition          # Get OpenAI tool definition
```

### Example Tool Creation

```ruby
# Simple function tool
def get_weather(city)
  "The weather in #{city} is sunny"
end

weather_tool = RAAF::FunctionTool.new(
  method(:get_weather),
  name: "get_weather",
  description: "Get weather information for a city",
  parameters: {
    type: "object",
    properties: {
      city: { type: "string", description: "City name" }
    },
    required: ["city"]
  }
)

agent.add_tool(weather_tool)
```

## Structured Output

Universal structured output that works across ALL providers using modern `response_format` or legacy `output_schema` approaches.

### Response Format (Recommended)

Modern approach using OpenAI-compatible `response_format` parameter that works with all providers.

```ruby
# Basic response_format usage
agent = RAAF::Agent.new(
  name: "ExtractorAgent",
  model: "gpt-4o",
  response_format: {
    type: "json_schema",
    json_schema: {
      name: "output_format",
      strict: true,
      schema: {
        type: "object",
        properties: {
          field1: { type: "string" },
          field2: { type: "integer" }
        },
        required: ["field1"],
        additionalProperties: false
      }
    }
  }
)

# Works with ANY provider automatically:
# - OpenAI: Native JSON schema support
# - Anthropic: Enhanced system prompts
# - Cohere: JSON object mode + schema
# - Groq: Direct parameter passthrough
# - Others: Intelligent adaptation
```

### Provider Compatibility

| Provider | Implementation | Native Support |
|----------|----------------|----------------|
| OpenAI | Direct `response_format` | ✅ Full |
| Groq | Direct `response_format` | ✅ Full |
| Anthropic | Enhanced system prompts | 🔄 Adapted |
| Cohere | JSON object + schema | 🔄 Adapted |
| Others | Prompt enhancement | 🔄 Adapted |

### Legacy Output Schema

Original approach using `output_schema` parameter (still supported for backward compatibility).

### Migration Guide

```ruby
# OLD: Legacy output_schema approach
agent_old = RAAF::Agent.new(
  name: "LegacyAgent",
  model: "gpt-4o",
  output_schema: {
    type: "object",
    properties: { name: { type: "string" } }
  }
)

# NEW: Modern response_format approach (recommended)
agent_new = RAAF::Agent.new(
  name: "ModernAgent",
  model: "gpt-4o",
  response_format: {
    type: "json_schema",
    json_schema: {
      name: "my_schema",
      strict: true,
      schema: {
        type: "object",
        properties: { name: { type: "string" } },
        additionalProperties: false
      }
    }
  }
)
```

### BaseSchema

Core schema validation class.

```ruby
# Constructor
RAAF::StructuredOutput::BaseSchema.new(schema)

# Methods
schema.validate(data)                    # Validate data against schema
schema.to_h                             # Get schema as hash
schema.to_json                          # Get schema as JSON string
```

### ObjectSchema

Builder class for object schemas.

```ruby
# Constructor
RAAF::StructuredOutput::ObjectSchema.new(
  properties: Hash,                     # Property definitions
  required: Array,                      # Required property names
  additional_properties: Boolean        # Allow additional properties
)

# Builder Pattern
schema = RAAF::StructuredOutput::ObjectSchema.build do
  string :name, required: true, minLength: 1
  integer :age, required: true, minimum: 0, maximum: 150
  string :email, pattern: '.*@.*'
  boolean :active, required: true
  array :tags, items: { type: "string" }, minItems: 1
  object :address, properties: {
    street: { type: "string" },
    city: { type: "string" }
  }, required: ["city"]
  
  # Constraints
  required :name, :age, :active
  no_additional_properties
end
```

### ArraySchema

Schema for array validation.

```ruby
RAAF::StructuredOutput::ArraySchema.new(
  items: Hash,                          # Schema for array items
  min_items: Integer,                   # Minimum array length
  max_items: Integer                    # Maximum array length
)
```

### StringSchema

Schema for string validation.

```ruby
RAAF::StructuredOutput::StringSchema.new(
  min_length: Integer,                  # Minimum string length
  max_length: Integer,                  # Maximum string length
  pattern: String,                      # Regex pattern
  enum: Array                          # Allowed values
)
```

### ResponseFormatter

Response validation and formatting.

```ruby
# Constructor
formatter = RAAF::StructuredOutput::ResponseFormatter.new(schema)

# Methods
formatter.format_response(data)         # Validate and format data
formatter.validate_and_format(json_string)  # Parse JSON and validate
```

### StrictSchema

Utilities for strict schema compliance (OpenAI requirement).

```ruby
# Ensure schema meets OpenAI strict requirements
strict_schema = RAAF::StrictSchema.ensure_strict_json_schema(schema)

# Features:
# - All object properties become required
# - additionalProperties set to false
# - Nested objects processed recursively
# - Handles arrays, unions (anyOf), intersections (allOf)
```

### Usage Examples

```ruby
# Basic schema usage
schema = {
  type: "object",
  properties: {
    name: { type: "string" },
    age: { type: "integer" }
  },
  required: ["name"],
  additionalProperties: false
}

# Agent with structured output
agent = RAAF::Agent.new(
  name: "DataExtractor",
  instructions: "Extract information as JSON.",
  model: "gpt-4o",
  output_schema: schema
)

# Validation
validator = RAAF::StructuredOutput::BaseSchema.new(schema)
begin
  validated_data = validator.validate(response_data)
  puts "Valid: #{validated_data}"
rescue RAAF::StructuredOutput::ValidationError => e
  puts "Invalid: #{e.message}"
end

# Complex schema with builder
user_schema = RAAF::StructuredOutput::ObjectSchema.build do
  string :first_name, required: true, minLength: 1
  string :last_name, required: true, minLength: 1
  integer :age, minimum: 0, maximum: 150
  string :email, pattern: '^[^@]+@[^@]+\.[^@]+$'
  array :hobbies, items: { type: "string" }
  object :address, properties: {
    street: { type: "string" },
    city: { type: "string" },
    zipcode: { type: "string", pattern: '^\d{5}$' }
  }, required: ["city"]
  
  required :first_name, :last_name
  no_additional_properties
end

# Use with agent
profile_agent = RAAF::Agent.new(
  name: "ProfileExtractor",
  instructions: "Extract user profile information.",
  model: "gpt-4o",
  output_schema: user_schema.to_h
)
```

### Error Handling

```ruby
# Custom exceptions
RAAF::StructuredOutput::ValidationError   # Schema validation failed
RAAF::StructuredOutput::SchemaError      # Invalid schema definition

# Usage
begin
  result = runner.run(messages)
  response = result.messages.last[:content]
  data = JSON.parse(response)
  validated = schema.validate(data)
rescue JSON::ParserError => e
  puts "Invalid JSON: #{e.message}"
rescue RAAF::StructuredOutput::ValidationError => e
  puts "Schema validation failed: #{e.message}"
rescue RAAF::StructuredOutput::SchemaError => e
  puts "Invalid schema: #{e.message}"
end
```

## Configuration

### Configuration Class

```ruby
# Constructor
RAAF::Configuration.new(environment: "development")

# Value Management
config.set(key, value)                 # Set configuration value
config.get(key)                        # Get configuration value
config.has_key?(key)                   # Check if key exists

# Nested Access
config.openai.api_key                  # Access nested values
config.agent.max_turns                 # Dot notation access

# File Operations
config.load_from_file(path)            # Load from YAML/JSON file
config.save_to_file(path, format: :yaml) # Save to file

# Validation and Watching
config.validate                        # Validate configuration
config.watch { |updated| ... }         # Watch for changes
config.reload                          # Reload from sources
```

### Environment Variables

```ruby
# OpenAI Configuration
ENV['OPENAI_API_KEY']                  # OpenAI API key
ENV['OPENAI_API_BASE']                 # Custom API base URL

# Anthropic Configuration
ENV['ANTHROPIC_API_KEY']               # Anthropic API key

# Tracing Configuration
ENV['RAAF_DISABLE_TRACING']   # Disable tracing
ENV['RAAF_DEBUG_CATEGORIES']  # Enable debug categories
ENV['RAAF_TRACE_BATCH_SIZE']  # Batch size for exports
```

## Models

### Model Providers

#### ResponsesProvider (Default)
```ruby
RAAF::Models::ResponsesProvider.new(
  api_key: String,                     # OpenAI API key
  api_base: String                     # Optional: Custom API base
)
```

#### OpenAIProvider
```ruby
RAAF::Models::OpenAIProvider.new(
  api_key: String,                     # OpenAI API key
  api_base: String,                    # Optional: Custom API base
  timeout: Integer                     # Request timeout
)
```

#### AnthropicProvider
```ruby
RAAF::Models::AnthropicProvider.new(
  api_key: String,                     # Anthropic API key
  timeout: Integer                     # Request timeout
)
```

#### MultiProvider
```ruby
RAAF::Models::MultiProvider.new(
  providers: Hash,                     # Provider mappings
  default_provider: String             # Default provider name
)
```

### Model Interface

All providers implement:

```ruby
provider.chat_completion(
  messages: Array,                     # Conversation messages
  model: String,                       # Model name
  tools: Array,                        # Available tools
  stream: Boolean,                     # Enable streaming
  **kwargs                            # Additional parameters
)

provider.stream_completion(...)        # Streaming version
provider.supported_models             # List supported models
provider.provider_name                # Provider identifier
```

## Error Handling

### Custom Exceptions

```ruby
RAAF::Error                    # Base error class
RAAF::APIError                 # API-related errors
RAAF::AuthenticationError      # Authentication failures
RAAF::RateLimitError           # Rate limit exceeded
RAAF::TimeoutError             # Request timeout
RAAF::ValidationError          # Input validation errors
RAAF::Guardrails::GuardrailError # Guardrail violations
```

### Example Error Handling

```ruby
begin
  result = runner.run(messages)
rescue RAAF::RateLimitError => e
  puts "Rate limit exceeded: #{e.message}"
  sleep(60)  # Wait before retry
rescue RAAF::Guardrails::GuardrailError => e
  puts "Input blocked by guardrails: #{e.message}"
rescue RAAF::APIError => e
  puts "API error: #{e.message}"
end
```

## Return Types

### RunResult

```ruby
result.messages                        # Array of conversation messages
result.last_agent                      # Agent that produced final response
result.turns                          # Number of conversation turns
result.usage                          # Token usage statistics
result.trace_id                       # Associated trace identifier
```

### Message Format

```ruby
{
  role: "user" | "assistant" | "tool",  # Message role
  content: String,                      # Message content
  tool_calls: Array,                    # Tool calls (if any)
  tool_call_id: String                  # Tool call identifier (for tool messages)
}
```

For complete examples and usage patterns, see the [Getting Started Guide](GETTING_STARTED.md) and [Examples](EXAMPLES.md).