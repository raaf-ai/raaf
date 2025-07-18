# RAAF Tools - Claude Code Guide

This gem provides a comprehensive collection of pre-built tools for RAAF agents, including web search, file operations, code execution, and more.

## Quick Start

```ruby
require 'raaf-tools'

# Add tools to agent
agent = RAAF::Agent.new(
  name: "ToolAgent",
  instructions: "You can use various tools to help users",
  model: "gpt-4o"
)

# Add pre-built tools
agent.add_tool(RAAF::Tools::WebSearchTool.new)
agent.add_tool(RAAF::Tools::FileSearchTool.new)
agent.add_tool(RAAF::Tools::DocumentTool.new)
```

## Available Tools

### Web Search Tool
```ruby
web_search = RAAF::Tools::WebSearchTool.new do |config|
  config.api_key = ENV['TAVILY_API_KEY']
  config.max_results = 10
  config.include_raw_content = true
  config.search_depth = "advanced"
end

agent.add_tool(web_search)

# Usage in conversation:
# User: "Search for recent Ruby on Rails updates"
# Agent will automatically use the web search tool
```

### File Search Tool
```ruby
file_search = RAAF::Tools::FileSearchTool.new do |config|
  config.search_paths = ["./docs", "./src", "./lib"]
  config.file_patterns = ["*.rb", "*.md", "*.yml"]
  config.max_file_size = 1_000_000  # 1MB
  config.respect_gitignore = true
end

agent.add_tool(file_search)
```

### Document Tool
```ruby
document_tool = RAAF::Tools::DocumentTool.new do |config|
  config.supported_formats = [:pdf, :docx, :txt, :md]
  config.extract_images = true
  config.chunk_size = 1000
  config.overlap = 200
end

agent.add_tool(document_tool)
```

### Code Interpreter Tool
```ruby
code_interpreter = RAAF::Tools::CodeInterpreterTool.new do |config|
  config.supported_languages = [:ruby, :python, :javascript]
  config.timeout = 30  # seconds
  config.sandbox_mode = true
  config.allowed_libraries = ["json", "csv", "math"]
end

agent.add_tool(code_interpreter)

# Usage:
# User: "Calculate the factorial of 10"
# Agent: [Uses code interpreter to run Ruby code]
```

### Computer Tool (Advanced)
```ruby
# Screen interaction and automation
computer_tool = RAAF::Tools::ComputerTool.new do |config|
  config.screen_resolution = "1920x1080"
  config.screenshot_quality = :high
  config.mouse_precision = :pixel_perfect
  config.keyboard_layout = :qwerty
  config.safety_mode = true  # Prevents destructive actions
end

agent.add_tool(computer_tool)
```

### Vector Search Tool
```ruby
vector_search = RAAF::Tools::VectorSearchTool.new do |config|
  config.embedding_model = "text-embedding-3-small"
  config.vector_database = :pinecone  # or :weaviate, :qdrant
  config.api_key = ENV['PINECONE_API_KEY']
  config.index_name = "knowledge_base"
end

agent.add_tool(vector_search)
```

### Local Shell Tool
```ruby
shell_tool = RAAF::Tools::LocalShellTool.new do |config|
  config.allowed_commands = ["ls", "cat", "grep", "find"]
  config.working_directory = "/safe/directory"
  config.timeout = 10
  config.capture_output = true
end

agent.add_tool(shell_tool)
```

## Tool Categories

### Basic Tools
```ruby
# Math and text utilities
agent.add_tool(RAAF::Tools::Basic::MathTools.new)
agent.add_tool(RAAF::Tools::Basic::TextTools.new)
```

### Advanced Tools
```ruby
# Code execution and computer interaction
agent.add_tool(RAAF::Tools::Advanced::CodeInterpreter.new)
agent.add_tool(RAAF::Tools::Advanced::ComputerTool.new)
```

## Custom Tools

```ruby
# Create custom tool using the base class
class WeatherTool < RAAF::Tools::Base
  def initialize
    super(
      name: "get_weather",
      description: "Get current weather for a location",
      parameters: {
        type: "object",
        properties: {
          location: {
            type: "string",
            description: "City name or coordinates"
          }
        },
        required: ["location"]
      }
    )
  end
  
  def execute(location:)
    # Call weather API
    weather_data = WeatherAPI.get_current(location)
    
    {
      temperature: weather_data[:temp],
      condition: weather_data[:condition],
      humidity: weather_data[:humidity],
      location: location
    }
  end
end

agent.add_tool(WeatherTool.new)
```

## Tool Configuration

### Global Configuration
```ruby
RAAF::Tools.configure do |config|
  config.default_timeout = 30
  config.sandbox_mode = true
  config.logging_enabled = true
  config.rate_limiting = true
end
```

### Per-Tool Configuration
```ruby
# Tool with custom error handling
web_search = RAAF::Tools::WebSearchTool.new do |config|
  config.retry_attempts = 3
  config.retry_delay = 1.0
  config.on_error = :fallback_search
  config.fallback_provider = :duckduckgo
end
```

## Tool Chaining

```ruby
# Tools can work together
agent = RAAF::Agent.new(
  name: "ResearchAgent",
  instructions: "Research topics thoroughly using multiple tools",
  model: "gpt-4o"
)

# Add complementary tools
agent.add_tool(RAAF::Tools::WebSearchTool.new)      # Find information
agent.add_tool(RAAF::Tools::DocumentTool.new)       # Process documents
agent.add_tool(RAAF::Tools::VectorSearchTool.new)   # Search knowledge base
agent.add_tool(RAAF::Tools::CodeInterpreterTool.new) # Analyze data

# Agent can now:
# 1. Search web for recent information
# 2. Download and analyze documents
# 3. Search internal knowledge base
# 4. Run calculations or data analysis
```

## Security Considerations

```ruby
# Secure tool configuration
RAAF::Tools.configure do |config|
  # Limit tool capabilities in production
  config.allow_file_write = false
  config.allow_network_access = ["api.trusted-service.com"]
  config.sandbox_all_code = true
  config.max_execution_time = 10
  
  # Audit tool usage
  config.log_all_executions = true
  config.audit_file_path = "/var/log/raaf-tools.log"
end
```

## Environment Variables

```bash
export TAVILY_API_KEY="your-tavily-key"
export PINECONE_API_KEY="your-pinecone-key"
export RAAF_TOOLS_SANDBOX="true"
export RAAF_TOOLS_TIMEOUT="30"
export RAAF_TOOLS_LOG_LEVEL="info"
```