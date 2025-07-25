**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf-ai.dev>.**

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

<!-- VALIDATION_FAILED: testing_guide.md:49 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant CustomerServiceAgent /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-91j6e7.rb:444:in '<main>'
```

```ruby
RSpec.describe CustomerServiceAgent do
  let(:agent) { RAAF::Agent.new(name: "CustomerService", instructions: "Help customers", model: "gpt-4o-mini") }
  
  it "configures appropriate model for customer service" do
    expect(agent.model).to eq("gpt-4o-mini")
  end
  
  it "has required name and instructions" do
    expect(agent.name).to eq("CustomerService")
    expect(agent.instructions).to include("Help customers")
  end
end
```

Tool testing validates business logic independently of AI integration. Since tools are Ruby methods or objects, standard testing practices apply. Tests verify correct parameter handling, expected return values, and proper error handling without involving AI providers.

<!-- VALIDATION_FAILED: testing_guide.md:66 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NoMethodError: undefined method 'eq' for main /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-czmcs2.rb:465:in 'block (3 levels) in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-czmcs2.rb:334:in 'Object#it' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-czmcs2.rb:462:in 'block (2 levels) in <main>'
```

```ruby
class OrderLookupTool
  def self.call(order_id:)
    return { error: "Invalid order ID format" } unless order_id.match?(/^\d+$/)
    
    orders = {
      "12345" => { id: "12345", status: "shipped", tracking_number: "TRACK123" }
    }
    
    if orders[order_id]
      { status: "success", order: orders[order_id] }
    else
      { status: "not_found", error: "Order not found" }
    end
  end
end

RSpec.describe OrderLookupTool do
  describe ".call" do
    it "returns order information for valid order ID" do
      result = OrderLookupTool.call(order_id: "12345")
      
      expect(result[:status]).to eq("success")
      expect(result[:order]).to include(
        id: "12345",
        status: "shipped",
        tracking_number: "TRACK123"
      )
    end
    
    it "handles missing orders gracefully" do
      result = OrderLookupTool.call(order_id: "99999")
      
      expect(result[:status]).to eq("not_found")
      expect(result[:error]).to eq("Order not found")
    end
    
    it "validates order ID format" do
      result = OrderLookupTool.call(order_id: "invalid-format")
      
      expect(result[:error]).to include("Invalid order ID format")
    end
  end
end
```

Workflow testing validates multi-step processes using test doubles. Mock providers enable testing complex agent interactions without API calls, ensuring workflows execute correctly regardless of AI response variations.

<!-- VALIDATION_FAILED: testing_guide.md:114 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NoMethodError: undefined method 'eq' for main /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-gllkyb.rb:466:in 'block (2 levels) in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-gllkyb.rb:334:in 'Object#it' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-gllkyb.rb:463:in 'block in <main>'
```

```ruby
class OrderProcessingWorkflow
  def initialize
    @steps_completed = []
  end
  
  def process_order(order_data)
    @steps_completed << :validation
    @steps_completed << :inventory
    @steps_completed << :payment
    @steps_completed << :shipping
    
    OpenStruct.new(status: :completed, steps_completed: @steps_completed)
  end
end

RSpec.describe OrderProcessingWorkflow do
  let(:workflow) { OrderProcessingWorkflow.new }
  let(:order_data) { { customer_id: "123", items: [{ id: "ITEM1", quantity: 1 }] } }
  
  it "processes order through complete workflow" do
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

<!-- VALIDATION_FAILED: testing_guide.md:150 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: undefined local variable or method 'be_empty' for main /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-xq6xx3.rb:452:in 'block (2 levels) in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-xq6xx3.rb:334:in 'Object#it' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-xq6xx3.rb:447:in 'block in <main>'
```

```ruby
RSpec.describe "Provider Integration", :integration do
  let(:agent) { RAAF::Agent.new(name: "Test", instructions: "Be helpful", model: "gpt-4o-mini") }
  
  it "successfully communicates with provider" do
    # Test actual communication pattern
    runner = RAAF::Runner.new(agent: agent)
    result = runner.run("Hello")
    
    expect(result.messages).not_to be_empty
    expect(result.messages.last[:content]).to be_a(String)
  end
end
```

Multi-agent integration testing validates handoffs and coordination. Tests verify that agents transfer control appropriately, maintain context across handoffs, and complete multi-agent workflows successfully.

<!-- VALIDATION_FAILED: testing_guide.md:167 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NoMethodError: undefined method 'agent' for an instance of RAAF::Runner /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-1n5f1x.rb:452:in 'block (2 levels) in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-1n5f1x.rb:334:in 'Object#it' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-1n5f1x.rb:448:in 'block in <main>'
```

```ruby
RSpec.describe "Multi-Agent Customer Service", :integration do
  let(:initial_agent) { RAAF::Agent.new(name: "Greeting", instructions: "Greet customers", model: "gpt-4o-mini") }
  let(:support_agent) { RAAF::Agent.new(name: "TechnicalSupport", instructions: "Provide technical support", model: "gpt-4o-mini") }
  
  it "configures multi-agent workflow" do
    initial_agent.add_handoff(support_agent)
    runner = RAAF::Runner.new(agent: initial_agent, agents: [initial_agent, support_agent])
    
    expect(runner.agent.name).to eq("Greeting")
    expect(runner.agents.map(&:name)).to include("Greeting", "TechnicalSupport")
  end
end
```

Rails-Specific Testing
----------------------

Rails applications require specialized testing approaches that integrate RAAF testing utilities with Rails testing conventions. The integration provides familiar Rails testing patterns while handling AI-specific concerns.

RSpec configuration for RAAF projects establishes consistent test environments. Configuration includes RAAF testing helpers, automatic provider mocking for agent tests, and proper cleanup between tests.

<!-- VALIDATION_FAILED: testing_guide.md:189 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
<internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require': cannot load such file -- raaf (LoadError) 	from <internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-14y9tf.rb:445:in '<main>'
```

```ruby
# spec/rails_helper.rb
require 'raaf'

RSpec.configure do |config|
  # Include helper methods for testing RAAF agents
  config.before(:each, type: :agent) do
    # Set up test environment for agent tests
    @test_agent = RAAF::Agent.new(
      name: "TestAgent", 
      instructions: "Test agent for RSpec", 
      model: "gpt-4o-mini"
    )
  end
end
```

Controller testing validates HTTP endpoints that interact with agents. Tests verify request handling, response formatting, and error conditions without making actual AI API calls.

<!-- VALIDATION_FAILED: testing_guide.md:208 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant Api /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-wz1rxo.rb:444:in '<main>'
```

```ruby
class Api::ChatController < ApplicationController
  def create
    agent = RAAF::Agent.new(
      name: "ChatBot", 
      instructions: "Help users with their questions", 
      model: "gpt-4o-mini"
    )
    
    runner = RAAF::Runner.new(agent: agent)
    result = runner.run(params[:message])
    
    render json: { 
      response: result.messages.last[:content],
      conversation_id: "conv_#{SecureRandom.hex(8)}"
    }
  rescue => e
    render json: { error: "Service temporarily unavailable" }, status: :service_unavailable
  end
end

RSpec.describe Api::ChatController, type: :controller do
  describe "POST #create" do
    it "processes chat message and returns response" do
      post :create, params: { message: "Hello" }, format: :json
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["response"]).to be_a(String)
      expect(json["conversation_id"]).to be_present
    end
  end
end
```

Service object testing validates business logic that orchestrates agent interactions. Tests ensure proper context building, agent selection, and result processing.

```ruby
class CustomerSupportService
  def initialize(user:)
    @user = user
  end
  
  def handle_inquiry(message)
    agent = RAAF::Agent.new(
      name: "SupportAgent",
      instructions: "Provide customer support",
      model: "gpt-4o-mini"
    )
    
    runner = RAAF::Runner.new(agent: agent)
    result = runner.run(message, context_variables: {
      user_id: @user.id,
      subscription_tier: @user.subscription
    })
    
    OpenStruct.new(
      agent_used: agent.name,
      response: result.messages.last[:content]
    )
  end
end

RSpec.describe CustomerSupportService do
  let(:user) { OpenStruct.new(id: 123, subscription: "premium") }
  let(:service) { CustomerSupportService.new(user: user) }
  
  describe "#handle_inquiry" do
    it "processes customer inquiry" do
      result = service.handle_inquiry("I need help")
      
      expect(result.agent_used).to eq("SupportAgent")
      expect(result.response).to be_a(String)
    end
  end
end
```

Performance Testing Considerations
----------------------------------

Performance testing for AI systems focuses on response latency, throughput capacity, and cost efficiency rather than traditional metrics. AI-specific performance characteristics require adapted testing approaches.

Response time testing measures end-to-end latency including AI provider calls. Tests establish baseline expectations and monitor for degradation. Mock providers enable consistent performance testing without API variability.

<!-- VALIDATION_FAILED: testing_guide.md:293 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: undefined local variable or method 'be' for main /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-u7bk2f.rb:453:in 'block (2 levels) in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-u7bk2f.rb:334:in 'Object#it' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-u7bk2f.rb:447:in 'block in <main>'
```

```ruby
RSpec.describe "Agent Performance", :performance do
  let(:agent) { RAAF::Agent.new(name: "FastAgent", instructions: "Be quick", model: "gpt-4o-mini") }
  
  it "responds within acceptable time limits" do
    start_time = Time.now
    runner = RAAF::Runner.new(agent: agent)
    result = runner.run("Quick question")
    end_time = Time.now
    
    expect(end_time - start_time).to be < 30  # 30 seconds for API call
    expect(result.messages).not_to be_empty
  end
end
```

Cost profiling tracks token usage and estimates operational costs. Tests verify that agents operate within budget constraints and flag expensive operations during development.

<!-- VALIDATION_FAILED: testing_guide.md:311 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: undefined local variable or method 'be_empty' for main /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-pqpenq.rb:452:in 'block (2 levels) in <main>' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-pqpenq.rb:334:in 'Object#it' /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-pqpenq.rb:447:in 'block in <main>'
```

```ruby
RSpec.describe "Cost Management", :cost do
  let(:agent) { RAAF::Agent.new(name: "CostAgent", instructions: "Be efficient", model: "gpt-4o-mini") }
  
  it "tracks token usage for interactions" do
    runner = RAAF::Runner.new(agent: agent)
    result = runner.run("Standard customer inquiry")
    
    # Basic validation that response was generated
    expect(result.messages).not_to be_empty
    expect(result.messages.last[:content]).to be_a(String)
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