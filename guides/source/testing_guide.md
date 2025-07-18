**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Testing Guide
==================

This guide covers comprehensive testing strategies for Ruby AI Agents Factory (RAAF) applications. Testing AI agents requires specialized approaches to handle non-deterministic behavior while ensuring reliable functionality.

After reading this guide, you will know:

* How to test AI agents with mock providers and deterministic responses
* Unit testing strategies for tools, agents, and workflows
* Integration testing for multi-agent systems
* Performance testing and load testing approaches
* Testing in production environments safely

--------------------------------------------------------------------------------

Introduction
------------

### The AI Testing Paradigm Shift

Testing AI agents requires a fundamental shift from traditional software testing approaches. Unlike deterministic systems where identical inputs produce identical outputs, AI systems introduce probabilistic behavior that challenges conventional testing methodologies.

### Core Testing Challenges

**Non-Deterministic Behavior**: AI models can generate different outputs for identical inputs, making traditional assertion-based testing insufficient. This variability requires testing strategies that focus on behavioral patterns rather than exact outputs.

**External API Dependencies**: AI agents depend on external provider APIs for core functionality, introducing network dependencies, rate limiting, and service availability concerns into the testing environment.

**Workflow Complexity**: Multi-agent systems with handoffs, state management, and coordination introduce complex interaction patterns that require sophisticated testing approaches.

**Economic Constraints**: API calls incur costs during testing, making traditional approaches that rely on extensive API interaction economically impractical for comprehensive test suites.

**Temporal Variability**: Network latency, model response times, and provider performance introduce timing variations that affect test reliability and execution duration.

### Economic Testing Constraints

AI testing introduces significant economic constraints that don't exist in traditional software testing. API-based AI services charge per token or request, making comprehensive testing expensive and economically impractical with traditional approaches.

**Cost Escalation Patterns**:

**CI/CD Integration**: Automated test suites that make real API calls during continuous integration can accumulate substantial costs across multiple builds and environments.

**Load Testing**: Performance testing with real AI providers can generate massive API usage costs due to the volume of requests required for meaningful load simulation.

**Integration Testing**: Comprehensive integration tests that generate large content volumes or complex workflows can consume significant token allowances.

**Parallel Execution**: Multiple test environments and parallel test execution multiply API usage costs exponentially.

### Testing Strategy Implications

These economic constraints necessitate testing strategies that minimize API usage while maintaining test coverage and reliability. This requires sophisticated mocking, recording, and selective integration testing approaches.

### Testing Paradigm Differences

Traditional software testing relies on deterministic behavior where identical inputs produce identical outputs. AI testing requires different approaches that account for probabilistic behavior:

**Deterministic Testing Pattern**:
```ruby
expect(add(2, 2)).to eq(4)  # Always passes
```

**Probabilistic Testing Pattern**:
```ruby
# AI responses vary: "4", "Four", "2+2 equals 4"
expect(agent.run("What's 2+2?")).to match_semantic_intent("four")
```

### Cost-Performance Trade-offs

AI testing faces unique cost-performance constraints that require strategic trade-offs:

**Cost Accumulation**: Large test suites making real API calls can generate substantial costs (1000 tests × 3 calls × $0.01 = $30 per run, scaling to $3,000/day with frequent execution).

**Execution Duration**: API latency significantly extends test execution times (1000 tests requiring 2-5 seconds each = 2-5 hours total execution time).

**Reliability Constraints**: Network dependencies introduce test flakiness and maintenance overhead that doesn't exist in isolated unit tests.

### Strategic Testing Approach

Effective AI testing requires strategic layering that balances coverage, cost, and reliability through selective use of mocking, recording, and real API integration.

### AI Testing Philosophy

Effective AI testing focuses on system behavior and integration patterns rather than AI output validation. The core principle: test your system's interaction with AI services, not the AI services themselves.

### Testing Strategy Principles

**Mock-First Approach**: Default to mocked AI responses for unit tests, reserving real API calls for specific integration scenarios. This approach provides fast, reliable, and cost-effective testing.

**Record-Replay Pattern**: Capture real AI responses during development or specific test runs, then replay them in subsequent tests. This provides realistic response patterns without ongoing API costs.

**Behavioral Testing**: Focus on testing whether the system calls the correct tools, handles responses appropriately, and follows expected workflows rather than validating specific AI-generated content.

**Concern Separation**: Test application logic thoroughly with mocked AI responses, then test AI integration lightly with focused scenarios that validate provider interaction patterns.

### Testing Infrastructure

RAAF provides comprehensive testing utilities designed specifically for AI system testing challenges:

**Mock Providers**: Deterministic response generation for reliable unit testing
**Response Recording**: Capture and replay mechanisms for realistic testing scenarios
**Behavioral Matchers**: Specialized assertion patterns for AI response validation
**Performance Tools**: Load and stress testing capabilities for AI system scalability
**Production Testing**: Safe live environment testing utilities for validation without disruption

Testing Fundamentals
--------------------

### AI Testing Architecture

Effective AI testing requires a structured approach with three distinct layers:

1. **Unit Tests (95% of tests)**
   - Mock everything
   - Test your logic, not the AI
   - Run in milliseconds
   - Cost: $0

2. **Integration Tests (4% of tests)**
   - Use recorded responses
   - Test interaction patterns
   - Run in seconds
   - Cost: $0 (after initial recording)

3. **Live Tests (1% of tests)**
   - Real API calls
   - Test current model behavior
   - Run nightly or pre-release
   - Cost: Controlled and budgeted

### Basic Test Setup

```ruby
# spec/spec_helper.rb
require 'raaf-testing'

RSpec.configure do |config|
  # Include RAAF testing utilities
  config.include RAAF::Testing::Matchers
  config.include RAAF::Testing::Helpers
  
  # Setup mock provider for all tests
  config.before(:each) do
    @original_provider = RAAF.default_provider
    RAAF.default_provider = RAAF::Testing::MockProvider.new
  end
  
  config.after(:each) do
    RAAF.default_provider = @original_provider
  end
end
```

This test configuration establishes a foundation for reliable AI agent testing. The `before(:each)` hook replaces the real AI provider with a mock for every test, ensuring that your tests run consistently without making actual API calls. This approach eliminates the randomness inherent in AI responses and removes the cost of running your test suite.

The inclusion of RAAF testing utilities provides specialized matchers and helpers designed for AI agent testing scenarios. These utilities understand the unique challenges of testing AI systems, such as checking for tool usage, verifying conversation flows, and asserting on response patterns rather than exact content matches.

### Simple Agent Test

```ruby
RSpec.describe 'Basic Agent' do
  let(:agent) do
    RAAF::Agent.new(
      name: "TestAgent",
      instructions: "You are a helpful test assistant",
      model: "gpt-4o"
    )
  end
  
  let(:mock_provider) { RAAF::Testing::MockProvider.new }
  let(:runner) { RAAF::Runner.new(agent: agent, provider: mock_provider) }
  
  it 'responds to simple queries' do
    mock_provider.add_response("Hello! How can I help you today?")
    
    result = runner.run("Hello")
    
    expect(result).to be_successful
    expect(result.messages.last[:content]).to eq("Hello! How can I help you today?")
  end
  
  it 'handles multiple turns' do
    mock_provider.add_responses([
      "Hi there!",
      "I'm doing well, thank you for asking!"
    ])
    
    result1 = runner.run("Hello")
    result2 = runner.run("How are you?")
    
    expect(result1.messages.last[:content]).to eq("Hi there!")
    expect(result2.messages.last[:content]).to eq("I'm doing well, thank you for asking!")
  end
end
```

This basic test demonstrates the fundamental pattern for testing AI agents. The `let` blocks establish test fixtures that create a consistent testing environment. The mock provider replaces the real AI service with predictable responses, allowing you to test your agent's behavior without depending on external services.

The first test shows how to verify simple request-response patterns. By pre-loading the mock provider with a specific response, you can test that your agent correctly processes input and returns the expected output. The second test demonstrates conversation state management by using multiple responses in sequence. This pattern is essential for testing conversational agents that need to maintain context across multiple turns.

Notice that the tests focus on the behavior and flow rather than the exact content. This approach recognizes that AI responses may vary while still ensuring that the core functionality works correctly.

Mock Providers
--------------

### The Evolution of Our Mocking Strategy

**Version 1: String Matching Hell**

```ruby
# DON'T DO THIS
if response.include?("Hello")
  "Hi there!"
elsif response.include?("weather")
  "It's sunny"
else
  "I don't understand"
end
```

This worked for 10 tests. At 100 tests, it was unmaintainable.

**Version 2: Random Responses**

```ruby
# ALSO BAD
["Response 1", "Response 2", "Response 3"].sample
```

This approach creates unreliable tests that reduce developer confidence in the test suite.

**Version 3: Structured Mocking (What Actually Works)**

The key insight: Mock the provider behavior, not the AI behavior.

### Basic Mock Provider

```ruby
# Simple mock with predefined responses
mock_provider = RAAF::Testing::MockProvider.new

# Add single response
mock_provider.add_response("Test response")

# Add multiple responses (for multi-turn conversations)
mock_provider.add_responses([
  "First response",
  "Second response", 
  "Third response"
])

# Add conditional responses
mock_provider.add_conditional_response(
  condition: ->(messages) { messages.last[:content].include?("weather") },
  response: "The weather is sunny today!"
)
```

### Advanced Mock Configuration

```ruby
advanced_mock = RAAF::Testing::MockProvider.new(
  # Response timing simulation
  response_delay: 100..500,  # Random delay between 100-500ms
  
  # Error simulation
  error_rate: 0.05,          # 5% of requests fail
  error_types: [
    { type: RAAF::Errors::RateLimitError, probability: 0.7 },
    { type: RAAF::Errors::APIError, probability: 0.3 }
  ],
  
  # Token usage simulation
  simulate_tokens: true,
  tokens_per_word: 1.3,
  
  # Cost tracking
  track_costs: true,
  cost_per_token: 0.00005
)

# Verify API call patterns
expect(advanced_mock.call_count).to eq(3)
expect(advanced_mock.total_tokens_used).to be > 0
expect(advanced_mock.total_cost).to be_within(0.01).of(0.05)
```

This advanced mock configuration simulates realistic production conditions in your tests. The response delay range mimics network latency and API processing time, helping you test how your application handles variable response times. This is crucial for ensuring that your user interface remains responsive and that timeout mechanisms work correctly.

The error simulation allows you to test your application's resilience to various failure modes. Rate limit errors are common in production, so testing how your application handles these scenarios is essential. The probability-based error generation helps you test different failure patterns without having to manually trigger each error type.

Token usage simulation enables you to test cost management and optimization features. By tracking tokens and costs, you can verify that your application stays within budget constraints and that cost-optimization features work as expected. This is particularly important for production systems where AI costs can quickly escalate.

### Contextual Mock Responses

```ruby
contextual_mock = RAAF::Testing::MockProvider.new

# Responses based on conversation context
contextual_mock.add_contextual_response do |messages, context|
  last_message = messages.last[:content]
  
  case last_message
  when /weather/i
    "The weather is nice today!"
  when /time/i
    "It's #{Time.now.strftime('%I:%M %p')}"
  when /help/i
    "I'm here to help! What do you need assistance with?"
  else
    "I understand you said: #{last_message}"
  end
end

# Stateful responses that remember context
contextual_mock.add_stateful_response do |messages, context, state|
  if state[:user_name].nil? && last_message.include?("my name is")
    name = last_message.match(/my name is (\w+)/i)&.captures&.first
    state[:user_name] = name
    "Nice to meet you, #{name}!"
  elsif state[:user_name]
    "How can I help you today, #{state[:user_name]}?"
  else
    "Hello! What's your name?"
  end
end
```

Tool Testing
------------

### Tool Input Validation

Tools require careful input validation to prevent type-related errors:

```ruby
def process_payment(amount:, currency: "USD")
  # Convert to cents
  amount_cents = amount * 100
  charge_customer(amount_cents, currency)
end
```

This code has a potential issue: when `amount` is passed as a string (e.g., `"99.99"`), Ruby's string multiplication creates a repeated string rather than performing numeric conversion. This can lead to unexpected behavior in downstream systems.

Proper input validation prevents these type-related errors.

### Unit Testing Tools

```ruby
RSpec.describe 'Weather Tool' do
  def get_weather(location:)
    case location.downcase
    when 'san francisco'
      { temperature: 68, conditions: 'foggy', humidity: 85 }
    when 'new york'
      { temperature: 45, conditions: 'clear', humidity: 60 }
    else
      { error: "Weather data not available for #{location}" }
    end
  end
  
  it 'returns weather for known locations' do
    result = get_weather(location: 'San Francisco')
    
    expect(result[:temperature]).to eq(68)
    expect(result[:conditions]).to eq('foggy')
  end
  
  it 'handles unknown locations gracefully' do
    result = get_weather(location: 'Unknown City')
    
    expect(result[:error]).to include('not available')
  end
  
  it 'validates required parameters' do
    expect { get_weather }.to raise_error(ArgumentError)
  end
end
```

This tool testing approach isolates the tool logic from the AI agent, allowing you to test the tool's behavior independently. The weather tool example demonstrates how to test both successful scenarios and error conditions. Testing tools in isolation is crucial because tools often contain complex business logic that shouldn't be obscured by AI response variability.

The test cases cover the happy path (known locations return expected data), error handling (unknown locations return error messages), and parameter validation (missing required parameters raise errors). This comprehensive approach ensures that your tools behave correctly before they're integrated with AI agents, making debugging much easier when issues arise in the full system.

Notice how the tool uses a deterministic approach—the same input always produces the same output. This makes tools much easier to test than AI responses, which is why separating tool logic from AI logic is so important for maintainable test suites.

### Tool Integration Testing

```ruby
RSpec.describe 'Agent with Weather Tool' do
  let(:agent) do
    agent = RAAF::Agent.new(
      name: "WeatherBot",
      instructions: "Help users get weather information",
      model: "gpt-4o"
    )
    agent.add_tool(method(:get_weather))
    agent
  end
  
  let(:mock_provider) { RAAF::Testing::MockProvider.new }
  let(:runner) { RAAF::Runner.new(agent: agent, provider: mock_provider) }
  
  it 'uses tools to answer questions' do
    # Mock the agent's response that includes tool usage
    mock_provider.add_tool_response(
      tool_calls: [
        { tool_name: 'get_weather', parameters: { location: 'San Francisco' } }
      ],
      final_response: "The weather in San Francisco is foggy with a temperature of 68°F."
    )
    
    result = runner.run("What's the weather in San Francisco?")
    
    expect(result).to be_successful
    expect(result).to have_used_tool('get_weather')
    expect(result.tool_calls).to include(
      hash_including(
        tool_name: 'get_weather',
        parameters: hash_including(location: 'San Francisco')
      )
    )
  end
  
  it 'handles tool errors gracefully' do
    mock_provider.add_tool_response(
      tool_calls: [
        { tool_name: 'get_weather', parameters: { location: 'Unknown City' } }
      ],
      final_response: "I'm sorry, I don't have weather data for that location."
    )
    
    result = runner.run("What's the weather in Unknown City?")
    
    expect(result).to be_successful
    expect(result.messages.last[:content]).to include("don't have weather data")
  end
end
```

This integration testing approach verifies that agents can properly invoke tools and incorporate tool results into their responses. The `add_tool_response` method allows you to simulate the AI model's decision to use a tool, along with the parameters it would pass and the final response after processing the tool's results.

The key insight here is that you're testing the integration between the AI agent and your tools, not the AI's reasoning ability. The mock provider simulates the AI's tool usage decisions, allowing you to verify that your system correctly handles tool invocation, parameter passing, and result processing.

The error handling test is particularly important because it demonstrates how your agent responds when tools fail or return error conditions. This ensures that your system degrades gracefully when external dependencies are unavailable or when users provide invalid inputs.

### Mock External Dependencies

```ruby
RSpec.describe 'Database Tool' do
  let(:mock_database) { instance_double('Database') }
  
  let(:db_tool) do
    DatabaseTool.new(connection: mock_database)
  end
  
  before do
    allow(mock_database).to receive(:execute).and_return([
      { id: 1, name: 'John Doe', email: 'john@example.com' },
      { id: 2, name: 'Jane Smith', email: 'jane@example.com' }
    ])
  end
  
  it 'queries database with correct SQL' do
    result = db_tool.query_customers(status: 'active')
    
    expect(mock_database).to have_received(:execute).with(
      "SELECT * FROM customers WHERE status = ?",
      ['active']
    )
    expect(result).to have(2).customers
  end
  
  it 'handles database errors' do
    allow(mock_database).to receive(:execute).and_raise(StandardError.new("Connection failed"))
    
    result = db_tool.query_customers(status: 'active')
    
    expect(result[:error]).to include("Connection failed")
  end
end
```

Multi-Agent Testing
-------------------

### Agent Handoff Testing

```ruby
RSpec.describe 'Multi-Agent Workflow' do
  let(:research_agent) do
    RAAF::Agent.new(
      name: "Researcher",
      instructions: "Research topics and hand off to Writer",
      model: "gpt-4o"
    )
  end
  
  let(:writer_agent) do
    RAAF::Agent.new(
      name: "Writer", 
      instructions: "Write content based on research",
      model: "gpt-4o"
    )
  end
  
  let(:mock_provider) { RAAF::Testing::MockProvider.new }
  
  before do
    research_agent.add_handoff(writer_agent)
  end
  
  it 'executes handoff between agents' do
    # Mock research agent response with handoff
    mock_provider.add_agent_response(
      agent_name: "Researcher",
      response: "I've completed my research on renewable energy.",
      handoff_to: "Writer",
      handoff_context: {
        research_findings: "Solar and wind power are the most viable options",
        sources: ["energy.gov", "iea.org"]
      }
    )
    
    # Mock writer agent response
    mock_provider.add_agent_response(
      agent_name: "Writer",
      response: "Based on the research, here's an article about renewable energy..."
    )
    
    runner = RAAF::Runner.new(
      agent: research_agent,
      agents: [research_agent, writer_agent],
      provider: mock_provider
    )
    
    result = runner.run("Write an article about renewable energy")
    
    expect(result).to be_successful
    expect(result.agent_sequence).to eq(["Researcher", "Writer"])
    expect(result.handoffs).to have(1).handoff
    expect(result.final_agent).to eq("Writer")
  end
  
  it 'handles handoff failures' do
    # Mock research agent response with invalid handoff
    mock_provider.add_agent_response(
      agent_name: "Researcher",
      response: "Research complete",
      handoff_to: "NonexistentAgent"
    )
    
    runner = RAAF::Runner.new(
      agent: research_agent,
      agents: [research_agent, writer_agent],
      provider: mock_provider
    )
    
    result = runner.run("Write an article")
    
    expect(result).to be_failed
    expect(result.error_type).to eq(:handoff_error)
    expect(result.error_message).to include("NonexistentAgent not found")
  end
end
```

This multi-agent testing approach verifies the complex orchestration between different agents in a workflow. The `add_agent_response` method allows you to simulate specific agent behaviors and handoff decisions, enabling you to test the coordination logic without relying on actual AI reasoning.

The handoff context is particularly important to test because it represents the information transfer between agents. In a real workflow, the research agent would gather information that the writer agent needs to create content. By testing this context passing, you ensure that information flows correctly through your multi-agent pipeline.

The error handling test demonstrates how your system responds to workflow failures. Multi-agent systems are inherently more complex than single-agent systems, so testing various failure modes is crucial. This includes scenarios where agents try to hand off to non-existent agents, where handoffs fail due to network issues, or where agents get stuck in loops.

### Context Sharing Testing

```ruby
RSpec.describe 'Shared Context in Multi-Agent Systems' do
  let(:shared_context) do
    {
      project_id: 'proj_123',
      user_preferences: { format: 'markdown', tone: 'professional' },
      deadline: '2024-02-01'
    }
  end
  
  it 'shares context between agents' do
    mock_provider = RAAF::Testing::MockProvider.new
    
    # Mock responses that reference shared context
    mock_provider.add_contextual_response do |messages, context|
      if context[:project_id] == 'proj_123'
        "Working on project #{context[:project_id]} with #{context[:user_preferences][:tone]} tone"
      else
        "No project context available"
      end
    end
    
    runner = RAAF::Runner.new(
      agent: research_agent,
      agents: [research_agent, writer_agent],
      provider: mock_provider,
      context_variables: shared_context
    )
    
    result = runner.run("Start working on the project")
    
    expect(result.messages.last[:content]).to include('proj_123')
    expect(result.messages.last[:content]).to include('professional')
  end
end
```

Response Recording and Playback
-------------------------------

### Recording Real Responses

```ruby
# Record responses from real AI providers for playback in tests
recorder = RAAF::Testing::ResponseRecorder.new(
  output_file: 'spec/fixtures/agent_responses.json',
  provider: RAAF::Models::OpenAIProvider.new
)

recording_runner = RAAF::Runner.new(
  agent: agent,
  provider: recorder
)

# Record actual interactions
result = recording_runner.run("What is machine learning?")
# Response saved to fixtures file

recorder.finalize  # Writes all recorded responses
```

### Playback in Tests

```ruby
# Use recorded responses in tests
playback_provider = RAAF::Testing::PlaybackProvider.new(
  fixture_file: 'spec/fixtures/agent_responses.json'
)

RSpec.describe 'Agent with Real Responses' do
  let(:runner) { RAAF::Runner.new(agent: agent, provider: playback_provider) }
  
  it 'uses recorded real responses' do
    # This will use the actual recorded response
    result = runner.run("What is machine learning?")
    
    expect(result).to be_successful
    expect(result.messages.last[:content]).to include('machine learning')
    # Response content will be exactly what was recorded from real API
  end
end
```

### Selective Recording

```ruby
# Record only specific scenarios
selective_recorder = RAAF::Testing::SelectiveRecorder.new(
  output_file: 'spec/fixtures/selective_responses.json',
  provider: RAAF::Models::OpenAIProvider.new,
  
  # Only record responses matching criteria
  record_when: ->(messages, context) {
    # Record complex queries only
    messages.last[:content].length > 100 ||
    context[:tools_used]&.any?
  }
)
```

Custom RSpec Matchers
--------------------

### Built-in Matchers

```ruby
RSpec.describe 'Agent Behavior' do
  it 'uses custom matchers' do
    result = runner.run("Hello")
    
    # Success/failure matchers
    expect(result).to be_successful
    expect(result).not_to be_failed
    
    # Content matchers
    expect(result).to have_response_containing("hello")
    expect(result).to have_response_matching(/greeting/i)
    
    # Tool usage matchers
    expect(result).to have_used_tool('get_weather')
    expect(result).to have_used_tools(['get_weather', 'get_time'])
    expect(result).not_to have_used_any_tools
    
    # Performance matchers
    expect(result).to have_responded_within(5.seconds)
    expect(result).to have_used_tokens_less_than(1000)
    
    # Agent workflow matchers
    expect(result).to have_agent_sequence(['Researcher', 'Writer'])
    expect(result).to have_handoff_to('Writer')
    expect(result).to have_context_variable(:project_id, 'proj_123')
  end
end
```

### Custom Matchers

```ruby
# spec/support/custom_matchers.rb
RSpec::Matchers.define :have_sentiment do |expected_sentiment|
  match do |result|
    content = result.messages.last[:content]
    detected_sentiment = sentiment_analyzer.analyze(content)
    detected_sentiment == expected_sentiment
  end
  
  failure_message do |result|
    content = result.messages.last[:content]
    detected_sentiment = sentiment_analyzer.analyze(content)
    "Expected sentiment #{expected_sentiment}, but got #{detected_sentiment} for content: '#{content}'"
  end
end

RSpec::Matchers.define :have_used_tool_with_params do |tool_name, expected_params|
  match do |result|
    tool_calls = result.tool_calls
    matching_call = tool_calls.find { |call| call[:tool_name] == tool_name }
    
    return false unless matching_call
    
    expected_params.all? do |key, value|
      matching_call[:parameters][key] == value
    end
  end
end

# Usage
expect(result).to have_sentiment(:positive)
expect(result).to have_used_tool_with_params('get_weather', location: 'San Francisco')
```

Performance Testing
-------------------

### Performance Testing Requirements

AI systems have unique performance characteristics that require specialized testing approaches. Unlike traditional web applications, AI systems face token rate limits, memory constraints from context management, and variable response times.

### Performance Testing Considerations

1. **API Rate Limits**: AI providers enforce rate limits that can be reached with moderate concurrent usage
2. **Memory Usage**: Conversation context storage can consume significant memory at scale
3. **Tool Execution**: Sequential tool calls create bottlenecks in multi-step workflows
4. **Cascading Effects**: Performance degradation in one component can affect the entire system

Performance testing for AI systems is essential for production readiness.

### Load Testing

```ruby
RSpec.describe 'Agent Performance' do
  let(:load_tester) { RAAF::Testing::LoadTester.new }
  
  it 'handles concurrent requests' do
    performance_results = load_tester.run_load_test(
      agent: agent,
      concurrent_users: 10,
      requests_per_user: 5,
      ramp_up_time: 30.seconds,
      test_duration: 2.minutes
    ) do |user_id, request_number|
      "Test message #{request_number} from user #{user_id}"
    end
    
    expect(performance_results.success_rate).to be >= 0.95  # 95% success rate
    expect(performance_results.average_response_time).to be < 5.seconds
    expect(performance_results.p99_response_time).to be < 15.seconds
    expect(performance_results.errors).to be_empty
  end
  
  it 'maintains performance under stress' do
    stress_results = load_tester.run_stress_test(
      agent: agent,
      max_concurrent_users: 50,
      ramp_up_strategy: :exponential,
      duration: 5.minutes,
      success_criteria: {
        min_success_rate: 0.90,
        max_avg_response_time: 10.seconds,
        max_error_rate: 0.05
      }
    )
    
    expect(stress_results).to meet_success_criteria
    expect(stress_results.breaking_point).to be > 30  # Can handle >30 concurrent users
  end
end
```

This performance testing approach validates that your AI agent system can handle production-level loads. The load test simulates realistic user behavior with multiple concurrent users making multiple requests over time. The ramp-up period prevents overwhelming the system immediately, which mirrors how tRAAFic typically increases in production.

The success criteria focus on key performance indicators that matter for user experience. A 95% success rate ensures reliability, while the response time thresholds guarantee acceptable user experience. The P99 response time is particularly important because it represents the worst-case scenario that a small percentage of users will experience.

The stress test pushes your system beyond normal operating conditions to find its breaking point. This is crucial for capacity planning and understanding how your system degrades under extreme load. The exponential ramp-up strategy gradually increases pressure, helping you identify the exact point where performance degrades unacceptably.

### Memory and Resource Testing

```ruby
RSpec.describe 'Resource Usage' do
  it 'does not leak memory' do
    memory_tracker = RAAF::Testing::MemoryTracker.new
    
    memory_tracker.track do
      100.times do |i|
        runner.run("Test message #{i}")
      end
    end
    
    expect(memory_tracker.memory_growth).to be < 10.megabytes
    expect(memory_tracker.memory_leaks_detected?).to be false
  end
  
  it 'releases resources properly' do
    resource_tracker = RAAF::Testing::ResourceTracker.new
    
    resource_tracker.track do
      runner.run("Test message")
    end
    
    expect(resource_tracker.open_connections).to eq(0)
    expect(resource_tracker.open_files).to eq(0)
    expect(resource_tracker.active_threads).to be <= 5
  end
end
```

Production Testing
------------------

### Canary Testing

```ruby
class CanaryTester
  def initialize(canary_agent, production_agent)
    @canary_agent = canary_agent
    @production_agent = production_agent
  end
  
  def run_canary_test(test_cases, canary_percentage: 10)
    results = {
      canary: [],
      production: [],
      differences: []
    }
    
    test_cases.each do |test_case|
      if should_route_to_canary?(canary_percentage)
        result = run_test_case(@canary_agent, test_case)
        results[:canary] << result
      else
        result = run_test_case(@production_agent, test_case)
        results[:production] << result
      end
    end
    
    # Compare results and detect anomalies
    compare_results(results)
  end
  
  private
  
  def should_route_to_canary?(percentage)
    rand(100) < percentage
  end
  
  def compare_results(results)
    # Compare success rates, response times, error patterns
    canary_success_rate = calculate_success_rate(results[:canary])
    production_success_rate = calculate_success_rate(results[:production])
    
    if (canary_success_rate - production_success_rate).abs > 0.05
      alert_significant_difference(canary_success_rate, production_success_rate)
    end
  end
end
```

### A/B Testing

```ruby
class ABTester
  def initialize(agent_a, agent_b)
    @agent_a = agent_a
    @agent_b = agent_b
  end
  
  def run_ab_test(test_scenarios, split: 50)
    results_a = []
    results_b = []
    
    test_scenarios.each do |scenario|
      if rand(100) < split
        result = run_scenario(@agent_a, scenario)
        results_a << result
      else
        result = run_scenario(@agent_b, scenario)
        results_b << result
      end
    end
    
    analyze_ab_results(results_a, results_b)
  end
  
  private
  
  def analyze_ab_results(results_a, results_b)
    {
      agent_a: {
        success_rate: calculate_success_rate(results_a),
        avg_response_time: calculate_avg_response_time(results_a),
        user_satisfaction: calculate_satisfaction(results_a)
      },
      agent_b: {
        success_rate: calculate_success_rate(results_b),
        avg_response_time: calculate_avg_response_time(results_b),
        user_satisfaction: calculate_satisfaction(results_b)
      },
      statistical_significance: calculate_significance(results_a, results_b)
    }
  end
end
```

### Shadow Testing

```ruby
class ShadowTester
  def initialize(production_agent, shadow_agent)
    @production_agent = production_agent
    @shadow_agent = shadow_agent
  end
  
  def run_shadow_test(request)
    # Run production agent (user sees this result)
    production_result = @production_agent.run(request)
    
    # Run shadow agent in background (user doesn't see this)
    shadow_future = Concurrent::Future.execute do
      @shadow_agent.run(request)
    end
    
    # Compare results asynchronously
    Concurrent::Future.execute do
      begin
        shadow_result = shadow_future.value(timeout: 30)
        compare_and_log_results(production_result, shadow_result, request)
      rescue Concurrent::TimeoutError
        log_shadow_timeout(request)
      rescue => e
        log_shadow_error(e, request)
      end
    end
    
    # Return production result immediately
    production_result
  end
  
  private
  
  def compare_and_log_results(production, shadow, request)
    comparison = {
      request: request,
      production_response_time: production.duration,
      shadow_response_time: shadow.duration,
      responses_similar: similarity_score(production, shadow),
      timestamp: Time.now
    }
    
    ShadowTestingLogger.log(comparison)
    
    if comparison[:responses_similar] < 0.8
      alert_significant_difference(comparison)
    end
  end
end
```

Continuous Testing
------------------

### Automated Test Suites

```ruby
# spec/integration/continuous_testing_spec.rb
RSpec.describe 'Continuous Agent Testing', type: :integration do
  let(:test_suite) { RAAF::Testing::ContinuousTestSuite.new }
  
  it 'runs smoke tests after deployment' do
    smoke_test_results = test_suite.run_smoke_tests(
      agent: deployed_agent,
      test_cases: load_smoke_test_cases,
      timeout: 5.minutes
    )
    
    expect(smoke_test_results.all_passed?).to be true
    expect(smoke_test_results.critical_failures).to be_empty
  end
  
  it 'runs regression tests daily' do
    regression_results = test_suite.run_regression_tests(
      agent: production_agent,
      test_cases: load_regression_test_cases,
      baseline_results: load_baseline_results
    )
    
    expect(regression_results.performance_regression?).to be false
    expect(regression_results.functionality_regression?).to be false
  end
  
  it 'runs end-to-end tests weekly' do
    e2e_results = test_suite.run_end_to_end_tests(
      workflow: complete_customer_journey,
      test_data: generate_realistic_test_data,
      environment: :staging
    )
    
    expect(e2e_results.customer_journey_completion_rate).to be >= 0.95
    expect(e2e_results.data_consistency_check).to be true
  end
end
```

### Test Data Management

```ruby
class TestDataManager
  def self.generate_realistic_conversations
    [
      {
        scenario: 'customer_support_technical',
        messages: [
          "I'm having trouble with my API integration",
          "The webhooks aren't being received",
          "I've checked the endpoint URL and it's correct"
        ],
        expected_tools: ['check_webhook_logs', 'test_webhook_endpoint'],
        expected_outcome: :resolved
      },
      {
        scenario: 'customer_support_billing',
        messages: [
          "I was charged twice for my subscription",
          "The charges were on January 15th and 16th",
          "My subscription ID is sub_123456"
        ],
        expected_tools: ['lookup_billing_history', 'process_refund'],
        expected_outcome: :escalated_to_billing
      }
    ]
  end
  
  def self.generate_edge_cases
    [
      {
        scenario: 'very_long_message',
        message: 'A' * 10000,  # Test token limits
        expected_behavior: :graceful_handling
      },
      {
        scenario: 'non_english_input',
        message: 'Bonjour, comment allez-vous?',
        expected_behavior: :language_detection
      },
      {
        scenario: 'malformed_input',
        message: '{"invalid": json}',
        expected_behavior: :error_handling
      }
    ]
  end
end
```

Best Practices
--------------

### The Million-Dollar Bug That Changed How We Test

AI testing requires balancing realistic scenarios with controlled conditions. Over-mocking can create false confidence, while under-mocking can make tests too expensive and slow.

### Common AI Testing Pitfalls

**Over-mocking**: Excessive mocking can test the mocks rather than the actual system behavior.

**Unrealistic test data**: Tests using static responses may not reflect real-world AI behavior variations.

**Insufficient integration testing**: Unit tests may pass while integration failures occur under load.

### Effective Testing Patterns

A balanced approach combines different testing strategies:

### Test Organization: Structure That Scales

**Key principle**: Organize tests by business risk and failure impact, not just code structure.

```ruby
# Structure focused on technical implementation
RSpec.describe RAAF::Agent do
  describe '#initialize' do
    # Tests for initialization edge cases
  end
end

# Structure focused on business-critical scenarios
RSpec.describe 'Critical Customer Flows' do
  describe 'order processing under load' do
    # Test high-traffic scenarios
  end
  
  describe 'price calculation accuracy' do
    # Test financial accuracy
  end
  
  describe 'error recovery' do
    # Test failure recovery mechanisms
  end
end
```

### Test Organization

```ruby
# Good test structure
RSpec.describe RAAF::Agent do
  describe 'initialization' do
    # Test agent creation and configuration
  end
  
  describe 'tool integration' do
    # Test tool addition and usage
  end
  
  describe 'conversation handling' do
    # Test message processing and responses
  end
  
  describe 'error handling' do
    # Test various error scenarios
  end
  
  describe 'performance' do
    # Test response times and resource usage
  end
end
```

### Test Data Isolation

Proper test data isolation prevents contamination between tests and production systems.

**Data isolation requirements**: 

- AI tests often generate realistic data that must be contained
- Parallel test execution requires isolated environments
- Production data access in tests creates compliance risks

**Implementation approaches**:

```ruby
# Database cleanup pattern
RSpec.describe 'Agent with Database Tools' do
  # Transaction rollback = your safety net
  around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
  
  # Explicit test data = no surprises
  before(:each) do
    @test_user = create(:user, name: 'Test User')
    @test_orders = create_list(:order, 3, user: @test_user)
  end
  
  # Each test is an island
  it 'queries user orders correctly' do
    # Test can't affect anything outside this block
  end
end
```

**Pro tip**: Use database names that scream "TEST" (test_raaf_dev). Your future self will thank you.

### Mock Strategy Guidelines: Finding the Sweet Spot

**Over-mocking risks**: Excessive mocking can create false confidence when tests pass but production fails due to changed dependencies.

**Balanced mocking approach**: Mock external dependencies while preserving core logic testing.

**What to Mock vs What to Keep Real**:

```ruby
# ✅ Mock External Services (they're slow, expensive, flaky)
RSpec.describe 'WeatherAgent' do
  before do
    allow(WeatherAPI).to receive(:get_current_weather).and_return(
      temperature: 72, conditions: 'sunny'
    )
  end
  # Rationale: Real weather API creates slow tests, API limits, and network dependencies
end

# ✅ Mock AI Responses (but thoughtfully)
RSpec.describe 'ConversationLogic' do
  let(:mock_provider) { RAAF::Testing::MockProvider.new }
  
  before do
    # Mock the AI, but test YOUR logic around it
    mock_provider.add_response("I understand you want weather information.")
  end
  # Rationale: Tests your code's handling of AI responses without per-test costs
end

# ❌ Never Mock Your Core Logic
RSpec.describe 'Agent' do
  before do
    allow(RAAF::Runner).to receive(:new).and_return(double)  # NO!
  end
  # Rationale: Mocking core logic tests the mocks rather than the actual implementation
end
```

**Core principle**: Mock external dependencies while testing internal logic thoroughly.

Next Steps
----------

Now that you understand RAAF testing:

* **[Performance Guide](performance_guide.html)** - Performance testing strategies
* **[Deployment Guide](deployment_guide.html)** - CI/CD integration for AI agents
* **[Monitoring Guide](tracing_guide.html)** - Production monitoring and testing
* **[Multi-Agent Guide](multi_agent_guide.html)** - Testing complex workflows
* **[RAAF Core Guide](core_guide.html)** - Understanding components for better testing