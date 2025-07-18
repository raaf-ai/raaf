**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Troubleshooting Guide
=========================

This guide helps you diagnose and resolve common issues when working with Ruby AI Agents Factory (RAAF). From setup problems to runtime errors, this guide provides systematic approaches to identify and fix issues.

After reading this guide, you will know:

* How to diagnose common RAAF setup and runtime issues
* Debugging techniques for agent behavior problems
* Performance troubleshooting and optimization
* Error handling best practices
* When and how to seek additional help

--------------------------------------------------------------------------------

Common Setup Issues
-------------------

### Installation Problems

#### Gem Installation Fails

**Symptoms:**
```
ERROR: Failed building gem native extension
```

**Solutions:**

1. **Update build tools:**
   ```bash
   # macOS
   xcode-select --install
   
   # Ubuntu/Debian
   sudo apt-get install build-essential
   
   # CentOS/RHEL
   sudo yum groupinstall "Development Tools"
   ```

2. **Install system dependencies:**
   ```bash
   # For vector storage (if using)
   pip install numpy scipy
   
   # For NLP features
   python -m spacy download en_core_web_sm
   ```

3. **Use specific Ruby version:**
   ```bash
   rbenv install 3.1.0
   rbenv global 3.1.0
   gem install raaf
   ```

#### Missing API Keys

**Symptoms:**
```
RAAF::Errors::AuthenticationError: API key not configured
```

**Solutions:**

1. **Set environment variables:**
   ```bash
   export OPENAI_API_KEY="your-api-key"
   export ANTHROPIC_API_KEY="your-anthropic-key"
   ```

2. **Check API key format:**

   ```ruby
   # OpenAI keys start with 'sk-'
   # Anthropic keys start with 'sk-ant-'
   # Groq keys start with 'gsk_'
   ```

3. **Verify API key permissions:**
   ```bash
   curl -H "Authorization: Bearer $OPENAI_API_KEY" \
        https://api.openai.com/v1/models
   ```

### Configuration Issues

#### Provider Not Found

**Symptoms:**
```
RAAF::Errors::ProviderError: Unknown provider 'custom_provider'
```

**Solutions:**

1. **Check provider spelling:**

   ```ruby
   # Correct
   provider = RAAF::Models::OpenAIProvider.new
   
   # Incorrect
   provider = RAAF::Models::OpenAiProvider.new  # Wrong case
   ```

2. **Ensure provider gem is installed:**

   ```ruby
   # For Anthropic
   gem 'anthropic-sdk'
   
   # For Groq
   gem 'groq-ruby'
   ```

3. **Use full provider class name:**

   ```ruby
   runner = RAAF::Runner.new(
     agent: agent,
     provider: RAAF::Models::AnthropicProvider.new
   )
   ```

Runtime Issues
--------------

### Agent Execution Problems

#### Agent Doesn't Respond

**Symptoms:**

- Agent returns empty responses
- Long delays without output
- Silent failures

**Debugging Steps:**

1. **Enable debug logging:**

   ```ruby
   RAAF.configure do |config|
     config.log_level = :debug
     config.debug_categories = [:api, :agents, :tools]
   end
   ```

2. **Check API connectivity:**

   ```ruby
   # Test basic API call
   runner = RAAF::Runner.new(agent: agent, debug: true)
   result = runner.run("Hello")
   puts result.error if result.error
   ```

3. **Verify model availability:**

   ```ruby
   provider = RAAF::Models::OpenAIProvider.new
   begin
     models = provider.list_models
     puts "Available models: #{models}"
   rescue => e
     puts "API Error: #{e.message}"
   end
   ```

#### Tool Execution Failures

**Symptoms:**
```
RAAF::Errors::ToolError: Tool 'get_weather' failed to execute
```

**Debugging Steps:**

1. **Test tool function directly:**

   ```ruby
   def get_weather(location:)
     puts "Called with location: #{location}"
     "Weather data for #{location}"
   end
   
   # Test directly
   result = get_weather(location: "San Francisco")
   puts result
   ```

2. **Check tool parameter types:**

   ```ruby
   # Ensure parameters match expected types
   def calculate_total(price:, tax_rate:)
     # price should be Numeric, not String
     raise ArgumentError, "price must be numeric" unless price.is_a?(Numeric)
     price * (1 + tax_rate)
   end
   ```

3. **Add error handling to tools:**

   ```ruby
   def robust_tool(param:)
     begin
       # Tool logic here
       perform_operation(param)
     rescue => e
       { error: "Tool failed: #{e.message}" }
     end
   end
   ```

### Memory and Context Issues

#### Context Not Preserved

**Symptoms:**

- Agent doesn't remember previous conversation
- Context variables reset unexpectedly
- Memory seems to be lost

**Solutions:**

1. **Verify memory manager configuration:**

   ```ruby
   memory_manager = RAAF::Memory::MemoryManager.new(
     store: RAAF::Memory::InMemoryStore.new,
     max_tokens: 4000
   )
   
   runner = RAAF::Runner.new(
     agent: agent,
     memory_manager: memory_manager
   )
   ```

2. **Check session ID consistency:**

   ```ruby
   # Use consistent session ID
   session_id = "user_#{user.id}_conversation"
   
   # All calls should use same session ID
   result1 = runner.run("Hello", session_id: session_id)
   result2 = runner.run("What did I just say?", session_id: session_id)
   ```

3. **Debug memory storage:**

   ```ruby
   # Check what's in memory
   messages = memory_manager.get_messages(session_id)
   puts "Stored messages: #{messages.length}"
   messages.each { |msg| puts "#{msg[:role]}: #{msg[:content]}" }
   ```

#### Memory Pruning Too Aggressive

**Symptoms:**

- Important context gets removed
- Agent forgets recent interactions
- Conversation becomes incoherent

**Solutions:**

1. **Adjust pruning strategy:**

   ```ruby
   memory_manager = RAAF::Memory::MemoryManager.new(
     store: store,
     max_tokens: 8000,  # Increase token limit
     pruning_strategy: :semantic_similarity,  # More intelligent pruning
     preserve_recent_count: 10  # Keep last 10 messages
   )
   ```

2. **Use context variables for persistent data:**

   ```ruby
   runner = RAAF::Runner.new(
     agent: agent,
     memory_manager: memory_manager,
     context_variables: {
       user_name: "Alice",
       preferences: { theme: "dark" },
       conversation_goal: "technical_support"
     }
   )
   ```

Performance Issues
------------------

### Slow Response Times

**Symptoms:**

- Agents take too long to respond
- Timeout errors
- Poor user experience

**Debugging Steps:**

1. **Enable performance tracing:**

   ```ruby
   tracer = RAAF::Tracing::SpanTracer.new
   tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new(
     include_timing: true
   ))
   
   runner = RAAF::Runner.new(agent: agent, tracer: tracer)
   ```

2. **Profile different components:**

   ```ruby
   require 'benchmark'
   
   time = Benchmark.measure do
     result = runner.run("Test message")
   end
   
   puts "Total time: #{time.real}s"
   ```

3. **Check model selection:**

   ```ruby
   # Fast models for simple tasks
   fast_agent = RAAF::Agent.new(
     name: "FastAgent",
     instructions: "Brief responses only",
     model: "gpt-4o-mini"  # Faster than gpt-4o
   )
   ```

**Optimization Strategies:**

1. **Use appropriate models:**

   ```ruby
   # For simple tasks
   simple_agent.model = "gpt-4o-mini"
   
   # For complex reasoning
   complex_agent.model = "gpt-4o"
   
   # For speed
   speed_agent.model = "groq:llama-3.1-70b-versatile"
   ```

2. **Optimize memory usage:**

   ```ruby
   # Reduce memory footprint
   memory_manager = RAAF::Memory::MemoryManager.new(
     store: store,
     max_tokens: 2000,  # Smaller context
     pruning_strategy: :sliding_window
   )
   ```

3. **Enable parallel processing:**

   ```ruby
   agent = RAAF::Agent.new(
     name: "ParallelAgent",
     instructions: "Use tools efficiently",
     model: "gpt-4o",
     parallel_tool_calls: true  # Enable parallel tool execution
   )
   ```

### High Token Usage

**Symptoms:**

- Unexpected API costs
- Token limit exceeded errors
- Poor cost efficiency

**Solutions:**

1. **Monitor token usage:**

   ```ruby
   result = runner.run("Test message")
   usage = result.usage
   
   puts "Prompt tokens: #{usage[:prompt_tokens]}"
   puts "Completion tokens: #{usage[:completion_tokens]}"
   puts "Total tokens: #{usage[:total_tokens]}"
   ```

2. **Optimize prompt size:**

   ```ruby
   # Keep instructions concise
   agent = RAAF::Agent.new(
     name: "EfficientAgent",
     instructions: "Be helpful and concise.",  # Short instructions
     model: "gpt-4o-mini"
   )
   ```

3. **Implement cost tracking:**

   ```ruby
   cost_tracker = RAAF::Tracing::CostTracker.new(
     pricing: {
       'gpt-4o' => { input: 5.00, output: 15.00 },  # Per 1M tokens
       'gpt-4o-mini' => { input: 0.15, output: 0.60 }
     }
   )
   ```

Error Handling
--------------

### API Errors

#### Rate Limiting

**Symptoms:**
```
RAAF::Errors::RateLimitError: Rate limit exceeded
```

**Solutions:**

1. **Implement exponential backoff:**

   ```ruby
   provider = RAAF::Models::OpenAIProvider.new(
     max_retries: 5,
     retry_backoff: :exponential,
     retry_jitter: true
   )
   ```

2. **Use rate limiting middleware:**

   ```ruby
   class RateLimitedRunner
     def initialize(runner, requests_per_minute: 60)
       @runner = runner
       @rate_limiter = RateLimiter.new(requests_per_minute)
     end
     
     def run(message)
       @rate_limiter.wait_if_needed
       @runner.run(message)
     end
   end
   ```

#### Authentication Errors

**Symptoms:**
```
RAAF::Errors::AuthenticationError: Invalid API key
```

**Solutions:**

1. **Verify API key:**

   ```ruby
   api_key = ENV['OPENAI_API_KEY']
   puts "API key starts with: #{api_key[0..10]}..." if api_key
   puts "API key length: #{api_key&.length}"
   ```

2. **Check permissions:**
   ```bash
   # Test API access
   curl -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"test"}]}' \
        https://api.openai.com/v1/chat/completions
   ```

### Tool Errors

#### Function Not Found

**Symptoms:**
```
RAAF::Errors::ToolError: Function 'undefined_tool' not found
```

**Solutions:**

1. **List available tools:**

   ```ruby
   tools = agent.tools
   puts "Available tools: #{tools.map { |t| t[:function][:name] }}"
   ```

2. **Check tool registration:**

   ```ruby
   def my_tool(param:)
     "Result: #{param}"
   end
   
   # Register tool
   agent.add_tool(method(:my_tool))
   
   # Verify registration
   puts agent.tools.inspect
   ```

#### Parameter Validation Errors

**Symptoms:**
```
ArgumentError: wrong number of arguments
```

**Solutions:**

1. **Add parameter validation:**

   ```ruby
   def validated_tool(required_param:, optional_param: nil)
     raise ArgumentError, "required_param cannot be nil" if required_param.nil?
     
     # Tool logic here
   end
   ```

2. **Use JSON schema validation:**

   ```ruby
   def schema_validated_tool(params)
     schema = {
       type: "object",
       properties: {
         name: { type: "string" },
         age: { type: "integer", minimum: 0 }
       },
       required: ["name"]
     }
     
     # Validate params against schema
     JSON::Validator.validate!(schema, params)
   end
   ```

Debugging Techniques
--------------------

### Logging and Tracing

#### Enable Comprehensive Logging

```ruby
# Configure detailed logging
RAAF.configure do |config|
  config.log_level = :debug
  config.debug_categories = [:api, :agents, :tools, :memory, :tracing]
end

# Custom logger
logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

RAAF.logger = logger
```

#### Trace Agent Execution

```ruby
# Console tracing for debugging
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new(
  log_level: :debug,
  include_payloads: true,
  include_timing: true
))

runner = RAAF::Runner.new(agent: agent, tracer: tracer)
```

#### Custom Debug Output

```ruby
class DebugRunner < RAAF::Runner
  def run(message, **options)
    puts "🚀 Starting conversation with message: #{message}"
    
    result = super(message, **options)
    
    puts "✅ Conversation completed in #{result.duration_ms}ms"
    puts "💬 Messages: #{result.messages.length}"
    puts "🔧 Tool calls: #{result.tool_calls.length}"
    puts "📊 Token usage: #{result.usage}"
    
    result
  end
end
```

### Testing and Isolation

#### Mock Providers for Testing

```ruby
RSpec.describe 'Agent Debugging' do
  let(:mock_provider) { RAAF::Testing::MockProvider.new }
  let(:runner) { RAAF::Runner.new(agent: agent, provider: mock_provider) }
  
  it 'debugs tool execution' do
    mock_provider.add_tool_response(
      tool_calls: [{ tool_name: 'get_weather', parameters: { location: 'SF' } }],
      final_response: "Weather response"
    )
    
    result = runner.run("What's the weather?")
    
    # Debug output
    puts "Tool calls made: #{result.tool_calls}"
    puts "Final response: #{result.messages.last[:content]}"
  end
end
```

#### Isolated Component Testing

```ruby
# Test memory in isolation
memory_store = RAAF::Memory::InMemoryStore.new
memory_manager = RAAF::Memory::MemoryManager.new(store: memory_store)

memory_manager.add_message("test_session", "user", "Hello")
messages = memory_manager.get_messages("test_session")

puts "Stored messages: #{messages}"
```

Performance Profiling
----------------------

### Memory Profiling

```ruby
require 'memory_profiler'

report = MemoryProfiler.report do
  result = runner.run("Complex task")
end

report.pretty_print(to_file: 'memory_profile.txt')
```

### CPU Profiling

```ruby
require 'ruby-prof'

RubyProf.start

result = runner.run("Performance test")

result = RubyProf.stop
printer = RubyProf::FlatPrinter.new(result)
printer.print(File.open('cpu_profile.txt', 'w'))
```

### Network Profiling

```ruby
require 'net/http'

# Monkey patch to track API calls
class Net::HTTP
  alias_method :original_request, :request
  
  def request(req)
    start_time = Time.now
    response = original_request(req)
    duration = Time.now - start_time
    
    puts "API Call: #{req.method} #{req.path} - #{duration}s"
    response
  end
end
```

Common Error Messages
---------------------

### "Agent not responding"

**Possible Causes:**

- Network connectivity issues
- API key problems
- Model not available
- Token limit exceeded

**Quick Fix:**

```ruby
# Test with minimal example
agent = RAAF::Agent.new(
  name: "TestAgent",
  instructions: "Just say hello",
  model: "gpt-4o-mini"
)

result = RAAF::Runner.new(agent: agent).run("Hi")
puts result.error || result.messages.last[:content]
```

### "Tool execution failed"

**Possible Causes:**

- Tool function errors
- Parameter mismatches
- Network issues in tools
- Tool not properly registered

**Quick Fix:**

```ruby
# Test tool directly
def test_tool(param:)
  puts "Tool called with: #{param}"
  "Tool result: #{param.upcase}"
end

# Test outside agent
result = test_tool(param: "hello")
puts result

# Then add to agent
agent.add_tool(method(:test_tool))
```

### "Memory not persisting"

**Possible Causes:**

- Session ID inconsistency
- Memory store configuration
- Pruning too aggressive
- Store not properly initialized

**Quick Fix:**

```ruby
# Simple memory test
memory_manager = RAAF::Memory::MemoryManager.new(
  store: RAAF::Memory::InMemoryStore.new
)

session_id = "test_session"
memory_manager.add_message(session_id, "user", "Remember this")
messages = memory_manager.get_messages(session_id)

puts "Messages in memory: #{messages.length}"
```

When to Seek Help
-----------------

### Community Resources

1. **GitHub Issues:** Report bugs or ask questions
2. **GitHub Discussions:** Community support and questions
3. **Stack Overflow:** Tag questions with `raaf` and `ruby`
4. **Documentation:** Check latest docs for updates

### Providing Information

When seeking help, include:

1. **Ruby version:** `ruby --version`
2. **RAAF version:** `gem list raaf`
3. **Error message:** Full stack trace
4. **Minimal reproduction:** Smallest possible example
5. **Environment:** OS, dependencies, configuration

### Bug Report Template

```ruby
# Minimal reproduction case
require 'raaf'

agent = RAAF::Agent.new(
  name: "BugAgent",
  instructions: "Reproduce the bug",
  model: "gpt-4o-mini"
)

runner = RAAF::Runner.new(agent: agent)

begin
  result = runner.run("Trigger the bug")
  puts result.messages.last[:content]
rescue => e
  puts "Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(10)
end
```

Next Steps
----------

For additional help:

* **[API Reference](api_reference.html)** - Complete API documentation
* **[Performance Guide](performance_guide.html)** - Optimization techniques
* **[Testing Guide](testing_guide.html)** - Testing strategies
* **[Contributing](contributing.html)** - How to contribute fixes
* **[GitHub Issues](https://github.com/raaf-ai/raaf/issues)** - Report problems