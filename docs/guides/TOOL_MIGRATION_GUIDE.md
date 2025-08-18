# Tool Migration Guide

This guide helps you migrate existing RAAF tools to the new unified tool architecture.

## Migration Overview

The new tool system provides:
- Single base class (`RAAF::Tool`) for all tools
- Automatic registration and discovery
- Convention over configuration
- Full backward compatibility

**Important**: Your existing code will continue to work. Migration is optional but recommended for new tools.

## Migration Paths

### Path 1: FunctionTool to Unified Tool

#### Before (FunctionTool)
```ruby
# Old style with FunctionTool
class MyAgent
  def search_web(query:, max_results: 10)
    # Implementation
    "Searching for #{query}"
  end
  
  def setup_tools
    @tools = []
    @tools << FunctionTool.new(
      method(:search_web),
      name: "web_search",
      description: "Search the web for information"
    )
  end
end
```

#### After (Unified Tool)
```ruby
# New style with unified Tool
class WebSearchTool < RAAF::Tool
  def call(query:, max_results: 10)
    "Searching for #{query}"
  end
end

# Tool is automatically:
# - Named "web_search"
# - Described as "Tool for web search operations"
# - Registered in the registry
```

### Path 2: DSL Tool to Unified Tool

#### Before (DSL Tool)
```ruby
# Old DSL tool
class SearchTool < RAAF::DSL::Tools::Tool
  def name
    "search"
  end
  
  def description
    "Searches for information"
  end
  
  def call(query:)
    # Implementation
  end
  
  def tool_definition
    {
      type: "function",
      function: {
        name: name,
        description: description,
        parameters: {...}
      }
    }
  end
end
```

#### After (Unified Tool)
```ruby
# New unified tool
class SearchTool < RAAF::Tool
  # Everything is automatic!
  def call(query:)
    # Implementation
  end
end
```

### Path 3: API Tool Migration

#### Before (Complex API Tool)
```ruby
class TavilySearchTool
  def initialize
    @api_key = ENV["TAVILY_API_KEY"]
    @endpoint = "https://api.tavily.com/search"
  end
  
  def call(query:, max_results: 5)
    uri = URI(@endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = {
      api_key: @api_key,
      query: query,
      max_results: max_results
    }.to_json
    
    response = http.request(request)
    JSON.parse(response.body)
  end
end
```

#### After (Unified API Tool)
```ruby
class TavilySearchTool < RAAF::Tool::API
  endpoint "https://api.tavily.com/search"
  api_key_env "TAVILY_API_KEY"
  
  def call(query:, max_results: 5)
    post("/search", json: {
      api_key: api_key,
      query: query,
      max_results: max_results
    })
  end
end
```

### Path 4: Native Tool Migration

#### Before (Native Tool with Complex Definition)
```ruby
class WebSearchNativeTool
  def to_h
    {
      type: "web_search",
      web_search: {
        enabled: true
      }
    }
  end
  
  def name
    "web_search"
  end
  
  def enabled?
    true
  end
end
```

#### After (Unified Native Tool)
```ruby
class WebSearchTool < RAAF::Tool::Native
  configure name: "web_search"
  
  native_config do
    web_search true
  end
end
```

## Step-by-Step Migration Process

### Step 1: Identify Tool Type

Determine which category your tool falls into:
- **Function Tool**: Regular Ruby methods
- **API Tool**: External service calls
- **Native Tool**: OpenAI infrastructure tools

### Step 2: Choose Base Class

```ruby
# For regular tools
class MyTool < RAAF::Tool

# For API tools
class MyAPITool < RAAF::Tool::API

# For native tools
class MyNativeTool < RAAF::Tool::Native
```

### Step 3: Migrate Core Logic

Move your execution logic to the `call` method:

```ruby
class MyTool < RAAF::Tool
  def call(param1:, param2: "default")
    # Your existing logic here
  end
end
```

### Step 4: Migrate Configuration

#### Explicit Parameters (if needed)
```ruby
class MyTool < RAAF::Tool
  parameters do
    property :text, type: "string", description: "Input text"
    property :mode, type: "string", enum: ["fast", "slow"]
    required :text
  end
end
```

#### Custom Name/Description (if needed)
```ruby
class MyTool < RAAF::Tool
  configure name: "custom_name",
           description: "Custom description"
end
```

### Step 5: Update Agent Integration

#### Before
```ruby
class MyAgent < RAAF::Agent
  def initialize
    add_tool(FunctionTool.new(method(:my_method)))
    add_tool(OldStyleTool.new)
  end
end
```

#### After
```ruby
class MyAgent < RAAF::DSL::Agent
  tool :my_tool        # Auto-discovery
  tool MyNewTool      # Direct reference
end
```

## Gradual Migration Strategy

You don't need to migrate everything at once:

### Phase 1: New Tools Only
- Keep existing tools as-is
- Write new tools using unified architecture
- Both will work together

### Phase 2: High-Use Tools
- Migrate frequently used tools
- Test thoroughly
- Keep old version as backup

### Phase 3: Complete Migration
- Migrate remaining tools
- Remove old tool code
- Update documentation

## Compatibility Features

### Using Old and New Together

```ruby
class MyAgent < RAAF::DSL::Agent
  # Mix old and new style tools
  tool MyNewUnifiedTool           # New style
  uses_tool :old_style_tool       # Old style (still works)
  
  def initialize
    # Can still add tools the old way
    add_tool(FunctionTool.new(method(:helper)))
  end
end
```

### Automatic Conversion

The compatibility layer automatically converts between formats:

```ruby
# Old FunctionTool
old_tool = FunctionTool.new(method(:search))

# Automatically works with new system
agent.tool old_tool  # Converted internally
```

## Common Migration Patterns

### Pattern 1: Simple Method to Tool

```ruby
# Before: Method in agent
def calculate(expression:)
  eval(expression)
end

# After: Standalone tool
class CalculatorTool < RAAF::Tool
  def call(expression:)
    eval(expression)
  end
end
```

### Pattern 2: Tool with State

```ruby
# Before: Instance variables
class CounterTool
  def initialize
    @count = 0
  end
  
  def call
    @count += 1
  end
end

# After: Still works the same
class CounterTool < RAAF::Tool
  def initialize(**options)
    super
    @count = 0
  end
  
  def call
    @count += 1
  end
end
```

### Pattern 3: Complex Parameters

```ruby
# Before: Manual parameter definition
def parameters_schema
  {
    type: "object",
    properties: {
      data: {
        type: "array",
        items: { type: "string" }
      }
    }
  }
end

# After: DSL-based definition
parameters do
  property :data, type: "array", items: { type: "string" }
  required :data
end
```

## Testing Your Migration

### Unit Test Template

```ruby
RSpec.describe MyMigratedTool do
  let(:tool) { described_class.new }
  
  it "has correct name" do
    expect(tool.name).to eq("my_migrated")
  end
  
  it "executes correctly" do
    result = tool.call(input: "test")
    expect(result).to eq(expected_output)
  end
  
  it "generates correct definition" do
    definition = tool.to_tool_definition
    expect(definition[:type]).to eq("function")
    expect(definition[:function][:name]).to eq("my_migrated")
  end
  
  it "converts to FunctionTool for compatibility" do
    function_tool = tool.to_function_tool
    expect(function_tool).to be_a(RAAF::FunctionTool)
    expect(function_tool.callable?).to be true
  end
end
```

### Integration Test

```ruby
RSpec.describe "Tool Integration" do
  it "works with agents" do
    agent = Class.new(RAAF::DSL::Agent) do
      tool MyMigratedTool
    end.new
    
    expect(agent.tools).to include_tool_named("my_migrated")
  end
end
```

## Troubleshooting

### Issue: Tool Not Found

```ruby
# Problem
agent.tool :my_tool  # => Tool not found

# Solution 1: Check naming convention
class MyToolTool < RAAF::Tool  # Note: "Tool" suffix
  # Will be found as :my_tool
end

# Solution 2: Explicit registration
RAAF::ToolRegistry.register("my_tool", MyCustomClass)
```

### Issue: Parameters Not Working

```ruby
# Problem: Parameters not extracted
class MyTool < RAAF::Tool
  def call(input)  # Wrong: positional parameter
    # ...
  end
end

# Solution: Use keyword parameters
class MyTool < RAAF::Tool
  def call(input:)  # Correct: keyword parameter
    # ...
  end
end
```

### Issue: API Key Not Found

```ruby
# Problem
class APITool < RAAF::Tool::API
  api_key ENV["KEY"]  # Evaluated at class load time
end

# Solution: Use api_key_env
class APITool < RAAF::Tool::API
  api_key_env "KEY"  # Evaluated at runtime
end
```

## Migration Checklist

- [ ] Identify all existing tools
- [ ] Categorize tools (Function/API/Native)
- [ ] Create new tool classes with appropriate base class
- [ ] Migrate `call` method implementation
- [ ] Add parameter definitions if needed
- [ ] Update agent tool references
- [ ] Test each migrated tool
- [ ] Update documentation
- [ ] Remove old tool code (when ready)

## Getting Help

If you encounter issues during migration:

1. Enable debug logging: `RAAF_DEBUG_CATEGORIES=tools,registry`
2. Check the [Unified Tools Documentation](../UNIFIED_TOOLS.md)
3. Review the [examples/tools/unified_tools_example.rb](../../examples/tools/unified_tools_example.rb)
4. File an issue with your specific migration challenge

## Summary

The new unified tool architecture simplifies tool development while maintaining full backward compatibility. You can migrate at your own pace, and both old and new tools will work together seamlessly.