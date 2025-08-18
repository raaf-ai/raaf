# RAAF Unified Tool Architecture

## Overview

The RAAF Unified Tool Architecture provides a single, consistent way to define and use tools across the framework. It follows Ruby's convention over configuration principle to minimize boilerplate while allowing full customization when needed.

## Key Features

- **Single Base Class**: All tools inherit from `RAAF::Tool`
- **Auto-Registration**: Tools register themselves automatically when defined
- **Convention Over Configuration**: Minimal code required for basic tools
- **Name-Based Discovery**: Find tools by name with intelligent resolution
- **User Override**: User-defined tools automatically override RAAF defaults
- **Backward Compatible**: Existing `FunctionTool` code continues to work

## Quick Start

### Basic Tool

```ruby
class CalculatorTool < RAAF::Tool
  def call(expression:)
    eval(expression)
  end
end

# Automatically:
# - Registered as "calculator"
# - Description: "Tool for calculator operations"
# - Parameters extracted from method signature
```

### Using Tools in Agents

```ruby
class MyAgent < RAAF::DSL::Agent
  tool :calculator           # Auto-discovery
  tool CalculatorTool       # Direct reference
  tool :weather, timeout: 5  # With options
end
```

## Tool Types

### Function Tools (Default)

Standard Ruby methods executed locally:

```ruby
class DataProcessorTool < RAAF::Tool
  def call(data:, format: "json")
    # Process data
  end
end
```

### API Tools

For external service integration:

```ruby
class WeatherTool < RAAF::Tool::API
  endpoint "https://api.weather.com/v1"
  api_key_env "WEATHER_API_KEY"
  timeout 30
  
  def call(city:)
    get("/weather", params: { q: city })
  end
end
```

### Native Tools

OpenAI infrastructure tools:

```ruby
class WebSearchTool < RAAF::Tool::Native
  configure name: "web_search"
  
  native_config do
    web_search true
  end
end
```

## Conventions

### Automatic Name Generation

```ruby
class SentimentAnalyzerTool < RAAF::Tool
  # Name: "sentiment_analyzer"
end

class URLFetcherTool < RAAF::Tool
  # Name: "url_fetcher"
end
```

### Automatic Description

```ruby
class ImageGeneratorTool < RAAF::Tool
  # Description: "Tool for image generator operations"
end
```

### Parameter Extraction

```ruby
class SearchTool < RAAF::Tool
  def call(query:, max_results: 10, filter: nil)
    # Automatically extracts:
    # - query (required, string)
    # - max_results (optional, integer, default: 10)
    # - filter (optional, string)
  end
end
```

## Customization

### Explicit Configuration

```ruby
class CustomTool < RAAF::Tool
  configure name: "my_custom_tool",
           description: "Performs custom operations",
           enabled: true
  
  def call(input:)
    # Implementation
  end
end
```

### Explicit Parameters

```ruby
class AdvancedTool < RAAF::Tool
  parameters do
    property :text, type: "string", description: "Input text"
    property :mode, type: "string", enum: ["fast", "accurate"]
    property :options, type: "object", properties: {
      timeout: { type: "integer" },
      retries: { type: "integer" }
    }
    required :text
  end
  
  def call(text:, mode: "fast", options: {})
    # Implementation
  end
end
```

### Conditional Enabling

```ruby
class PremiumTool < RAAF::Tool
  def enabled?
    ENV["PREMIUM_FEATURES"] == "true"
  end
  
  def call(data:)
    # Premium functionality
  end
end
```

## Tool Discovery

### Resolution Order

When you reference a tool by name (e.g., `:web_search`), RAAF searches in this order:

1. **Registry**: Explicitly registered tools
2. **User Namespace**: `Ai::Tools::WebSearchTool`
3. **RAAF Namespace**: `RAAF::Tools::WebSearchTool`

### User Override Example

```ruby
# RAAF provides a default
module RAAF::Tools
  class WebSearchTool < RAAF::Tool
    # Default implementation
  end
end

# User can override
module Ai::Tools
  class WebSearchTool < RAAF::Tool
    # Custom implementation (automatically takes precedence)
  end
end

# In agent
class MyAgent < RAAF::DSL::Agent
  tool :web_search  # Uses Ai::Tools::WebSearchTool
end
```

## API Tool Features

### HTTP Methods

```ruby
class APITool < RAAF::Tool::API
  endpoint "https://api.example.com"
  
  def call(action:, data: nil)
    case action
    when "fetch"
      get("/resource")
    when "create"
      post("/resource", json: data)
    when "update"
      put("/resource", json: data)
    when "remove"
      delete("/resource")
    end
  end
end
```

### Authentication

```ruby
class SecureAPITool < RAAF::Tool::API
  endpoint "https://secure-api.com"
  api_key_env "SECURE_API_KEY"  # From environment
  # OR
  api_key "direct_key_value"    # Direct (not recommended)
  
  def call(query:)
    # API key automatically added as Bearer token
    get("/search", params: { q: query })
  end
end
```

### Error Handling & Retries

```ruby
class RobustAPITool < RAAF::Tool::API
  endpoint "https://api.example.com"
  retries 3
  retry_delay 1.5
  timeout 30
  
  def call(data:)
    post("/process", json: data)
    # Automatically retries on failure
  rescue RAAF::Tool::API::RateLimitError => e
    # Handle rate limiting
    { error: "Rate limited", retry_after: e.retry_after }
  end
end
```

## Native Tool Integration

Native tools are executed by OpenAI's infrastructure:

```ruby
class CodeInterpreterTool < RAAF::Tool::Native
  configure name: "code_interpreter"
  
  native_config do
    code_interpreter true
  end
  
  # No call method needed - OpenAI handles execution
end
```

## Migration Guide

### From FunctionTool

**Before:**
```ruby
def search(query:)
  # Search logic
end

tool = FunctionTool.new(method(:search))
agent.add_tool(tool)
```

**After:**
```ruby
class SearchTool < RAAF::Tool
  def call(query:)
    # Search logic
  end
end

agent.tool :search  # Or: agent.tool SearchTool
```

### From Hash Tools

**Before:**
```ruby
tool = {
  type: "function",
  function: {
    name: "calculator",
    description: "Evaluates expressions",
    parameters: { ... }
  }
}
```

**After:**
```ruby
class CalculatorTool < RAAF::Tool
  configure description: "Evaluates expressions"
  
  def call(expression:)
    eval(expression)
  end
end
```

## Backward Compatibility

The system maintains full backward compatibility:

```ruby
# Old style - still works
agent.add_tool(FunctionTool.new(method(:search)))

# New style - recommended
class SearchTool < RAAF::Tool
  def call(query:)
    search(query)
  end
end
agent.tool :search

# Both produce the same result
```

## Debugging

Enable debug logging to see tool operations:

```bash
export RAAF_DEBUG_CATEGORIES=tools,registry
export RAAF_LOG_LEVEL=debug
```

This will show:
- Tool registration
- Name resolution
- Tool discovery
- API requests
- Error details

## Best Practices

1. **Use Conventions**: Let the framework generate names and descriptions
2. **Explicit When Needed**: Only override conventions when necessary
3. **Namespace Organization**: Put custom tools in `Ai::Tools` namespace
4. **Error Handling**: Always handle errors gracefully in `call` method
5. **Parameter Types**: Use explicit parameter definitions for complex inputs
6. **API Keys**: Use environment variables for API keys, never hardcode
7. **Testing**: Test tools in isolation before integrating with agents

## Performance Considerations

- **Lazy Loading**: Tools are loaded only when needed
- **Registry Caching**: Class lookups are cached after first resolution
- **Thread Safety**: All registry operations are thread-safe
- **Minimal Overhead**: Convention-based defaults avoid runtime computation

## Complete Example

```ruby
# Define a custom tool
class TranslationTool < RAAF::Tool::API
  endpoint "https://api.translator.com"
  api_key_env "TRANSLATOR_API_KEY"
  timeout 15
  
  configure description: "Translates text between languages"
  
  parameters do
    property :text, type: "string", description: "Text to translate"
    property :from, type: "string", description: "Source language code"
    property :to, type: "string", description: "Target language code"
    required :text, :to
  end
  
  def call(text:, from: "auto", to:)
    response = post("/translate", json: {
      text: text,
      source_lang: from,
      target_lang: to
    })
    
    {
      original: text,
      translated: response["translation"],
      confidence: response["confidence"]
    }
  end
end

# Use in an agent
class InternationalAgent < RAAF::DSL::Agent
  agent_name "International Assistant"
  
  # Add the translation tool
  tool TranslationTool
  # Or by name after registration
  tool :translation
  
  # Add other tools
  tool :web_search
  tool :calculator
end

# Create and run the agent
agent = InternationalAgent.new
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Translate 'Hello World' to Spanish")
```

## Troubleshooting

### Tool Not Found

If you get "Tool not found" errors:

1. Check the tool class is loaded
2. Verify the name resolution (`:my_tool` looks for `MyToolTool`)
3. Check namespace (user tools in `Ai::Tools`, RAAF tools in `RAAF::Tools`)
4. Enable debug logging to see the search process

### Parameters Not Extracted

If parameters aren't being extracted correctly:

1. Use keyword arguments in the `call` method
2. Define parameters explicitly using the `parameters` DSL
3. Check parameter names match between definition and usage

### API Tools Not Working

For API tool issues:

1. Verify the endpoint URL is correct
2. Check API key is set (environment variable or direct)
3. Test with curl to ensure the API is accessible
4. Enable debug logging to see request/response details

## Further Reading

- [Tool Development Guide](./guides/tool_development.md)
- [API Tool Patterns](./guides/api_tools.md)
- [Native Tool Integration](./guides/native_tools.md)
- [Testing Tools](./guides/testing_tools.md)