# Core Examples

This directory contains working examples demonstrating the core functionality of RAAF (Ruby AI Agents Factory).

## Working Examples

All examples in this directory are **functional and tested**. They demonstrate real RAAF capabilities using actual implemented classes.

| Example | Description | Key Features |
|---------|-------------|--------------|
| `basic_example.rb` | ✅ Simple agent creation and conversation | Basic agent setup, chat completion |
| `multi_agent_example.rb` | ✅ Multi-agent collaboration with handoffs | Agent handoffs, specialized tools, complex workflows |
| `structured_output_example.rb` | ✅ JSON schema validation and structured responses | Schema definition, output validation |
| `handoff_objects_example.rb` | ✅ Advanced handoff patterns | Agent delegation, conversation context |
| `message_flow_example.rb` | ✅ Message flow visualization and debugging | API flow, debugging patterns |
| `configuration_example.rb` | ✅ Production configuration management | Environment config, API key management, retry settings |

## Prerequisites

1. **API Key**: Most examples require an OpenAI API key:
   ```bash
   export OPENAI_API_KEY="your-api-key"
   ```

2. **Dependencies**: Install required gems:
   ```bash
   bundle install
   ```

## Running Examples

### Basic Usage
```bash
# Start with the simplest example
ruby examples/basic_example.rb

# Try multi-agent workflows
ruby examples/multi_agent_example.rb

# Explore structured output
ruby examples/structured_output_example.rb
```

### Production Configuration
```bash
# Comprehensive configuration example
ruby examples/configuration_example.rb

# Message flow debugging
RAAF_DEBUG_CONVERSATION=true ruby examples/message_flow_example.rb
```

## Example Validation

All examples are automatically validated in CI using:
```bash
# Run validation script
ruby scripts/validate_examples.rb
```

The validation system:
- ✅ **Syntax checks** all example files
- ✅ **Execution tests** with proper error handling  
- ✅ **Success pattern validation** to ensure examples work
- ⏭️ **Graceful skipping** when API keys are missing
- 📊 **CI integration** with detailed reporting

## Key Concepts Demonstrated

### Agent Creation
```ruby
agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant",
  model: "gpt-4o"
)
```

### Tool Integration
```ruby
def get_weather(city:)
  "Weather in #{city}: sunny, 22°C"
end

agent.add_tool(method(:get_weather))
```

### Multi-Agent Handoffs
```ruby
# Configure handoffs between specialized agents
research_agent.add_handoff(writer_agent)
writer_agent.add_handoff(research_agent)
```

### Built-in Retry Logic
```ruby
# All providers have built-in retry - no wrapper needed
provider = RAAF::Models::ResponsesProvider.new
provider.configure_retry(max_attempts: 5, base_delay: 2.0)
```

### Structured Output
```ruby
schema = RAAF::StructuredOutput::ObjectSchema.build do
  string :name, required: true
  number :price, minimum: 0
  array :features, items: { type: "string" }
end
```

## Best Practices

1. **Start Simple**: Begin with `basic_example.rb` to understand core concepts
2. **API Keys**: Use environment variables for secure credential management
3. **Error Handling**: Examples include proper error handling patterns
4. **Logging**: Enable debug logging for troubleshooting
5. **Configuration**: Use `configuration_example.rb` patterns for production deployments

## Architecture Notes

- **Default Provider**: `ResponsesProvider` with built-in retry logic
- **Tool-based Handoffs**: Handoffs use function calling, not text parsing  
- **Python Compatibility**: Maintains OpenAI Agents SDK compatibility
- **Flexible Agent ID**: Supports both Agent objects and string names

## Troubleshooting

### Common Issues

**"OpenAI API key is required"**
```bash
export OPENAI_API_KEY="your-actual-api-key"
```

**"uninitialized constant"**
- Example uses non-existent class (invalid example)
- All examples in this directory use real, implemented classes

**Connection/timeout errors**
- Built-in retry logic handles transient failures automatically
- Configure retry behavior: `provider.configure_retry(max_attempts: 5)`

## Development

Examples are continuously validated to ensure they remain functional as the library evolves. See the GitHub Actions workflow for automated testing.