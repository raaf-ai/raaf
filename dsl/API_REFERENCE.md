# AI Agent DSL - API Reference

Complete API reference for the AI Agent DSL gem.

## Core Classes

### `AiAgentDsl::Agents::Base`

Base class for all AI agents. Provides the foundation for creating intelligent AI agents with OpenAI integration.

#### Constructor

```ruby
def initialize(context:, processing_params:)
```

**Parameters:**
- `context` (Hash) - Context data that flows through the agent workflow
- `processing_params` (Hash) - Processing parameters for agent execution

#### Instance Methods

##### `#create_agent`
Creates an OpenAI agent instance with tracing support.

**Returns:** OpenAI agent instance configured with the agent's settings

##### `#run`
Executes the agent and returns structured results.

**Returns:** Hash containing agent execution results

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

### `AiAgentDsl::AgentDsl`

Module providing DSL methods for declarative agent configuration. Include this module in your agent classes to access the DSL.

#### Configuration Methods

##### `agent_name(name)`
Sets the agent name for configuration lookup.

**Parameters:**
- `name` (String) - The agent name

**Example:**
```ruby
class MyAgent < AiAgentDsl::Agents::Base
  include AiAgentDsl::AgentDsl
  
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

#### Workflow Management

##### `hands_off_to(agent_class, options = {})`
Defines agent handoff in workflows.

**Parameters:**
- `agent_class` (Class) - Target agent class
- `options` (Hash) - Handoff options

#### Hook Methods


---

### `AiAgentDsl::Prompts::Base`

Base class for structured prompt management with variable contracts and context mapping.

#### Constructor

```ruby
def initialize(**kwargs)
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
class MyPrompt < AiAgentDsl::Prompts::Base
  requires :company_name, :analysis_type
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

### `AiAgentDsl::Config`

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
config = AiAgentDsl::Config.for_agent("DocumentAnalyzer")
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
AiAgentDsl::Config.reload!
```

---

### `AiAgentDsl::Tools::Base`

Base class for AI tool integration.

#### Constructor

```ruby
def initialize(**options)
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

### `AiAgentDsl::ToolDsl`

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
class MyTool < AiAgentDsl::Tools::Base
  include AiAgentDsl::ToolDsl
  
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

### `AiAgentDsl::Error`
Base error class for all gem-specific errors.

### `AiAgentDsl::ConfigurationError`
Raised when configuration is invalid or missing.

### `AiAgentDsl::ValidationError`
Raised when validation fails.

### `AiAgentDsl::VariableContractError`
Raised when prompt variable contracts are violated.

### `AiAgentDsl::ToolExecutionError`
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
AiAgentDsl::DEFAULT_MODEL = "gpt-4o"
AiAgentDsl::DEFAULT_MAX_TURNS = 3
AiAgentDsl::DEFAULT_TEMPERATURE = 0.7
AiAgentDsl::DEFAULT_TIMEOUT = 120
```

### Supported Models

```ruby
AiAgentDsl::SUPPORTED_MODELS = [
  "gpt-4o",
  "gpt-4o-mini", 
  "gpt-4-turbo",
  "gpt-3.5-turbo"
]
```