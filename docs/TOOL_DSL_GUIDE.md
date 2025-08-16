# Tool DSL Guide

> Version: 1.0.0
> Last Updated: 2025-01-16

## Table of Contents

- [Overview](#overview)
- [Why the `call` Method Convention](#why-the-call-method-convention)
- [Tool Types](#tool-types)
- [Basic Tool Creation](#basic-tool-creation)
- [API Tools](#api-tools)
- [Native Tools](#native-tools)
- [Auto-Discovery and Registration](#auto-discovery-and-registration)
- [Performance Features](#performance-features)
- [Configuration and Customization](#configuration-and-customization)
- [Best Practices](#best-practices)
- [Examples](#examples)

## Overview

The RAAF Tool DSL provides a unified, elegant way to create and manage tools for AI agents. It supports three types of tools:

- **Tool** - Basic executable tools with local implementation
- **Tool::API** - External API integration tools with built-in HTTP handling
- **Tool::Native** - OpenAI native tools (code_interpreter, file_search, etc.)

The DSL emphasizes **Convention over Configuration**, automatically generating tool metadata from class names and method signatures while providing extensive customization options.

### Key Benefits

- **Unified Interface**: All tools use the same `call` method convention
- **Auto-Generation**: Names, descriptions, and parameter schemas generated automatically
- **Performance Optimized**: Built-in caching and thread-safe operations
- **Auto-Discovery**: Tools automatically registered when loaded
- **Type Safety**: Parameter validation and schema generation
- **OpenAI Compatible**: Direct integration with OpenAI's function calling API

## Why the `call` Method Convention

The Tool DSL follows Ruby's **callable object convention** using the `call` method as the standard execution interface. This design choice provides several benefits:

### Ruby Ecosystem Alignment

Ruby's callable objects (Proc, Lambda, Method) all use `call` as their execution method:

```ruby
# Ruby's built-in callable objects
proc = Proc.new { |x| x * 2 }
proc.call(5)  # => 10

lambda = -> (x) { x * 2 }
lambda.call(5)  # => 10

# RAAF tools follow the same pattern
tool = CalculatorTool.new
tool.call(operation: "add", a: 5, b: 3)  # => { result: 8 }
```

### Syntactic Sugar Support

Ruby provides syntactic sugar for callable objects with `.()`:

```ruby
# Standard call syntax
result = tool.call(city: "New York")

# Syntactic sugar (equivalent)
result = tool.(city: "New York")
```

### Framework Integration

The `call` convention enables seamless integration with Ruby frameworks and metaprogramming:

```ruby
# Tools can be stored and invoked uniformly
tools = [weather_tool, calculator_tool, search_tool]
results = tools.map { |tool| tool.call(**params) }

# Duck typing works naturally
def execute_callable(callable, **params)
  callable.call(**params)  # Works with tools, procs, lambdas, etc.
end
```

### OpenAI Function Calling Alignment

OpenAI's function calling expects a callable interface, making `call` the natural choice:

```ruby
# Agent execution flow
tool_call = openai_response.tool_calls.first
tool = agent.find_tool(tool_call.function.name)
result = tool.call(**tool_call.function.arguments)  # Direct execution
```

## Tool Types

### Tool (Basic)

The base Tool class for locally executed tools with custom logic:

```ruby
class CalculatorTool < RAAF::DSL::Tools::Tool
  def call(operation:, a:, b:)
    case operation
    when "add" then { result: a + b }
    when "subtract" then { result: a - b }
    when "multiply" then { result: a * b }
    when "divide" then b.zero? ? { error: "Division by zero" } : { result: a.to_f / b }
    else { error: "Unknown operation: #{operation}" }
    end
  end
end
```

### Tool::API (External APIs)

Specialized for external API integrations with built-in HTTP handling:

```ruby
class WeatherTool < RAAF::DSL::Tools::Tool::API
  endpoint "https://api.weather.com/v1/current"
  api_key ENV['WEATHER_API_KEY']
  timeout 30
  
  def call(city:, units: "celsius")
    get(params: { q: city, key: api_key, units: units })
  end
end
```

### Tool::Native (OpenAI Native)

Configuration-only tools executed by OpenAI's infrastructure:

```ruby
class CodeInterpreterTool < RAAF::DSL::Tools::Tool::Native
  tool_type "code_interpreter"
  
  configure name: "code_interpreter",
            description: "Execute Python code in a sandboxed environment"
  
  parameter :code, type: :string, required: true,
            description: "Python code to execute"
end
```

## Basic Tool Creation

### Simple Tool with Auto-Generation

The simplest tool leverages convention over configuration:

```ruby
class WeatherTool < RAAF::DSL::Tools::Tool
  # Auto-generates:
  # - name: "weather" (from class name)
  # - description: "Tool for weather operations"
  # - parameter schema from method signature
  
  def call(city:, country: "US", units: "celsius")
    # Simulate weather API call
    {
      city: city,
      country: country,
      temperature: rand(10..30),
      units: units,
      conditions: ["sunny", "cloudy", "rainy"].sample
    }
  end
end
```

### Tool with Custom Configuration

Override auto-generated metadata:

```ruby
class AdvancedSearchTool < RAAF::DSL::Tools::Tool
  configure name: "semantic_search",
            description: "Perform semantic search across document collections",
            enabled: true
  
  def call(query:, limit: 10, filters: {}, include_metadata: true)
    # Enhanced search implementation
    {
      query: query,
      results: search_documents(query, limit, filters),
      metadata: include_metadata ? generate_metadata : nil,
      total_found: count_matches(query)
    }
  end
  
  private
  
  def search_documents(query, limit, filters)
    # Implementation details...
  end
  
  def generate_metadata
    { search_time: Time.now, algorithm: "semantic" }
  end
end
```

### Tool with Result Processing

Add post-processing to tool results:

```ruby
class DataAnalysisTool < RAAF::DSL::Tools::Tool
  def call(data:, analysis_type: "summary")
    raw_result = perform_analysis(data, analysis_type)
    process_result(raw_result)
  end
  
  def process_result(result)
    # Add standard metadata to all results
    result.merge({
      processed_at: Time.now,
      tool_version: "1.2.0",
      confidence: calculate_confidence(result)
    })
  end
  
  private
  
  def perform_analysis(data, type)
    # Analysis implementation...
  end
  
  def calculate_confidence(result)
    # Confidence calculation...
  end
end
```

## API Tools

API Tools provide sophisticated HTTP client capabilities with built-in error handling, authentication, and response parsing.

### Basic API Tool

```ruby
class GitHubTool < RAAF::DSL::Tools::Tool::API
  endpoint "https://api.github.com"
  headers({
    "Accept" => "application/vnd.github.v3+json",
    "User-Agent" => "RAAF-Tool/1.0"
  })
  timeout 30
  
  def call(username:, action: "profile")
    case action
    when "profile"
      get("/users/#{username}")
    when "repos"
      get("/users/#{username}/repos", params: { sort: "updated" })
    else
      { error: "Unknown action: #{action}" }
    end
  end
end
```

### API Tool with Authentication

```ruby
class SlackTool < RAAF::DSL::Tools::Tool::API
  endpoint "https://slack.com/api"
  
  def call(channel:, message:, thread_ts: nil)
    payload = {
      channel: channel,
      text: message
    }
    payload[:thread_ts] = thread_ts if thread_ts
    
    post("/chat.postMessage", 
         json: payload,
         headers: { "Authorization" => "Bearer #{ENV['SLACK_TOKEN']}" })
  end
end
```

### API Tool with Complex Request Handling

```ruby
class CRMTool < RAAF::DSL::Tools::Tool::API
  endpoint ENV['CRM_API_URL']
  api_key ENV['CRM_API_KEY']
  timeout 60
  
  def call(action:, **params)
    case action
    when "create_contact"
      create_contact(params)
    when "search_contacts"
      search_contacts(params)
    when "update_contact"
      update_contact(params)
    else
      { error: "Unknown action: #{action}" }
    end
  end
  
  private
  
  def create_contact(name:, email:, company: nil, **custom_fields)
    contact_data = {
      name: name,
      email: email,
      company: company,
      custom_fields: custom_fields
    }.compact
    
    post("/contacts", 
         json: contact_data,
         headers: auth_headers)
  end
  
  def search_contacts(query:, limit: 10)
    get("/contacts/search", 
        params: { q: query, limit: limit },
        headers: auth_headers)
  end
  
  def update_contact(id:, **updates)
    put("/contacts/#{id}", 
        json: updates,
        headers: auth_headers)
  end
  
  def auth_headers
    { "X-API-Key" => api_key }
  end
end
```

### HTTP Methods and Features

API Tools support all standard HTTP methods:

```ruby
class RESTfulTool < RAAF::DSL::Tools::Tool::API
  endpoint "https://api.example.com/v1"
  
  def call(method:, path:, **options)
    case method.downcase
    when "get"
      get(path, params: options[:params], headers: options[:headers])
    when "post"
      post(path, json: options[:data], headers: options[:headers])
    when "put"
      put(path, json: options[:data], headers: options[:headers])
    when "delete"
      delete(path, params: options[:params], headers: options[:headers])
    else
      { error: "Unsupported HTTP method: #{method}" }
    end
  end
end
```

## Native Tools

Native Tools are configuration-only tools that define structure for OpenAI's built-in functionality.

### Code Interpreter Tool

```ruby
class CodeInterpreterTool < RAAF::DSL::Tools::Tool::Native
  tool_type "code_interpreter"
  
  configure name: "code_interpreter",
            description: "Execute Python code in a sandboxed environment with data analysis capabilities"
end
```

### File Search Tool

```ruby
class FileSearchTool < RAAF::DSL::Tools::Tool::Native
  tool_type "file_search"
  
  configure name: "file_search",
            description: "Search through uploaded files and documents"
  
  # Optional: Configure file search specific settings
  def initialize(options = {})
    super(options.merge({
      max_results: 20,
      ranking_options: { score_threshold: 0.7 }
    }))
  end
end
```

### Custom Function Tool

For more complex native functions that OpenAI should handle:

```ruby
class CustomAnalysisTool < RAAF::DSL::Tools::Tool::Native
  tool_type "function"
  
  configure name: "advanced_analysis",
            description: "Perform complex data analysis using OpenAI's infrastructure"
  
  parameter :data_source, type: :string, required: true,
            description: "Source of data to analyze"
  parameter :analysis_type, type: :string, required: true,
            enum: ["statistical", "predictive", "exploratory"],
            description: "Type of analysis to perform"
  parameter :include_visualization, type: :boolean, default: false,
            description: "Whether to include data visualizations"
  parameter :confidence_threshold, type: :number, default: 0.8,
            minimum: 0.0, maximum: 1.0,
            description: "Minimum confidence threshold for results"
end
```

## Auto-Discovery and Registration

The Tool DSL automatically discovers and registers tools when they're loaded, providing seamless tool availability across your application.

### Automatic Registration

Tools are automatically registered when classes are loaded:

```ruby
# Just defining the class automatically registers it
class WeatherTool < RAAF::DSL::Tools::Tool
  def call(city:)
    # Implementation
  end
end

# Tool is now available globally
RAAF::DSL::Tools::ToolRegistry.get(:weather)  # => WeatherTool
```

### Namespace Registration

Register namespaces for auto-discovery:

```ruby
# Register your custom tool namespace
RAAF::DSL::Tools::ToolRegistry.register_namespace("MyApp::Tools")

# All tools in MyApp::Tools will be auto-discovered
module MyApp
  module Tools
    class CustomTool < RAAF::DSL::Tools::Tool
      def call(input:)
        # Implementation
      end
    end
  end
end

# Auto-discovered and available as :custom
RAAF::DSL::Tools::ToolRegistry.get(:custom)  # => MyApp::Tools::CustomTool
```

### Manual Registration with Aliases

```ruby
# Register with custom name and aliases
RAAF::DSL::Tools::ToolRegistry.register(
  :weather_service,
  WeatherTool,
  aliases: [:weather, :forecast],
  enabled: true,
  namespace: "MyApp::Tools"
)

# Available under multiple names
RAAF::DSL::Tools::ToolRegistry.get(:weather_service)  # => WeatherTool
RAAF::DSL::Tools::ToolRegistry.get(:weather)         # => WeatherTool
RAAF::DSL::Tools::ToolRegistry.get(:forecast)        # => WeatherTool
```

### Discovery Statistics

Monitor tool registration and usage:

```ruby
stats = RAAF::DSL::Tools::ToolRegistry.statistics
# => {
#   registered_tools: 15,
#   registered_namespaces: 3,
#   lookups: 142,
#   cache_hits: 128,
#   discoveries: 8,
#   not_found: 6,
#   cache_hit_ratio: 0.901
# }
```

## Performance Features

The Tool DSL includes several performance optimizations:

### Automatic Caching

- Tool metadata is cached at class load time
- Tool lookup results are cached for fast subsequent access
- Thread-safe caching with Concurrent::Hash

### Lazy Loading

- Tools are only instantiated when needed
- Parameter schemas generated once and cached
- Discovery results cached to avoid repeated filesystem access

### Performance Monitoring

```ruby
# Get performance statistics
stats = RAAF::DSL::Tools::ToolRegistry.statistics

puts "Cache hit ratio: #{(stats[:cache_hit_ratio] * 100).round(1)}%"
puts "Total lookups: #{stats[:lookups]}"
puts "Discoveries: #{stats[:discoveries]}"
```

### Optimization Tips

1. **Use Auto-Discovery**: Let the system discover tools automatically rather than manual registration
2. **Leverage Caching**: Tool definitions are cached, so repeated access is fast
3. **Namespace Organization**: Group related tools in namespaces for better discovery performance
4. **Minimal Instantiation**: Tools are only created when actually used

## Configuration and Customization

### Tool-Level Configuration

```ruby
class ConfigurableTool < RAAF::DSL::Tools::Tool
  # Override auto-generated metadata
  configure name: "custom_name",
            description: "Custom description",
            enabled: true
  
  def call(input:)
    # Implementation
  end
end
```

### Instance-Level Configuration

```ruby
# Override configuration at instantiation
tool = ConfigurableTool.new(
  name: "instance_name",
  description: "Instance-specific description",
  enabled: false
)
```

### Environment-Based Configuration

```ruby
class EnvironmentAwareTool < RAAF::DSL::Tools::Tool::API
  endpoint ENV.fetch('API_ENDPOINT', 'https://api.default.com')
  api_key ENV['API_KEY']
  timeout ENV.fetch('API_TIMEOUT', 30).to_i
  
  def call(**params)
    # Tool automatically uses environment configuration
    get(params: params)
  end
end
```

### Conditional Tool Registration

```ruby
class ProductionOnlyTool < RAAF::DSL::Tools::Tool
  configure enabled: Rails.env.production?
  
  def call(sensitive_operation:)
    # Only available in production
  end
end
```

## Best Practices

### 1. Use Descriptive Class Names

```ruby
# Good: Clear, descriptive names
class WeatherForecastTool < RAAF::DSL::Tools::Tool
class CustomerDataEnrichmentTool < RAAF::DSL::Tools::Tool::API
class DocumentSearchTool < RAAF::DSL::Tools::Tool::Native

# Avoid: Generic names
class DataTool < RAAF::DSL::Tools::Tool
class APITool < RAAF::DSL::Tools::Tool::API
```

### 2. Leverage Convention Over Configuration

```ruby
# Good: Let the DSL generate metadata
class UserSearchTool < RAAF::DSL::Tools::Tool
  def call(query:, limit: 10, include_inactive: false)
    # Implementation
  end
end

# Only override when necessary
class SpecializedTool < RAAF::DSL::Tools::Tool
  configure description: "Highly specialized tool for complex operations"
  
  def call(complex_params:)
    # Implementation
  end
end
```

### 3. Handle Errors Gracefully

```ruby
class RobustTool < RAAF::DSL::Tools::Tool
  def call(operation:, **params)
    validate_params(operation, params)
    
    case operation
    when "process"
      process_data(params)
    else
      { error: "Unknown operation: #{operation}" }
    end
  rescue => e
    {
      error: e.message,
      error_type: e.class.name,
      timestamp: Time.now
    }
  end
  
  private
  
  def validate_params(operation, params)
    case operation
    when "process"
      raise ArgumentError, "data parameter required" unless params[:data]
    end
  end
end
```

### 4. Use Result Processing for Consistency

```ruby
class ConsistentTool < RAAF::DSL::Tools::Tool
  def call(**params)
    raw_result = perform_operation(params)
    process_result(raw_result)
  end
  
  def process_result(result)
    # Add consistent metadata to all results
    {
      **result,
      tool_name: name,
      timestamp: Time.now,
      version: self.class::VERSION
    }
  end
end
```

### 5. Document Complex Tools

```ruby
# Complex tools benefit from explicit documentation
class MLModelTool < RAAF::DSL::Tools::Tool
  configure description: "Execute machine learning model predictions with confidence scoring"
  
  # @param model_id [String] Identifier for the ML model to use
  # @param input_data [Hash] Input features for prediction
  # @param confidence_threshold [Float] Minimum confidence for predictions (0.0-1.0)
  # @return [Hash] Prediction results with confidence scores
  def call(model_id:, input_data:, confidence_threshold: 0.8)
    # Implementation with clear parameter handling
  end
end
```

## Examples

### Complete Weather Tool

```ruby
class WeatherTool < RAAF::DSL::Tools::Tool::API
  endpoint "https://api.openweathermap.org/data/2.5"
  api_key ENV['OPENWEATHER_API_KEY']
  timeout 10
  
  headers({
    "User-Agent" => "RAAF-Weather-Tool/1.0"
  })
  
  def call(city:, country: "US", units: "metric", include_forecast: false)
    validate_api_key!
    
    location = country ? "#{city},#{country}" : city
    
    if include_forecast
      get_forecast(location, units)
    else
      get_current_weather(location, units)
    end
  rescue => e
    handle_error(e)
  end
  
  private
  
  def get_current_weather(location, units)
    response = get("/weather", params: {
      q: location,
      units: units,
      appid: api_key
    })
    
    format_weather_response(response)
  end
  
  def get_forecast(location, units)
    response = get("/forecast", params: {
      q: location,
      units: units,
      cnt: 8,  # 24 hours (3-hour intervals)
      appid: api_key
    })
    
    format_forecast_response(response)
  end
  
  def format_weather_response(response)
    return response if response[:error]
    
    {
      location: response.dig("name"),
      country: response.dig("sys", "country"),
      temperature: response.dig("main", "temp"),
      feels_like: response.dig("main", "feels_like"),
      humidity: response.dig("main", "humidity"),
      description: response.dig("weather", 0, "description"),
      wind_speed: response.dig("wind", "speed")
    }
  end
  
  def format_forecast_response(response)
    return response if response[:error]
    
    {
      location: response.dig("city", "name"),
      country: response.dig("city", "country"),
      forecast: response["list"]&.map do |item|
        {
          datetime: item["dt_txt"],
          temperature: item.dig("main", "temp"),
          description: item.dig("weather", 0, "description"),
          humidity: item.dig("main", "humidity")
        }
      end
    }
  end
  
  def validate_api_key!
    raise ArgumentError, "OpenWeather API key not configured" unless api_key
  end
  
  def handle_error(error)
    {
      error: "Weather service error",
      message: error.message,
      type: error.class.name
    }
  end
end
```

### Database Query Tool

```ruby
class DatabaseQueryTool < RAAF::DSL::Tools::Tool
  configure description: "Execute safe database queries with automatic result formatting"
  
  def call(query_type:, table:, conditions: {}, limit: 100, fields: ["*"])
    validate_query_safety!(query_type, table, conditions)
    
    case query_type.downcase
    when "select"
      execute_select(table, fields, conditions, limit)
    when "count"
      execute_count(table, conditions)
    else
      { error: "Unsupported query type: #{query_type}" }
    end
  rescue => e
    handle_database_error(e)
  end
  
  private
  
  def execute_select(table, fields, conditions, limit)
    # Simulate database query (replace with actual database connection)
    query = build_select_query(table, fields, conditions, limit)
    
    # In real implementation, use parameterized queries
    results = simulate_database_query(query)
    
    {
      query_type: "select",
      table: table,
      count: results.size,
      data: results,
      executed_at: Time.now
    }
  end
  
  def execute_count(table, conditions)
    query = build_count_query(table, conditions)
    count = simulate_count_query(query)
    
    {
      query_type: "count",
      table: table,
      count: count,
      executed_at: Time.now
    }
  end
  
  def build_select_query(table, fields, conditions, limit)
    # Build safe parameterized query
    # This is a simplified example
    {
      sql: "SELECT #{fields.join(', ')} FROM #{table}",
      conditions: conditions,
      limit: limit
    }
  end
  
  def validate_query_safety!(query_type, table, conditions)
    allowed_tables = %w[users products orders customers]
    allowed_query_types = %w[select count]
    
    unless allowed_query_types.include?(query_type.downcase)
      raise ArgumentError, "Query type '#{query_type}' not allowed"
    end
    
    unless allowed_tables.include?(table.downcase)
      raise ArgumentError, "Table '#{table}' not allowed"
    end
    
    # Validate condition keys don't contain SQL injection attempts
    conditions.keys.each do |key|
      if key.to_s.match?(/[;'"\\]/)
        raise ArgumentError, "Invalid condition key: #{key}"
      end
    end
  end
  
  def simulate_database_query(query)
    # Simulate database results
    [
      { id: 1, name: "Example Record 1", status: "active" },
      { id: 2, name: "Example Record 2", status: "inactive" }
    ]
  end
  
  def simulate_count_query(query)
    42  # Simulated count
  end
  
  def handle_database_error(error)
    {
      error: "Database query failed",
      message: error.message,
      type: error.class.name,
      timestamp: Time.now
    }
  end
end
```

These examples demonstrate the flexibility and power of the Tool DSL while following best practices for error handling, validation, and result formatting.