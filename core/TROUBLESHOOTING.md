# Troubleshooting Guide

Common issues and solutions for RAAF (Ruby AI Agents Factory).

## Table of Contents

1. [Installation Issues](#installation-issues)
2. [Authentication Problems](#authentication-problems)
3. [API and Network Issues](#api-and-network-issues)
4. [Agent Execution Problems](#agent-execution-problems)
5. [Tool Integration Issues](#tool-integration-issues)
6. [Tracing and Monitoring](#tracing-and-monitoring)
7. [Performance Issues](#performance-issues)
8. [Memory and Resource Problems](#memory-and-resource-problems)
9. [Configuration Issues](#configuration-issues)
10. [Error Messages](#error-messages)

## Installation Issues

### Gem Installation Fails

**Problem**: `gem install raaf` fails with compilation errors.

**Solution**:
```bash
# Update system dependencies
# On macOS:
xcode-select --install
brew install openssl

# On Ubuntu/Debian:
sudo apt-get update
sudo apt-get install build-essential libssl-dev

# Install with specific flags
gem install raaf -- --with-openssl-include=/opt/homebrew/include/openssl
```

### Bundle Install Issues

**Problem**: `bundle install` fails with dependency conflicts.

**Solution**:
```bash
# Clear bundle cache
bundle clean --force
rm -rf .bundle
rm Gemfile.lock

# Update bundler
gem update bundler

# Install with specific Ruby version
rbenv install 3.2.0
rbenv local 3.2.0
bundle install
```

### Version Compatibility

**Problem**: Gem doesn't work with older Ruby versions.

**Solution**:
- Upgrade to Ruby 3.0 or higher
- Check compatibility matrix in README
- Use specific gem version for older Ruby

```ruby
# In Gemfile for Ruby 2.7
gem 'raaf', '~> 0.1.0'
```

## Authentication Problems

### Invalid API Key

**Problem**: `RAAF::AuthenticationError: Invalid API key`

**Solutions**:
```bash
# Verify API key format
echo $OPENAI_API_KEY | grep -E '^sk-proj-[a-zA-Z0-9]{64,}$'

# Check key permissions on OpenAI platform
# Ensure key has correct project access

# Set key correctly
export OPENAI_API_KEY="sk-proj-your-actual-key-here"

# Test key directly
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
     https://api.openai.com/v1/models
```

### Key Not Found

**Problem**: `OPENAI_API_KEY environment variable not set`

**Solutions**:
```ruby
# Option 1: Set environment variable
ENV['OPENAI_API_KEY'] = 'your-key'

# Option 2: Pass key directly
agent = RAAF::Agent.new(
  name: "Assistant",
  model: "gpt-4",
  api_key: "your-key"
)

# Option 3: Use configuration
config = RAAF::Configuration.new
config.set("openai.api_key", "your-key")
```

### Multiple Provider Keys

**Problem**: Using multiple providers but some keys are missing.

**Solution**:
```bash
# Set all required keys
export OPENAI_API_KEY="sk-proj-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GEMINI_API_KEY="..."

# Or handle missing keys gracefully
begin
  claude_agent = RAAF::Agent.new(model: "claude-3-sonnet")
rescue RAAF::AuthenticationError => e
  puts "Claude not available: #{e.message}"
  # Fall back to OpenAI
  agent = RAAF::Agent.new(model: "gpt-4")
end
```

## API and Network Issues

### Connection Timeouts

**Problem**: Requests timeout or hang indefinitely.

**Solutions**:
```ruby
# Set timeouts in configuration
config = RAAF::Configuration.new
config.set("openai.timeout", 30)
config.set("openai.max_retries", 3)

# Or configure provider directly
provider = RAAF::Models::OpenAIProvider.new(
  timeout: 30,
  max_retries: 3
)

runner = RAAF::Runner.new(agent: agent, provider: provider)
```

### Rate Limiting

**Problem**: `RAAF::RateLimitError: Rate limit exceeded`

**Solutions**:
```ruby
# Implement exponential backoff
def run_with_retry(runner, messages, max_retries: 3)
  retry_count = 0
  
  begin
    runner.run(messages)
  rescue RAAF::RateLimitError => e
    retry_count += 1
    
    if retry_count <= max_retries
      delay = 2 ** retry_count
      puts "Rate limited, retrying in #{delay}s..."
      sleep(delay)
      retry
    else
      raise e
    end
  end
end

# Use guardrails to prevent rate limiting
guardrails = RAAF::Guardrails::GuardrailManager.new
guardrails.add_guardrail(
  RAAF::Guardrails::RateLimitGuardrail.new(
    max_requests_per_minute: 50  # Below your API limit
  )
)
```

### SSL/TLS Issues

**Problem**: SSL certificate verification fails.

**Solutions**:
```ruby
# Update certificates
# On macOS:
brew install ca-certificates

# Set SSL options
require 'openssl'
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE  # Not recommended for production

# Or update Ruby with proper SSL support
rbenv install 3.2.0
rbenv global 3.2.0
```

### Proxy Configuration

**Problem**: Behind corporate firewall/proxy.

**Solution**:
```ruby
# Set proxy environment variables
ENV['HTTP_PROXY'] = 'http://proxy.company.com:8080'
ENV['HTTPS_PROXY'] = 'https://proxy.company.com:8080'

# Or configure in code
require 'net/http'
Net::HTTP.class_eval do
  alias_method :original_initialize, :initialize
  
  def initialize(address, port = nil)
    original_initialize(address, port)
    @proxy_addr = 'proxy.company.com'
    @proxy_port = 8080
  end
end
```

## Agent Execution Problems

### Agent Not Responding

**Problem**: Agent calls complete but return empty or nonsensical responses.

**Debugging**:
```ruby
# Enable debug logging
ENV['RAAF_DEBUG_CATEGORIES'] = 'all'

# Check agent configuration
puts agent.inspect
puts "Instructions: #{agent.instructions}"
puts "Model: #{agent.model}"

# Test with simple message
result = runner.run("Hello, can you hear me?")
puts "Response: #{result.messages.last[:content]}"
```

**Solutions**:
- Check agent instructions are clear and specific
- Verify model supports the requested functionality
- Ensure API key has access to the specified model

### Tool Calls Not Working

**Problem**: Agent doesn't use available tools.

**Debugging**:
```ruby
# Check tool registration
puts "Available tools: #{agent.tools.map(&:name)}"

# Verify tool definitions
agent.tools.each do |tool|
  puts "Tool: #{tool.name}"
  puts "Description: #{tool.description}"
  puts "Parameters: #{tool.parameters}"
end

# Test tool directly
result = agent.execute_tool("tool_name", param: "value")
puts "Tool result: #{result}"
```

**Solutions**:
```ruby
# Ensure tools have clear descriptions
def get_weather(city)
  "Current weather in #{city}"
end

tool = RAAF::FunctionTool.new(
  method(:get_weather),
  name: "get_weather",
  description: "Get current weather information for any city", # Clear description
  parameters: {
    type: "object",
    properties: {
      city: { 
        type: "string", 
        description: "Name of the city to get weather for" # Clear parameter description
      }
    },
    required: ["city"]
  }
)

# Update agent instructions to mention tools
agent = RAAF::Agent.new(
  name: "WeatherBot",
  instructions: "You are a weather assistant. Use the get_weather tool to provide current weather information when users ask about weather.",
  model: "gpt-4"
)
```

### Handoffs Not Working

**Problem**: Agent handoffs aren't triggered.

**Debugging**:
```ruby
# Check handoff configuration
puts "Handoffs: #{agent.handoffs.map(&:name)}"

# Verify handoff conditions in instructions
puts agent.instructions
```

**Solutions**:
```ruby
# Clear handoff instructions
support_agent = RAAF::Agent.new(
  name: "CustomerSupport",
  instructions: "You handle general customer inquiries. 
                 If a customer has a technical issue, billing question, 
                 or complex problem, transfer them to TechnicalSupport using handoff.",
  model: "gpt-4"
)

tech_agent = RAAF::Agent.new(
  name: "TechnicalSupport",
  instructions: "You handle technical support issues and troubleshooting.",
  model: "gpt-4"
)

support_agent.add_handoff(tech_agent)

# Test with explicit handoff request
result = runner.run("I'm having technical issues with the API")
```

## Tool Integration Issues

### Tool Execution Errors

**Problem**: Tools fail with runtime errors.

**Debugging**:
```ruby
# Test tool independently
begin
  result = agent.execute_tool("problematic_tool", param: "test")
  puts "Success: #{result}"
rescue => e
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(5)
end
```

**Solutions**:
```ruby
# Add error handling to tools
def robust_tool(input)
  # Validate input
  raise ArgumentError, "Input cannot be nil" if input.nil?
  
  # Process with error handling
  begin
    # Your tool logic here
    result = process_input(input)
    
    # Validate output
    raise "Invalid result" if result.nil?
    
    result
  rescue => e
    # Return helpful error message
    "Error processing request: #{e.message}"
  end
end

# Use FunctionTool with validation
tool = RAAF::FunctionTool.new(
  proc do |input|
    # Validate parameters
    raise ArgumentError, "Input required" if input.to_s.strip.empty?
    
    robust_tool(input)
  end,
  name: "robust_tool",
  description: "A tool with proper error handling"
)
```

### File Search Issues

**Problem**: FileSearchTool not finding files.

**Solutions**:
```ruby
# Check search paths exist
search_paths = ["./src", "./docs"]
search_paths.each do |path|
  puts "#{path}: #{Dir.exist?(path) ? 'exists' : 'missing'}"
end

# Verify file permissions
Dir.glob("./src/**/*").each do |file|
  puts "#{file}: #{File.readable?(file) ? 'readable' : 'not readable'}"
end

# Configure tool correctly
file_search = RAAF::Tools::FileSearchTool.new(
  search_paths: search_paths.select { |path| Dir.exist?(path) },
  file_extensions: [".rb", ".md", ".txt"],
  max_results: 10,
  exclude_patterns: ["*/node_modules/*", "*/.git/*"]
)
```

### Web Search Issues

**Problem**: WebSearchTool not returning results.

**Solutions**:
```ruby
# Test search engine directly
require 'net/http'
require 'uri'

# Check DuckDuckGo availability
uri = URI('https://duckduckgo.com/')
response = Net::HTTP.get_response(uri)
puts "DuckDuckGo status: #{response.code}"

# Configure with fallback
web_search = RAAF::Tools::WebSearchTool.new(
  search_engine: "duckduckgo",
  max_results: 5,
  timeout: 30
)

# Test search directly
begin
  results = web_search.call(query: "Ruby programming")
  puts "Results: #{results}"
rescue => e
  puts "Search failed: #{e.message}"
end
```

## Tracing and Monitoring

### Traces Not Appearing

**Problem**: Traces not showing up in OpenAI dashboard.

**Debugging**:
```ruby
# Enable trace debugging
ENV['RAAF_DEBUG_CATEGORIES'] = 'all'

# Check if tracing is enabled
puts "Tracing disabled: #{RAAF::Tracing::TraceProvider.disabled?}"

# Verify tracer configuration
tracer = RAAF::Tracing::SpanTracer.new
puts "Processors: #{tracer.processors.length}"

# Force flush traces
RAAF::Tracing::TraceProvider.force_flush
sleep(2)  # Wait for upload
```

**Solutions**:
```ruby
# Ensure OpenAI processor is added
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)

# Or use global tracer
RAAF.configure_tracing do |config|
  config.add_processor(RAAF::Tracing::OpenAIProcessor.new)
end

# Check API key permissions
# Ensure your OpenAI API key has traces access
```

### Trace Format Issues

**Problem**: Traces have wrong format or missing data.

**Solutions**:
```ruby
# Use RunConfig for proper trace formatting
config = RAAF::RunConfig.new(
  trace_include_sensitive_data: true,  # Include full conversation
  workflow_name: "My Application"      # Set descriptive workflow name
)

result = runner.run(messages, config: config)

# Verify span data
tracer.current_span&.attributes&.each do |key, value|
  puts "#{key}: #{value}"
end
```

### Performance Monitoring

**Problem**: Need to monitor agent performance.

**Solution**:
```ruby
# Add custom metrics
class MetricsTracker
  def self.track_agent_performance(agent_name, &block)
    start_time = Time.current
    start_memory = memory_usage
    
    result = yield
    
    duration = Time.current - start_time
    memory_used = memory_usage - start_memory
    
    puts "Agent: #{agent_name}"
    puts "Duration: #{duration}s"
    puts "Memory: #{memory_used}MB"
    puts "Tokens: #{result.usage&.dig(:total_tokens)}"
    
    result
  end
  
  private
  
  def self.memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i / 1024
  end
end

# Use in your code
result = MetricsTracker.track_agent_performance("CustomerSupport") do
  runner.run(messages)
end
```

## Performance Issues

### Slow Response Times

**Problem**: Agent responses are very slow.

**Debugging**:
```ruby
# Time each component
start = Time.current
result = runner.run(messages)
total_time = Time.current - start

puts "Total time: #{total_time}s"
puts "Model: #{agent.model}"
puts "Messages: #{messages.length}"
puts "Tools used: #{result.usage&.dig(:tool_calls) || 0}"
```

**Solutions**:
```ruby
# Use faster models for simple tasks
fast_agent = RAAF::Agent.new(
  name: "FastAssistant",
  model: "gpt-3.5-turbo",  # Faster than gpt-4
  instructions: "Be concise and direct."
)

# Reduce max_turns for simple conversations
agent = RAAF::Agent.new(
  name: "Assistant",
  model: "gpt-4",
  max_turns: 3  # Limit conversation length
)

# Use streaming for long responses
streaming_runner = RAAF::StreamingRunner.new(agent: agent)
streaming_runner.run_streaming(messages) do |chunk|
  print chunk[:content]  # Display immediately
end
```

### High Token Usage

**Problem**: Consuming too many tokens.

**Solutions**:
```ruby
# Monitor token usage
tracker = RAAF::UsageTracking::UsageTracker.new
tracker.add_alert(:high_tokens) do |usage|
  usage[:tokens_today] > 100_000
end

# Add token limits to guardrails
guardrails = RAAF::Guardrails::GuardrailManager.new
guardrails.add_guardrail(
  RAAF::Guardrails::LengthGuardrail.new(
    max_input_length: 10_000,   # Limit input
    max_output_length: 2_000    # Limit output
  )
)

# Use more efficient prompting
agent = RAAF::Agent.new(
  name: "EfficientAgent",
  instructions: "Be concise. Use bullet points. Avoid repetition.",
  model: "gpt-4"
)
```

## Memory and Resource Problems

### Memory Leaks

**Problem**: Application memory usage grows continuously.

**Debugging**:
```ruby
# Monitor memory usage
def check_memory
  memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
  puts "Memory usage: #{memory_mb}MB"
  memory_mb
end

initial_memory = check_memory

# Run your code
1000.times do |i|
  runner.run("Hello #{i}")
  
  if i % 100 == 0
    current_memory = check_memory
    growth = current_memory - initial_memory
    puts "Memory growth after #{i} iterations: #{growth}MB"
  end
end
```

**Solutions**:
```ruby
# Clear traces periodically
class MemoryManagedRunner < RAAF::Runner
  def initialize(*args, **kwargs)
    super
    @request_count = 0
  end
  
  def run(messages, **kwargs)
    result = super
    
    @request_count += 1
    
    # Clear traces every 100 requests
    if @request_count % 100 == 0
      @tracer&.clear
      GC.start  # Force garbage collection
    end
    
    result
  end
end

# Use object pooling for frequently created objects
class ObjectPool
  def initialize(size: 10, &block)
    @pool = Array.new(size, &block)
    @mutex = Mutex.new
  end
  
  def with_object
    @mutex.synchronize do
      object = @pool.pop
      begin
        yield object
      ensure
        object.reset if object.respond_to?(:reset)
        @pool.push(object)
      end
    end
  end
end
```

### CPU Usage Issues

**Problem**: High CPU usage during agent execution.

**Solutions**:
```ruby
# Use async processing for multiple requests
require 'async'

Async do
  tasks = messages_batch.map do |messages|
    Async do
      runner.run(messages)
    end
  end
  
  results = tasks.map(&:wait)
end

# Implement request queuing
class QueuedRunner
  def initialize(agent, max_concurrent: 5)
    @agent = agent
    @semaphore = Async::Semaphore.new(max_concurrent)
  end
  
  def run_async(messages)
    @semaphore.async do
      runner = RAAF::Runner.new(agent: @agent)
      runner.run(messages)
    end
  end
end
```

## Configuration Issues

### Configuration Not Loading

**Problem**: Configuration files not being read.

**Debugging**:
```ruby
# Check file existence
config_file = "config/openai_agents.yml"
puts "Config file exists: #{File.exist?(config_file)}"

# Check file permissions
puts "Config file readable: #{File.readable?(config_file)}" if File.exist?(config_file)

# Check YAML syntax
begin
  YAML.load_file(config_file)
  puts "YAML syntax is valid"
rescue => e
  puts "YAML error: #{e.message}"
end
```

**Solutions**:
```ruby
# Specify config file explicitly
config = RAAF::Configuration.new(
  config_file: "/path/to/your/config.yml"
)

# Use environment-specific config
config = RAAF::Configuration.new(environment: Rails.env)

# Fall back to defaults if config missing
begin
  config = RAAF::Configuration.load_from_file("config.yml")
rescue => e
  puts "Config file not found, using defaults: #{e.message}"
  config = RAAF::Configuration.new
end
```

### Environment Variables

**Problem**: Environment variables not being recognized.

**Solutions**:
```ruby
# Check if variables are set
required_vars = %w[OPENAI_API_KEY ANTHROPIC_API_KEY]
missing_vars = required_vars.select { |var| ENV[var].nil? }

unless missing_vars.empty?
  puts "Missing environment variables: #{missing_vars.join(', ')}"
end

# Load from .env file
require 'dotenv'
Dotenv.load('.env.local', '.env')

# Set defaults
ENV['RAAF_LOG_LEVEL'] ||= 'info'
ENV['RAAF_ENVIRONMENT'] ||= 'development'
```

## Error Messages

### Common Error Messages and Solutions

#### "Model not found"
```ruby
# Check model availability
provider = RAAF::Models::OpenAIProvider.new
puts "Supported models: #{provider.supported_models}"

# Use correct model name
agent = RAAF::Agent.new(
  name: "Assistant",
  model: "gpt-4o",  # Correct model name
  instructions: "You are helpful."
)
```

#### "Tool 'X' not found"
```ruby
# Check tool registration
puts "Available tools: #{agent.tools.map(&:name)}"

# Ensure tool is properly added
agent.add_tool(method(:your_tool))

# Check tool name matches
def your_tool(param)
  "Result"
end

tool = RAAF::FunctionTool.new(
  method(:your_tool),
  name: "your_tool"  # Must match method name
)
```

#### "Invalid parameters for tool call"
```ruby
# Check parameter schema
tool.parameters.each do |key, schema|
  puts "#{key}: #{schema}"
end

# Ensure required parameters are specified
parameters: {
  type: "object",
  properties: {
    required_param: { type: "string" }
  },
  required: ["required_param"]  # Must list required params
}
```

#### "Connection refused"
```ruby
# Check network connectivity
require 'net/http'
uri = URI('https://api.openai.com/v1/models')
response = Net::HTTP.get_response(uri)
puts "OpenAI API status: #{response.code}"

# Check proxy settings
puts "HTTP_PROXY: #{ENV['HTTP_PROXY']}"
puts "HTTPS_PROXY: #{ENV['HTTPS_PROXY']}"
```

### Debug Mode

Enable comprehensive debugging:

```ruby
# Enable all debug features
ENV['RAAF_DEBUG_CATEGORIES'] = 'all'
ENV['RAAF_LOG_LEVEL'] = 'debug'

# Use debugging runner
debugger = RAAF::Debugging::Debugger.new
debugger.set_breakpoint("agent_run_start")
debugger.enable_step_mode

debug_runner = RAAF::Debugging::DebugRunner.new(
  agent: agent,
  debugger: debugger
)

result = debug_runner.run(messages)
```

### Getting Help

If you can't resolve an issue:

1. **Check the logs** with debug mode enabled
2. **Search existing issues** on GitHub
3. **Create a minimal reproduction case**
4. **Include relevant configuration** and error messages
5. **Check the API status** at status.openai.com

For additional support, see:
- [GitHub Issues](https://github.com/enterprisemodules/openai-agents-ruby/issues)
- [API Documentation](API_REFERENCE.md)
- [Security Guide](SECURITY.md)