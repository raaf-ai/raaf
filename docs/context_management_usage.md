# Context Management Usage Guide

This guide shows how to enable and use the context management feature in OpenAI Agents Ruby to handle long conversations efficiently.

## Quick Start

### Method 1: Environment Variable (Easiest)

```bash
# Enable context management with balanced defaults
export OPENAI_AGENTS_CONTEXT_MANAGEMENT=true

# Run your agent
ruby your_agent_script.rb
```

### Method 2: Basic Configuration

```ruby
require 'openai_agents'

agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful assistant.",
  model: "gpt-4o"
)

# Enable context management with default settings
context_manager = OpenAIAgents::ContextManager.new(model: "gpt-4o")

runner = OpenAIAgents::Runner.new(
  agent: agent,
  context_manager: context_manager
)

# Use normally - context is automatically managed
result = runner.run("Start a conversation...")
```

### Method 3: Using Configuration Presets

```ruby
# Conservative - keeps context small for cost savings
config = OpenAIAgents::ContextConfig.conservative(model: "gpt-4o")

# Balanced - good default for most use cases
config = OpenAIAgents::ContextConfig.balanced(model: "gpt-4o")

# Aggressive - uses most of available context
config = OpenAIAgents::ContextConfig.aggressive(model: "gpt-4o")

# Message-based - limits by message count instead of tokens
config = OpenAIAgents::ContextConfig.message_based(max_messages: 30)

runner = OpenAIAgents::Runner.new(
  agent: agent,
  context_config: config
)
```

## How It Works

The context manager uses a **token-based sliding window** strategy:

1. **Token Counting**: Accurately counts tokens using the tiktoken library
2. **Smart Truncation**: Removes oldest messages first while preserving:
   - System messages (instructions)
   - Recent messages (configurable, default 5)
3. **Truncation Notice**: Adds a system message noting how many messages were removed
4. **Model-Aware Limits**: Automatically sets appropriate limits based on the model

## Token Limits by Model

Default limits (with safety buffer):
- **GPT-4o/GPT-4-turbo**: 120,000 tokens (from 128k limit)
- **GPT-4**: 7,500 tokens (from 8k limit)
- **GPT-3.5-turbo-16k**: 15,000 tokens (from 16k limit)
- **GPT-3.5-turbo**: 3,500 tokens (from 4k limit)

## Custom Configuration

```ruby
# Full control over context management
context_manager = OpenAIAgents::ContextManager.new(
  model: "gpt-4o",
  max_tokens: 50_000,        # Custom token limit
  preserve_system: true,     # Always keep system messages
  preserve_recent: 10        # Keep last 10 messages
)

runner = OpenAIAgents::Runner.new(
  agent: agent,
  context_manager: context_manager
)
```

## Manual Context Management

You can also manage context manually:

```ruby
context_manager = OpenAIAgents::ContextManager.new(model: "gpt-4o")

# Check token usage
messages = [
  { role: "system", content: "You are a helpful assistant." },
  { role: "user", content: "Hello!" },
  { role: "assistant", content: "Hi there! How can I help?" }
]

total_tokens = context_manager.count_total_tokens(messages)
puts "Total tokens: #{total_tokens}"

# Manually manage context
managed_messages = context_manager.manage_context(messages)

# Check individual message tokens
messages.each do |msg|
  tokens = context_manager.count_message_tokens(msg)
  puts "#{msg[:role]}: #{tokens} tokens"
end
```

## Configuration Object Details

```ruby
config = OpenAIAgents::ContextConfig.new
config.enabled = true                    # Enable/disable context management
config.strategy = :token_sliding_window  # Strategy to use
config.max_tokens = 50_000              # Token limit (nil = model default)
config.max_messages = 50                # Message count limit
config.preserve_system = true           # Keep system messages
config.preserve_recent = 5              # Number of recent messages to keep

# Future strategies (not yet implemented):
config.summarization_enabled = false    # Enable summarization
config.summarization_threshold = 0.8    # Summarize at 80% capacity
config.summarization_model = "gpt-3.5-turbo"  # Model for summarization
```

## Benefits

1. **Automatic**: No manual intervention needed
2. **Cost-Effective**: Reduces token usage and API costs
3. **Error Prevention**: Avoids token limit errors
4. **Preserves Context**: Keeps most recent and relevant messages
5. **Model-Aware**: Adapts to different model capabilities

## Example: Long Conversation

```ruby
# This will automatically manage context as the conversation grows
agent = OpenAIAgents::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful coding assistant.",
  model: "gpt-4o"
)

runner = OpenAIAgents::Runner.new(
  agent: agent,
  context_config: OpenAIAgents::ContextConfig.balanced
)

conversation = []

# Simulate a long conversation
100.times do |i|
  result = runner.run(
    conversation + [{ role: "user", content: "Tell me about Ruby feature ##{i}" }]
  )
  
  conversation = result.messages
  
  # Context manager automatically keeps conversation within limits
  # Older messages are removed as needed
end
```

## Monitoring Context Usage

```ruby
context_manager = OpenAIAgents::ContextManager.new(model: "gpt-4o")

# After a conversation
total_tokens = context_manager.count_total_tokens(conversation)
limit = context_manager.max_tokens
usage_percent = (total_tokens.to_f / limit * 100).round(2)

puts "Token usage: #{total_tokens}/#{limit} (#{usage_percent}%)"

# Check if truncation occurred
if conversation.any? { |msg| msg[:content]&.include?("[Note:") }
  puts "Context was truncated to fit within limits"
end
```

## Best Practices

1. **Start with Balanced**: Use `ContextConfig.balanced` for most use cases
2. **Monitor Usage**: Check token usage periodically in long conversations
3. **Adjust Limits**: Use conservative limits for cost-sensitive applications
4. **Preserve Recent**: Keep enough recent messages for context continuity
5. **Test Thoroughly**: Test with your specific use cases to find optimal settings

## Troubleshooting

### "Context was truncated" messages appearing too often
- Increase `max_tokens` or use `aggressive` configuration
- Reduce `preserve_recent` to make more room

### Important context being lost
- Increase `preserve_recent` to keep more messages
- Consider implementing summarization (future feature)

### High API costs
- Use `conservative` configuration
- Reduce `max_tokens` limit
- Enable for long conversations only

## Future Enhancements

The following strategies are documented but not yet implemented:
- **Summarization**: Automatically summarize old messages
- **Topic-based**: Keep messages related to current topic
- **Importance-based**: Preserve important messages regardless of age
- **Compression**: Compress message content while preserving meaning