**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf-ai.dev>.**

RAAF API Reference
==================

This is a comprehensive API reference for Ruby AI Agents Factory (RAAF). This guide covers all public classes, methods, and configuration options available in the RAAF framework.

**How to use this reference:** This document serves as both a quick reference for experienced developers and a detailed specification for those implementing integrations. Each API entry includes not just the method signature, but the reasoning behind parameter choices and practical usage considerations.

The API design follows Ruby conventions while optimizing for AI agent use cases. Method names are descriptive, parameters use keyword arguments for clarity, and return values are consistently structured. Error handling follows Ruby patterns with meaningful exception types and messages.

**Design philosophy:** The RAAF API prioritizes clarity over brevity. Parameter names are explicit (`instructions` rather than `prompt`), method names describe intent (`add_tool` rather than `add`), and configuration options are grouped logically. This verbosity pays dividends in maintainability and reduces the cognitive load of working with AI systems.

After reading this reference, you will know:

* All public API methods and their parameters
* Configuration options for each component
* Return types and error handling
* Code examples for common usage patterns

--------------------------------------------------------------------------------

Core Classes
------------

### RAAF::Agent

The main agent class for creating AI agents.

**Architectural role:** The Agent class is a specification, not a runtime entity. It defines what an agent should do (instructions), what capabilities it has (tools), and how it should behave (model settings). The actual execution happens through the Runner class, which uses the Agent as a blueprint.

This separation enables powerful patterns: the same agent definition can be used across multiple conversations simultaneously, agents can be serialized and stored, and agent configurations can be tested independently of their runtime behavior.

#### Constructor

```ruby
RAAF::Agent.new(
  name: String,
  instructions: String,
  model: String,
  tools: Array = [],
  tool_choice: String = "auto",
  parallel_tool_calls: Boolean = true
)
```

**Parameters:**

* `name` (String, required) - Unique identifier for the agent
* `instructions` (String, required) - System instructions for the agent
* `model` (String, required) - AI model to use (e.g., "gpt-4o", "claude-3-5-sonnet-20241022")
* `tools` (Array, optional) - Array of tool functions to add to the agent
* `tool_choice` (String, optional) - Tool selection strategy: "auto", "none", or specific tool name
* `parallel_tool_calls` (Boolean, optional) - Whether to allow parallel tool execution

**Example:**

```ruby
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful AI assistant",
  model: "gpt-4o"
)
```

#### Instance Methods

##### #add_tool(tool_function, name: nil, description: nil)

Adds a tool function to the agent.

**Parameters:**

* `tool_function` (Method|Proc|Lambda, required) - The tool function to add
* `name` (String, optional) - Custom name for the tool (defaults to function name)
* `description` (String, optional) - Custom description for the tool

**Returns:** `self` (for method chaining)

**Example:**

```ruby
def get_weather(location:)
  "Weather in #{location}: sunny, 72°F"
end

agent.add_tool(method(:get_weather))
agent.add_tool(lambda { |query:| "Search results for: #{query}" }, name: "web_search")
```

##### #remove_tool(tool_name)

Removes a tool from the agent.

**Parameters:**

* `tool_name` (String, required) - Name of the tool to remove

**Returns:** `Boolean` - true if tool was removed, false if not found

##### #tools

Returns the list of tools available to the agent.

**Returns:** `Array<Hash>` - Array of tool definitions

##### #model=(new_model)

Changes the AI model used by the agent.

**Parameters:**

* `new_model` (String, required) - New model name

##### #instructions=(new_instructions)

Updates the agent's system instructions.

**Parameters:**

* `new_instructions` (String, required) - New system instructions

### RAAF::Runner

Handles conversation execution with agents.

#### Constructor

```ruby
RAAF::Runner.new(
  agent: RAAF::Agent,
  agents: Array = [],
  context_variables: Hash = {},
  max_turns: Integer = 25,
  execute_tools: Boolean = true,
  provider: Provider = nil,
  tracer: Tracer = nil,
  memory_manager: MemoryManager = nil
)
```

**Parameters:**

* `agent` (RAAF::Agent, required) - Primary agent to use
* `agents` (Array, optional) - Additional agents for handoffs
* `context_variables` (Hash, optional) - Persistent context variables
* `max_turns` (Integer, optional) - Maximum conversation turns
* `execute_tools` (Boolean, optional) - Whether to automatically execute tools
* `provider` (Provider, optional) - AI model provider (defaults to ResponsesProvider)
* `tracer` (Tracer, optional) - Tracing/monitoring system
* `memory_manager` (MemoryManager, optional) - Memory management system

#### Instance Methods

##### #run(message, agent: nil, context_variables: {}, stream: false, debug: false)

Executes a conversation turn.

**Parameters:**

* `message` (String, required) - User message to process
* `agent` (RAAF::Agent, optional) - Override default agent
* `context_variables` (Hash, optional) - Additional context for this turn
* `stream` (Boolean, optional) - Enable streaming responses
* `debug` (Boolean, optional) - Enable debug logging

**Returns:** `RAAF::Response` - Response object with results

**Example:**

```ruby
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Hello, how can you help me?")
puts result.messages.last[:content]
```

##### #run_and_stream(message, &block)

Executes conversation with streaming responses.

**Parameters:**

* `message` (String, required) - User message to process
* `block` (Block, required) - Block to handle streaming chunks

**Yields:** `RAAF::StreamChunk` for each response chunk

**Example:**

```ruby
runner.run_and_stream("Tell me a story") do |chunk|
  print chunk.delta if chunk.type == :content
end
```

### RAAF::Response

Response object containing conversation results.

#### Instance Methods

##### #messages

Returns the conversation messages.

**Returns:** `Array<Hash>` - Array of message objects

##### #agent

Returns the final agent that handled the conversation.

**Returns:** `RAAF::Agent`

##### #context_variables

Returns the updated context variables.

**Returns:** `Hash`

##### #success?

Checks if the conversation completed successfully.

**Returns:** `Boolean`

##### #error

Returns error information if the conversation failed.

**Returns:** `String|Nil`

##### #tool_calls

Returns the tool calls that were made.

**Returns:** `Array<Hash>`

##### #usage

Returns token usage information.

**Returns:** `Hash` with keys: `:prompt_tokens`, `:completion_tokens`, `:total_tokens`

##### #duration_ms

Returns the conversation duration in milliseconds.

**Returns:** `Integer`

Provider Classes
---------------

### RAAF::Models::ResponsesProvider

Default provider that uses OpenAI's Responses API for 100% Python SDK compatibility.

#### Constructor

```ruby
RAAF::Models::ResponsesProvider.new(
  api_key: String = ENV['OPENAI_API_KEY'],
  organization: String = ENV['OPENAI_ORG_ID'],
  project: String = ENV['OPENAI_PROJECT_ID'],
  base_url: String = "https://api.openai.com/v1"
)
```

### RAAF::Models::OpenAIProvider

**DEPRECATED**: Direct OpenAI Chat Completions API integration. Use ResponsesProvider instead.

#### Constructor

```ruby
RAAF::Models::OpenAIProvider.new(
  api_key: String = ENV['OPENAI_API_KEY'],
  api_base: String = ENV['OPENAI_API_BASE'] || "https://api.openai.com/v1"
)
```

### RAAF::Models::AnthropicProvider

Anthropic Claude API integration.

#### Constructor

```ruby
RAAF::Models::AnthropicProvider.new(
  api_key: String = ENV['ANTHROPIC_API_KEY'],
  base_url: String = "https://api.anthropic.com/v1",
  timeout: Integer = 30,
  max_retries: Integer = 3
)
```

### RAAF::Models::GroqProvider

Groq API integration for fast inference.

#### Constructor

```ruby
RAAF::Models::GroqProvider.new(
  api_key: String = ENV['GROQ_API_KEY'],
  base_url: String = "https://api.groq.com/openai/v1",
  timeout: Integer = 30
)
```

### RAAF::Models::LiteLLMProvider

Multi-provider support through LiteLLM.

#### Constructor

```ruby
RAAF::Models::LiteLLMProvider.new(
  base_url: String = "http://localhost:4000",
  api_key: String = nil,
  timeout: Integer = 30
)
```

Memory Classes
--------------

### RAAF::Memory::MemoryManager

Main memory management class.

#### Constructor

```ruby
RAAF::Memory::MemoryManager.new(
  store: Store,
  max_tokens: Integer = 4000,
  pruning_strategy: Symbol = :sliding_window,
  context_variables: Hash = {}
)
```

**Parameters:**

* `store` (Store, required) - Memory storage backend
* `max_tokens` (Integer, optional) - Maximum tokens to maintain
* `pruning_strategy` (Symbol, optional) - Strategy for pruning old messages
* `context_variables` (Hash, optional) - Persistent context variables

#### Instance Methods

##### #add_message(session_id, role, content, metadata: {})

Adds a message to memory.

**Parameters:**

* `session_id` (String, required) - Session identifier
* `role` (String, required) - Message role ("user", "assistant", "system")
* `content` (String, required) - Message content
* `metadata` (Hash, optional) - Additional message metadata

##### #get_messages(session_id, limit: nil)

Retrieves messages for a session.

**Parameters:**

* `session_id` (String, required) - Session identifier
* `limit` (Integer, optional) - Maximum number of messages to return

**Returns:** `Array<Hash>` - Array of message objects

##### #clear_session(session_id)

Clears all messages for a session.

**Parameters:**

* `session_id` (String, required) - Session identifier

##### #update_context(session_id, variables)

Updates context variables for a session.

**Parameters:**

* `session_id` (String, required) - Session identifier
* `variables` (Hash, required) - Context variables to update

### RAAF::Memory::InMemoryStore

In-memory storage backend.

#### Constructor

```ruby
RAAF::Memory::InMemoryStore.new(
  max_size: Integer = nil,
  max_entries: Integer = nil
)
```

### RAAF::Memory::FileStore

File-based storage backend.

#### Constructor

```ruby
RAAF::Memory::FileStore.new(
  directory: String,
  session_id: String,
  compression: Symbol = nil,
  encryption: Hash = nil
)
```

### RAAF::Memory::DatabaseStore

Database storage backend.

#### Constructor

```ruby
RAAF::Memory::DatabaseStore.new(
  model: Class = nil,
  connection: Object = nil,
  table_name: String = nil,
  session_column: String = 'session_id',
  content_column: String = 'content',
  metadata_column: String = 'metadata'
)
```

### RAAF::Memory::VectorStore

Vector-based storage with semantic search.

#### Constructor

```ruby
RAAF::Memory::VectorStore.new(
  backend: Symbol = :openai,
  embedding_model: String = 'text-embedding-3-small',
  dimension: Integer = 1536,
  similarity_threshold: Float = 0.7,
  api_key: String = nil,
  index_name: String = nil
)
```

Tracing Classes
---------------

### RAAF::Tracing::SpanTracer

Main tracing coordinator.

#### Constructor

```ruby
RAAF::Tracing::SpanTracer.new(
  service_name: String = "raaf-agents",
  processors: Array = []
)
```

#### Instance Methods

##### #add_processor(processor)

Adds a trace processor.

**Parameters:**

* `processor` (Processor, required) - Processor to add

##### #start_span(operation_name, attributes: {})

Starts a new trace span.

**Parameters:**

* `operation_name` (String, required) - Name of the operation
* `attributes` (Hash, optional) - Span attributes

**Returns:** `RAAF::Tracing::Span`

### RAAF::Tracing::OpenAIProcessor

Sends traces to OpenAI dashboard.

#### Constructor

```ruby
RAAF::Tracing::OpenAIProcessor.new(
  api_key: String = ENV['OPENAI_API_KEY'],
  organization: String = ENV['OPENAI_ORG_ID'],
  project_id: String = ENV['OPENAI_PROJECT_ID'],
  batch_size: Integer = 100,
  flush_interval: Duration = 30.seconds
)
```

### RAAF::Tracing::ConsoleProcessor

Outputs traces to console.

#### Constructor

```ruby
RAAF::Tracing::ConsoleProcessor.new(
  log_level: Symbol = :info,
  colorize: Boolean = true,
  include_payloads: Boolean = false,
  format: Symbol = :pretty
)
```

DSL Classes
-----------

### RAAF::DSL::AgentBuilder

Declarative agent building.

#### Class Methods

##### .build(&block)

Builds an agent using DSL syntax.

**Parameters:**

* `block` (Block, required) - DSL configuration block

**Returns:** `RAAF::Agent`

**Example:**

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "WebSearchAgent"
  instructions "Help users search the web"
  model "gpt-4o"
  
  use_web_search
  use_file_search
  
  tool :analyze_sentiment do |text|
    { sentiment: "positive", confidence: 0.85 }
  end
end
```

#### DSL Methods (used within build block)

##### name(agent_name)

Sets the agent name.

##### instructions(agent_instructions)

Sets the agent instructions.

##### model(model_name)

Sets the AI model.

##### tool(tool_name, &block)

Defines a custom tool.

##### use_web_search(options = {})

Adds web search capability.

##### use_file_search(options = {})

Adds file search capability.

##### use_code_execution(options = {})

Adds code execution capability.

Testing Classes
---------------

### RAAF::Testing::MockProvider

Mock provider for testing.

#### Constructor

```ruby
RAAF::Testing::MockProvider.new(
  response_delay: Range = nil,
  error_rate: Float = 0.0,
  simulate_tokens: Boolean = false
)
```

#### Instance Methods

##### #add_response(content)

Adds a predefined response.

##### #add_responses(responses)

Adds multiple predefined responses.

##### #add_conditional_response(condition:, response:)

Adds a conditional response.

### RAAF::Testing::ResponseRecorder

Records real API responses for playback.

#### Constructor

```ruby
RAAF::Testing::ResponseRecorder.new(
  output_file: String,
  provider: Provider
)
```

#### Instance Methods

##### #finalize

Writes recorded responses to file.

### RAAF::Testing::PlaybackProvider

Plays back recorded responses.

#### Constructor

```ruby
RAAF::Testing::PlaybackProvider.new(
  fixture_file: String
)
```

Guardrails Classes
------------------

### RAAF::Guardrails::GuardrailManager

Manages security and safety filters.

#### Constructor

```ruby
RAAF::Guardrails::GuardrailManager.new(
  guards: Array = [],
  enforcement_mode: Symbol = :block
)
```

#### Instance Methods

##### #add_guard(guard)

Adds a guardrail.

##### #evaluate(content, context: {})

Evaluates content against all guardrails.

### RAAF::Guardrails::PIIDetector

Detects personally identifiable information.

#### Constructor

```ruby
RAAF::Guardrails::PIIDetector.new(
  detection_model: String = 'en_core_web_sm',
  confidence_threshold: Float = 0.8,
  mask_detected: Boolean = true
)
```

### RAAF::Guardrails::ContentModerator

Moderates content for inappropriate material.

#### Constructor

```ruby
RAAF::Guardrails::ContentModerator.new(
  moderation_model: String = 'text-moderation-latest',
  categories: Array = ['hate', 'harassment', 'violence'],
  threshold: Float = 0.7
)
```

Error Classes
-------------

### RAAF::Errors::AgentError

Base class for agent-related errors.

### RAAF::Errors::ProviderError

Base class for provider-related errors.

### RAAF::Errors::ToolError

Raised when tool execution fails.

### RAAF::Errors::GuardrailViolation

Raised when content violates guardrails.

### RAAF::Errors::RateLimitError

Raised when API rate limits are exceeded.

### RAAF::Errors::AuthenticationError

Raised when API authentication fails.

Configuration
-------------

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENAI_API_KEY` | OpenAI API key | Required |
| `OPENAI_ORG_ID` | OpenAI organization ID | Optional |
| `OPENAI_PROJECT_ID` | OpenAI project ID | Optional |
| `ANTHROPIC_API_KEY` | Anthropic API key | Optional |
| `GROQ_API_KEY` | Groq API key | Optional |
| `RAAF_LOG_LEVEL` | Logging level | `info` |
| `RAAF_DEBUG_CATEGORIES` | Debug categories | None |
| `RAAF_DEFAULT_MODEL` | Default AI model | `gpt-4o` |
| `RAAF_MAX_TOKENS` | Default max tokens | `4000` |

### Global Configuration

```ruby
RAAF.configure do |config|
  config.default_provider = RAAF::Models::ResponsesProvider.new
  config.default_model = "gpt-4o"
  config.max_retries = 3
  config.timeout = 30
  config.log_level = :info
  config.debug_categories = [:api, :tracing]
end
```

Constants
---------

### Model Names

```ruby
RAAF::Models::OPENAI_MODELS = [
  "gpt-4o",
  "gpt-4o-mini", 
  "gpt-4-turbo",
  "gpt-3.5-turbo"
]

RAAF::Models::ANTHROPIC_MODELS = [
  "claude-3-5-sonnet-20241022",
  "claude-3-5-haiku-20241022",
  "claude-3-opus-20240229",
  "claude-3-sonnet-20240229",
  "claude-3-haiku-20240307"
]

RAAF::Models::GROQ_MODELS = [
  "llama-3.1-405b-reasoning",
  "llama-3.1-70b-versatile",
  "mixtral-8x7b-32768"
]
```

### Default Values

```ruby
RAAF::DEFAULT_MAX_TURNS = 25
RAAF::DEFAULT_MAX_TOKENS = 4000
RAAF::DEFAULT_TIMEOUT = 30
RAAF::DEFAULT_MODEL = "gpt-4o"
```

Type Definitions
----------------

### Message Format

```ruby
{
  role: String,        # "user", "assistant", "system", "tool"
  content: String,     # Message content
  name: String,        # Optional: message sender name
  tool_calls: Array,   # Optional: tool calls made
  tool_call_id: String # Optional: for tool responses
}
```

### Tool Call Format

```ruby
{
  id: String,          # Unique tool call ID
  type: String,        # Always "function"
  function: {
    name: String,      # Tool function name
    arguments: String  # JSON string of arguments
  }
}
```

### Usage Format

```ruby
{
  prompt_tokens: Integer,
  completion_tokens: Integer, 
  total_tokens: Integer
}
```

Next Steps
----------

For more detailed information:

* **[Getting Started](getting_started.html)** - Quick start guide
* **[RAAF Core Guide](core_guide.html)** - Core concepts and patterns
* **[Examples Repository](https://github.com/raaf/examples)** - Code examples
* **[Contributing Guide](contributing.html)** - How to contribute to RAAF