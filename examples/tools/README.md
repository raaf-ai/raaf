# Tool DSL Examples

This directory contains practical examples demonstrating the RAAF Tool DSL system. Each example showcases different aspects of tool creation and usage.

## Examples Overview

### 1. Basic API Tool (`basic_api_tool.rb`)
**Level: Beginner**

A simple weather API tool demonstrating:
- Basic API tool configuration with `Tool::API`
- Automatic parameter generation from method signatures
- Built-in HTTP methods (`get`, `post`, etc.)
- Error handling and response formatting
- Auto-discovery and registration

**Key Features:**
- Endpoint configuration
- API key authentication
- Request timeout handling
- Response transformation
- Parameter validation

**Run the example:**
```bash
ruby basic_api_tool.rb
```

### 2. Native Tool (`native_tool.rb`)
**Level: Beginner**

OpenAI native tools for code execution and file search:
- `Tool::Native` for OpenAI infrastructure tools
- Code interpreter configuration
- File search capabilities
- Custom function definitions with parameter schemas
- JSON Schema parameter validation

**Key Features:**
- Code interpreter setup
- File search configuration
- Advanced parameter definitions
- OpenAI API integration format

**Run the example:**
```bash
ruby native_tool.rb
```

### 3. Complex API Tool (`complex_api_tool.rb`)
**Level: Advanced**

A comprehensive CRM API tool demonstrating:
- Advanced API patterns with action-based routing
- Multiple HTTP methods (GET, POST, PUT, DELETE)
- Authentication and request headers
- Bulk operations and batch processing
- Error handling and recovery strategies
- Response transformation and normalization

**Key Features:**
- Action-based method routing
- Complex parameter validation
- Bulk import operations
- Analytics and reporting endpoints
- Comprehensive error handling
- Response caching and transformation

**Run the example:**
```bash
ruby complex_api_tool.rb
```

### 4. Agent with Tools (`agent_with_tools.rb`)
**Level: Intermediate**

A complete agent setup using multiple tool types:
- Mixed tool integration (basic, API, and native tools)
- Auto-discovery and namespace registration
- Agent configuration with `AgentBuilder`
- Performance testing and benchmarking
- Registry statistics and monitoring

**Key Features:**
- Calculator tool (basic computation)
- Text analyzer tool (sentiment analysis)
- Time utility tool (timezone operations)
- Weather API tool (external service)
- Code executor tool (native OpenAI)
- Multi-tool agent configuration

**Run the example:**
```bash
ruby agent_with_tools.rb
```

## Quick Start

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Set environment variables (for API examples):**
   ```bash
   export OPENWEATHER_API_KEY="your_api_key"
   export CRM_API_URL="https://your-crm-api.com/v1"
   export CRM_API_KEY="your_crm_key"
   ```

3. **Run any example:**
   ```bash
   ruby examples/tools/basic_api_tool.rb
   ```

## Code Patterns Demonstrated

### Auto-Discovery Pattern
```ruby
# Tools are automatically discovered when classes are loaded
class MyTool < RAAF::DSL::Tools::Tool
  def call(input:)
    # Implementation
  end
end

# Tool is now available globally
RAAF::DSL::Tools::ToolRegistry.get(:my_tool)
```

### Convention over Configuration
```ruby
# Auto-generates name, description, and parameter schema
class WeatherForecastTool < RAAF::DSL::Tools::Tool
  def call(city:, country: "US", units: "metric")
    # Parameters automatically inferred from method signature
  end
end
```

### API Tool Pattern
```ruby
class APITool < RAAF::DSL::Tools::Tool::API
  endpoint "https://api.example.com"
  api_key ENV['API_KEY']
  timeout 30
  
  def call(action:, **params)
    case action
    when "get_data" then get("/data", params: params)
    when "create" then post("/create", json: params)
    end
  end
end
```

### Native Tool Pattern
```ruby
class NativeTool < RAAF::DSL::Tools::Tool::Native
  tool_type "function"
  
  parameter :input, type: :string, required: true
  parameter :options, type: :object, default: {}
end
```

### Agent Integration Pattern
```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "Multi-Tool Agent"
  instructions "You have access to various tools..."
  
  use_tool :calculator      # Auto-discovered
  use_tool :weather_api     # Auto-discovered
  use_tool :code_executor   # Native tool
end
```

## Performance Considerations

The examples include performance testing and demonstrate:

- **Caching**: Tool definitions and metadata are cached for fast access
- **Thread Safety**: All operations use concurrent data structures
- **Lazy Loading**: Tools are only instantiated when needed
- **Auto-Discovery**: Minimal overhead for tool registration

Example performance results from `agent_with_tools.rb`:
```
Calculator tool performance:
  1000 calls in 0.0234s
  Average: 0.02ms per call

Registry performance:
  Registered tools: 5
  Total lookups: 15
  Cache hits: 12
  Cache hit ratio: 80.0%
```

## Error Handling Examples

Each example demonstrates different error handling patterns:

### Validation Errors
```ruby
def call(email:, **params)
  validate_email!(email)  # Raises ArgumentError for invalid emails
  # Implementation
end
```

### API Errors
```ruby
def call(**params)
  response = get("/endpoint", params: params)
  return response if response[:error]  # API error handling
  # Process successful response
end
```

### Native Tool Errors
```ruby
def call(**params)
  raise NotImplementedError, "Native tools executed by OpenAI"
end
```

## Debugging and Monitoring

The examples show how to:

1. **Monitor registry statistics:**
   ```ruby
   stats = RAAF::DSL::Tools::ToolRegistry.statistics
   puts "Cache hit ratio: #{stats[:cache_hit_ratio]}"
   ```

3. **Validate tool configurations:**
   ```ruby
   tool = MyTool.new
   pp tool.tool_configuration
   ```

## Migration Examples

See the [Tool Migration Guide](../../docs/TOOL_MIGRATION_GUIDE.md) for step-by-step migration examples from the old tool system to the new Tool DSL.

## Best Practices Demonstrated

1. **Use descriptive class names** (`WeatherForecastTool` vs `APITool`)
2. **Leverage auto-generation** for standard cases
3. **Override only when necessary** (custom names/descriptions)
4. **Handle errors gracefully** with structured error responses
5. **Validate inputs** before processing
6. **Transform responses** for consistency
7. **Use namespaces** for organization
8. **Test tool configurations** during development

## Additional Resources

- [Tool DSL Guide](../../docs/TOOL_DSL_GUIDE.md) - Complete guide to the Tool DSL
- [Tool API Reference](../../docs/TOOL_API_REFERENCE.md) - Comprehensive API documentation
- [Tool Migration Guide](../../docs/TOOL_MIGRATION_GUIDE.md) - Migration from old tools

## Support

For questions or issues with these examples:

1. Check the [documentation](../../docs/)
2. Review the [API reference](../../docs/TOOL_API_REFERENCE.md)
3. Look at the source code comments in each example
4. Test with the provided debugging tools