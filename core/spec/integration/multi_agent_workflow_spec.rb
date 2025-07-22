# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Multi-Agent Workflows", :integration do
  let(:mock_provider) { create_mock_provider }

  let(:greeting_agent) do
    create_test_agent(
      name: "GreetingAgent",
      instructions: "You greet customers and route them to appropriate specialists"
    )
  end

  let(:support_agent) do
    create_test_agent(
      name: "SupportAgent",
      instructions: "You provide technical support"
    )
  end

  let(:billing_agent) do
    create_test_agent(
      name: "BillingAgent",
      instructions: "You handle billing inquiries"
    )
  end

  before do
    # Set up agent handoffs
    greeting_agent.add_handoff(support_agent)
    greeting_agent.add_handoff(billing_agent)
  end

  describe "Customer service workflow" do
    it "handles handoff from greeting to support" do
      # Configure mock responses for workflow
      mock_provider.add_response(
        "I'll transfer you to technical support",
        tool_calls: [{
          function: { name: "transfer_to_supportagent", arguments: "{}" }
        }]
      )
      mock_provider.add_response("I can help with technical issues")

      runner = RAAF::Runner.new(
        agent: greeting_agent,
        provider: mock_provider
      )

      result = runner.run("I have a technical problem with my account")

      expect(result.success?).to be true
      expect(result.last_agent&.name).to eq("SupportAgent")
    end

    it "handles handoff from greeting to billing" do
      mock_provider.add_response(
        "Let me connect you with billing",
        tool_calls: [{
          function: { name: "transfer_to_billingagent", arguments: "{}" }
        }]
      )
      mock_provider.add_response("I can help with your billing question")

      runner = RAAF::Runner.new(
        agent: greeting_agent,
        provider: mock_provider
      )

      result = runner.run("I have a question about my invoice")

      expect(result.success?).to be true
      expect(result.last_agent&.name).to eq("BillingAgent")
    end

    it "maintains context across handoffs" do
      mock_provider.add_response(
        "I'll transfer you to billing with your account info",
        tool_calls: [{
          function: { name: "transfer_to_billingagent", arguments: '{"context": "premium customer"}' }
        }]
      )
      mock_provider.add_response("I see you're a premium customer, I can help")

      runner = RAAF::Runner.new(
        agent: greeting_agent,
        provider: mock_provider
      )

      result = runner.run("I'm a premium customer with a billing issue")

      expect(result.success?).to be true
      expect(result.messages).not_to be_empty
      expect(result.last_agent&.name).to eq("BillingAgent")
    end

    it "handles complex multi-step workflows" do
      # Multi-step workflow: greeting -> support -> billing
      mock_provider.add_response(
        "Let me check with technical support first",
        tool_calls: [{
          function: { name: "transfer_to_supportagent", arguments: "{}" }
        }]
      )
      mock_provider.add_response(
        "This seems to be a billing-related technical issue",
        tool_calls: [{
          function: { name: "transfer_to_billingagent", arguments: "{}" }
        }]
      )
      mock_provider.add_response("I can help resolve this billing technical issue")

      # Set up support -> billing handoff
      support_agent.add_handoff(billing_agent)

      runner = RAAF::Runner.new(
        agent: greeting_agent,
        provider: mock_provider
      )

      result = runner.run("My premium features stopped working after payment")

      expect(result.success?).to be true
      expect(result.last_agent&.name).to eq("BillingAgent")
      # Verify handoffs occurred (can't directly count handoffs in current API)
    end
  end

  describe "Error handling in workflows" do
    it "handles failed handoffs gracefully" do
      # Agent tries to handoff to non-existent agent
      mock_provider.add_response(
        "Let me transfer you",
        tool_calls: [{
          function: { name: "transfer_to_nonexistent", arguments: "{}" }
        }]
      )

      runner = RAAF::Runner.new(
        agent: greeting_agent,
        provider: mock_provider
      )

      result = runner.run("I need help")

      # Should still succeed but remain with original agent
      expect(result.success?).to be true
      expect(result.last_agent&.name).to eq("GreetingAgent")
    end

    it "handles provider errors during handoffs" do
      mock_provider.add_error(RAAF::Models::APIError.new("Service temporarily unavailable"))

      runner = RAAF::Runner.new(
        agent: greeting_agent,
        provider: mock_provider
      )

      expect do
        runner.run("Help me")
      end.to raise_error(RAAF::Models::APIError)
    end
  end

  describe "Workflow performance" do
    it "completes workflows within reasonable time" do
      mock_provider.add_response(
        "Quick response",
        tool_calls: [{
          function: { name: "transfer_to_supportagent", arguments: "{}" }
        }]
      )
      mock_provider.add_response("Quick support response")

      runner = RAAF::Runner.new(
        agent: greeting_agent,
        provider: mock_provider
      )

      if defined?(RSpec::Benchmark)
        expect do
          runner.run("Quick question")
        end.to perform_under(1).second
      end
    end
  end
end
