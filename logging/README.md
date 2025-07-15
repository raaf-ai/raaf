# RAAF Logging

[![Gem Version](https://badge.fury.io/rb/raaf-logging.svg)](https://badge.fury.io/rb/raaf-logging)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Logging** gem provides a comprehensive, unified logging system for the Ruby AI Agents Factory (RAAF) ecosystem. It offers structured logging with Rails integration, category-based debug filtering, and seamless integration across all RAAF components.

## Overview

RAAF (Ruby AI Agents Factory) Logging extends the core logging capabilities from `raaf-core` to provide:

- **Unified Logging Interface** - Consistent logging across all RAAF gems
- **Rails Integration** - Automatic Rails logger integration when available
- **Category-Based Filtering** - Fine-grained debug control by category
- **Structured Logging** - JSON and text output formats
- **Performance Optimized** - Minimal overhead with lazy evaluation
- **Configurable Output** - Console, file, Rails, or custom targets

## Key Features

### Category-Based Debug Logging

```ruby
# Enable specific debug categories
RubyAIAgentsFactory::Logging.configure do |config|
  config.debug_categories = [:api, :tracing, :tools]
end

# Use category-specific debug logging
include RubyAIAgentsFactory::Logger

log_debug_api("API request", url: "/chat/completions", method: "POST")
log_debug_tracing("Span created", span_id: "abc123", parent_id: "xyz789")
log_debug_tools("Tool executed", tool: "search", duration: 150)
```

### Structured Logging

```ruby
# JSON format output
RubyAIAgentsFactory::Logging.configure do |config|
  config.log_format = :json
end

log_info("Agent started", agent: "GPT-4", session_id: "session123")
# Output: {"timestamp":"2024-01-01T00:00:00.000Z","level":"INFO","message":"Agent started","context":{"agent":"GPT-4","session_id":"session123"}}
```

### Rails Integration

```ruby
# In Rails applications, automatically uses Rails.logger
class AgentController < ApplicationController
  include RubyAIAgentsFactory::Logger
  
  def create
    log_info("Creating agent", params: agent_params)
    # Logs to Rails.logger with proper formatting
  end
end
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-logging', '~> 1.0'
```

And then execute:

```bash
bundle install
```

## Usage

### Basic Logging

```ruby
require 'raaf-logging'

# Method 1: Include Logger mixin
class MyAgent
  include RubyAIAgentsFactory::Logger
  
  def process
    log_info("Processing started", agent: "MyAgent", task_id: 123)
    log_debug_api("API call", url: "https://api.openai.com")
    log_error("Processing failed", error: exception)
  end
end

# Method 2: Direct module usage
RubyAIAgentsFactory::Logging.info("Agent started", agent: "GPT-4")
RubyAIAgentsFactory::Logging.debug("Debug message", category: :tools)
```

### Configuration

```ruby
RubyAIAgentsFactory::Logging.configure do |config|
  config.log_level = :debug                        # :debug, :info, :warn, :error, :fatal
  config.log_format = :json                        # :text or :json
  config.log_output = :rails                       # :console, :file, :rails, :auto
  config.debug_categories = [:api, :tracing]       # Enable specific categories
end
```

### Environment Variables

```bash
# Set log level
export RAAF_LOG_LEVEL=debug

# Set log format
export RAAF_LOG_FORMAT=json

# Set output target
export RAAF_LOG_OUTPUT=console

# Enable debug categories
export RAAF_DEBUG_CATEGORIES=api,tracing,tools
```

### Debug Categories

Available debug categories:

- **:api** - API calls, responses, HTTP details
- **:tracing** - Span lifecycle, trace processing
- **:tools** - Tool execution, function calls
- **:handoff** - Agent handoffs, delegation
- **:context** - Context management, memory
- **:http** - HTTP debug output
- **:general** - General debug messages
- **:all** - Enable all categories
- **:none** - Disable all debug output

### Advanced Usage

```ruby
# Custom logger with file output
RubyAIAgentsFactory::Logging.configure do |config|
  config.log_output = :file
  config.log_file = "/var/log/raaf/agents.log"
  config.log_rotation = :daily
  config.log_max_size = 10.megabytes
end

# Contextual logging
RubyAIAgentsFactory::Logging.with_context(session_id: "abc123") do
  log_info("Processing request")  # Automatically includes session_id
end

# Performance monitoring
RubyAIAgentsFactory::Logging.benchmark("API call") do
  # Expensive operation
end
```

## Relationship with Other Gems

### Foundation Dependency

- **raaf-core** - Extends core logging interfaces and base classes

### Used By All Gems

RAAF Logging is used by **every other gem** in the ecosystem:

#### Core Infrastructure
- **raaf-configuration** - Logs configuration changes and validation
- **raaf-providers** - Logs API calls and provider interactions
- **raaf-dsl** - Logs DSL compilation and execution

#### Agent Features
- **raaf-tracing** - Logs span lifecycle and trace processing
- **raaf-memory** - Logs memory operations and vector searches
- **raaf-tools-basic** - Logs tool execution and results
- **raaf-tools-advanced** - Logs advanced tool operations

#### Integration & Streaming
- **raaf-rails** - Integrates with Rails logging infrastructure
- **raaf-streaming** - Logs streaming events and connections
- **raaf-testing** - Logs test execution and assertions

#### Enterprise & Security
- **raaf-guardrails** - Logs safety violations and validations
- **raaf-compliance** - Logs audit events and compliance checks
- **raaf-security** - Logs security events and threats
- **raaf-monitoring** - Logs monitoring events and metrics

#### Development & Operations
- **raaf-debug** - Provides debug-specific logging enhancements
- **raaf-analytics** - Logs analytics events and data processing
- **raaf-deployment** - Logs deployment events and status
- **raaf-cli** - Logs CLI operations and user interactions

### Integration Patterns

```ruby
# Other gems integrate like this:
class SomeFeature
  include RubyAIAgentsFactory::Logger
  
  def process
    log_info("Feature processing", feature: "SomeFeature")
    log_debug_api("API call", endpoint: "/some/endpoint")
  end
end
```

## Architecture

### Core Components

```
RubyAIAgentsFactory::Logging::
├── Logger                   # Main logging interface
├── Configuration            # Configuration management
├── Formatter                # Log formatting (JSON/text)
├── Output                   # Output targets (console/file/Rails)
├── CategoryFilter           # Debug category filtering
├── ContextManager           # Contextual logging
└── Benchmarker             # Performance monitoring
```

### Output Targets

1. **Console** - Standard output with color support
2. **File** - File-based logging with rotation
3. **Rails** - Rails.logger integration
4. **Custom** - Custom logger implementations

### Formatters

1. **Text Formatter** - Human-readable text format
2. **JSON Formatter** - Structured JSON output
3. **Rails Formatter** - Rails-compatible format

## Performance Considerations

- **Lazy Evaluation** - Debug messages only evaluated when enabled
- **Category Filtering** - Minimal overhead for disabled categories
- **Async Logging** - Optional async logging for high-throughput scenarios
- **Memory Efficient** - Minimal memory footprint

## Development

### Running Tests

```bash
cd logging/
bundle exec rspec
```

### Testing Integration

```ruby
# Test logging in your specs
RSpec.describe MyAgent do
  include RubyAIAgentsFactory::Testing::LoggingMatchers
  
  it "logs processing events" do
    expect { agent.process }.to log_info("Processing started")
  end
end
```

## Best Practices

1. **Use Appropriate Levels** - Info for important events, debug for detailed tracing
2. **Include Context** - Add relevant metadata to log entries
3. **Use Categories** - Organize debug logs by category
4. **Avoid Secrets** - Never log sensitive information
5. **Performance Impact** - Use debug categories to minimize production overhead

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This gem is available as open source under the terms of the [MIT License](LICENSE).

## Support

- **Documentation**: [Ruby AI Agents Factory Docs](https://raaf-ai.github.io/ruby-ai-agents-factory/)
- **Issues**: [GitHub Issues](https://github.com/raaf-ai/ruby-ai-agents-factory/issues)
- **Discussions**: [GitHub Discussions](https://github.com/raaf-ai/ruby-ai-agents-factory/discussions)
- **Email**: bert.hajee@enterprisemodules.com

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a list of changes and version history.