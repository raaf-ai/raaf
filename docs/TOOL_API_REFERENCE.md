# Tool API Reference

> Version: 1.0.0
> Last Updated: 2025-01-16

## Table of Contents

- [Overview](#overview)
- [RAAF::DSL::Tools::Tool](#raafdsltoolstool)
- [RAAF::DSL::Tools::Tool::API](#raafdsltoolstoolapi)
- [RAAF::DSL::Tools::Tool::Native](#raafdsltoolstoolnative)
- [RAAF::DSL::Tools::ToolRegistry](#raafdsltoolstoolregistry)
- [RAAF::DSL::Tools::ConventionOverConfiguration](#raafdsltoolsconventionoverconfiguration)
- [RAAF::DSL::Tools::PerformanceOptimizer](#raafdsltoolsperformanceoptimizer)
- [Module Loading and Discovery](#module-loading-and-discovery)

## Overview

The RAAF Tool DSL provides a comprehensive API for creating, configuring, and managing tools in AI agents. This reference documents all classes, methods, parameters, and options available in the system.

### Class Hierarchy

```
RAAF::DSL::Tools::Tool
├── RAAF::DSL::Tools::Tool::API
└── RAAF::DSL::Tools::Tool::Native

Modules:
├── RAAF::DSL::Tools::ConventionOverConfiguration
├── RAAF::DSL::Tools::PerformanceOptimizer
└── RAAF::DSL::Tools::ToolRegistry
```

---

## RAAF::DSL::Tools::Tool

Base class for all executable tools in the RAAF DSL framework.

### Class Methods

#### `.configure(options = {})`

Configure tool-level metadata and behavior.

**Parameters:**
- `name` [String, optional] - Override auto-generated tool name
- `description` [String, optional] - Override auto-generated description  
- `enabled` [Boolean, optional] - Whether tool is enabled by default (default: `true`)

**Example:**
```ruby
class MyTool < RAAF::DSL::Tools::Tool
  configure name: "custom_name",
            description: "Custom description for the tool",
            enabled: true
end
```

#### `.tool_name`

Returns the configured or auto-generated tool name.

**Returns:** [String] The tool name

#### `.tool_description`

Returns the configured or auto-generated tool description.

**Returns:** [String] The tool description

#### `.tool_enabled`

Returns whether the tool is enabled by default.

**Returns:** [Boolean] Enabled status

### Instance Methods

#### `#initialize(options = {})`

Initialize a tool instance with configuration options.

**Parameters:**
- `options` [Hash] Configuration options
  - `:name` [String] - Override tool name for this instance
  - `:description` [String] - Override tool description for this instance
  - `:enabled` [Boolean] - Override enabled status for this instance

**Example:**
```ruby
tool = MyTool.new(
  name: "instance_specific_name",
  enabled: false
)
```

#### `#call(**params)` *(abstract)*

Execute the tool with given parameters. **Must be implemented by subclasses.**

**Parameters:**
- `**params` [Hash] - Tool-specific parameters as keyword arguments

**Returns:** [Object] Tool execution result

**Raises:** `NotImplementedError` if not implemented by subclass

**Example:**
```ruby
def call(operation:, a:, b:)
  case operation
  when "add" then { result: a + b }
  when "subtract" then { result: a - b }
  else { error: "Unknown operation" }
  end
end
```

#### `#name`

Returns the tool name (instance override or class default).

**Returns:** [String] Tool name

#### `#description`

Returns the tool description (instance override or class default).

**Returns:** [String] Tool description

#### `#enabled?`

Check if the tool is enabled.

**Returns:** [Boolean] Whether the tool is enabled

#### `#to_tool_definition`

Generate OpenAI-compatible tool definition.

**Returns:** [Hash] Tool definition in OpenAI function format

**Example Response:**
```ruby
{
  type: "function",
  function: {
    name: "calculator",
    description: "Tool for calculator operations",
    parameters: {
      type: "object",
      properties: {
        operation: { type: "string", description: "Operation" },
        a: { type: "number", description: "A" },
        b: { type: "number", description: "B" }
      },
      required: ["operation", "a", "b"],
      additionalProperties: false
    }
  }
}
```

#### `#tool_configuration`

Returns complete tool configuration for framework integration.

**Returns:** [Hash] Complete tool configuration

**Example Response:**
```ruby
{
  tool: { /* tool definition */ },
  callable: #<ToolInstance>,
  enabled: true,
  metadata: {
    class: "MyTool",
    options: { name: "custom_name" }
  }
}
```

#### `#process_result(result)`

Process the result after tool execution. Override to customize result handling.

**Parameters:**
- `result` [Object] - The result from tool execution

**Returns:** [Object] The processed result

**Example:**
```ruby
def process_result(result)
  result.merge(
    timestamp: Time.now,
    tool_version: "1.0.0"
  )
end
```

---

## RAAF::DSL::Tools::Tool::API

Specialized tool class for external API integrations with built-in HTTP handling.

### Class Methods

#### `.endpoint(url)`

Configure the base URL for API endpoints.

**Parameters:**
- `url` [String] - Base URL for API requests

**Example:**
```ruby
class WeatherTool < RAAF::DSL::Tools::Tool::API
  endpoint "https://api.weather.com/v1"
end
```

#### `.api_key(key)`

Configure API key for authentication.

**Parameters:**
- `key` [String] - API key value (often from environment variables)

**Example:**
```ruby
class WeatherTool < RAAF::DSL::Tools::Tool::API
  api_key ENV['WEATHER_API_KEY']
end
```

#### `.headers(headers = {})`

Configure default headers for all requests.

**Parameters:**
- `headers` [Hash] - Default headers

**Example:**
```ruby
class GitHubTool < RAAF::DSL::Tools::Tool::API
  headers({
    "Accept" => "application/vnd.github.v3+json",
    "User-Agent" => "MyApp/1.0"
  })
end
```

#### `.timeout(seconds)`

Configure request timeout.

**Parameters:**
- `seconds` [Integer] - Timeout in seconds

**Example:**
```ruby
class SlowAPITool < RAAF::DSL::Tools::Tool::API
  timeout 60
end
```

### Instance Methods

#### `#initialize(options = {})`

Initialize API tool with configuration.

**Parameters:**
- `options` [Hash] Configuration options
  - `:endpoint` [String] - Override endpoint URL
  - `:api_key` [String] - Override API key
  - `:headers` [Hash] - Override default headers
  - `:timeout` [Integer] - Override timeout

#### `#get(path = "", params: {}, headers: {})`

Perform GET request.

**Parameters:**
- `path` [String] - API endpoint path (optional if full URL in endpoint)
- `params` [Hash] - Query parameters
- `headers` [Hash] - Additional headers

**Returns:** [Hash] Parsed response

**Example:**
```ruby
def call(city:)
  get("/weather", params: { q: city, key: api_key })
end
```

#### `#post(path = "", json: nil, params: {}, headers: {})`

Perform POST request.

**Parameters:**
- `path` [String] - API endpoint path
- `json` [Hash] - JSON body data
- `params` [Hash] - Query parameters  
- `headers` [Hash] - Additional headers

**Returns:** [Hash] Parsed response

**Example:**
```ruby
def call(data:)
  post("/create", json: data, headers: auth_headers)
end
```

#### `#put(path = "", json: nil, params: {}, headers: {})`

Perform PUT request.

**Parameters:**
- `path` [String] - API endpoint path
- `json` [Hash] - JSON body data
- `params` [Hash] - Query parameters
- `headers` [Hash] - Additional headers

**Returns:** [Hash] Parsed response

#### `#delete(path = "", params: {}, headers: {})`

Perform DELETE request.

**Parameters:**
- `path` [String] - API endpoint path
- `params` [Hash] - Query parameters
- `headers` [Hash] - Additional headers

**Returns:** [Hash] Parsed response

#### `#api_key`

Get the configured API key value.

**Returns:** [String, nil] API key value

### Response Handling

API tools automatically handle:

- **JSON parsing** - Automatically parses `application/json` responses
- **Error handling** - Returns structured error responses for HTTP errors
- **Status codes** - Handles 2xx, 4xx, and 5xx status codes appropriately
- **Timeouts** - Network timeout handling with configurable duration

**Error Response Format:**
```ruby
{
  error: "Client error: 404",
  message: "Not Found"
}
```

**Network Error Format:**
```ruby
{
  error: "Net::TimeoutError", 
  message: "execution expired",
  backtrace: ["..."]
}
```

---

## RAAF::DSL::Tools::Tool::Native

Configuration-only tools executed by OpenAI's infrastructure (code_interpreter, file_search, etc.).

### Class Methods

#### `.tool_type(type = nil)`

Configure or get the OpenAI tool type.

**Parameters:**
- `type` [String, optional] - OpenAI tool type

**Valid Tool Types:**
- `"function"` - Custom function executed by OpenAI
- `"code_interpreter"` - Python code execution
- `"file_search"` - File search capabilities

**Returns:** [String] Current tool type (when called without parameters)

**Example:**
```ruby
class CodeInterpreterTool < RAAF::DSL::Tools::Tool::Native
  tool_type "code_interpreter"
end
```

#### `.parameter(name, options = {})`

Define a parameter for function-type tools.

**Parameters:**
- `name` [Symbol] - Parameter name
- `type` [Symbol] - Parameter type (`:string`, `:number`, `:integer`, `:boolean`, `:array`, `:object`)
- `required` [Boolean] - Whether parameter is required (default: `false`)
- `description` [String] - Parameter description
- `**options` [Hash] - Additional JSON Schema options

**JSON Schema Options:**
- `enum` [Array] - Allowed values
- `default` [Object] - Default value
- `minimum` [Number] - Minimum value (for numbers)
- `maximum` [Number] - Maximum value (for numbers)
- `items` [Hash] - Array item schema (for arrays)
- `properties` [Hash] - Object properties (for objects)

**Example:**
```ruby
class AnalysisTool < RAAF::DSL::Tools::Tool::Native
  tool_type "function"
  
  parameter :query, type: :string, required: true,
            description: "Search query"
  parameter :limit, type: :integer, default: 10,
            minimum: 1, maximum: 100,
            description: "Maximum results"
  parameter :filters, type: :array, items: { type: :string },
            description: "Filter criteria"
end
```

#### `.parameters(schema)`

Configure complete parameter schema at once.

**Parameters:**
- `schema` [Hash] - Complete JSON Schema for parameters

**Example:**
```ruby
class CustomTool < RAAF::DSL::Tools::Tool::Native
  parameters({
    type: "object",
    properties: {
      input: { type: "string", description: "Input data" },
      options: { 
        type: "object",
        properties: {
          format: { type: "string", enum: ["json", "xml"] }
        }
      }
    },
    required: ["input"]
  })
end
```

#### `.reset_parameters!`

Reset parameter schema (useful for testing).

### Instance Methods

#### `#call(**params)`

**Always raises `NotImplementedError`** - Native tools are executed by OpenAI infrastructure.

#### `#native?`

Check if this is a native tool.

**Returns:** [Boolean] Always `true` for native tools

#### `#to_tool_definition`

Generate OpenAI native tool definition.

**Returns:** [Hash] Tool definition in OpenAI native format

**Example Response:**
```ruby
# For code_interpreter
{
  type: "code_interpreter"
}

# For function type
{
  type: "function",
  function: {
    name: "analysis_tool",
    description: "Perform data analysis",
    parameters: {
      type: "object",
      properties: { /* parameters */ },
      required: ["query"]
    }
  }
}
```

#### `#tool_configuration`

Returns native tool configuration.

**Returns:** [Hash] Native tool configuration

**Example Response:**
```ruby
{
  tool: { /* tool definition */ },
  native: true,
  enabled: true,
  metadata: {
    class: "AnalysisTool",
    tool_type: "function",
    options: {}
  }
}
```

---

## RAAF::DSL::Tools::ToolRegistry

Central registry for tool discovery, registration, and management.

### Class Methods

#### `.register(name, tool_class, **options)`

Register a tool class with a name.

**Parameters:**
- `name` [Symbol, String] - Name to register the tool under
- `tool_class` [Class] - Tool class to register
- `**options` [Hash] - Registration options
  - `:aliases` [Array<Symbol>] - Alternative names for the tool
  - `:enabled` [Boolean] - Whether tool is enabled by default
  - `:namespace` [String] - Namespace the tool belongs to
  - `:metadata` [Hash] - Additional metadata

**Returns:** [Symbol] Registered tool name

**Example:**
```ruby
ToolRegistry.register(
  :weather_service,
  WeatherTool,
  aliases: [:weather, :forecast],
  enabled: true,
  namespace: "MyApp::Tools"
)
```

#### `.get(name, strict: true)`

Get a tool class by name with auto-discovery.

**Parameters:**
- `name` [Symbol, String] - Tool name to retrieve
- `strict` [Boolean] - Whether to raise error if not found (default: `true`)

**Returns:** [Class, nil] Tool class if found

**Raises:** `ToolNotFoundError` if tool not found and `strict` is `true`

**Example:**
```ruby
tool_class = ToolRegistry.get(:weather)
tool_class = ToolRegistry.get(:nonexistent, strict: false)  # => nil
```

#### `.registered?(name)`

Check if a tool is registered.

**Parameters:**
- `name` [Symbol, String] - Tool name to check

**Returns:** [Boolean] Whether tool is registered

#### `.register_namespace(namespace)`

Register a namespace for auto-discovery.

**Parameters:**
- `namespace` [String] - Namespace to register (e.g., "MyApp::Tools")

**Example:**
```ruby
ToolRegistry.register_namespace("MyApp::Tools")
ToolRegistry.register_namespace("Ai::Tools")
```

#### `.auto_discover_tools(force: false)`

Auto-discover and register tools from all registered namespaces.

**Parameters:**
- `force` [Boolean] - Whether to force re-discovery (default: `false`)

**Returns:** [Integer] Number of tools discovered

#### `.names`

Get all registered tool names.

**Returns:** [Array<Symbol>] Array of registered tool names

#### `.available_tools`

Get available tools as strings.

**Returns:** [Array<String>] Array of available tool names

#### `.tool_info(namespace: nil)`

Get detailed information about registered tools.

**Parameters:**
- `namespace` [String, nil] - Filter by namespace (optional)

**Returns:** [Hash] Detailed tool information

**Example Response:**
```ruby
{
  :weather => {
    class_name: "WeatherTool",
    namespace: "MyApp::Tools", 
    enabled: true,
    aliases: [:weather, :forecast],
    registered_at: 2025-01-16 10:30:00 UTC
  }
}
```

#### `.statistics`

Get registry performance statistics.

**Returns:** [Hash] Registry statistics

**Example Response:**
```ruby
{
  registered_tools: 15,
  registered_namespaces: 3,
  lookups: 142,
  cache_hits: 128,
  discoveries: 8,
  not_found: 6,
  cache_hit_ratio: 0.901
}
```

#### `.suggest_similar_tools(name, max_suggestions: 3)`

Suggest similar tool names for typos (requires `levenshtein` gem for best results).

**Parameters:**
- `name` [Symbol] - Misspelled tool name
- `max_suggestions` [Integer] - Maximum suggestions to return

**Returns:** [Array<Symbol>] Suggested tool names

**Example:**
```ruby
ToolRegistry.suggest_similar_tools(:wheather)
# => [:weather]
```

#### `.clear!`

Clear all registered tools (mainly for testing).

#### `.validate_tool_class!(tool_class)`

Validate tool class before registration.

**Parameters:**
- `tool_class` [Class] - Tool class to validate

**Returns:** [Boolean] `true` if valid

**Raises:** `ArgumentError` if tool class is invalid

### Exceptions

#### `ToolRegistry::ToolNotFoundError`

Raised when a tool is not found and suggestions are provided.

**Attributes:**
- `tool_name` [String] - The requested tool name
- `suggestions` [Array<Symbol>] - Suggested alternatives

---

## RAAF::DSL::Tools::ConventionOverConfiguration

Module providing automatic generation of tool metadata based on conventions.

### Module Methods

When included in a tool class, automatically generates:

- **Tool name** from class name (`WeatherTool` → `"weather"`)
- **Tool description** from class name (`WeatherTool` → `"Tool for weather operations"`)
- **Parameter schema** from `call` method signature
- **Tool definition** for OpenAI compatibility

### Class Methods (when included)

#### `.generate_tool_metadata`

Generate tool metadata at class load time with caching.

#### `.tool_name`

Get auto-generated tool name with caching.

**Returns:** [String] Generated tool name

#### `.tool_description`

Get auto-generated tool description with caching.

**Returns:** [String] Generated tool description

#### `.parameter_schema`

Get auto-generated parameter schema with caching.

**Returns:** [Hash] Generated JSON Schema for parameters

#### `.tool_definition_for_instance(instance)`

Get tool definition for a specific instance.

**Parameters:**
- `instance` [Tool] - Tool instance

**Returns:** [Hash] Complete tool definition

### Instance Methods (when included)

#### `#metadata_generated?`

Check if metadata has been generated.

**Returns:** [Boolean] Whether metadata generation completed

#### `#regenerate_metadata!`

Regenerate metadata (useful for development/testing).

#### `#parameter_info`

Get parameter information for debugging.

**Returns:** [Hash] Parameter analysis information

**Example Response:**
```ruby
{
  method_signature: [[:keyreq, :operation], [:key, :a], [:key, :b]],
  parameter_schema: { /* generated schema */ },
  generated_at: true
}
```

### Auto-Generation Rules

#### Tool Name Generation

- Removes `"Tool"` suffix from class name
- Converts `CamelCase` to `snake_case`
- Uses last component of namespaced class names

**Examples:**
- `WeatherTool` → `"weather"`
- `AdvancedSearchTool` → `"advanced_search"`
- `MyApp::Tools::DataProcessorTool` → `"data_processor"`

#### Description Generation

- Converts class name to human-readable description
- Removes `"Tool"` suffix
- Adds `"Tool for X operations"` format

**Examples:**
- `WeatherTool` → `"Tool for weather operations"`
- `DataProcessorTool` → `"Tool for data processor operations"`

#### Parameter Schema Generation

Analyzes `call` method signature and generates JSON Schema:

**Parameter Types:**
- `:keyreq` → Required parameter
- `:key` → Optional parameter with default
- `:keyrest` → Accepts additional parameters

**Type Inference:**
- Names ending in `count`, `limit`, `size` → `"integer"`
- Names ending in `price`, `rate`, `score` → `"number"`  
- Names ending in `enabled`, `active`, `valid` → `"boolean"`
- Names ending in `tags`, `items`, `list` → `"array"`
- Names ending in `config`, `options`, `params` → `"object"`
- Everything else → `"string"`

**Format Detection:**
- Names containing `email` → `"email"` format
- Names containing `url`, `uri` → `"uri"` format
- Names containing `date` → `"date"` format
- Names containing `time` → `"date-time"` format

---

## RAAF::DSL::Tools::PerformanceOptimizer

Module providing performance optimizations for tool operations.

### Features

- **Method Caching** - Caches generated tool definitions and metadata
- **Thread Safety** - Uses `Concurrent::Hash` for thread-safe operations
- **Lazy Loading** - Only generates metadata when needed
- **Memory Efficiency** - Optimized caching strategies

### Methods (when included)

#### `#cache_generated_methods`

Cache generated tool metadata for performance.

#### `#cached_tool_definition`

Get cached tool definition.

**Returns:** [Hash] Cached tool definition

#### `#cached_parameter_schema`

Get cached parameter schema.

**Returns:** [Hash] Cached parameter schema

---

## Module Loading and Discovery

### Auto-Discovery Process

1. **Namespace Registration** - Register tool namespaces with `ToolRegistry.register_namespace`
2. **Class Loading** - When tool classes are loaded, they automatically register via `ConventionOverConfiguration`
3. **Discovery** - `ToolRegistry.auto_discover_tools` finds classes in registered namespaces
4. **Validation** - Tool classes are validated before registration
5. **Caching** - Discovery results are cached for performance

### Discovery Patterns

The registry looks for classes matching these patterns:

- `*Tool` (e.g., `WeatherTool`, `CalculatorTool`)
- `*Agent` (e.g., `SearchAgent`, `DataAgent`)
- `*Service` (e.g., `APIService`, `ProcessingService`)

### Error Handling

- **Fuzzy Matching** - Suggests similar names for typos
- **Clear Messages** - Detailed error messages with available tools
- **Graceful Degradation** - Auto-discovery failures don't break the system

### Performance Considerations

- **O(1) Lookup** - Registry uses hash-based lookups
- **Cached Discovery** - Results cached to avoid repeated filesystem access
- **Thread Safe** - All operations use concurrent data structures
- **Memory Efficient** - Lazy loading and optimized caching

### Example Integration

```ruby
# 1. Setup (application initialization)
RAAF::DSL::Tools::ToolRegistry.register_namespace("MyApp::Tools")

# 2. Define tools (anywhere in your application)
module MyApp::Tools
  class WeatherTool < RAAF::DSL::Tools::Tool::API
    endpoint "https://api.weather.com"
    
    def call(city:)
      get(params: { q: city })
    end
  end
end

# 3. Use tools (automatically available)
agent = RAAF::DSL::AgentBuilder.build do
  name "Weather Agent"
  use_tool :weather  # Auto-discovered
end

# 4. Direct access
tool_class = RAAF::DSL::Tools::ToolRegistry.get(:weather)
tool = tool_class.new
result = tool.call(city: "New York")
```

This API reference provides comprehensive documentation for all components of the RAAF Tool DSL system, enabling developers to effectively create, configure, and use tools in their AI applications.