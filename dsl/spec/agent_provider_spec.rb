# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::DSL::Agent provider configuration" do
  describe "provider DSL methods" do
    it "allows explicit provider specification" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        model "claude-3-5-sonnet-20241022"
        provider :anthropic
      end

      expect(agent_class.provider).to eq(:anthropic)
    end

    it "allows provider options specification" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        provider :anthropic
        provider_options api_key: "test-key", max_tokens: 4000
      end

      expect(agent_class.provider_options).to eq({ api_key: "test-key", max_tokens: 4000 })
    end

    it "defaults auto_detect_provider to true" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
      end

      expect(agent_class.auto_detect_provider).to be true
    end

    it "allows disabling auto_detect_provider" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        auto_detect_provider false
      end

      expect(agent_class.auto_detect_provider).to be false
    end
  end

  describe "provider auto-detection" do
    it "auto-detects provider from OpenAI model" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "GPTAgent"
        model "gpt-4o"
      end

      agent = agent_class.new
      expect(agent.provider).to be_a(RAAF::Models::ResponsesProvider)
    end

    it "auto-detects provider from Claude model" do
      # Skip if AnthropicProvider not available
      skip "AnthropicProvider not available" unless defined?(RAAF::Models::AnthropicProvider)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ClaudeAgent"
        model "claude-3-5-sonnet-20241022"
      end

      agent = agent_class.new
      expect(agent.provider).to be_a(RAAF::Models::AnthropicProvider)
    end

    it "does not auto-detect when disabled" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        model "gpt-4o"
        auto_detect_provider false
      end

      agent = agent_class.new
      expect(agent.provider).to be_nil
    end

    it "uses explicit provider over auto-detection" do
      # Skip if AnthropicProvider not available
      skip "AnthropicProvider not available" unless defined?(RAAF::Models::AnthropicProvider)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        model "gpt-4o"  # Would auto-detect to :openai
        provider :anthropic  # But explicitly set to :anthropic
      end

      agent = agent_class.new
      expect(agent.provider).to be_a(RAAF::Models::AnthropicProvider)
    end
  end

  describe "provider instance creation" do
    it "creates provider instance with no options" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        model "gpt-4o"
      end

      agent = agent_class.new
      expect(agent.provider).to be_a(RAAF::Models::ResponsesProvider)
    end

    it "passes provider options to provider constructor" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        provider :openai
        provider_options api_key: "custom-key"
      end

      agent = agent_class.new
      expect(agent.provider).to be_a(RAAF::Models::ResponsesProvider)
      # Provider was created with custom options
    end

    it "returns nil when provider creation fails" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        provider :invalid_provider
      end

      agent = agent_class.new
      expect(agent.provider).to be_nil
    end

    it "handles model with no detected provider" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        model "unknown-model-name"
      end

      agent = agent_class.new
      expect(agent.provider).to be_nil
    end
  end

  describe "integration with Runner" do
    it "Runner uses agent's provider when available" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        model "gpt-4o"
        static_instructions "Test agent"
      end

      agent = agent_class.new
      runner = RAAF::Runner.new(agent: agent)

      # Runner should use the agent's provider
      expect(runner.instance_variable_get(:@provider)).to be_a(RAAF::Models::ResponsesProvider)
      expect(runner.instance_variable_get(:@provider)).to eq(agent.provider)
    end

    it "Runner uses explicit provider over agent's provider" do
      # Skip if AnthropicProvider not available
      skip "AnthropicProvider not available" unless defined?(RAAF::Models::AnthropicProvider)

      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        model "gpt-4o"
        static_instructions "Test agent"
      end

      agent = agent_class.new
      explicit_provider = RAAF::Models::AnthropicProvider.new

      runner = RAAF::Runner.new(agent: agent, provider: explicit_provider)

      # Runner should use the explicitly provided provider
      expect(runner.instance_variable_get(:@provider)).to eq(explicit_provider)
    end

    it "Runner falls back to default provider when agent has none" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "TestAgent"
        model "gpt-4o"
        auto_detect_provider false  # Disable auto-detection
        static_instructions "Test agent"
      end

      agent = agent_class.new
      runner = RAAF::Runner.new(agent: agent)

      # Runner should create default ResponsesProvider
      expect(runner.instance_variable_get(:@provider)).to be_a(RAAF::Models::ResponsesProvider)
    end
  end
end
