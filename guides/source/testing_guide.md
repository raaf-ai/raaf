**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Testing Guide
==================

This comprehensive guide covers testing strategies for Ruby AI Agents Factory (RAAF) applications. Testing AI systems requires specialized approaches that balance deterministic test expectations with probabilistic AI behavior while managing economic constraints unique to API-based services.

After reading this guide, you will know:

* Testing paradigms and strategies for AI systems
* Unit testing approaches for agents, tools, and workflows
* Integration testing patterns for multi-agent systems
* Performance and load testing considerations
* Rails-specific testing strategies with RAAF
* Economic optimization for API-based testing

--------------------------------------------------------------------------------

Understanding AI Testing Challenges
-----------------------------------

Testing AI agents differs fundamentally from traditional software testing. Where conventional systems produce deterministic outputs from given inputs, AI systems introduce probabilistic behavior that requires different validation approaches.

The non-deterministic nature of AI responses means that identical inputs can produce semantically equivalent but textually different outputs. An agent asked "What's 2+2?" might respond with "4", "Four", "2+2 equals 4", or "The sum is 4". Traditional assertion-based testing fails in this environment, requiring semantic validation approaches instead.

External dependencies compound testing complexity. AI agents rely on provider APIs that introduce network latency, rate limiting, service availability concerns, and usage costs. These dependencies make comprehensive testing both technically challenging and economically expensive without proper strategies.

The economic dimension of AI testing deserves particular attention. API calls during testing incur real costs that can escalate quickly. A modest test suite of 1,000 tests, each making 3 API calls at $0.01 per call, costs $30 per run. With continuous integration running tests on every commit, costs can reach thousands of dollars daily. This economic reality necessitates sophisticated mocking and selective integration testing strategies.

Testing Strategy Foundations
----------------------------

Effective AI testing focuses on system behavior rather than AI output validation. The fundamental principle guides all testing decisions: test your system's interaction with AI services, not the AI services themselves.

The mock-first approach forms the foundation of economical AI testing. Unit tests should default to mocked AI responses, providing fast, reliable, and cost-free test execution. Real API calls are reserved for specific integration scenarios that validate provider interaction patterns. This approach enables comprehensive testing without incurring prohibitive costs.

Record-replay patterns provide a middle ground between mocked and live testing. By capturing real AI responses during development or specific test runs, you create realistic test scenarios without ongoing API costs. This approach provides confidence that tests reflect actual AI behavior while maintaining test suite economics.

Behavioral testing validates system behavior rather than specific outputs. Tests verify that agents call appropriate tools, handle responses correctly, and follow expected workflows. This approach remains stable despite variations in AI responses, reducing test maintenance while ensuring system correctness.

Unit Testing Patterns
---------------------

Unit testing focuses on individual components in isolation. For AI systems, this means testing agent configuration, tool execution, and workflow logic independently of AI provider interactions.

Agent unit tests validate configuration and initialization rather than AI responses. Tests ensure agents are created with correct models, appropriate instructions, and required tools. Configuration validation prevents deployment of misconfigured agents that could produce incorrect results or incur unexpected costs.

```ruby
RSpec.describe CustomerServiceAgent do
  let(:agent) { described_class.new }
  
  it "configures appropriate model for customer service" do
    expect(agent.model).to eq("gpt-4o-mini")
  end
  
  it "includes required customer service tools" do
    tool_names = agent.tools.map { |t| t[:function][:name] }
    expect(tool_names).to include("lookup_order", "process_return", "check_inventory")
  end
  
  it "sets appropriate temperature for consistent responses" do
    expect(agent.temperature).to eq(0.3)
  end
end
```

Tool testing validates business logic independently of AI integration. Since tools are Ruby methods or objects, standard testing practices apply. Tests verify correct parameter handling, expected return values, and proper error handling without involving AI providers.

```ruby
RSpec.describe Tools::OrderLookup do
  let(:tool) { described_class.new }
  
  describe "#call" do
    it "returns order information for valid order ID" do
      result = tool.call(order_id: "12345")
      
      expect(result[:status]).to eq("success")
      expect(result[:order]).to include(
        id: "12345",
        status: "shipped",
        tracking_number: be_present
      )
    end
    
    it "handles missing orders gracefully" do
      result = tool.call(order_id: "nonexistent")
      
      expect(result[:status]).to eq("not_found")
      expect(result[:error]).to eq("Order not found")
    end
    
    it "validates order ID format" do
      result = tool.call(order_id: "invalid-format")
      
      expect(result[:status]).to eq("error")
      expect(result[:error]).to include("Invalid order ID format")
    end
  end
end
```

Workflow testing validates multi-step processes using test doubles. Mock providers enable testing complex agent interactions without API calls, ensuring workflows execute correctly regardless of AI response variations.

```ruby
RSpec.describe OrderProcessingWorkflow do
  let(:mock_provider) { RAAF::Testing::MockProvider.new }
  let(:workflow) { described_class.new(provider: mock_provider) }
  
  it "processes order through complete workflow" do
    # Configure mock responses for each workflow step
    mock_provider.add_response("Order validated successfully")
    mock_provider.add_response("Inventory confirmed")
    mock_provider.add_response("Payment processed")
    mock_provider.add_response("Shipment created")
    
    result = workflow.process_order(order_data)
    
    expect(result.status).to eq(:completed)
    expect(result.steps_completed).to eq([:validation, :inventory, :payment, :shipping])
  end
end
```

Integration Testing Approaches
------------------------------

Integration testing validates interactions between system components and external services. For AI systems, this includes testing agent-provider communication, multi-agent coordination, and end-to-end workflows.

Provider integration tests verify communication patterns rather than response content. Tests ensure proper request formatting, authentication handling, and error response processing. These tests run infrequently to minimize costs while ensuring integration correctness.

```ruby
RSpec.describe "Provider Integration", :integration do
  let(:agent) { create_test_agent }
  
  it "successfully communicates with provider" do
    VCR.use_cassette("provider_communication") do
      result = agent.run("Hello")
      
      expect(result.messages).to be_present
      expect(result.usage.total_tokens).to be_positive
    end
  end
  
  it "handles rate limiting gracefully" do
    VCR.use_cassette("rate_limit_response") do
      expect {
        10.times { agent.run("Test") }
      }.to raise_error(RAAF::Errors::RateLimitError)
    end
  end
end
```

Multi-agent integration testing validates handoffs and coordination. Tests verify that agents transfer control appropriately, maintain context across handoffs, and complete multi-agent workflows successfully.

```ruby
RSpec.describe "Multi-Agent Customer Service", :integration do
  let(:initial_agent) { GreetingAgent.new }
  let(:support_agent) { TechnicalSupportAgent.new }
  let(:runner) { RAAF::Runner.new(agent: initial_agent, agents: [initial_agent, support_agent]) }
  
  it "handles handoff from greeting to support" do
    mock_provider.add_response("I need technical help", tool_calls: [
      { function: { name: "transfer_to_support" } }
    ])
    mock_provider.add_response("I can help with technical issues")
    
    result = runner.run("I have a technical problem")
    
    expect(result.last_agent.name).to eq("TechnicalSupport")
    expect(result.messages).to include(
      hash_including(role: "assistant", content: include("technical"))
    )
  end
end
```

Rails-Specific Testing
----------------------

Rails applications require specialized testing approaches that integrate RAAF testing utilities with Rails testing conventions. The integration provides familiar Rails testing patterns while handling AI-specific concerns.

RSpec configuration for RAAF projects establishes consistent test environments. Configuration includes RAAF testing helpers, automatic provider mocking for agent tests, and proper cleanup between tests.

```ruby
# spec/rails_helper.rb
require 'raaf/testing'

RSpec.configure do |config|
  config.include RAAF::Testing::Helpers
  config.include RAAF::Testing::Matchers
  
  config.before(:each, type: :agent) do
    RAAF.configure do |c|
      c.provider = RAAF::Testing::MockProvider.new
    end
  end
  
  config.after(:each, type: :agent) do
    RAAF.reset_configuration!
  end
end
```

Controller testing validates HTTP endpoints that interact with agents. Tests verify request handling, response formatting, and error conditions without making actual AI API calls.

```ruby
RSpec.describe Api::ChatController, type: :controller do
  let(:user) { create(:user) }
  let(:mock_provider) { RAAF::Testing::MockProvider.new }
  
  before do
    sign_in user
    allow(RAAF.configuration).to receive(:provider).and_return(mock_provider)
  end
  
  describe "POST #create" do
    it "processes chat message and returns response" do
      mock_provider.add_response("I can help you with that order")
      
      post :create, params: { message: "Check order status" }, format: :json
      
      expect(response).to have_http_status(:success)
      
      json = JSON.parse(response.body)
      expect(json["response"]).to include("help you with that order")
      expect(json["conversation_id"]).to be_present
    end
    
    it "handles provider errors gracefully" do
      mock_provider.add_error(RAAF::Errors::ProviderError.new("Service unavailable"))
      
      post :create, params: { message: "Hello" }, format: :json
      
      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)["error"]).to include("temporarily unavailable")
    end
  end
end
```

Service object testing validates business logic that orchestrates agent interactions. Tests ensure proper context building, agent selection, and result processing.

```ruby
RSpec.describe CustomerSupportService do
  let(:user) { create(:user, subscription: "premium") }
  let(:service) { described_class.new(user: user) }
  let(:mock_provider) { RAAF::Testing::MockProvider.new }
  
  before do
    allow(service).to receive(:provider).and_return(mock_provider)
  end
  
  describe "#handle_inquiry" do
    it "routes to appropriate agent based on inquiry type" do
      mock_provider.add_response("I'll help you with billing", tool_calls: [
        { function: { name: "categorize_inquiry", arguments: { category: "billing" } } }
      ])
      
      result = service.handle_inquiry("Question about my invoice")
      
      expect(result.agent_used).to eq("BillingSupport")
      expect(result.response).to include("billing")
    end
    
    it "includes user context in agent interactions" do
      expect_any_instance_of(RAAF::Runner).to receive(:run) do |_, message, options|
        expect(options[:context_variables]).to include(
          user_id: user.id,
          subscription_tier: "premium"
        )
      end.and_return(double(messages: [], usage: double(total_tokens: 0)))
      
      service.handle_inquiry("Help needed")
    end
  end
end
```

Performance Testing Considerations
----------------------------------

Performance testing for AI systems focuses on response latency, throughput capacity, and cost efficiency rather than traditional metrics. AI-specific performance characteristics require adapted testing approaches.

Response time testing measures end-to-end latency including AI provider calls. Tests establish baseline expectations and monitor for degradation. Mock providers enable consistent performance testing without API variability.

```ruby
RSpec.describe "Agent Performance", :performance do
  let(:agent) { HighPerformanceAgent.new }
  
  it "responds within acceptable time limits" do
    expect {
      agent.run("Quick question")
    }.to perform_under(2).seconds
  end
  
  it "handles concurrent requests efficiently" do
    expect {
      threads = 10.times.map do
        Thread.new { agent.run("Concurrent request") }
      end
      threads.each(&:join)
    }.to perform_under(5).seconds
  end
end
```

Cost profiling tracks token usage and estimates operational costs. Tests verify that agents operate within budget constraints and flag expensive operations during development.

```ruby
RSpec.describe "Cost Management", :cost do
  let(:agent) { CustomerServiceAgent.new }
  
  it "operates within token budget for typical interactions" do
    result = agent.run("Standard customer inquiry")
    
    expect(result.usage.total_tokens).to be < 500
    expect(result.estimated_cost).to be < 0.02
  end
  
  it "warns on expensive operations" do
    expect {
      agent.run("Analyze this 10,000 word document")
    }.to output(/High token usage warning/).to_stderr
  end
end
```

Load testing validates system behavior under concurrent load. Tests verify connection pooling, rate limit handling, and graceful degradation under stress.

Testing Best Practices
----------------------

Effective AI testing requires balancing thoroughness with practicality. Comprehensive test coverage must be achieved without incurring prohibitive costs or maintenance burden.

Test data management ensures consistent, realistic test scenarios. Use factories to generate test data that reflects production patterns. Maintain test fixtures for complex scenarios that require specific data configurations. Regular test data audits prevent drift between test and production environments.

Continuous integration strategies minimize costs while maintaining quality. Run unit tests on every commit using mocked providers. Execute integration tests on pull requests with recorded responses. Reserve live API tests for release candidates. This tiered approach balances cost with confidence.

Test maintenance requires ongoing attention as AI models and behaviors evolve. Regular test reviews identify brittle assertions that fail on acceptable response variations. Semantic matchers that validate meaning rather than exact text improve test stability. Version-specific test suites handle model transitions gracefully.

Debugging test failures in AI systems requires specialized approaches. Capture full request/response cycles for failure analysis. Log token usage and costs for budget debugging. Implement detailed error messages that distinguish between system failures and AI behavior variations.

Next Steps
----------

* **[RAAF Core Guide](core_guide.html)** - Understanding components for effective testing
* **[Performance Guide](performance_guide.html)** - Performance testing and optimization
* **[Rails Guide](rails_guide.html)** - Rails-specific testing patterns
* **[Best Practices](best_practices.html)** - Testing best practices and patterns