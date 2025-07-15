# RAAF Tools Basic

[![Gem Version](https://badge.fury.io/rb/raaf-tools-basic.svg)](https://badge.fury.io/rb/raaf-tools-basic)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Essential tools and utilities for Ruby AI Agents Factory (RAAF). This gem provides basic tools that extend AI agent capabilities with common utility functions including mathematical calculations, text processing, file operations, web scraping, API calls, and data manipulation.

## Overview

RAAF (Ruby AI Agents Factory) Tools Basic provides the foundational tools that AI agents need for everyday tasks. These tools are designed to be safe, secure, and easy to use, providing agents with capabilities beyond text generation.

## Features

- **Mathematical Tools** - Safe arithmetic calculations, unit conversions, random number generation, and statistical analysis
- **Text Processing** - Word counting, text summarization, formatting, searching, replacement, and validation
- **File Operations** - Read, write, and manipulate files with proper security controls
- **Web Scraping** - Extract data from web pages with rate limiting and respect for robots.txt
- **API Calls** - Make HTTP requests to external APIs with authentication and error handling
- **Data Manipulation** - CSV/JSON processing, data transformation, and format conversion
- **Security First** - All tools include input validation and security controls
- **Extensible** - Easy to add custom tools following established patterns

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-tools-basic'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install raaf-tools-basic
```

## Quick Start

### Basic Usage

```ruby
require 'raaf-tools-basic'

# Create an agent with basic tools
agent = RubyAIAgentsFactory::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant with basic tools",
  model: "gpt-4o"
)

# Add all basic tools at once
RubyAIAgentsFactory::Tools::Basic.add_all_tools(agent)

# Or add individual tools
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.calculator)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.text_processor)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.file_handler)

# Run the agent
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("Calculate 15 * 23 and summarize this text: 'The quick brown fox jumps over the lazy dog multiple times.'")
puts result.messages.last[:content]
```

### With Configuration

```ruby
require 'raaf-tools-basic'

# Configure basic tools
RubyAIAgentsFactory::Tools::Basic.configure do |config|
  config.math_tools.precision = 6
  config.text_tools.max_length = 1000
  config.file_tools.max_size = 10 * 1024 * 1024  # 10MB
  config.web_tools.timeout = 30
  config.api_tools.rate_limit = 60  # requests per minute
end

# Create agent with configured tools
agent = RubyAIAgentsFactory::Agent.new(
  name: "ConfiguredAgent",
  instructions: "You have access to configured basic tools"
)

RubyAIAgentsFactory::Tools::Basic.add_all_tools(agent)
```

## Available Tools

### Mathematical Tools

Safe mathematical operations with security controls:

```ruby
# Calculator tool
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.calculator)

# Unit conversion tool
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.unit_converter)

# Random number generator
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.random_generator)

# Statistical analysis
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.statistics)

# Example usage:
# "Calculate 15 * 23"
# "Convert 100 kilometers to miles"
# "Generate a random number between 1 and 100"
# "Analyze these numbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]"
```

**Available Operations:**
- Basic arithmetic: `+`, `-`, `*`, `/`, `()` with proper precedence
- Unit conversions: length, weight, temperature, volume
- Random generation: integers, floats, strings, UUIDs, choices
- Statistics: mean, median, mode, standard deviation, quartiles, outliers

### Text Processing Tools

Comprehensive text manipulation capabilities:

```ruby
# Word counting
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.word_counter)

# Text summarization
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.text_summarizer)

# Text formatting
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.text_formatter)

# Text search and replace
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.text_search)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.text_replace)

# Text validation
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.text_validator)

# Example usage:
# "Count words in this document"
# "Summarize this article in 200 words"
# "Convert this text to title case"
# "Find all email addresses in this text"
# "Replace all instances of 'old' with 'new'"
# "Validate this email address"
```

**Available Operations:**
- Word/character/line counting with paragraph detection
- Extractive summarization using word frequency scoring
- Text formatting: uppercase, lowercase, capitalize, title case, sentence case
- Pattern search with case sensitivity options
- Global/single replacement with regex support
- Validation: email, URL, phone, credit card, UUID formats

### File Operations

Secure file handling with proper access controls:

```ruby
# File operations
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.file_reader)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.file_writer)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.file_manager)

# Directory operations
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.directory_manager)

# Example usage:
# "Read the contents of config.json"
# "Write this data to output.txt"
# "List all files in the documents folder"
# "Create a new directory called 'reports'"
# "Delete the temporary file temp.log"
```

**Available Operations:**
- File reading with encoding detection and size limits
- File writing with backup and atomic operations
- Directory listing with filtering and sorting
- File/directory creation, deletion, and management
- Path validation and security checks

### Web Scraping

Respectful web scraping with rate limiting:

```ruby
# Web scraping
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.web_scraper)

# URL operations
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.url_manager)

# Example usage:
# "Extract the main content from https://example.com"
# "Get all links from this webpage"
# "Download the image from this URL"
# "Check if this website is accessible"
```

**Available Operations:**
- HTML content extraction with CSS selectors
- Link extraction and validation
- Image and file downloading
- Robots.txt compliance checking
- Rate limiting and request throttling
- User-agent rotation and header management

### API Calls

HTTP client for external API integration:

```ruby
# API client
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.api_client)

# Example usage:
# "Make a GET request to https://api.example.com/users"
# "POST this data to the webhook URL"
# "Get weather data from the weather API"
```

**Available Operations:**
- HTTP methods: GET, POST, PUT, DELETE, PATCH
- Authentication: Bearer tokens, API keys, Basic auth
- Request/response handling with proper error handling
- JSON/XML parsing and formatting
- Rate limiting and retry logic

### Data Manipulation

CSV, JSON, and data transformation tools:

```ruby
# Data processors
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.csv_processor)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.json_processor)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.data_transformer)

# Example usage:
# "Parse this CSV file and show the first 10 rows"
# "Convert this JSON to CSV format"
# "Transform this data by grouping by category"
# "Filter this dataset where age > 25"
```

**Available Operations:**
- CSV reading/writing with header detection
- JSON parsing and formatting with validation
- Data filtering, sorting, and grouping
- Format conversion between CSV, JSON, XML
- Data validation and cleaning

## Configuration

### Global Configuration

```ruby
RubyAIAgentsFactory::Tools::Basic.configure do |config|
  # Mathematical tools
  config.math_tools.precision = 6
  config.math_tools.max_expression_length = 200
  
  # Text tools
  config.text_tools.max_length = 1000
  config.text_tools.summarization_ratio = 0.3
  
  # File tools
  config.file_tools.max_size = 10 * 1024 * 1024  # 10MB
  config.file_tools.allowed_extensions = ['.txt', '.json', '.csv']
  config.file_tools.base_path = '/safe/directory'
  
  # Web tools
  config.web_tools.timeout = 30
  config.web_tools.max_redirects = 5
  config.web_tools.respect_robots_txt = true
  config.web_tools.rate_limit = 60  # requests per minute
  
  # API tools
  config.api_tools.timeout = 30
  config.api_tools.rate_limit = 60
  config.api_tools.max_response_size = 5 * 1024 * 1024  # 5MB
  
  # Data tools
  config.data_tools.max_rows = 10000
  config.data_tools.max_file_size = 50 * 1024 * 1024  # 50MB
end
```

### Environment Variables

```bash
# File operations
export RAAF_FILE_MAX_SIZE="10485760"  # 10MB
export RAAF_FILE_BASE_PATH="/safe/directory"

# Web scraping
export RAAF_WEB_TIMEOUT="30"
export RAAF_WEB_RATE_LIMIT="60"
export RAAF_WEB_RESPECT_ROBOTS="true"

# API calls
export RAAF_API_TIMEOUT="30"
export RAAF_API_RATE_LIMIT="60"

# Data processing
export RAAF_DATA_MAX_ROWS="10000"
export RAAF_DATA_MAX_SIZE="52428800"  # 50MB
```

## Security Features

### Input Validation

All tools include comprehensive input validation:

```ruby
# Mathematical expressions are sanitized
# Only allowed characters: 0-9, +, -, *, /, (, ), .
calculator.safe_calculate(expression: "2 + 3 * 4")  # ✓ Safe
calculator.safe_calculate(expression: "exec('rm -rf /')")  # ✗ Rejected

# File paths are validated
# Only allow access to designated directories
file_reader.read_file(path: "/safe/directory/file.txt")  # ✓ Safe
file_reader.read_file(path: "/etc/passwd")  # ✗ Rejected

# URLs are validated and rate-limited
web_scraper.scrape_url(url: "https://example.com")  # ✓ Safe
web_scraper.scrape_url(url: "file:///etc/passwd")  # ✗ Rejected
```

### Resource Limits

Configure resource limits to prevent abuse:

```ruby
RubyAIAgentsFactory::Tools::Basic.configure do |config|
  config.math_tools.max_expression_length = 200
  config.file_tools.max_size = 10 * 1024 * 1024
  config.web_tools.timeout = 30
  config.data_tools.max_rows = 10000
end
```

### Rate Limiting

Built-in rate limiting for external requests:

```ruby
# Web scraping respects robots.txt and implements delays
config.web_tools.rate_limit = 60  # requests per minute
config.web_tools.respect_robots_txt = true

# API calls include rate limiting
config.api_tools.rate_limit = 60  # requests per minute
config.api_tools.retry_after_rate_limit = true
```

## Relationship with Other RAAF Gems

### Dependencies

RAAF Tools Basic depends on:

- **[raaf-core](../core/)** - Core agent functionality and base classes
- **[raaf-logging](../logging/)** - Unified logging system

### Complements

Works well with:

- **[raaf-tools-advanced](../tools-advanced/)** - Enterprise-grade tools (computer control, document processing)
- **[raaf-guardrails](../guardrails/)** - Safety validation and content filtering
- **[raaf-memory](../memory/)** - Memory management for tool results
- **[raaf-tracing](../tracing/)** - Monitor tool usage and performance

### Integration Example

```ruby
# Full-featured agent with basic tools, guardrails, and memory
require 'raaf-core'
require 'raaf-tools-basic'
require 'raaf-guardrails'
require 'raaf-memory'

# Create agent with memory
agent = RubyAIAgentsFactory::Agent.new(
  name: "SmartAssistant",
  instructions: "You are a helpful assistant with tools and memory",
  model: "gpt-4o"
)

# Add basic tools
RubyAIAgentsFactory::Tools::Basic.add_all_tools(agent)

# Add guardrails
agent.add_guardrail(RubyAIAgentsFactory::Guardrails::InputSanitizer.new)
agent.add_guardrail(RubyAIAgentsFactory::Guardrails::OutputFilter.new)

# Add memory
memory = RubyAIAgentsFactory::Memory::AgentMemory.new(
  store: RubyAIAgentsFactory::Memory::VectorStore.new
)
agent.memory = memory

# Run with full capabilities
runner = RubyAIAgentsFactory::Runner.new(agent: agent)
result = runner.run("Calculate the average of these numbers: 10, 20, 30, 40, 50")
```

## Architecture

### Tool Structure

```
RubyAIAgentsFactory::Tools::Basic::
├── MathTools              # Mathematical operations
├── TextTools              # Text processing
├── FileTools              # File operations  
├── WebTools               # Web scraping
├── ApiTools               # HTTP client
├── DataTools              # Data manipulation
└── SecurityTools          # Input validation
```

### Extension Points

Create custom tools by extending the base classes:

```ruby
class MyCustomTool < RubyAIAgentsFactory::FunctionTool
  def initialize(**options)
    super(
      method(:execute_custom_action),
      name: "custom_tool",
      description: "My custom tool for specific tasks"
    )
    @options = options
  end

  def execute_custom_action(input:, **params)
    # Validate input
    return "Invalid input" if input.nil? || input.empty?

    # Process request
    result = process_input(input, params)
    
    # Return result
    {
      success: true,
      result: result,
      processed_at: Time.now
    }.to_json
  end

  private

  def process_input(input, params)
    # Your custom logic here
    "Processed: #{input}"
  end
end

# Use with agent
agent.add_tool(MyCustomTool.new(option1: "value1"))
```

## Advanced Usage

### Custom Tool Collections

Create specialized tool collections:

```ruby
module MyCompany
  module Tools
    class CompanyToolkit
      def self.add_to_agent(agent)
        # Add basic tools
        RubyAIAgentsFactory::Tools::Basic.add_all_tools(agent)
        
        # Add company-specific tools
        agent.add_tool(CompanyDatabaseTool.new)
        agent.add_tool(CompanyApiTool.new)
        agent.add_tool(CompanyReportTool.new)
      end
    end
  end
end

# Use company toolkit
agent = RubyAIAgentsFactory::Agent.new(name: "CompanyAgent")
MyCompany::Tools::CompanyToolkit.add_to_agent(agent)
```

### Error Handling

Handle tool errors gracefully:

```ruby
begin
  result = agent.run("Calculate 1 / 0")
rescue RubyAIAgentsFactory::Tools::Basic::MathError => e
  puts "Math error: #{e.message}"
rescue RubyAIAgentsFactory::Tools::Basic::ValidationError => e
  puts "Validation error: #{e.message}"
rescue RubyAIAgentsFactory::Tools::Basic::SecurityError => e
  puts "Security error: #{e.message}"
end
```

### Performance Optimization

Optimize tool performance:

```ruby
# Use caching for repeated operations
RubyAIAgentsFactory::Tools::Basic.configure do |config|
  config.enable_caching = true
  config.cache_ttl = 300  # 5 minutes
end

# Batch operations when possible
results = RubyAIAgentsFactory::Tools::Basic.batch_execute([
  { tool: :calculator, expression: "2 + 2" },
  { tool: :calculator, expression: "3 * 3" },
  { tool: :text_counter, text: "Hello world" }
])
```

## Examples

### Complete Examples

See the [examples directory](examples/) for complete working examples:

- **[basic_example.rb](examples/basic_example.rb)** - Simple agent with calculator and weather tools
- **[tool_context_example.rb](examples/tool_context_example.rb)** - Using tools with context management
- **[tool_context_simple.rb](examples/tool_context_simple.rb)** - Simplified tool context usage

### Real-World Use Cases

**Data Analysis Assistant:**
```ruby
# Agent that can analyze data files
agent = RubyAIAgentsFactory::Agent.new(
  name: "DataAnalyst",
  instructions: "You analyze data files and provide insights",
  model: "gpt-4o"
)

agent.add_tool(RubyAIAgentsFactory::Tools::Basic.file_reader)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.csv_processor)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.statistics)

# "Analyze the sales data in sales.csv and provide insights"
```

**Content Processing Assistant:**
```ruby
# Agent that processes text content
agent = RubyAIAgentsFactory::Agent.new(
  name: "ContentProcessor",
  instructions: "You process and analyze text content",
  model: "gpt-4o"
)

agent.add_tool(RubyAIAgentsFactory::Tools::Basic.text_summarizer)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.text_formatter)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.word_counter)

# "Summarize this article and format it as a title case"
```

**Web Research Assistant:**
```ruby
# Agent that researches topics on the web
agent = RubyAIAgentsFactory::Agent.new(
  name: "WebResearcher",
  instructions: "You research topics using web scraping",
  model: "gpt-4o"
)

agent.add_tool(RubyAIAgentsFactory::Tools::Basic.web_scraper)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.api_client)
agent.add_tool(RubyAIAgentsFactory::Tools::Basic.text_summarizer)

# "Research the latest trends in Ruby development"
```

## Development

### Setup

```bash
git clone https://github.com/raaf-ai/ruby-ai-agents-factory
cd ruby-ai-agents-factory/tools-basic
bundle install
```

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/math_tools_spec.rb

# Run with coverage
bundle exec rspec --coverage
```

### Code Quality

```bash
# Run RuboCop
bundle exec rubocop

# Fix auto-fixable issues
bundle exec rubocop -a

# Type checking (if using Sorbet)
bundle exec srb tc
```

### Adding New Tools

1. Create new tool class in `lib/raaf/tools/basic/`
2. Inherit from `RubyAIAgentsFactory::FunctionTool`
3. Implement security validation
4. Add comprehensive tests
5. Update documentation
6. Add to main module

Example:
```ruby
# lib/raaf/tools/basic/my_tool.rb
module RubyAIAgentsFactory
  module Tools
    module Basic
      class MyTool
        def self.tool
          RubyAIAgentsFactory::FunctionTool.new(
            method(:execute),
            name: "my_tool",
            description: "Description of what this tool does"
          )
        end

        def self.execute(input:, **options)
          # Validation
          return "Error: Invalid input" if input.nil?
          
          # Processing
          result = process_input(input, options)
          
          # Return formatted result
          result
        end

        private

        def self.process_input(input, options)
          # Tool logic here
          "Processed: #{input}"
        end
      end
    end
  end
end
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for your changes
5. Ensure all tests pass (`bundle exec rspec`)
6. Run code quality checks (`bundle exec rubocop`)
7. Commit your changes (`git commit -am 'Add amazing feature'`)
8. Push to the branch (`git push origin feature/amazing-feature`)
9. Open a Pull Request

### Guidelines

- Follow the existing code style and patterns
- Add comprehensive tests for new features
- Include security validation in all tools
- Document new functionality
- Update CHANGELOG.md with your changes
- Ensure backward compatibility

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Links

- **Main Repository**: https://github.com/raaf-ai/ruby-ai-agents-factory
- **Documentation**: https://docs.raaf.ai/tools-basic
- **Issues**: https://github.com/raaf-ai/ruby-ai-agents-factory/issues
- **RubyGems**: https://rubygems.org/gems/raaf-tools-basic