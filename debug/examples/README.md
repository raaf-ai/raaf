# Debug Examples

This directory contains examples demonstrating debugging capabilities for RAAF (Ruby AI Agents Factory).

## Example Status

✅ = Working example  

## Debug Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `debugging_tools_example.rb` | ✅ | Debugging tools and utilities | Fully working |
| `interactive_repl_example.rb` | ✅ | Interactive debugging REPL | Fully working |

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

### Running Debug Examples

```bash
# Debugging tools
ruby debug/examples/debugging_tools_example.rb

# Interactive REPL
ruby debug/examples/interactive_repl_example.rb
```

## Debug Features

### Debugging Tools
- **Step-by-step execution**: Debug agent conversations
- **Variable inspection**: Examine agent state
- **Breakpoints**: Pause execution at specific points
- **Call stack analysis**: Understand execution flow

### Interactive REPL
- **Live interaction**: Test agents interactively
- **Command history**: Navigate previous commands
- **Variable exploration**: Inspect runtime state
- **Hot reloading**: Modify agents without restart

### Debug Utilities
- **Logging enhancement**: Detailed debug output
- **Performance profiling**: Identify bottlenecks
- **Memory analysis**: Track memory usage
- **Error analysis**: Deep dive into failures

## Debug Patterns

### Basic Debugging
```ruby
debugger = RAAF::Debug::Debugger.new
debugger.attach(agent)
debugger.set_breakpoint(:before_tool_call)

runner = RAAF::Runner.new(agent: agent, debugger: debugger)
result = runner.run("Debug this conversation")
```

### Interactive Session
```ruby
repl = RAAF::Debug::REPL.new
repl.start_session(agent)

# Interactive commands:
# > inspect agent
# > step
# > continue
# > help
```

### Performance Profiling
```ruby
profiler = RAAF::Debug::Profiler.new
profiler.start

runner.run("Your query")

report = profiler.stop
puts report.summary
```

## Debug Commands

### REPL Commands
- **step**: Execute one step
- **continue**: Continue execution
- **inspect <object>**: Examine object state
- **trace**: Show execution trace
- **help**: Show available commands
- **exit**: Exit debug session

### Breakpoint Types
- **before_tool_call**: Before any tool execution
- **after_tool_call**: After tool completion
- **on_error**: When errors occur
- **custom**: User-defined breakpoints

## Advanced Debugging

### Remote Debugging
- **Network debugging**: Debug agents running remotely
- **Distributed tracing**: Debug multi-agent systems
- **Production debugging**: Safe production debugging
- **Log aggregation**: Centralized debug information

### Performance Analysis
- **Token usage tracking**: Monitor API consumption
- **Response time analysis**: Identify slow operations
- **Memory profiling**: Track memory usage patterns
- **Concurrency analysis**: Debug threading issues

## Notes

- Debug tools are designed for development and testing
- Production debugging features are safe for live systems
- Interactive REPL provides immediate feedback
- Performance profiling helps optimize agent performance
- Check individual example files for detailed usage patterns