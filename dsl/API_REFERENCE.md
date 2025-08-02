# AI Agent DSL - API Reference

Complete API reference for the AI Agent DSL gem.

## Core Classes

### `RAAF::DSL::Agent`

Unified agent class for the RAAF DSL framework. Combines all features from Base and SmartAgent into a single, powerful agent implementation that provides:
- Declarative agent configuration with DSL
- Automatic retry logic with configurable strategies
- Circuit breaker pattern for fault tolerance
- Context validation and requirements
- Built-in error handling and categorization
- Automatic result parsing and extraction
- Schema building with inline DSL

#### Constructor

```ruby
def initialize(context: nil, context_variables: nil, processing_params: {}, debug: nil)
  # Supports both context and context_variables parameters
  # Context is unified - no separate context_variables
  @context = ContextVariables.new(context || context_variables || {})
  @processing_params = processing_params
  @debug_enabled = debug
end
```

**Parameters:**
- `context` (Hash, ContextVariables) - Context data that flows through the agent workflow
- `context_variables` (Hash, ContextVariables) - Alternative parameter name for context (backward compatibility)
- `processing_params` (Hash) - Processing parameters for agent execution
- `debug` (Boolean) - Enable debug logging for this agent instance

#### Instance Methods

##### `#create_agent`
Creates an OpenAI agent instance with tracing support.

**Returns:** OpenAI agent instance configured with the agent's settings

##### `#run(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false)`
Executes the agent with optional smart features (retry, circuit breaker, etc.).

**Parameters:**
- `context` (Hash, ContextVariables) - Context to use (overrides instance context)
- `input_context_variables` (Hash, ContextVariables) - Alternative parameter name for context
- `stop_checker` (Proc) - Optional stop checker for execution control
- `skip_retries` (Boolean) - Skip retry/circuit breaker logic (default: false)

**Returns:** Hash containing agent execution results

**Behavior:**
- If agent has smart features configured (retry, circuit breaker, validation), they are used by default
- Pass `skip_retries: true` to bypass smart features and execute directly
- Automatically logs execution start/completion for agents with smart features

##### `#agent_name`
Gets the agent name for configuration lookup.

**Returns:** String agent name

##### `#model_name`
Gets the configured model name from configuration or defaults.

**Returns:** String model name (e.g., "gpt-4o", "gpt-4o-mini")

##### `#max_turns`
Gets the configured maximum conversation turns.

**Returns:** Integer maximum turns

##### Template Methods (Override in Subclasses)

- `#build_instructions` - Build agent instructions
- `#build_schema` - Build response schema

---

### DSL Methods (Built into Agent)

The unified `RAAF::DSL::Agent` class includes all DSL methods for declarative agent configuration. These methods are available directly when inheriting from Agent.

#### Configuration Methods

##### `agent_name(name)`
Sets the agent name for configuration lookup.

**Parameters:**
- `name` (String) - The agent name

**Example:**
```ruby
class MyAgent < RAAF::DSL::Agent
  
  agent_name "MyCustomAgent"
end
```

##### `model(model_name)`
Sets the AI model to use.

**Parameters:**
- `model_name` (String) - OpenAI model name

**Example:**
```ruby
model "gpt-4o"
```

##### `max_turns(count)`
Sets the maximum conversation turns.

**Parameters:**
- `count` (Integer) - Maximum number of turns

**Example:**
```ruby
max_turns 5
```

##### `description(text)`
Sets the agent description.

**Parameters:**
- `text` (String) - Agent description

#### Tool Integration

##### `uses_tool(tool_name, options = {})`
Adds a tool integration to the agent.

**Parameters:**
- `tool_name` (Symbol) - Name of the tool
- `options` (Hash) - Tool-specific options

**Example:**
```ruby
uses_tool :web_search, timeout: 30, max_results: 10
uses_tool :database_query, connection: :primary
```

##### `uses_tools(*tool_names)`
Adds multiple tools at once.

**Parameters:**
- `tool_names` (Array<Symbol>) - Array of tool names

#### Schema Definition

##### `schema(&block)`
Defines the response schema using a builder DSL.

**Example:**
```ruby
schema do
  field :results, type: :array, required: true
  field :summary, type: :string
  field :confidence, type: :integer, range: 0..100
end
```

#### Smart Features Configuration

##### `requires(*keys)`
Declares required context keys that must be present.

**Parameters:**
- `keys` (Array<Symbol>) - Required context key names

**Example:**
```ruby
class MyAgent < RAAF::DSL::Agent
  requires :api_key, :endpoint
end
```

##### `validates(key, **rules)`
Adds validation rules for context values.

**Parameters:**
- `key` (Symbol) - Context key to validate
- `rules` (Hash) - Validation rules (type, presence, etc.)

**Example:**
```ruby
validates :api_key, type: String, presence: true
validates :score, type: Integer, validate: -> (v) { v.between?(0, 100) }
```

##### `retry_on(error_type, max_attempts: 3, backoff: :linear, delay: 1)`
Configures retry behavior for specific error types.

**Parameters:**
- `error_type` (Symbol, Class) - Error type to retry on
- `max_attempts` (Integer) - Maximum retry attempts
- `backoff` (Symbol) - Backoff strategy (:linear, :exponential)
- `delay` (Integer) - Base delay in seconds

**Example:**
```ruby
retry_on :rate_limit, max_attempts: 3, backoff: :exponential
retry_on Timeout::Error, max_attempts: 2
```

##### `circuit_breaker(threshold: 5, timeout: 60, reset_timeout: 300)`
Configures circuit breaker pattern for fault tolerance.

**Parameters:**
- `threshold` (Integer) - Failure threshold before opening circuit
- `timeout` (Integer) - Timeout for each attempt
- `reset_timeout` (Integer) - Time before attempting to close circuit

##### `system_prompt(prompt = nil, &block)`
Defines the system prompt with string or block.

**Example:**
```ruby
system_prompt "You are a helpful assistant"

# Or with block for dynamic prompts
system_prompt do |ctx|
  "You are analyzing #{ctx.get(:document_type)} documents"
end
```

##### `user_prompt(prompt = nil, &block)`
Defines the user prompt with string or block.

#### Workflow Management

##### `hands_off_to(agent_class, options = {})`
Defines agent handoff in workflows.

**Parameters:**
- `agent_class` (Class) - Target agent class
- `options` (Hash) - Handoff options

#### Hook Methods


---

### `RAAF::DSL::Prompts::Base`

Base class for structured prompt management with variable contracts and context mapping.

#### Constructor

```ruby
def initialize(**kwargs)
  @variables = kwargs
end
```

**Parameters:**
- `kwargs` (Hash) - Context and variable data

#### Class Methods

##### `requires(*variables)`
Declares required variables for the prompt.

**Parameters:**
- `variables` (Array<Symbol>) - Required variable names

**Example:**
```ruby
class MyPrompt < RAAF::DSL::Prompts::Base
  required :company_name, :analysis_type
  
  def system
    "System prompt with #{@company_name}"
  end
  
  def user
    "User prompt for #{@analysis_type}"
  end
end
```

##### `requires_from_context(var, path:, default: nil)`
Maps context variables with path navigation.

**Parameters:**
- `var` (Symbol) - Variable name
- `path` (Array) - Path to navigate in context
- `default` (Any) - Default value if path not found

**Example:**
```ruby
requires_from_context :company_name, path: [:company, :name]
requires_from_context :industry, path: [:company, :industry], default: "Unknown"
```

##### `optional_from_context(var, path:, default: nil)`
Maps optional context variables.

**Parameters:**
- `var` (Symbol) - Variable name  
- `path` (Array) - Path to navigate in context
- `default` (Any) - Default value if path not found

##### `contract_mode(mode)`
Sets the validation mode for variable contracts.

**Parameters:**
- `mode` (Symbol) - Validation mode (:strict, :warn, :lenient)

**Example:**
```ruby
contract_mode :strict  # Raises errors for missing required variables
```

#### Instance Methods

##### `#system`
Defines the system prompt. Override in subclasses.

**Returns:** String system prompt

**Example:**
```ruby
def system
  <<~SYSTEM
    You are analyzing #{company_name} in the #{industry} industry.
    Focus on #{analysis_type} analysis.
  SYSTEM
end
```

##### `#user`
Defines the user prompt. Override in subclasses.

**Returns:** String user prompt

##### `#render(type = :both)`
Renders the specified prompt type.

**Parameters:**
- `type` (Symbol) - Prompt type (:system, :user, :both)

**Returns:** String rendered prompt

##### `#context`
Provides access to the stored context.

**Returns:** Hash context data

---

### `RAAF::DSL::Config`

Configuration management class for environment-aware agent settings.

#### Class Methods

##### `.for_agent(agent_name, environment: nil)`
Gets complete configuration for an agent.

**Parameters:**
- `agent_name` (String) - Agent name
- `environment` (String) - Environment name (defaults to Rails.env)

**Returns:** Hash agent configuration

**Example:**
```ruby
config = RAAF::DSL::Config.for_agent("DocumentAnalyzer")
# => { model: "gpt-4o", max_turns: 5, temperature: 0.7 }
```

##### `.model_for(agent_name)`
Gets the model name for an agent.

**Parameters:**
- `agent_name` (String) - Agent name

**Returns:** String model name

##### `.max_turns_for(agent_name)`
Gets the maximum turns for an agent.

**Parameters:**
- `agent_name` (String) - Agent name

**Returns:** Integer maximum turns

##### `.temperature_for(agent_name)`
Gets the temperature setting for an agent.

**Parameters:**
- `agent_name` (String) - Agent name

**Returns:** Float temperature value

##### `.reload!`
Reloads configuration from the YAML file.

**Returns:** Hash reloaded configuration

**Example:**
```ruby
# Useful in development when config file changes
config = RAAF::DSL::Config.reload!
puts "Config reloaded: #{config.inspect}"
```

---

### `RAAF::DSL::Tools::Base`

Base class for AI tool integration.

#### Constructor

```ruby
def initialize(**options)
  @options = options
end
```

**Parameters:**
- `options` (Hash) - Tool configuration options

#### Class Methods

##### `tool_name(name)`
Sets the tool name.

**Parameters:**
- `name` (String) - Tool name

##### `parameter(name, options = {})`
Defines a tool parameter.

**Parameters:**
- `name` (Symbol) - Parameter name
- `options` (Hash) - Parameter options (type, required, default, etc.)

#### Instance Methods

##### `#execute(**params)`
Executes the tool with given parameters.

**Parameters:**
- `params` (Hash) - Execution parameters

**Returns:** Hash execution results

---

### `RAAF::DSL::ToolDsl`

Module providing DSL methods for tool definition.

#### Parameter Definition

##### `parameter(name, options = {})`
Defines a tool parameter with validation.

**Parameters:**
- `name` (Symbol) - Parameter name
- `options` (Hash) - Parameter configuration

**Options:**
- `type` (Symbol) - Parameter type (:string, :integer, :boolean, etc.)
- `required` (Boolean) - Whether parameter is required
- `default` (Any) - Default value
- `enum` (Array) - Allowed values
- `range` (Range) - Numeric range validation
- `format` (Regexp) - String format validation

**Example:**
```ruby
class MyTool < RAAF::DSL::Tools::Base
  include RAAF::DSL::ToolDsl
  
  parameter :query, type: :string, required: true
  parameter :limit, type: :integer, default: 10, range: 1..100
  parameter :format, type: :string, enum: ["json", "xml", "csv"]
end
```

#### Validation

##### `validates(param, options = {})`
Adds custom validation for a parameter.

**Parameters:**
- `param` (Symbol) - Parameter name
- `options` (Hash) - Validation options

**Example:**
```ruby
validates :email, format: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
validates :age, numericality: { greater_than: 0, less_than: 150 }
```

#### Execution Control

##### `execution_timeout(seconds)`
Sets execution timeout.

**Parameters:**
- `seconds` (Integer) - Timeout in seconds


---

## Error Classes

### `RAAF::DSL::Error`
Base error class for all gem-specific errors.

### `RAAF::DSL::ConfigurationError`
Raised when configuration is invalid or missing.

### `RAAF::DSL::ValidationError`
Raised when validation fails.

### `RAAF::DSL::VariableContractError`
Raised when prompt variable contracts are violated.

### `RAAF::DSL::ToolExecutionError`
Raised when tool execution fails.

---

## Configuration Schema

### Agent Configuration Structure

```yaml
environment_name:
  global:
    model: "gpt-4o"
    max_turns: 3
    temperature: 0.7
    timeout: 120
  
  agents:
    agent_name:
      model: "gpt-4o-mini"    # Override global
      max_turns: 5            # Override global
      temperature: 0.5        # Override global
```

### Supported Configuration Keys

- `model` (String) - OpenAI model name
- `max_turns` (Integer) - Maximum conversation turns
- `temperature` (Float) - Response creativity (0.0-2.0)
- `timeout` (Integer) - Request timeout in seconds
- `top_p` (Float) - Nucleus sampling parameter
- `frequency_penalty` (Float) - Frequency penalty (-2.0 to 2.0)
- `presence_penalty` (Float) - Presence penalty (-2.0 to 2.0)

---

## Constants

### Default Values

```ruby
RAAF::DSL::DEFAULT_MODEL = "gpt-4o"
RAAF::DSL::DEFAULT_MAX_TURNS = 3
RAAF::DSL::DEFAULT_TEMPERATURE = 0.7
RAAF::DSL::DEFAULT_TIMEOUT = 120
```

### Supported Models

```ruby
RAAF::DSL::SUPPORTED_MODELS = [
  "gpt-4o",
  "gpt-4o-mini", 
  "gpt-4-turbo",
  "gpt-3.5-turbo"
]
```