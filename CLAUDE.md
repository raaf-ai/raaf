# Claude Code Guide for OpenAI Agents Ruby

This repository contains a comprehensive Ruby implementation of OpenAI Agents for building sophisticated multi-agent AI workflows. This guide will help you understand the codebase structure, common development patterns, and useful commands.

## Repository Overview

This is a Ruby gem that provides 100% feature parity with the Python OpenAI Agents library, plus additional enterprise-grade capabilities. The gem enables building multi-agent AI workflows with advanced features like voice interactions, guardrails, usage tracking, and comprehensive monitoring.

## Architecture Overview

### Core Components

- **Agent (`lib/openai_agents/agent.rb`)** - Main agent class with tools and handoff capabilities
- **Runner (`lib/openai_agents/runner.rb`)** - Executes agent conversations and manages flow
- **FunctionTool (`lib/openai_agents/function_tool.rb`)** - Wraps Ruby methods/procs as agent tools
- **Tracing (`lib/openai_agents/tracing/`)** - Comprehensive span-based monitoring system
- **Models (`lib/openai_agents/models/`)** - Multi-provider abstraction (OpenAI, Anthropic, Gemini)

### Advanced Features

- **Guardrails (`lib/openai_agents/guardrails.rb`)** - Safety and validation systems
- **Voice Workflows (`lib/openai_agents/voice/`)** - Speech-to-text and text-to-speech pipeline
- **Usage Tracking (`lib/openai_agents/usage_tracking.rb`)** - Analytics and monitoring
- **Configuration (`lib/openai_agents/configuration.rb`)** - Environment-based settings
- **Extensions (`lib/openai_agents/extensions.rb`)** - Plugin architecture
- **Advanced Handoffs (`lib/openai_agents/handoffs/`)** - Context-aware agent routing
- **Structured Output (`lib/openai_agents/structured_output.rb`)** - Schema validation
- **Advanced Tools (`lib/openai_agents/tools/`)** - File search, web search, computer control
- **Visualization (`lib/openai_agents/visualization.rb`)** - Workflow and trace visualization
- **REPL (`lib/openai_agents/repl.rb`)** - Interactive development environment
- **Debugging (`lib/openai_agents/debugging.rb`)** - Enhanced debugging capabilities

## Key Development Patterns

### 1. Agent Creation Pattern
```ruby
agent = OpenAIAgents::Agent.new(
  name: "AgentName",
  instructions: "System prompt",
  model: "gpt-4",
  max_turns: 10
)
```

### 2. Tool Integration Pattern
```ruby
def custom_tool(param)
  # Tool implementation
end

agent.add_tool(method(:custom_tool))
```

### 3. Multi-Agent Handoff Pattern
```ruby
agent1.add_handoff(agent2)
# OR advanced handoffs
handoff_manager = OpenAIAgents::Handoffs::AdvancedHandoff.new
handoff_manager.add_agent(agent1, capabilities: [:support])
```

### 4. Configuration Pattern
```ruby
config = OpenAIAgents::Configuration.new(environment: "production")
config.set("agent.default_model", "gpt-4")
```

### 5. Tracing Pattern
```ruby
tracer = OpenAIAgents::Tracing::SpanTracer.new
tracer.add_processor(OpenAIAgents::Tracing::ConsoleSpanProcessor.new)
runner = OpenAIAgents::Runner.new(agent: agent, tracer: tracer)
```

## File Structure

```
lib/openai_agents/
├── agent.rb                    # Core agent implementation
├── runner.rb                   # Agent execution engine
├── function_tool.rb            # Tool wrapper system
├── errors.rb                   # Custom exceptions
├── streaming.rb                # Streaming responses
├── configuration.rb            # Environment-based config
├── extensions.rb               # Plugin architecture
├── guardrails.rb               # Safety systems
├── structured_output.rb        # Schema validation
├── usage_tracking.rb           # Analytics and monitoring
├── result.rb                   # Response structures
├── repl.rb                     # Interactive development
├── visualization.rb            # Workflow visualization
├── debugging.rb                # Enhanced debugging
├── models/                     # Multi-provider support
│   ├── interface.rb
│   ├── openai_provider.rb
│   ├── anthropic_provider.rb
│   └── multi_provider.rb
├── tracing/                    # Monitoring system
│   └── spans.rb
├── handoffs/                   # Advanced handoffs
│   └── advanced_handoff.rb
├── voice/                      # Voice workflows
│   └── voice_workflow.rb
└── tools/                      # Advanced tools
    ├── file_search_tool.rb
    ├── web_search_tool.rb
    └── computer_tool.rb
```

## Common Commands

### Development Commands
```bash
# Install dependencies
bundle install

# Run tests (if available)
bundle exec rspec

# Run linting (if configured)
bundle exec rubocop

# Start interactive Ruby session with gem loaded
bundle exec irb -r ./lib/openai_agents

# Run the comprehensive example
ruby examples/complete_features_showcase.rb
```

### Git Commands
```bash
# Check status
git status

# Stage all changes
git add .

# Commit changes
git commit -m "Description of changes"

# View commit history
git log --oneline
```

### Environment Setup
```bash
# Required API keys
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-anthropic-key"
export GEMINI_API_KEY="your-gemini-key"

# Optional configuration
export OPENAI_AGENTS_ENVIRONMENT="development"
export OPENAI_AGENTS_LOG_LEVEL="info"
```

## Testing and Examples

### Key Example Files
- `examples/complete_features_showcase.rb` - Comprehensive demonstration of all features
- `examples/basic_example.rb` - Simple agent with tools (if exists)
- `examples/multi_agent_example.rb` - Multi-agent workflows (if exists)

### Running Examples
```bash
# Run the complete showcase (demonstrates all features)
ruby examples/complete_features_showcase.rb

# Run with debugging
ruby -d examples/complete_features_showcase.rb
```

## Common Issues and Solutions

### 1. Missing API Keys
- **Issue**: Agent fails with authentication error
- **Solution**: Set the appropriate environment variables (OPENAI_API_KEY, etc.)

### 2. Model Not Found
- **Issue**: "Model not found" error
- **Solution**: Check model name spelling and provider availability

### 3. Tool Execution Errors
- **Issue**: Tools fail to execute
- **Solution**: Ensure tool methods are properly defined and accessible

### 4. Handoff Failures
- **Issue**: Agent handoffs don't work
- **Solution**: Check that target agents are properly added with `add_handoff`

## Key Configuration Files

### Gemspec
- `openai_agents.gemspec` - Gem specification and dependencies

### Documentation
- `README.md` - Basic quick start guide
- `README_COMPREHENSIVE.md` - Complete documentation with examples
- `CLAUDE.md` - This file (development guide)

## Development Guidelines

### Code Style
- Follow Ruby community conventions
- Use meaningful variable and method names
- Add comprehensive documentation to all public methods
- Include examples in method documentation

### Error Handling
- Use custom exception classes that inherit from `OpenAIAgents::Error`
- Provide descriptive error messages
- Handle API failures gracefully

### Testing Strategy
- Write unit tests for core functionality
- Include integration tests for multi-agent workflows
- Test error conditions and edge cases
- Mock external API calls in tests

### Documentation Standards
- Use RDoc format for method documentation
- Include parameter types and descriptions
- Provide usage examples
- Document exceptions that may be raised

## Debugging Tips

### 1. Enable Tracing
```ruby
tracer = OpenAIAgents::Tracing::SpanTracer.new
tracer.add_processor(OpenAIAgents::Tracing::ConsoleSpanProcessor.new)
```

### 2. Use REPL for Interactive Development
```ruby
repl = OpenAIAgents::REPL.new(agent: agent, tracer: tracer)
repl.start
```

### 3. Check Usage Analytics
```ruby
tracker = OpenAIAgents::UsageTracking::UsageTracker.new
analytics = tracker.analytics(:today)
puts analytics.inspect
```

### 4. Enable Debug Logging
```ruby
require 'logger'
logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG
```

## Performance Considerations

### 1. Token Usage
- Monitor token consumption with usage tracking
- Set appropriate `max_turns` to control conversation length
- Use streaming for long responses

### 2. API Rate Limits
- Implement rate limiting with guardrails
- Use exponential backoff for retries
- Monitor API usage patterns

### 3. Memory Management
- Clean up old tracing data periodically
- Use appropriate retention policies for usage data
- Monitor session cache sizes

## Security Best Practices

### 1. API Key Management
- Never commit API keys to version control
- Use environment variables for sensitive data
- Rotate keys regularly

### 2. Input Validation
- Use guardrails for content safety
- Validate input schemas
- Implement length limits

### 3. Output Sanitization
- Validate structured outputs
- Filter sensitive information
- Implement content safety checks

## Extension Development

### Creating Custom Tools
```ruby
class CustomTool < OpenAIAgents::FunctionTool
  def initialize
    super(
      proc { |input| process(input) },
      name: "custom_tool",
      description: "Custom tool description"
    )
  end
  
  private
  
  def process(input)
    # Tool implementation
  end
end
```

### Creating Extensions
```ruby
class MyExtension < OpenAIAgents::Extensions::BaseExtension
  def self.extension_info
    {
      name: :my_extension,
      type: :tool,
      version: "1.0.0"
    }
  end
  
  def setup(config)
    # Extension setup
  end
  
  def activate
    # Extension activation
  end
end
```

## Monitoring and Analytics

### Usage Tracking Setup
```ruby
tracker = OpenAIAgents::UsageTracking::UsageTracker.new
tracker.add_alert(:cost_limit) { |usage| usage[:total_cost_today] > 50.0 }
```

### Getting Analytics
```ruby
analytics = tracker.analytics(:today, group_by: :agent)
dashboard = tracker.dashboard_data
report = tracker.generate_report(:month)
```

## Production Deployment

### Configuration
- Use production environment settings
- Enable comprehensive logging
- Set up monitoring and alerting
- Configure appropriate retention policies

### Monitoring
- Track API usage and costs
- Monitor agent performance
- Set up alerts for anomalies
- Generate regular usage reports

This guide should help you navigate and contribute to the OpenAI Agents Ruby codebase effectively. The repository contains a comprehensive, production-ready framework with extensive documentation and examples.