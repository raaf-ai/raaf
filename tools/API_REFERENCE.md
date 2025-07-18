# Tools API Reference

Complete Ruby API documentation for RAAF Tools components.

## Table of Contents

1. [Built-in Tools](#built-in-tools)
   - [FileSearchTool (Local)](#filesearchtool-local)
   - [HostedFileSearchTool (OpenAI API)](#hostedfilesearchtool-openai-api)
   - [WebSearchTool (OpenAI Hosted)](#websearchtool-openai-hosted)
   - [ComputerTool](#computertool)
   - [CodeInterpreterTool](#codeinterpretertool)
2. [Custom Tool Creation](#custom-tool-creation)
3. [Tool Interface](#tool-interface)

## Built-in Tools

### FileSearchTool (Local)

Local file search tool for searching files on the filesystem.

```ruby
# Constructor
RAAF::Tools::FileSearchTool.new(
  search_paths: Array[String],     # Directories to search (default: ["."]) 
  file_extensions: Array[String],  # File types to include (optional)
  max_results: Integer,            # Maximum results (default: 10)
  exclude_patterns: Array[String]  # Patterns to exclude (optional)
)

# Methods
tool.call(query:)                # Execute search with query string
tool.search_files(query)         # Internal search method
tool.read_file_content(path)     # Read file content safely
tool.to_tool_definition          # Get OpenAI tool definition
```

#### Example Usage

```ruby
# Basic file search
file_search = RAAF::Tools::FileSearchTool.new(
  search_paths: ["./src", "./docs"],
  file_extensions: [".rb", ".md", ".txt"],
  max_results: 20
)

# Add to agent
agent.add_tool(file_search)

# Direct usage
results = file_search.call(query: "database connection")
```

### HostedFileSearchTool (OpenAI API)

Hosted file search tool using OpenAI's file search API for searching uploaded files.

```ruby
# Constructor
RAAF::Tools::HostedFileSearchTool.new(
  file_ids: Array[String],         # OpenAI file IDs to search
  max_results: Integer,            # Maximum results (default: 10)
  ranking_options: Hash,           # Search ranking options (optional)
  api_key: String                  # OpenAI API key (optional, uses ENV)
)

# Methods
tool.call(query:)                # Execute search against uploaded files
tool.search_files(query)         # Internal search method
tool.to_tool_definition          # Get OpenAI tool definition
```

#### Example Usage

```ruby
# Upload files to OpenAI first
file_ids = ["file-abc123", "file-def456"]

# Create hosted search tool
hosted_search = RAAF::Tools::HostedFileSearchTool.new(
  file_ids: file_ids,
  max_results: 5,
  ranking_options: {
    ranker: "auto",
    score_threshold: 0.0
  }
)

# Add to agent
agent.add_tool(hosted_search)

# Direct usage
results = hosted_search.call(query: "pricing information")
```

### WebSearchTool (OpenAI Hosted)

OpenAI hosted web search tool using the Responses API.

```ruby
# Constructor
RAAF::Tools::WebSearchTool.new(
  user_location: Hash,             # { type: "approximate", city: "San Francisco" }
  search_context_size: String,     # "low", "medium", "high" (default: "medium")
  max_results: Integer,            # Maximum results (default: 5)
  api_key: String                  # OpenAI API key (optional, uses ENV)
)

# Methods
tool.call(query:)                # Execute web search
tool.search_web(query)           # Internal search method
tool.to_tool_definition          # Get OpenAI tool definition
```

#### Example Usage

```ruby
# Create web search tool
web_search = RAAF::Tools::WebSearchTool.new(
  user_location: {
    type: "approximate",
    city: "San Francisco",
    region: "CA",
    country: "US"
  },
  search_context_size: "high",  # More context for better results
  max_results: 10
)

# Add to agent
agent.add_tool(web_search)

# Direct usage
results = web_search.call(query: "latest Ruby on Rails news")
```

### ComputerTool

Tool for computer interaction capabilities (screenshots, clicks, typing, scrolling).

```ruby
# Constructor
RAAF::Tools::ComputerTool.new(
  allowed_actions: Array[Symbol],  # [:screenshot, :click, :type, :scroll]
  screen_size: Hash,              # { width: 1920, height: 1080 }
  safe_mode: Boolean              # Enable safety restrictions (default: true)
)

# Methods
tool.call(action:, **params)     # Execute computer action
tool.screenshot                  # Take screenshot
tool.click(x:, y:)              # Click at coordinates
tool.type(text:)                # Type text
tool.scroll(direction:, amount:) # Scroll screen
tool.to_tool_definition          # Get OpenAI tool definition
```

#### Example Usage

```ruby
# Create computer tool with specific permissions
computer = RAAF::Tools::ComputerTool.new(
  allowed_actions: [:screenshot, :click, :type],
  screen_size: { width: 1920, height: 1080 },
  safe_mode: true
)

# Add to agent
agent.add_tool(computer)

# Direct usage
screenshot = computer.call(action: "screenshot")
computer.call(action: "click", x: 500, y: 300)
computer.call(action: "type", text: "Hello, world!")
```

### CodeInterpreterTool

Tool for executing code in a sandboxed environment.

```ruby
# Constructor
RAAF::Tools::CodeInterpreterTool.new(
  allowed_languages: Array[String], # ["python", "ruby", "javascript"]
  timeout: Integer,                # Execution timeout in seconds (default: 30)
  memory_limit: Integer,           # Memory limit in MB (default: 128)
  safe_mode: Boolean              # Enable safety restrictions (default: true)
)

# Methods
tool.call(language:, code:)      # Execute code
tool.execute_python(code)        # Execute Python code
tool.execute_ruby(code)          # Execute Ruby code
tool.execute_javascript(code)    # Execute JavaScript code
tool.to_tool_definition          # Get OpenAI tool definition
```

#### Example Usage

```ruby
# Create code interpreter with specific languages
interpreter = RAAF::Tools::CodeInterpreterTool.new(
  allowed_languages: ["python", "ruby"],
  timeout: 60,
  memory_limit: 256,
  safe_mode: true
)

# Add to agent
agent.add_tool(interpreter)

# Direct usage
result = interpreter.call(
  language: "python",
  code: "import math\nprint(math.pi * 2)"
)

result = interpreter.call(
  language: "ruby",
  code: "puts (1..10).reduce(:+)"
)
```

## Custom Tool Creation

### Basic Custom Tool

```ruby
# Method-based tool
def calculate_compound_interest(principal:, rate:, time:, n: 12)
  amount = principal * (1 + rate / n) ** (n * time)
  interest = amount - principal
  {
    amount: amount.round(2),
    interest: interest.round(2)
  }
end

# Create tool from method
compound_interest_tool = RAAF::FunctionTool.new(
  method(:calculate_compound_interest),
  name: "calculate_compound_interest",
  description: "Calculate compound interest for an investment",
  parameters: {
    type: "object",
    properties: {
      principal: { 
        type: "number", 
        description: "Initial investment amount" 
      },
      rate: { 
        type: "number", 
        description: "Annual interest rate (as decimal, e.g., 0.05 for 5%)" 
      },
      time: { 
        type: "number", 
        description: "Time period in years" 
      },
      n: { 
        type: "integer", 
        description: "Number of times interest is compounded per year (default: 12)",
        default: 12
      }
    },
    required: ["principal", "rate", "time"]
  }
)

agent.add_tool(compound_interest_tool)
```

### Class-based Custom Tool

```ruby
class DatabaseTool < RAAF::Tools::BaseTool
  def initialize(connection_string:)
    @db = Database.connect(connection_string)
    super()
  end

  def name
    "database_query"
  end

  def description
    "Execute SQL queries against the database"
  end

  def parameters
    {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "SQL query to execute"
        },
        params: {
          type: "array",
          description: "Query parameters for prepared statements",
          items: { type: "string" }
        }
      },
      required: ["query"]
    }
  end

  def call(query:, params: [])
    # Validate query (read-only)
    unless query.strip.upcase.start_with?("SELECT")
      return { error: "Only SELECT queries are allowed" }
    end

    begin
      results = @db.execute(query, params)
      {
        rows: results,
        count: results.count
      }
    rescue => e
      { error: e.message }
    end
  end
end

# Usage
db_tool = DatabaseTool.new(connection_string: "postgres://...")
agent.add_tool(db_tool)
```

### Async Tool

```ruby
class AsyncWeatherTool < RAAF::Tools::BaseTool
  def name
    "get_weather_async"
  end

  def description
    "Get weather information asynchronously"
  end

  def parameters
    {
      type: "object",
      properties: {
        locations: {
          type: "array",
          description: "List of city names",
          items: { type: "string" }
        }
      },
      required: ["locations"]
    }
  end

  def call(locations:)
    require 'async'
    
    Async do
      tasks = locations.map do |location|
        Async do
          fetch_weather(location)
        end
      end
      
      results = tasks.map(&:wait)
      
      {
        weather_data: locations.zip(results).to_h
      }
    end.wait
  end

  private

  def fetch_weather(location)
    # Simulate API call
    sleep(0.5)
    {
      temperature: rand(60..85),
      conditions: ["sunny", "cloudy", "rainy"].sample
    }
  end
end
```

## Tool Interface

All tools must implement the following interface:

### Required Methods

```ruby
# Tool name (must be unique within an agent)
def name
  String
end

# Human-readable description
def description
  String
end

# JSON Schema for parameters
def parameters
  Hash
end

# Execute the tool
def call(**kwargs)
  # Tool implementation
  # Should return a Hash or String
end

# Convert to OpenAI tool definition
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
```

### Optional Methods

```ruby
# Validate parameters before execution
def validate_params(**kwargs)
  # Return true if valid, raise exception if not
  true
end

# Clean up resources
def cleanup
  # Optional cleanup logic
end

# Check if tool is available
def available?
  # Return true if tool can be used
  true
end
```

### Error Handling

```ruby
class SafeTool < RAAF::Tools::BaseTool
  def call(**kwargs)
    validate_params(**kwargs)
    
    begin
      # Tool logic here
      result = perform_operation(**kwargs)
      
      # Always return a hash or string
      if result.nil?
        { status: "success", message: "Operation completed" }
      else
        result
      end
    rescue StandardError => e
      # Return error information
      {
        status: "error",
        error: e.class.name,
        message: e.message
      }
    end
  end
  
  private
  
  def validate_params(**kwargs)
    # Validate required parameters
    required = parameters.dig("required") || []
    missing = required - kwargs.keys.map(&:to_s)
    
    unless missing.empty?
      raise ArgumentError, "Missing required parameters: #{missing.join(', ')}"
    end
    
    true
  end
end
```

### Tool Testing

```ruby
# Test your custom tool
tool = MyCustomTool.new

# Test parameter validation
begin
  tool.call(invalid: "params")
rescue => e
  puts "Validation error: #{e.message}"
end

# Test successful execution
result = tool.call(valid: "params")
puts "Result: #{result}"

# Test error handling
result = tool.call(trigger_error: true)
puts "Error handled: #{result[:error]}"

# Test with agent
agent = RAAF::Agent.new(name: "TestAgent", model: "gpt-4")
agent.add_tool(tool)

runner = RAAF::Runner.new(agent: agent)
result = runner.run("Use the custom tool to do something")
```

For more examples and patterns, see the main [Core API Reference](../core/API_REFERENCE.md).