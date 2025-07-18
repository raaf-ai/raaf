# Streaming Examples

This directory contains examples demonstrating streaming and asynchronous capabilities for RAAF (Ruby AI Agents Factory).

## Example Status

✅ = Working example  

## Streaming Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `async_example.rb` | ✅ | Concurrent agent operations | Fixed - now shows proper concurrent patterns using threads |
| `streaming_example.rb` | ✅ | Real-time response streaming | Fully working streaming implementation |

## Running Examples

### Prerequisites

1. Set your OpenAI API key:
   ```bash
   export OPENAI_API_KEY="your-api-key"
   ```

2. Install required gems:
   ```bash
   bundle install
   ```

### Running Streaming Examples

```bash
# Asynchronous operations
ruby streaming/examples/async_example.rb

# Real-time streaming
ruby streaming/examples/streaming_example.rb
```

## Streaming Features

### Real-time Streaming
- **Token-by-token streaming**: Receive responses as they're generated
- **Low latency**: Immediate response start
- **Interactive experience**: Users see progress in real-time
- **Cancellation support**: Stop streaming mid-response

### Asynchronous Operations
- **Concurrent agents**: Run multiple agents simultaneously
- **Thread-safe operations**: Safe concurrent execution
- **Resource management**: Automatic cleanup of resources
- **Error isolation**: Failures don't affect other operations

### Performance Benefits
- **Reduced perceived latency**: Users see output immediately
- **Better resource utilization**: Concurrent processing
- **Improved user experience**: Interactive, responsive interface
- **Scalable architecture**: Handle multiple requests efficiently

## Streaming Patterns

### Basic Streaming
```ruby
runner = RAAF::Runner.new(agent: agent)
runner.run("Your query") do |chunk|
  print chunk  # Output each token as received
end
```

### Asynchronous Execution
```ruby
# Run multiple agents concurrently
threads = []
agents.each do |agent|
  threads << Thread.new do
    runner = RAAF::Runner.new(agent: agent)
    runner.run("Process this data")
  end
end

# Wait for all to complete
results = threads.map(&:value)
```

### Error Handling
```ruby
runner.run("Your query") do |chunk|
  print chunk
rescue => error
  puts "Streaming error: #{error.message}"
end
```

## Advanced Streaming

### Stream Processing
- **Token filtering**: Process tokens before display
- **Format conversion**: Convert streamed content
- **State tracking**: Maintain conversation state during streaming
- **Progress indicators**: Show completion progress

### Integration Patterns
- **WebSocket streaming**: Real-time web interfaces
- **CLI streaming**: Interactive command-line tools
- **API streaming**: Server-sent events for web APIs
- **File streaming**: Stream to files for large outputs

### Concurrency Control
- **Rate limiting**: Control concurrent request rates
- **Resource pools**: Manage shared resources
- **Priority queues**: Handle high-priority requests first
- **Load balancing**: Distribute load across resources

## Performance Considerations

### Memory Management
- **Streaming reduces memory usage** by processing tokens as received
- **Garbage collection** is minimized with streaming
- **Large responses** don't accumulate in memory
- **Resource cleanup** happens automatically

### Network Optimization
- **Reduced time to first token** with streaming
- **Better network utilization** with concurrent requests
- **Connection pooling** for multiple agents
- **Retry logic** for failed streams

## Integration Examples

### Web Applications
```ruby
# Streaming to web clients
def stream_to_client(query)
  runner.run(query) do |chunk|
    yield "data: #{chunk}\n\n"  # Server-sent events format
  end
end
```

### CLI Applications
```ruby
# Interactive CLI with streaming
def interactive_cli
  loop do
    print "> "
    query = gets.chomp
    break if query == "exit"
    
    runner.run(query) do |chunk|
      print chunk
    end
    puts "\n"
  end
end
```

## Notes

- All streaming examples are fully functional and tested
- Asynchronous operations use Ruby threads for concurrency
- Error handling is built into streaming operations
- Performance benefits are significant for long responses
- Check individual example files for detailed implementation patterns