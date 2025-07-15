# RAAF Testing

[![Gem Version](https://badge.fury.io/rb/raaf-testing.svg)](https://badge.fury.io/rb/raaf-testing)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **RAAF Testing** gem provides comprehensive testing utilities, RSpec matchers, and test helpers for the Ruby AI Agents Factory (RAAF) ecosystem. This gem makes it easy to write robust, reliable tests for AI agents, tools, memory systems, providers, and multi-agent workflows.

## Overview

RAAF (Ruby AI Agents Factory) Testing extends the core RAAF functionality with specialized testing capabilities:

- **RSpec Matchers** - Custom matchers for agent responses, tool usage, and behavior validation
- **Mock Providers** - Test-friendly LLM providers for consistent, fast testing without API calls
- **Conversation Testing** - Utilities for testing multi-turn conversations and context handling
- **Response Validation** - Tools for validating agent responses against custom criteria
- **Fixtures & Factories** - Pre-built test data and agent configurations
- **VCR Integration** - Record and replay HTTP interactions for consistent testing
- **Performance Testing** - Benchmarking and performance validation utilities
- **Integration Testing** - End-to-end testing utilities for multi-agent systems

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raaf-testing'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install raaf-testing
```

## Quick Start

### Basic RSpec Setup

```ruby
# spec/spec_helper.rb
require 'raaf-testing'

RSpec.configure do |config|
  # Include RAAF testing utilities
  config.include RubyAIAgentsFactory::Testing::Helpers
  
  # Configure testing environment
  config.before(:suite) do
    RubyAIAgentsFactory::Testing.setup_test_environment
  end
  
  # Clean up after each test
  config.after(:each) do
    RubyAIAgentsFactory::Testing.cleanup_test_resources
  end
end
```

### Simple Agent Testing

```ruby
# spec/agent_spec.rb
require 'spec_helper'

RSpec.describe "Customer Support Agent" do
  let(:agent) { create_test_agent(name: "Support", instructions: "Help customers") }
  
  it "responds to greetings" do
    result = agent.run("Hello")
    expect(result).to be_successful
    expect(result).to have_message_containing("hello")
  end
  
  it "provides helpful responses" do
    result = agent.run("How can you help me?")
    expect(result).to be_successful
    expect(result).to have_positive_sentiment
    expect(result).to have_message_length_between(10, 200)
  end
end
```

### Mock Provider Usage

```ruby
RSpec.describe "Weather Agent" do
  let(:mock_provider) { RubyAIAgentsFactory::Testing::MockProvider.new }
  let(:agent) do
    RubyAIAgentsFactory::Agent.new(
      name: "WeatherAgent",
      instructions: "You provide weather information",
      provider: mock_provider
    )
  end
  
  before do
    mock_provider.add_response("weather", "It's sunny today!")
    mock_provider.add_response(/rain/i, "It's raining cats and dogs!")
  end
  
  it "provides weather information" do
    result = agent.run("What's the weather like?")
    expect(result).to be_successful
    expect(result).to have_message_containing("sunny")
  end
end
```

## RSpec Matchers

### Response Success Matchers

```ruby
# Test for successful responses
expect(result).to be_successful
expect(result).to be_safe

# Test for failures
expect(result).not_to be_successful
```

### Content Matchers

```ruby
# Test message content
expect(result).to have_message_containing("hello")
expect(result).to have_message_containing(/weather/i)

# Test message length
expect(result).to have_message_length(100)
expect(result).to have_message_length_between(50, 200)
```

### Performance Matchers

```ruby
# Test response time
expect(result).to have_response_time_less_than(2.0)

# Test token usage
expect(result).to have_token_usage_less_than(100)
expect(result).to have_used_tokens(50)
```

### Tool and Handoff Matchers

```ruby
# Test tool usage
expect(result).to have_used_tool("web_search")
expect(result).to have_used_tools(["web_search", "calculator"])

# Test agent handoffs
expect(result).to have_handed_off_to("specialist_agent")
```

### Guardrails Matchers

```ruby
# Test guardrails violations
expect(result).to be_blocked_by_guardrails
expect(result).to have_violation_type(:toxicity)
expect(result).to have_violation_type(:pii)
```

### Memory and Context Matchers

```ruby
# Test conversation context
expect(result).to have_conversation_context
expect(result).to remember_previous_message

# Test memory
expect(result).to remember_information("user's name is John")
```

### Sentiment Matchers

```ruby
# Test sentiment
expect(result).to have_positive_sentiment
expect(result).to have_negative_sentiment
expect(result).to have_neutral_sentiment
```

### Streaming Matchers

```ruby
# Test streaming responses
expect(result).to be_streaming
expect(result).to have_streamed_chunks(5)
```

## Mock Provider

The `MockProvider` class provides a test-friendly LLM provider that returns predefined responses without making actual API calls.

### Basic Usage

```ruby
# Create mock provider
mock_provider = RubyAIAgentsFactory::Testing::MockProvider.new(
  default_response: "I'm a test agent",
  response_delay: 0.1,
  failure_rate: 0.0
)

# Add specific responses
mock_provider.add_response("Hello", "Hi there!")
mock_provider.add_response(/weather/i, "It's sunny today")

# Add multiple responses
mock_provider.add_responses({
  "Hello" => "Hi there!",
  "Goodbye" => "See you later!",
  /help/i => "How can I assist you?"
})
```

### Advanced Response Configuration

```ruby
# Response with metadata
mock_provider.add_response("weather", {
  content: "It's sunny today",
  metadata: { 
    source: "weather_api",
    confidence: 0.9
  }
})

# Pattern matching with dynamic responses
mock_provider.add_response(/calculate (.+)/, -> (match) {
  "The result is #{eval(match[1])}"
})
```

### Statistics and Monitoring

```ruby
# Get provider statistics
stats = mock_provider.stats
puts "Total requests: #{stats[:total_requests]}"
puts "Success rate: #{stats[:success_rate]}"
puts "Average response time: #{stats[:average_response_time]}"

# Get request history
history = mock_provider.request_history
puts "Last request: #{mock_provider.last_request}"

# Reset statistics
mock_provider.reset_stats
```

### Simulating Failures

```ruby
# Create provider with failure rate
mock_provider = RubyAIAgentsFactory::Testing::MockProvider.new(
  failure_rate: 0.1  # 10% failure rate
)

# Test error handling
expect {
  10.times { agent.run("test") }
}.to raise_error(/Simulated API failure/)
```

## Conversation Testing

### Basic Conversation Helper

```ruby
conversation = RubyAIAgentsFactory::Testing::ConversationHelper.new(agent)

# Test multi-turn conversation
conversation.user_says("Hello")
conversation.agent_responds_with(/hi|hello/i)

conversation.user_says("What's the weather?")
conversation.agent_responds_with(/weather|temperature/i)

conversation.user_says("Thank you")
conversation.agent_responds_with(/welcome|pleasure/i)

expect(conversation).to be_successful
```

### Advanced Conversation Testing

```ruby
conversation = RubyAIAgentsFactory::Testing::ConversationHelper.new(agent)

# Test conversation flow
conversation.start_conversation
conversation.expect_greeting
conversation.simulate_user_input("I need help with my account")
conversation.expect_response_containing("account")
conversation.expect_tool_usage("account_lookup")
conversation.end_conversation

# Validate conversation
expect(conversation.messages).to have(4).items
expect(conversation.total_tokens).to be < 1000
expect(conversation.duration).to be < 10.0
```

## Response Validation

### Basic Validation

```ruby
validator = RubyAIAgentsFactory::Testing::ResponseValidator.new

# Add validation rules
validator.must_contain_keywords(["helpful", "assistant"])
validator.must_not_contain_keywords(["sorry", "can't"])
validator.must_be_shorter_than(500)
validator.must_have_positive_sentiment

# Validate response
result = agent.run("How can you help me?")
expect(result).to pass_validation(validator)
```

### Advanced Validation

```ruby
validator = RubyAIAgentsFactory::Testing::ResponseValidator.new(
  strict_mode: true,
  content_filters: [:profanity, :pii]
)

# Custom validation rules
validator.add_custom_rule("must_be_json") do |response|
  JSON.parse(response.content)
  true
rescue JSON::ParserError
  false
end

validator.add_custom_rule("must_include_timestamp") do |response|
  response.content.include?(Time.current.strftime("%Y-%m-%d"))
end

# Validate with custom rules
expect(result).to pass_validation(validator)
```

## Fixtures and Factories

### Pre-built Test Data

```ruby
# Load test fixtures
fixtures = RubyAIAgentsFactory::Testing::Fixtures.load(:conversation_samples)

# Use fixture data
test_messages = fixtures[:messages]
test_responses = fixtures[:responses]

# Create test agents
agent = RubyAIAgentsFactory::Testing::Factories.create_agent(:helpful_assistant)
tool = RubyAIAgentsFactory::Testing::Factories.create_tool(:web_search)
```

### Custom Fixtures

```ruby
# Create custom fixtures
RubyAIAgentsFactory::Testing::Fixtures.define(:my_test_data) do
  {
    messages: [
      { role: "user", content: "Hello" },
      { role: "assistant", content: "Hi there!" }
    ],
    expected_responses: ["greeting", "help_offer"]
  }
end

# Use custom fixtures
test_data = RubyAIAgentsFactory::Testing::Fixtures.load(:my_test_data)
```

## VCR Integration

### Basic VCR Setup

```ruby
# spec/spec_helper.rb
require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "spec/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
end
```

### Record and Replay

```ruby
RSpec.describe "Live Agent API", :vcr do
  it "makes real API calls" do
    # First run records the interaction
    # Subsequent runs replay the recorded response
    agent = RubyAIAgentsFactory::Agent.new(
      name: "LiveAgent",
      model: "gpt-4o"
    )
    
    result = agent.run("What's 2 + 2?")
    expect(result).to be_successful
    expect(result).to have_message_containing("4")
  end
end
```

## Performance Testing

### Response Time Testing

```ruby
RSpec.describe "Performance" do
  it "responds quickly" do
    start_time = Time.current
    result = agent.run("Quick question")
    end_time = Time.current
    
    expect(result).to be_successful
    expect(end_time - start_time).to be < 2.0
  end
  
  it "uses performance matcher" do
    result = agent.run("Test message")
    expect(result).to have_response_time_less_than(1.0)
  end
end
```

### Memory Usage Testing

```ruby
RSpec.describe "Memory Usage" do
  it "doesn't leak memory" do
    initial_memory = memory_usage
    
    100.times do
      agent.run("Test message #{rand}")
    end
    
    final_memory = memory_usage
    expect(final_memory - initial_memory).to be < 50 * 1024 * 1024 # 50MB
  end
end
```

### Benchmark Testing

```ruby
require 'benchmark'

RSpec.describe "Benchmarks" do
  it "benchmarks agent performance" do
    result = Benchmark.measure do
      100.times { agent.run("Test message") }
    end
    
    puts "100 requests took #{result.real} seconds"
    expect(result.real).to be < 10.0
  end
end
```

## Integration Testing

### End-to-End Testing

```ruby
RSpec.describe "E2E Agent Workflow" do
  let(:agent) { create_test_agent_with_tools }
  
  it "completes full workflow" do
    # Start conversation
    result = agent.run("I need help planning a trip")
    expect(result).to be_successful
    expect(result).to have_used_tool("trip_planner")
    
    # Follow up
    result = agent.run("What about the weather?")
    expect(result).to be_successful
    expect(result).to have_used_tool("weather_api")
    
    # Complete workflow
    result = agent.run("Book the trip")
    expect(result).to be_successful
    expect(result).to have_used_tool("booking_api")
  end
end
```

### Multi-Agent Testing

```ruby
RSpec.describe "Multi-Agent System" do
  let(:primary_agent) { create_test_agent(name: "Primary") }
  let(:specialist_agent) { create_test_agent(name: "Specialist") }
  
  it "handles agent handoffs" do
    result = primary_agent.run("I need specialized help")
    expect(result).to have_handed_off_to("Specialist")
    
    # Continue with specialist
    result = specialist_agent.run("Previous context...")
    expect(result).to be_successful
  end
end
```

## Configuration

### Global Configuration

```ruby
RubyAIAgentsFactory::Testing.configure do |config|
  # Mock provider settings
  config.mock_provider.default_response = "Custom test response"
  config.mock_provider.response_delay = 0.05
  config.mock_provider.failure_rate = 0.1

  # Performance settings
  config.performance.max_response_time = 3.0
  config.performance.memory_threshold = 200 * 1024 * 1024
  config.performance.enable_profiling = true

  # Validation settings
  config.validation.strict_mode = true
  config.validation.content_filters = [:profanity, :pii, :toxicity]
  
  # Test helpers
  config.helpers.auto_cleanup = true
  config.helpers.default_timeout = 30
  config.helpers.retry_count = 3
end
```

### Environment Variables

```bash
# Test configuration
export RAAF_TEST_MODE="true"
export RAAF_TEST_TIMEOUT="30"
export RAAF_TEST_RETRY_COUNT="3"

# Mock provider
export RAAF_MOCK_RESPONSE_DELAY="0.1"
export RAAF_MOCK_FAILURE_RATE="0.0"

# Performance testing
export RAAF_PERFORMANCE_ENABLED="true"
export RAAF_MAX_RESPONSE_TIME="5.0"
export RAAF_MEMORY_THRESHOLD="100000000"

# VCR configuration
export VCR_CASSETTE_DIR="spec/vcr_cassettes"
export VCR_RECORD_MODE="once"
```

## Test Helpers

### Common Test Utilities

```ruby
RSpec.describe "With Helpers" do
  include RubyAIAgentsFactory::Testing::Helpers
  
  it "uses test helpers" do
    # Create test agent
    agent = create_test_agent
    
    # Create mock provider
    provider = create_mock_provider
    
    # Create conversation helper
    conversation = create_conversation_helper(agent)
    
    # Create response validator
    validator = create_response_validator
    
    # Test with helpers
    result = agent.run("Test message")
    expect(result).to be_successful
  end
end
```

### Time and Date Helpers

```ruby
require 'timecop'

RSpec.describe "Time-based Testing" do
  it "freezes time for consistent testing" do
    Timecop.freeze(Time.parse("2024-01-01 12:00:00 UTC")) do
      result = agent.run("What time is it?")
      expect(result).to have_message_containing("12:00")
    end
  end
  
  it "travels through time" do
    Timecop.travel(1.day.from_now) do
      result = agent.run("What's today's date?")
      expect(result).to have_message_containing("2024-01-02")
    end
  end
end
```

## Relationship with Other RAAF Gems

### Core Dependencies

RAAF Testing depends on and extends:

- **raaf-core** - Uses core agent classes and interfaces for testing
- **raaf-logging** - Integrates with logging system for test output
- **raaf-configuration** - Uses configuration system for test settings

### Testing Support For

RAAF Testing provides specialized matchers and helpers for:

- **raaf-providers** - Mock providers and provider testing utilities
- **raaf-tools-basic** - Tool execution testing and validation
- **raaf-tools-advanced** - Advanced tool testing scenarios
- **raaf-memory** - Memory system testing and validation
- **raaf-guardrails** - Guardrails testing and violation detection
- **raaf-streaming** - Streaming response testing
- **raaf-dsl** - DSL-based agent testing
- **raaf-tracing** - Trace validation and testing
- **raaf-rails** - Rails integration testing

### Integration Testing

Provides end-to-end testing capabilities for:

- **raaf-compliance** - Compliance workflow testing
- **raaf-security** - Security feature testing
- **raaf-monitoring** - Monitoring system testing
- **raaf-analytics** - Analytics pipeline testing
- **raaf-deployment** - Deployment testing utilities

## Architecture

### Testing Framework Structure

```
RubyAIAgentsFactory::Testing::
├── Matchers/                    # RSpec matchers
│   ├── ResponseMatchers        # Response validation matchers
│   ├── PerformanceMatchers     # Performance testing matchers
│   ├── ToolMatchers           # Tool usage matchers
│   ├── GuardrailsMatchers     # Guardrails testing matchers
│   └── ConversationMatchers   # Conversation testing matchers
├── Helpers/                    # Test helper utilities
│   ├── AgentHelpers           # Agent creation helpers
│   ├── ConversationHelpers    # Conversation testing helpers
│   ├── PerformanceHelpers     # Performance testing helpers
│   └── ValidationHelpers      # Response validation helpers
├── Fixtures/                   # Test data management
│   ├── AgentFixtures          # Pre-built agent configurations
│   ├── ConversationFixtures   # Sample conversations
│   └── ResponseFixtures       # Sample responses
├── Factories/                  # Test object factories
│   ├── AgentFactory           # Agent creation factory
│   ├── ToolFactory            # Tool creation factory
│   └── ProviderFactory        # Provider creation factory
└── Providers/                  # Test providers
    ├── MockProvider           # Mock LLM provider
    ├── RecordingProvider      # Recording provider for VCR
    └── FailureProvider        # Failure simulation provider
```

### Extension Points

The testing gem provides several extension points:

1. **Custom Matchers** - Define domain-specific matchers
2. **Test Helpers** - Create reusable test utilities
3. **Mock Providers** - Implement custom testing providers
4. **Fixtures** - Define custom test data
5. **Validation Rules** - Create custom validation logic

## Best Practices

### Test Organization

```ruby
# Group related tests
RSpec.describe "Agent Behavior" do
  describe "greetings" do
    it "responds to hello" do
      # Test greeting behavior
    end
  end
  
  describe "help requests" do
    it "provides assistance" do
      # Test help behavior
    end
  end
end
```

### Test Data Management

```ruby
# Use factories for consistent test data
RSpec.describe "With Factories" do
  let(:agent) { create_test_agent(:helpful_assistant) }
  let(:conversation) { create_conversation_sample(:customer_support) }
  
  it "uses factory data" do
    # Test with factory-created data
  end
end
```

### Cleanup and Isolation

```ruby
RSpec.describe "Clean Tests" do
  after(:each) do
    # Clean up test resources
    RubyAIAgentsFactory::Testing.cleanup_test_resources
  end
  
  it "maintains test isolation" do
    # Test code here
  end
end
```

## Development

After checking out the repo, run:

```bash
bundle install
bundle exec rspec
```

### Adding New Matchers

1. Create matcher in `lib/raaf/testing/matchers.rb`
2. Add comprehensive tests in `spec/`
3. Update documentation
4. Consider edge cases and error handling

### Contributing New Features

1. Follow the existing architecture patterns
2. Add comprehensive test coverage
3. Update documentation and examples
4. Consider backward compatibility

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/raaf-ai/ruby-ai-agents-factory.

## License

This gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).