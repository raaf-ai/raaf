# Tool Migration Guide

> Version: 1.0.0
> Last Updated: 2025-01-16

## Table of Contents

- [Overview](#overview)
- [Migration Strategy](#migration-strategy)
- [Before and After Comparisons](#before-and-after-comparisons)
- [Step-by-Step Migration](#step-by-step-migration)
- [Common Patterns](#common-patterns)
- [Troubleshooting](#troubleshooting)
- [Validation and Testing](#validation-and-testing)

## Overview

This guide helps you migrate from the old tool system to the new unified Tool DSL. The new system provides better performance, automatic registration, and a more intuitive API while maintaining full backward compatibility during the transition period.

### Migration Benefits

- **Simplified Code**: Reduce boilerplate by 60-80%
- **Auto-Discovery**: No manual tool registration required
- **Better Performance**: Built-in caching and optimization
- **Type Safety**: Automatic parameter validation
- **Unified Interface**: Consistent `call` method across all tools
- **Enhanced Error Handling**: Better error messages and debugging

### Compatibility

- **Backward Compatible**: Old tools continue to work during migration
- **Gradual Migration**: Migrate tools one at a time
- **Mixed Usage**: New and old tools can coexist in the same agent

## Migration Strategy

### Phase 1: Assessment (1-2 days)

1. **Inventory Existing Tools**: Document all current tools and their usage
2. **Identify Complexity**: Categorize tools by migration complexity
3. **Plan Migration Order**: Start with simple tools, progress to complex ones

### Phase 2: Foundation (1 day)

1. **Update Dependencies**: Ensure you have the latest RAAF DSL version
2. **Setup Auto-Discovery**: Configure tool namespaces for auto-registration
3. **Create Test Environment**: Setup testing for both old and new tools

### Phase 3: Migration (1-2 weeks)

1. **Start with Simple Tools**: Migrate basic tools first
2. **Test Each Migration**: Validate functionality after each tool migration
3. **Update Agent Configurations**: Switch agents to use new tools
4. **Performance Testing**: Verify performance improvements

### Phase 4: Cleanup (1-2 days)

1. **Remove Old Tool Code**: Clean up deprecated tool implementations
2. **Update Documentation**: Document new tool patterns and usage
3. **Final Testing**: Comprehensive testing of all migrated tools

## Before and After Comparisons

### Basic Tool Migration

**Before (Old System):**
```ruby
class WeatherTool
  def initialize(api_key:)
    @api_key = api_key
  end
  
  def name
    "weather"
  end
  
  def description
    "Get weather information for a city"
  end
  
  def parameters
    {
      type: "object",
      properties: {
        city: { type: "string", description: "City name" },
        units: { type: "string", enum: ["celsius", "fahrenheit"], default: "celsius" }
      },
      required: ["city"],
      additionalProperties: false
    }
  end
  
  def execute(city:, units: "celsius")
    # Implementation
    api_call(city, units)
  end
  
  def to_tool_definition
    {
      type: "function",
      function: {
        name: name,
        description: description,
        parameters: parameters
      }
    }
  end
  
  private
  
  def api_call(city, units)
    # HTTP request implementation
    uri = URI("https://api.weather.com/v1/current")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    
    response = http.request(request)
    JSON.parse(response.body)
  end
end

# Manual registration required
agent.add_tool(WeatherTool.new(api_key: ENV['WEATHER_API_KEY']))
```

**After (New Tool DSL):**
```ruby
class WeatherTool < RAAF::DSL::Tools::Tool::API
  endpoint "https://api.weather.com/v1/current"
  api_key ENV['WEATHER_API_KEY']
  
  # Auto-generates: name, description, parameters from method signature
  def call(city:, units: "celsius")
    get(params: { q: city, units: units, key: api_key })
  end
end

# Auto-discovery: No manual registration needed!
# Tool automatically available when class is loaded
```

**Lines of Code Reduction: 47 lines → 8 lines (83% reduction)**

### API Tool Migration

**Before (Old System):**
```ruby
class SlackTool
  def initialize(token:)
    @token = token
    @base_url = "https://slack.com/api"
  end
  
  def name
    "slack_message"
  end
  
  def description
    "Send a message to a Slack channel"
  end
  
  def parameters
    {
      type: "object",
      properties: {
        channel: { type: "string", description: "Slack channel ID or name" },
        message: { type: "string", description: "Message to send" },
        thread_ts: { type: "string", description: "Thread timestamp for replies" }
      },
      required: ["channel", "message"],
      additionalProperties: false
    }
  end
  
  def execute(channel:, message:, thread_ts: nil)
    uri = URI("#{@base_url}/chat.postMessage")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@token}"
    request["Content-Type"] = "application/json"
    
    payload = { channel: channel, text: message }
    payload[:thread_ts] = thread_ts if thread_ts
    request.body = payload.to_json
    
    response = http.request(request)
    
    if response.code.to_i >= 200 && response.code.to_i < 300
      JSON.parse(response.body)
    else
      { error: "HTTP #{response.code}", message: response.body }
    end
  rescue => e
    { error: e.class.name, message: e.message }
  end
  
  def to_tool_definition
    {
      type: "function",
      function: {
        name: name,
        description: description,
        parameters: parameters
      }
    }
  end
end
```

**After (New Tool DSL):**
```ruby
class SlackTool < RAAF::DSL::Tools::Tool::API
  endpoint "https://slack.com/api"
  
  def call(channel:, message:, thread_ts: nil)
    payload = { channel: channel, text: message }
    payload[:thread_ts] = thread_ts if thread_ts
    
    post("/chat.postMessage", 
         json: payload,
         headers: { "Authorization" => "Bearer #{ENV['SLACK_TOKEN']}" })
  end
end
```

**Lines of Code Reduction: 58 lines → 12 lines (79% reduction)**

### Native Tool Migration

**Before (Old System):**
```ruby
class CodeInterpreterTool
  def name
    "code_interpreter"
  end
  
  def description
    "Execute Python code in a sandboxed environment"
  end
  
  def parameters
    {
      type: "object",
      properties: {
        code: { 
          type: "string", 
          description: "Python code to execute" 
        }
      },
      required: ["code"],
      additionalProperties: false
    }
  end
  
  def execute(code:)
    raise NotImplementedError, "Native tools are executed by OpenAI"
  end
  
  def to_tool_definition
    {
      type: "code_interpreter"
    }
  end
  
  def native?
    true
  end
end
```

**After (New Tool DSL):**
```ruby
class CodeInterpreterTool < RAAF::DSL::Tools::Tool::Native
  tool_type "code_interpreter"
  
  configure name: "code_interpreter",
            description: "Execute Python code in a sandboxed environment"
end
```

**Lines of Code Reduction: 32 lines → 6 lines (81% reduction)**

## Step-by-Step Migration

### Step 1: Setup the New System

First, ensure you have the latest RAAF DSL and configure auto-discovery:

```ruby
# In your application initialization
RAAF::DSL::Tools::ToolRegistry.register_namespace("MyApp::Tools")
RAAF::DSL::Tools::ToolRegistry.auto_discover_tools
```

### Step 2: Create a New Tool Namespace

Organize your new tools in a dedicated namespace:

```ruby
# app/tools/my_app/tools/base.rb
module MyApp
  module Tools
    class Base < RAAF::DSL::Tools::Tool
      # Common functionality for your tools
    end
  end
end
```

### Step 3: Migrate Your First Tool

Start with the simplest tool. Here's a complete example:

**Original Tool:**
```ruby
class CalculatorTool
  def name
    "calculator"
  end
  
  def description
    "Perform basic mathematical operations"
  end
  
  def parameters
    {
      type: "object",
      properties: {
        operation: { type: "string", enum: ["add", "subtract", "multiply", "divide"] },
        a: { type: "number" },
        b: { type: "number" }
      },
      required: ["operation", "a", "b"]
    }
  end
  
  def execute(operation:, a:, b:)
    case operation
    when "add" then { result: a + b }
    when "subtract" then { result: a - b }
    when "multiply" then { result: a * b }
    when "divide" then b.zero? ? { error: "Division by zero" } : { result: a.to_f / b }
    end
  end
  
  def to_tool_definition
    {
      type: "function",
      function: {
        name: name,
        description: description,
        parameters: parameters
      }
    }
  end
end
```

**Migrated Tool:**
```ruby
# app/tools/my_app/tools/calculator_tool.rb
module MyApp
  module Tools
    class CalculatorTool < Base
      def call(operation:, a:, b:)
        case operation
        when "add" then { result: a + b }
        when "subtract" then { result: a - b }
        when "multiply" then { result: a * b }
        when "divide" then b.zero? ? { error: "Division by zero" } : { result: a.to_f / b }
        end
      end
    end
  end
end
```

### Step 4: Test the Migration

Create tests to verify the migration:

```ruby
# spec/tools/calculator_tool_spec.rb
RSpec.describe MyApp::Tools::CalculatorTool do
  subject(:tool) { described_class.new }
  
  describe "#call" do
    it "performs addition" do
      result = tool.call(operation: "add", a: 5, b: 3)
      expect(result[:result]).to eq(8)
    end
    
    it "handles division by zero" do
      result = tool.call(operation: "divide", a: 5, b: 0)
      expect(result[:error]).to eq("Division by zero")
    end
  end
  
  describe "auto-generated metadata" do
    it "generates correct tool name" do
      expect(tool.name).to eq("calculator")
    end
    
    it "generates tool description" do
      expect(tool.description).to include("calculator")
    end
    
    it "generates parameter schema" do
      schema = tool.to_tool_definition[:function][:parameters]
      expect(schema[:properties].keys).to include("operation", "a", "b")
    end
  end
end
```

### Step 5: Update Agent Configuration

Switch your agents to use the new tool:

**Before:**
```ruby
agent = RAAF::Agent.new(
  name: "Calculator Agent",
  instructions: "You can perform calculations",
  tools: [CalculatorTool.new]  # Manual instantiation
)
```

**After:**
```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "Calculator Agent"
  instructions "You can perform calculations"
  
  # Auto-discovery finds the tool by name
  use_tool :calculator
  
  # Or use the class directly
  # use_tool MyApp::Tools::CalculatorTool
end
```

### Step 6: Migrate Complex Tools

For more complex tools like API integrations:

**Original API Tool:**
```ruby
class CRMTool
  def initialize(api_key:, base_url:)
    @api_key = api_key
    @base_url = base_url
  end
  
  def execute(action:, **params)
    case action
    when "create_contact"
      create_contact(params)
    when "search_contacts"
      search_contacts(params)
    end
  end
  
  private
  
  def create_contact(name:, email:)
    # Complex HTTP handling...
  end
  
  def search_contacts(query:)
    # Complex HTTP handling...
  end
end
```

**Migrated API Tool:**
```ruby
module MyApp
  module Tools
    class CRMTool < RAAF::DSL::Tools::Tool::API
      endpoint ENV['CRM_BASE_URL']
      api_key ENV['CRM_API_KEY']
      timeout 30
      
      def call(action:, **params)
        case action
        when "create_contact"
          create_contact(params)
        when "search_contacts"
          search_contacts(params)
        else
          { error: "Unknown action: #{action}" }
        end
      end
      
      private
      
      def create_contact(name:, email:, **options)
        post("/contacts", 
             json: { name: name, email: email, **options },
             headers: auth_headers)
      end
      
      def search_contacts(query:, limit: 10)
        get("/contacts/search", 
            params: { q: query, limit: limit },
            headers: auth_headers)
      end
      
      def auth_headers
        { "X-API-Key" => api_key }
      end
    end
  end
end
```

## Common Patterns

### Pattern 1: Custom Parameter Validation

**Before:**
```ruby
def execute(input:)
  raise ArgumentError, "Input cannot be empty" if input.empty?
  # Implementation
end
```

**After:**
```ruby
def call(input:)
  validate_input!(input)
  # Implementation
end

private

def validate_input!(input)
  raise ArgumentError, "Input cannot be empty" if input.empty?
end
```

### Pattern 2: Result Post-Processing

**Before:**
```ruby
def execute(**params)
  result = perform_operation(params)
  result.merge(timestamp: Time.now, tool_version: "1.0")
end
```

**After:**
```ruby
def call(**params)
  raw_result = perform_operation(params)
  process_result(raw_result)
end

def process_result(result)
  result.merge(timestamp: Time.now, tool_version: "1.0")
end
```

### Pattern 3: Conditional Tool Availability

**Before:**
```ruby
class ProductionOnlyTool
  def available?
    Rails.env.production?
  end
  
  def execute(**params)
    raise "Tool not available" unless available?
    # Implementation
  end
end
```

**After:**
```ruby
class ProductionOnlyTool < RAAF::DSL::Tools::Tool
  configure enabled: Rails.env.production?
  
  def call(**params)
    # Implementation - availability handled automatically
  end
end
```

### Pattern 4: Tool with Multiple Actions

**Before:**
```ruby
class MultiActionTool
  def execute(action:, **params)
    case action
    when "create" then create_resource(params)
    when "update" then update_resource(params)
    when "delete" then delete_resource(params)
    end
  end
end
```

**After (Option 1: Keep as single tool):**
```ruby
class MultiActionTool < RAAF::DSL::Tools::Tool
  def call(action:, **params)
    case action
    when "create" then create_resource(params)
    when "update" then update_resource(params)
    when "delete" then delete_resource(params)
    else { error: "Unknown action: #{action}" }
    end
  end
end
```

**After (Option 2: Split into separate tools):**
```ruby
class CreateResourceTool < RAAF::DSL::Tools::Tool
  def call(**params)
    create_resource(params)
  end
end

class UpdateResourceTool < RAAF::DSL::Tools::Tool
  def call(id:, **params)
    update_resource(id, params)
  end
end

class DeleteResourceTool < RAAF::DSL::Tools::Tool
  def call(id:)
    delete_resource(id)
  end
end
```

### Pattern 5: Shared Configuration

**Before:**
```ruby
class APIToolBase
  def initialize(api_key:, base_url:)
    @api_key = api_key
    @base_url = base_url
  end
  
  def auth_headers
    { "Authorization" => "Bearer #{@api_key}" }
  end
end

class SpecificAPITool < APIToolBase
  def execute(**params)
    # Implementation using auth_headers
  end
end
```

**After:**
```ruby
module MyApp
  module Tools
    class APIBase < RAAF::DSL::Tools::Tool::API
      endpoint ENV['API_BASE_URL']
      api_key ENV['API_KEY']
      timeout 30
      
      private
      
      def auth_headers
        { "Authorization" => "Bearer #{api_key}" }
      end
    end
  end
end

class SpecificAPITool < MyApp::Tools::APIBase
  def call(**params)
    get("/endpoint", headers: auth_headers)
  end
end
```

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: Tool Not Auto-Discovered

**Symptom:**
```ruby
RAAF::DSL::Tools::ToolRegistry.get(:my_tool)
# => ToolNotFoundError: Tool 'my_tool' not found
```

**Solutions:**

1. **Check namespace registration:**
```ruby
# Ensure your tool's namespace is registered
RAAF::DSL::Tools::ToolRegistry.register_namespace("MyApp::Tools")
```

2. **Verify class naming:**
```ruby
# Tool class should end with "Tool"
class MyTool < RAAF::DSL::Tools::Tool  # ✓ Good
class MyHelper < RAAF::DSL::Tools::Tool  # ✗ Won't auto-discover
```

3. **Manual registration:**
```ruby
# Register manually if auto-discovery fails
RAAF::DSL::Tools::ToolRegistry.register(:my_tool, MyApp::Tools::MyTool)
```

#### Issue 2: Parameter Schema Not Generated

**Symptom:**
Tool works but parameter schema is empty or incorrect.

**Solution:**
Ensure `call` method uses keyword arguments:

```ruby
# ✓ Good - generates parameter schema
def call(name:, age: 25, active: true)
  # Implementation
end

# ✗ Bad - cannot generate schema
def call(params)
  # Implementation
end
```

#### Issue 3: API Tool Connection Issues

**Symptom:**
API tools fail to connect or return unexpected responses.

**Solutions:**

1. **Check endpoint configuration:**
```ruby
class MyAPITool < RAAF::DSL::Tools::Tool::API
  endpoint "https://api.example.com/v1"  # Include version in URL
  timeout 30  # Increase timeout for slow APIs
end
```

2. **Verify authentication:**
```ruby
def call(**params)
  # Test API key is working
  raise "API key not configured" unless api_key
  
  get("/test", headers: { "Authorization" => "Bearer #{api_key}" })
end
```

3. **Debug HTTP requests:**
```ruby
def call(**params)
  response = get("/endpoint", params: params)
  
  # Add debugging information
  if response[:error]
    puts "API Error: #{response}"
  end
  
  response
end
```

#### Issue 4: Native Tool Configuration

**Symptom:**
Native tools not appearing in OpenAI tool definitions.

**Solution:**
Ensure proper tool type configuration:

```ruby
class MyNativeTool < RAAF::DSL::Tools::Tool::Native
  tool_type "function"  # Required for custom native tools
  
  configure name: "my_function",
            description: "Clear description"
  
  parameter :input, type: :string, required: true
end
```

#### Issue 5: Performance Issues

**Symptom:**
Tool registration or lookup is slow.

**Solutions:**

1. **Check registry statistics:**
```ruby
stats = RAAF::DSL::Tools::ToolRegistry.statistics
puts "Cache hit ratio: #{stats[:cache_hit_ratio]}"
```

2. **Optimize tool loading:**
```ruby
# Use lazy loading for expensive tools
class ExpensiveTool < RAAF::DSL::Tools::Tool
  def call(**params)
    expensive_resource = ExpensiveResource.instance
    # Implementation
  end
end
```

3. **Batch tool registration:**
```ruby
# Register multiple tools at once
tools = [Tool1, Tool2, Tool3]
tools.each { |tool_class| tool_class.new }  # Triggers auto-registration
```

### Debug Mode

Enable debug logging to troubleshoot issues:

```ruby
# Enable debug mode for tool registry
RAAF.logger.level = Logger::DEBUG

# Check registry contents
pp RAAF::DSL::Tools::ToolRegistry.tool_info

# Verify tool configuration
tool = MyTool.new
pp tool.tool_configuration
```

## Validation and Testing

### Migration Validation Checklist

Use this checklist to validate each migrated tool:

```ruby
# spec/support/tool_migration_helper.rb
module ToolMigrationHelper
  def validate_migrated_tool(old_tool_instance, new_tool_class)
    new_tool = new_tool_class.new
    
    # Test 1: Basic functionality
    expect(new_tool).to respond_to(:call)
    
    # Test 2: Auto-registration
    tool_name = new_tool.name.to_sym
    expect(RAAF::DSL::Tools::ToolRegistry.registered?(tool_name)).to be true
    
    # Test 3: Tool definition compatibility
    old_definition = old_tool_instance.to_tool_definition
    new_definition = new_tool.to_tool_definition
    
    expect(new_definition[:function][:name]).to eq(old_definition[:function][:name])
    expect(new_definition[:function][:description]).to be_present
    
    # Test 4: Parameter compatibility
    old_params = old_definition[:function][:parameters][:properties].keys
    new_params = new_definition[:function][:parameters][:properties].keys
    
    expect(new_params).to match_array(old_params)
    
    # Test 5: Execution compatibility
    test_params = generate_test_params(old_params)
    
    begin
      old_result = old_tool_instance.execute(**test_params)
      new_result = new_tool.call(**test_params)
      
      # Results should be functionally equivalent
      expect(new_result.keys).to include(*old_result.keys)
    rescue => e
      # Log any execution differences for manual review
      puts "Execution difference detected: #{e.message}"
    end
  end
  
  private
  
  def generate_test_params(param_names)
    # Generate safe test parameters for validation
    param_names.each_with_object({}) do |param, hash|
      hash[param.to_sym] = case param.to_s
                          when /name|title/ then "test"
                          when /count|limit|size/ then 1
                          when /enabled|active/ then true
                          else "test_value"
                          end
    end
  end
end
```

### Comprehensive Test Suite

```ruby
# spec/tools/migration_spec.rb
RSpec.describe "Tool Migration" do
  include ToolMigrationHelper
  
  describe "Calculator Tool Migration" do
    let(:old_tool) { CalculatorTool.new }
    let(:new_tool_class) { MyApp::Tools::CalculatorTool }
    
    it "maintains functional compatibility" do
      validate_migrated_tool(old_tool, new_tool_class)
    end
    
    it "improves performance" do
      new_tool = new_tool_class.new
      
      # Measure tool definition generation
      old_time = Benchmark.measure { 1000.times { old_tool.to_tool_definition } }
      new_time = Benchmark.measure { 1000.times { new_tool.to_tool_definition } }
      
      expect(new_time.real).to be < old_time.real
    end
  end
  
  describe "Registry Integration" do
    it "auto-discovers migrated tools" do
      expect(RAAF::DSL::Tools::ToolRegistry.get(:calculator)).to eq(MyApp::Tools::CalculatorTool)
    end
    
    it "provides error suggestions" do
      expect {
        RAAF::DSL::Tools::ToolRegistry.get(:calcuator, strict: true)
      }.to raise_error(RAAF::DSL::Tools::ToolRegistry::ToolNotFoundError, /Did you mean.*calculator/)
    end
  end
end
```

### Performance Benchmarking

```ruby
# scripts/benchmark_migration.rb
require 'benchmark'

def benchmark_tool_performance(iterations = 1000)
  # Old tool benchmark
  old_tool = OldCalculatorTool.new
  old_time = Benchmark.measure do
    iterations.times do
      old_tool.to_tool_definition
      old_tool.execute(operation: "add", a: 1, b: 2)
    end
  end
  
  # New tool benchmark
  new_tool = MyApp::Tools::CalculatorTool.new
  new_time = Benchmark.measure do
    iterations.times do
      new_tool.to_tool_definition
      new_tool.call(operation: "add", a: 1, b: 2)
    end
  end
  
  puts "Performance Comparison (#{iterations} iterations):"
  puts "Old Tool: #{old_time.real.round(4)}s"
  puts "New Tool: #{new_time.real.round(4)}s"
  puts "Improvement: #{((old_time.real - new_time.real) / old_time.real * 100).round(1)}%"
end

benchmark_tool_performance
```

This migration guide provides a comprehensive path from the old tool system to the new Tool DSL, with practical examples, troubleshooting tips, and validation strategies to ensure a successful migration.