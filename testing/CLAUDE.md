# RAAF Testing - Claude Code Guide

This gem provides testing utilities and mocks for RAAF agents, making it easy to test agent behavior without calling real APIs.

## Quick Start

```ruby
require 'raaf-testing'

# Use mock provider in tests
RSpec.describe "Agent behavior" do
  let(:mock_provider) { RAAF::Testing::MockProvider.new }
  let(:agent) { RAAF::Agent.new(name: "TestAgent", instructions: "Be helpful") }
  let(:runner) { RAAF::Runner.new(agent: agent, provider: mock_provider) }

  it "responds correctly" do
    mock_provider.add_response("Hello! How can I help you?")
    
    result = runner.run("Hello")
    expect(result.messages.last[:content]).to eq("Hello! How can I help you?")
  end
end
```

## Core Components

- **MockProvider** - Mock AI provider for testing
- **AgentMatchers** - RSpec matchers for agent behavior
- **TestHelpers** - Utility methods for test setup
- **ResponseRecorder** - Record and replay agent interactions

## Mock Provider

```ruby
# Set up mock responses
mock_provider = RAAF::Testing::MockProvider.new

# Add single response
mock_provider.add_response("I can help with that!")

# Add multiple responses (returned in order)
mock_provider.add_responses([
  "First response",
  "Second response", 
  "Third response"
])

# Add response with tool calls
mock_provider.add_response_with_tools(
  content: "I'll check the weather for you",
  tool_calls: [
    { name: "get_weather", arguments: { location: "New York" } }
  ]
)

# Add response with usage data
mock_provider.add_response(
  "Response text",
  usage: { input_tokens: 10, output_tokens: 20, total_tokens: 30 }
)
```

## RSpec Integration

### Comprehensive RSpec Matchers

RAAF Testing provides extensive RSpec matchers for testing agents, DSL components, and context handling:

```ruby
require 'raaf-testing'

# Automatic setup (recommended)
RAAF::Testing.setup_rspec

RSpec.describe "Weather Agent" do
  let(:mock_provider) { create_mock_provider }
  let(:agent) do
    RAAF::Agent.new(
      name: "WeatherAgent",
      instructions: "Help with weather queries",
      provider: mock_provider
    )
  end
  let(:runner) { RAAF::Runner.new(agent: agent) }

  describe "tool usage" do
    it "uses weather tool for location queries" do
      mock_provider.add_response_with_tools(
        content: "I'll check the weather",
        tool_calls: [{ name: "get_weather", arguments: { location: "Tokyo" } }]
      )

      result = runner.run("What's the weather in Tokyo?")
      
      expect(result).to have_used_tool(:get_weather)
      expect(result).to have_used_tool(:get_weather, location: "Tokyo")
      expect(result).to have_successful_execution
      expect(result).to complete_within(5.0)
    end
  end

  describe "conversation handling" do
    it "maintains conversation flow" do
      mock_provider.add_responses([
        "Hello! I can help with weather.",
        "The weather in Paris is sunny, 22°C"
      ])

      result1 = runner.run("Hello")
      result2 = runner.run("Weather in Paris")

      expect(result1).to have_response_containing("help")
      expect(result2).to have_response_containing(/\d+°C/)
      expect(result2).to have_conversation_turns(2)
    end
  end
end
```

### DSL Component Testing

For DSL-based agents, additional matchers are available:

```ruby
require 'raaf-testing'
require 'raaf-dsl'

RSpec.describe MyDSLAgent do
  # Test agent configuration
  describe "configuration" do
    it "has valid agent configuration" do
      expect(MyDSLAgent).to have_valid_agent_config
      expect(MyDSLAgent).to require_context_keys(:product, :company)
      expect(MyDSLAgent).to have_tools(:web_search, :calculator)
    end
  end

  # Test agent instances
  describe "execution" do
    let(:context) { mock_context_variables(product: "SaaS", company: "Acme") }
    let(:agent) { MyDSLAgent.new(context: context) }

    it "uses context correctly" do
      expect(agent).to have_context_values(product: "SaaS", company: "Acme")
      
      result = agent.run("Analyze market fit")
      expect(result).to have_successful_execution
      expect(result).to have_output_structure(
        success: :boolean,
        data: :hash,
        analysis: :array
      )
    end
  end
end
```

### Context Variables Testing

Test the immutable ContextVariables system:

```ruby
RSpec.describe "ContextVariables" do
  let(:context) { RAAF::DSL::ContextVariables.new }

  it "follows immutable pattern" do
    expect(context).to be_immutable
    expect(context).to have_context_size(0)
    
    # Test immutability preservation
    expect {
      new_context = context.set(:key, "value")
      expect(new_context).to have_context_size(1)
    }.to preserve_original_context(context)
    
    expect(context).to have_context_size(0) # Original unchanged
  end

  it "handles nested data safely" do
    complex_data = {
      user: { name: "John", preferences: { theme: "dark" } },
      features: ["search", "analytics"]
    }
    
    new_context = context.set(:complex_data, complex_data)
    
    expect(new_context).to handle_nested_data_safely
    expect(new_context).to be_serializable
    expect(new_context).to have_context_keys(:complex_data)
    expect(new_context).to have_context_values(complex_data: complex_data)
  end
end
```

### Multi-Agent Testing

Test agent handoffs and multi-agent workflows:

```ruby
RSpec.describe "Multi-agent workflow" do
  let(:research_agent) { create_test_agent(name: "Researcher") }
  let(:writer_agent) { create_test_agent(name: "Writer") }
  
  before do
    research_agent.add_handoff(writer_agent)
  end
  
  it "performs agent handoffs" do
    mock_provider.add_response_with_tools(
      content: "Research complete, transferring to Writer",
      tool_calls: [{ name: "transfer_to_Writer", arguments: {} }]
    )
    mock_provider.add_response("Here's the final article.")

    runner = RAAF::Runner.new(
      agent: research_agent,
      agents: [research_agent, writer_agent],
      provider: mock_provider
    )

    result = runner.run("Research and write about Ruby")
    
    expect(result).to have_agent_handoff(from: "Researcher", to: "Writer")
    expect(result).to have_final_agent("Writer")
    expect(result).to have_conversation_turns(2)
  end
end
```

## Test Helpers

```ruby
include RAAF::Testing::TestHelpers

# Create test agent with mock provider
agent = create_test_agent(
  name: "TestAgent",
  instructions: "Test instructions",
  tools: [:calculator, :weather]
)

# Create mock conversation
conversation = mock_conversation([
  { role: :user, content: "Hello" },
  { role: :assistant, content: "Hi there!" },
  { role: :user, content: "What's 2+2?" },
  { role: :assistant, content: "4" }
])

# Verify agent behavior
assert_agent_follows_instructions(agent, conversation)
assert_tool_usage_appropriate(agent, conversation)
```

## Response Recording

```ruby
# Record real agent interactions for replay in tests
recorder = RAAF::Testing::ResponseRecorder.new("weather_agent_responses.yml")

# Record during development/staging
agent = RAAF::Agent.new(name: "WeatherAgent", instructions: "Help with weather")
runner = RAAF::Runner.new(agent: agent, provider: recorder.recording_provider)

result = runner.run("What's the weather in London?")
recorder.save_interaction(result)

# Replay in tests
recorded_provider = recorder.playback_provider
test_runner = RAAF::Runner.new(agent: agent, provider: recorded_provider)

# Will return the recorded response
test_result = test_runner.run("What's the weather in London?")
```

## Advanced Testing Patterns

### Tool Testing
```ruby
RSpec.describe "Calculator Tool" do
  include RAAF::Testing::Matchers

  let(:calculator_tool) do
    RAAF::FunctionTool.new(
      name: "calculate",
      description: "Perform calculations"
    ) { |expression| eval(expression) }
  end

  let(:agent) do
    agent = create_test_agent
    agent.add_tool(calculator_tool)
    agent
  end

  it "performs calculations correctly" do
    mock_provider.add_response_with_tools(
      content: "I'll calculate that",
      tool_calls: [{ name: "calculate", arguments: { expression: "2 + 2" } }]
    )

    result = runner.run("What's 2 + 2?")
    
    expect(result).to have_used_tool(:calculate)
    expect(result.tool_results).to include(4)
  end
end
```

### Multi-Agent Testing
```ruby
RSpec.describe "Multi-agent workflow" do
  let(:research_agent) { create_test_agent(name: "Researcher") }
  let(:writer_agent) { create_test_agent(name: "Writer") }
  
  it "hands off between agents" do
    mock_provider.add_responses([
      handoff_response(to: "Writer", context: "Research complete"),
      "Here's the final article based on the research."
    ])

    runner = RAAF::Runner.new(
      agent: research_agent,
      agents: [research_agent, writer_agent],
      provider: mock_provider
    )

    result = runner.run("Research and write about Ruby")
    
    expect(result).to have_agent_handoff(from: "Researcher", to: "Writer")
    expect(result).to have_final_agent("Writer")
  end
end
```

### Error Scenario Testing
```ruby
RSpec.describe "Error handling" do
  it "handles API failures gracefully" do
    mock_provider.add_error(RAAF::Errors::RateLimitError.new("Rate limited"))
    
    expect {
      runner.run("Hello")
    }.to raise_error(RAAF::Errors::RateLimitError)
  end

  it "retries on transient errors" do
    mock_provider.add_error(Net::TimeoutError.new("Timeout"))
    mock_provider.add_response("Successful response after retry")
    
    retryable_provider = RAAF::Models::RetryableProvider.new(mock_provider)
    runner = RAAF::Runner.new(agent: agent, provider: retryable_provider)
    
    result = runner.run("Hello")
    expect(result.messages.last[:content]).to eq("Successful response after retry")
  end
end
```

## Performance Testing

```ruby
# Load testing with mock responses
RSpec.describe "Performance" do
  it "handles high throughput" do
    mock_provider.add_responses(["Response"] * 1000)
    
    start_time = Time.now
    
    1000.times do |i|
      runner.run("Message #{i}")
    end
    
    duration = Time.now - start_time
    expect(duration).to be < 10.seconds
  end

  it "manages memory efficiently" do
    initial_memory = memory_usage
    
    100.times do
      mock_provider.add_response("Test response")
      runner.run("Test message")
    end
    
    final_memory = memory_usage
    memory_increase = final_memory - initial_memory
    
    expect(memory_increase).to be < 50.megabytes
  end
end
```

## Configuration

```ruby
# Configure testing behavior
RAAF::Testing.configure do |config|
  config.default_response_delay = 0.1  # seconds
  config.enable_request_logging = true
  config.strict_tool_validation = true
  config.mock_provider_class = RAAF::Testing::MockProvider
end
```