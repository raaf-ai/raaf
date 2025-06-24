# API Reference

Complete Ruby API documentation for OpenAI Agents.

## Table of Contents

1. [Agent Class](#agent-class)
2. [Runner Classes](#runner-classes)
3. [Tools](#tools)
4. [Structured Output](#structured-output)
5. [Tracing](#tracing)
6. [Guardrails](#guardrails)
7. [Configuration](#configuration)
8. [Usage Tracking](#usage-tracking)
9. [Extensions](#extensions)
10. [Voice](#voice)
11. [Models](#models)

## Agent Class

The core agent class for creating AI agents.

### Constructor

```ruby
OpenAIAgents::Agent.new(
  name: String,                    # Required: Unique agent identifier
  instructions: String,            # Optional: System prompt/behavior
  model: String,                   # Optional: LLM model (default: "gpt-4")
  max_turns: Integer,              # Optional: Max conversation turns (default: 10)
  tools: Array,                    # Optional: Pre-configured tools
  handoffs: Array,                 # Optional: Pre-configured handoff agents
  output_schema: Hash              # Optional: JSON schema for structured output
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
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4"
)

# Agent with tools and handoffs
agent = OpenAIAgents::Agent.new(
  name: "Support",
  instructions: "Handle customer support inquiries.",
  model: "gpt-4",
  max_turns: 15,
  tools: [lookup_order_tool],
  handoffs: [technical_agent]
)
```

## Runner Classes

### Runner

Synchronous agent execution.

```ruby
# Constructor
OpenAIAgents::Runner.new(
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
OpenAIAgents::StreamingRunner.new(agent: agent)

# Methods
runner.run_streaming(messages) do |chunk|
  # Handle streaming chunks
end
```

### Examples

```ruby
# Basic execution
runner = OpenAIAgents::Runner.new(agent: agent)
result = runner.run("Hello, help me with my order")

# With configuration
config = OpenAIAgents::RunConfig.new(
  max_turns: 5,
  trace_include_sensitive_data: false
)
result = runner.run(messages, config: config)

# Streaming
streaming_runner = OpenAIAgents::StreamingRunner.new(agent: agent)
streaming_runner.run_streaming(messages) do |chunk|
  case chunk[:type]
  when "content"
    print chunk[:content]
  when "tool_call"
    puts "\nTool: #{chunk[:tool_call]}"
  end
end
```

## Tools

### FunctionTool

Wrapper for custom functions.

```ruby
# Constructor
OpenAIAgents::FunctionTool.new(
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

### Built-in Tools

#### FileSearchTool

```ruby
OpenAIAgents::Tools::FileSearchTool.new(
  search_paths: Array[String],     # Directories to search
  file_extensions: Array[String],  # File types to include
  max_results: Integer,            # Maximum results (default: 10)
  exclude_patterns: Array[String]  # Patterns to exclude
)
```

#### WebSearchTool

```ruby
OpenAIAgents::Tools::WebSearchTool.new(
  search_engine: String,           # "duckduckgo", "google", "bing"
  max_results: Integer,            # Maximum results (default: 5)
  api_key: String                 # Optional: API key for premium engines
)
```

#### ComputerTool

```ruby
OpenAIAgents::Tools::ComputerTool.new(
  allowed_actions: Array[Symbol],  # [:screenshot, :click, :type, :scroll]
  screen_size: Hash               # { width: 1920, height: 1080 }
)
```

#### CodeInterpreterTool

```ruby
OpenAIAgents::Tools::CodeInterpreterTool.new(
  allowed_languages: Array[String], # ["python", "ruby", "javascript"]
  timeout: Integer,                # Execution timeout (default: 30)
  memory_limit: Integer           # Memory limit in MB (default: 128)
)
```

### Example Tool Creation

```ruby
# Simple function tool
def get_weather(city)
  "The weather in #{city} is sunny"
end

weather_tool = OpenAIAgents::FunctionTool.new(
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

Schema-based output validation and enforcement for consistent agent responses.

### BaseSchema

Core schema validation class.

```ruby
# Constructor
OpenAIAgents::StructuredOutput::BaseSchema.new(schema)

# Methods
schema.validate(data)                    # Validate data against schema
schema.to_h                             # Get schema as hash
schema.to_json                          # Get schema as JSON string
```

### ObjectSchema

Builder class for object schemas.

```ruby
# Constructor
OpenAIAgents::StructuredOutput::ObjectSchema.new(
  properties: Hash,                     # Property definitions
  required: Array,                      # Required property names
  additional_properties: Boolean        # Allow additional properties
)

# Builder Pattern
schema = OpenAIAgents::StructuredOutput::ObjectSchema.build do
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
OpenAIAgents::StructuredOutput::ArraySchema.new(
  items: Hash,                          # Schema for array items
  min_items: Integer,                   # Minimum array length
  max_items: Integer                    # Maximum array length
)
```

### StringSchema

Schema for string validation.

```ruby
OpenAIAgents::StructuredOutput::StringSchema.new(
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
formatter = OpenAIAgents::StructuredOutput::ResponseFormatter.new(schema)

# Methods
formatter.format_response(data)         # Validate and format data
formatter.validate_and_format(json_string)  # Parse JSON and validate
```

### StrictSchema

Utilities for strict schema compliance (OpenAI requirement).

```ruby
# Ensure schema meets OpenAI strict requirements
strict_schema = OpenAIAgents::StrictSchema.ensure_strict_json_schema(schema)

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
agent = OpenAIAgents::Agent.new(
  name: "DataExtractor",
  instructions: "Extract information as JSON.",
  model: "gpt-4o",
  output_schema: schema
)

# Validation
validator = OpenAIAgents::StructuredOutput::BaseSchema.new(schema)
begin
  validated_data = validator.validate(response_data)
  puts "Valid: #{validated_data}"
rescue OpenAIAgents::StructuredOutput::ValidationError => e
  puts "Invalid: #{e.message}"
end

# Complex schema with builder
user_schema = OpenAIAgents::StructuredOutput::ObjectSchema.build do
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
profile_agent = OpenAIAgents::Agent.new(
  name: "ProfileExtractor",
  instructions: "Extract user profile information.",
  model: "gpt-4o",
  output_schema: user_schema.to_h
)
```

### Error Handling

```ruby
# Custom exceptions
OpenAIAgents::StructuredOutput::ValidationError   # Schema validation failed
OpenAIAgents::StructuredOutput::SchemaError      # Invalid schema definition

# Usage
begin
  result = runner.run(messages)
  response = result.messages.last[:content]
  data = JSON.parse(response)
  validated = schema.validate(data)
rescue JSON::ParserError => e
  puts "Invalid JSON: #{e.message}"
rescue OpenAIAgents::StructuredOutput::ValidationError => e
  puts "Schema validation failed: #{e.message}"
rescue OpenAIAgents::StructuredOutput::SchemaError => e
  puts "Invalid schema: #{e.message}"
end
```

## Tracing

### SpanTracer

Main tracing interface.

```ruby
# Constructor
OpenAIAgents::Tracing::SpanTracer.new(provider: nil)

# Processor Management
tracer.add_processor(processor)          # Add span processor
tracer.processors                       # Get all processors

# Span Creation
tracer.start_span(name, kind: :internal, **attributes) do |span|
  # Your code here
end

# Convenience Methods
tracer.agent_span(agent_name, **attributes) { }     # Agent execution span
tracer.tool_span(tool_name, **attributes) { }       # Tool execution span
tracer.llm_span(model_name, **attributes) { }       # LLM call span
tracer.handoff_span(from, to, **attributes) { }     # Agent handoff span
tracer.custom_span(name, data = {}, **attributes) { } # Custom span

# Span Management
tracer.current_span                     # Get current active span
tracer.finish_span(span = nil)          # Finish a span
tracer.add_event(name, **attributes)    # Add event to current span
tracer.set_attribute(key, value)        # Set attribute on current span

# Export and Utilities
tracer.export_spans(format: :json)      # Export spans as JSON/Hash
tracer.trace_summary                    # Get trace summary
tracer.clear                           # Clear all spans
tracer.flush                           # Flush processors
```

### Span Processors

#### ConsoleSpanProcessor
```ruby
processor = OpenAIAgents::Tracing::ConsoleSpanProcessor.new
tracer.add_processor(processor)
```

#### FileSpanProcessor
```ruby
processor = OpenAIAgents::Tracing::FileSpanProcessor.new("traces.jsonl")
tracer.add_processor(processor)
```

#### OpenAIProcessor
```ruby
processor = OpenAIAgents::Tracing::OpenAIProcessor.new(api_key: "sk-...")
tracer.add_processor(processor)
```

#### MemorySpanProcessor
```ruby
processor = OpenAIAgents::Tracing::MemorySpanProcessor.new
tracer.add_processor(processor)
spans = processor.spans  # Access collected spans
```

### Span Objects

```ruby
# Span attributes
span.span_id                           # Unique span identifier
span.trace_id                          # Parent trace identifier
span.parent_id                         # Parent span identifier
span.name                              # Span name
span.kind                              # Span kind (:agent, :llm, :tool, etc.)
span.start_time                        # Start timestamp
span.end_time                          # End timestamp
span.attributes                        # Key-value attributes
span.events                            # Time-stamped events
span.status                            # Status (:ok, :error, :cancelled)

# Span methods
span.set_attribute(key, value)         # Set attribute
span.add_event(name, attributes: {})   # Add event
span.set_status(status, description: nil) # Set status
span.finish(end_time: nil)             # Mark as finished
span.finished?                         # Check if finished
span.duration                          # Duration in seconds
span.to_h                              # Convert to hash
span.to_json                           # Convert to JSON
```

## Guardrails

### GuardrailManager

Central guardrail management.

```ruby
# Constructor
OpenAIAgents::Guardrails::GuardrailManager.new

# Guardrail Management
manager.add_guardrail(guardrail)       # Add guardrail
manager.remove_guardrail(name)         # Remove guardrail
manager.guardrails                     # Get all guardrails

# Validation
manager.validate_input(input)          # Validate input
manager.validate_output(output)        # Validate output
manager.validate_tool_call(name, args) # Validate tool call
```

### Built-in Guardrails

#### ContentSafetyGuardrail
```ruby
OpenAIAgents::Guardrails::ContentSafetyGuardrail.new(
  strict_mode: false,                  # Enable strict filtering
  block_categories: Array[Symbol],     # Categories to block
  custom_filters: Array[Proc]          # Custom filter functions
)
```

#### RateLimitGuardrail
```ruby
OpenAIAgents::Guardrails::RateLimitGuardrail.new(
  max_requests_per_minute: 60,         # Rate limit
  max_requests_per_hour: 1000,         # Hourly limit
  max_requests_per_day: 10000          # Daily limit
)
```

#### LengthGuardrail
```ruby
OpenAIAgents::Guardrails::LengthGuardrail.new(
  max_input_length: 10000,             # Max input length
  max_output_length: 5000,             # Max output length
  max_tool_input_length: 1000          # Max tool input length
)
```

#### SchemaGuardrail
```ruby
OpenAIAgents::Guardrails::SchemaGuardrail.new(
  input_schema: Hash,                  # Input validation schema
  output_schema: Hash                  # Output validation schema
)
```

### Custom Guardrails

```ruby
class CustomGuardrail < OpenAIAgents::Guardrails::BaseGuardrail
  def validate_input(input)
    # Custom validation logic
    raise OpenAIAgents::Guardrails::GuardrailError, "Invalid input" if invalid?
  end
  
  def validate_output(output)
    # Custom output validation
  end
end
```

## Configuration

### Configuration Class

```ruby
# Constructor
OpenAIAgents::Configuration.new(environment: "development")

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
ENV['OPENAI_AGENTS_DISABLE_TRACING']   # Disable tracing
ENV['OPENAI_AGENTS_TRACE_DEBUG']       # Enable trace debugging
ENV['OPENAI_AGENTS_TRACE_BATCH_SIZE']  # Batch size for exports
```

## Usage Tracking

### UsageTracker

```ruby
# Constructor
OpenAIAgents::UsageTracking::UsageTracker.new

# Alert Management
tracker.add_alert(name) { |usage| condition }  # Add usage alert
tracker.remove_alert(name)                     # Remove alert
tracker.check_alerts                           # Check all alerts

# Tracking Methods
tracker.track_api_call(
  provider: String,                    # Provider name
  model: String,                       # Model used
  tokens_used: Hash,                   # Token counts
  cost: Float,                         # API cost
  duration: Float                      # Request duration
)

tracker.track_agent_interaction(
  agent_name: String,                  # Agent name
  user_id: String,                     # User identifier
  session_id: String,                  # Session identifier
  duration: Float,                     # Interaction duration
  satisfaction_score: Float,           # User satisfaction
  outcome: Symbol                      # :resolved, :escalated, etc.
)

# Analytics
tracker.analytics(period, group_by: nil)       # Get analytics data
tracker.generate_report(period, options)       # Generate usage report
tracker.dashboard_data                         # Get dashboard data
```

### Usage Analytics

```ruby
# Get analytics for different periods
analytics = tracker.analytics(:today)
analytics = tracker.analytics(:week)
analytics = tracker.analytics(:month)

# Analytics structure
{
  api_calls: {
    count: Integer,
    total_tokens: Integer,
    average_duration: Float
  },
  costs: {
    total: Float,
    by_provider: Hash,
    by_model: Hash
  },
  agent_interactions: {
    count: Integer,
    average_satisfaction: Float,
    outcome_distribution: Hash
  }
}
```

## Extensions

### Extension System

```ruby
# Define Extension
class MyExtension < OpenAIAgents::Extensions::BaseExtension
  def self.extension_info
    {
      name: :my_extension,
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

# Load and Activate
OpenAIAgents::Extensions.load_extension(MyExtension)
OpenAIAgents::Extensions.activate(:my_extension, config)

# Inline Registration
OpenAIAgents::Extensions.register(:weather_tool) do |ext|
  ext.name = "Weather Tool"
  ext.type = :tool
  ext.setup { |config| puts "Weather tool configured" }
end
```

## Voice

### VoiceWorkflow

```ruby
# Constructor
OpenAIAgents::Voice::VoiceWorkflow.new(
  transcription_model: "whisper-1",    # Speech-to-text model
  tts_model: "tts-1-hd",              # Text-to-speech model
  voice: "nova"                       # Voice selection
)

# Audio Processing
workflow.process_audio_file(file_path, agent)    # Process audio file
workflow.transcribe_audio(file_path)             # Transcribe only
workflow.synthesize_speech(text)                 # Generate speech
workflow.play_audio(file_path)                   # Play audio file

# Streaming
workflow.start_streaming_session(agent) do |session|
  session.on_transcription { |text| ... }
  session.on_response { |text| ... }
  session.on_audio { |audio_file| ... }
end
```

## Models

### Model Providers

#### ResponsesProvider (Default)
```ruby
OpenAIAgents::Models::ResponsesProvider.new(
  api_key: String,                     # OpenAI API key
  api_base: String                     # Optional: Custom API base
)
```

#### OpenAIProvider
```ruby
OpenAIAgents::Models::OpenAIProvider.new(
  api_key: String,                     # OpenAI API key
  api_base: String,                    # Optional: Custom API base
  timeout: Integer                     # Request timeout
)
```

#### AnthropicProvider
```ruby
OpenAIAgents::Models::AnthropicProvider.new(
  api_key: String,                     # Anthropic API key
  timeout: Integer                     # Request timeout
)
```

#### MultiProvider
```ruby
OpenAIAgents::Models::MultiProvider.new(
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
OpenAIAgents::Error                    # Base error class
OpenAIAgents::APIError                 # API-related errors
OpenAIAgents::AuthenticationError      # Authentication failures
OpenAIAgents::RateLimitError           # Rate limit exceeded
OpenAIAgents::TimeoutError             # Request timeout
OpenAIAgents::ValidationError          # Input validation errors
OpenAIAgents::Guardrails::GuardrailError # Guardrail violations
```

### Example Error Handling

```ruby
begin
  result = runner.run(messages)
rescue OpenAIAgents::RateLimitError => e
  puts "Rate limit exceeded: #{e.message}"
  sleep(60)  # Wait before retry
rescue OpenAIAgents::Guardrails::GuardrailError => e
  puts "Input blocked by guardrails: #{e.message}"
rescue OpenAIAgents::APIError => e
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