# RAAF DSL Examples

This directory contains executable examples demonstrating various features of the RAAF DSL.

## Running Examples

All examples are standalone Ruby scripts that can be run directly:

```bash
ruby examples/basic_agent_example.rb
```

## Available Examples

### 1. Basic Agent Example (`basic_agent_example.rb`)
Demonstrates creating a simple conversational agent with basic configuration.

**Key concepts:**
- Creating agents with `AgentBuilder`
- Setting instructions and model
- Configuring temperature and max_turns
- Running basic conversations

### 2. Tools Example (`tools_example.rb`)
Shows how to create custom tools and add them to agents.

**Key concepts:**
- Building tools with `ToolBuilder`
- Defining parameters and execution logic
- Adding tools to agents
- Creating inline tools

### 3. Prompts Example (`prompts_example.rb`)
Demonstrates the flexible prompt system with validation and context mapping.

**Key concepts:**
- Creating prompt classes with required/optional variables
- Context mapping for nested data structures
- Contract modes (strict, warn, lenient)
- Dynamic prompt content

### 4. Multi-Agent Example (`multi_agent_example.rb`)
Shows how to create multiple agents that can hand off conversations.

**Key concepts:**
- Creating specialized agents
- Enabling handoffs between agents
- Multi-agent runners
- Agent-specific tools

### 5. Web Search Example (`web_search_example.rb`)
Demonstrates using the built-in web search capabilities.

**Key concepts:**
- Enabling web search with `use_web_search`
- Configuring search parameters
- Creating research agents
- Different search strategies

**Requirements:**
- Set `TAVILY_API_KEY` environment variable
- Get your API key from https://tavily.com

### 6. Debugging Example (`debugging_example.rb`)
Shows the debugging and inspection tools available.

**Key concepts:**
- Context inspection
- Prompt debugging
- LLM call interception
- Performance monitoring
- Debug logging

## Environment Setup

Some examples require API keys:

```bash
export OPENAI_API_KEY="your-openai-key"
export TAVILY_API_KEY="your-tavily-key"  # For web search
```

## Common Patterns

### Creating an Agent
```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "MyAgent"
  instructions "You are a helpful assistant"
  model "gpt-4o"
end
```

### Adding Tools
```ruby
tool :my_tool do |param|
  # Tool logic here
  { result: param.upcase }
end
```

### Using Prompts
```ruby
class MyPrompt < RAAF::DSL::Prompts::Base
  required :field1
  optional :field2, default: "value"
  
  def system
    "System prompt with #{field1}"
  end
  
  def user
    "User prompt"
  end
end
```

### Running Agents
```ruby
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Your message here")
puts result.messages.last[:content]
```

## Debugging Tips

1. Enable debug logging:
   ```bash
   RAAF_LOG_LEVEL=debug ruby examples/your_example.rb
   ```

2. Use the debugging tools:
   ```ruby
   inspector = RAAF::DSL::Debugging::ContextInspector.new
   inspector.inspect_agent(agent)
   ```

3. Check tool execution:
   ```ruby
   result = tool.call(param: "value")
   puts result.inspect
   ```

## More Information

For detailed documentation, see the main RAAF DSL documentation.