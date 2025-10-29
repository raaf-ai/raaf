# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::DSL::Agent continuation configuration" do
  # Define test agent classes for different scenarios
  class BasicContinuationAgent < RAAF::DSL::Agent
    agent_name "BasicContinuationAgent"
    model "gpt-4o"

    # Basic continuation enabling
    enable_continuation

    static_instructions "You are a test assistant with continuation support."
  end

  class ConfiguredContinuationAgent < RAAF::DSL::Agent
    agent_name "ConfiguredContinuationAgent"
    model "gpt-4o"

    # Continuation with custom configuration
    enable_continuation(
      max_attempts: 15,
      output_format: :csv,
      on_failure: :raise_error
    )

    static_instructions "You are a test assistant with custom continuation config."
  end

  class PartialConfigAgent < RAAF::DSL::Agent
    agent_name "PartialConfigAgent"
    model "gpt-4o"

    # Partial configuration (should use defaults for unspecified)
    enable_continuation(max_attempts: 5)

    static_instructions "Partially configured continuation agent."
  end

  class NoContinuationAgent < RAAF::DSL::Agent
    agent_name "NoContinuationAgent"
    model "gpt-4o"

    # No continuation enabled
    static_instructions "Agent without continuation support."
  end

  describe "Agent-Level Configuration" do
    describe "RAAF::DSL::Agent#enable_continuation" do
      it "accepts enable_continuation class method call" do
        expect { BasicContinuationAgent }.not_to raise_error
        expect(BasicContinuationAgent).to respond_to(:_continuation_config)
      end

      it "stores configuration in agent metadata" do
        config = BasicContinuationAgent._continuation_config
        expect(config).not_to be_nil
        expect(config).to be_a(Hash)
      end

      it "allows multiple configuration options" do
        config = ConfiguredContinuationAgent._continuation_config
        expect(config).to include(
          max_attempts: 15,
          output_format: :csv,
          on_failure: :raise_error
        )
      end

      it "accepts max_attempts option" do
        config = ConfiguredContinuationAgent._continuation_config
        expect(config[:max_attempts]).to eq(15)
      end

      it "accepts output_format option (:csv, :markdown, :json, :auto)" do
        [:csv, :markdown, :json, :auto].each do |format|
          test_agent = Class.new(RAAF::DSL::Agent) do
            agent_name "FormatTestAgent"
            model "gpt-4o"
            enable_continuation(output_format: format)
          end

          config = test_agent._continuation_config
          expect(config[:output_format]).to eq(format)
        end
      end

      it "accepts on_failure option (:return_partial, :raise_error)" do
        [:return_partial, :raise_error].each do |failure_mode|
          test_agent = Class.new(RAAF::DSL::Agent) do
            agent_name "FailureTestAgent"
            model "gpt-4o"
            enable_continuation(on_failure: failure_mode)
          end

          config = test_agent._continuation_config
          expect(config[:on_failure]).to eq(failure_mode)
        end
      end
    end
  end

  describe "Configuration Validation" do
    it "validates max_attempts is positive integer" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "InvalidAttemptsAgent"
          model "gpt-4o"
          enable_continuation(max_attempts: -1)
        end
      }.to raise_error(RAAF::InvalidConfigurationError, /max_attempts must be a positive integer/)
    end

    it "validates max_attempts <= 50" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "TooManyAttemptsAgent"
          model "gpt-4o"
          enable_continuation(max_attempts: 51)
        end
      }.to raise_error(RAAF::InvalidConfigurationError, /max_attempts cannot exceed 50/)
    end

    it "validates output_format is one of :csv, :markdown, :json, :auto" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "InvalidFormatAgent"
          model "gpt-4o"
          enable_continuation(output_format: :xml)
        end
      }.to raise_error(RAAF::InvalidConfigurationError, /Invalid output_format: xml/)
    end

    it "validates on_failure is one of :return_partial, :raise_error" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "InvalidFailureAgent"
          model "gpt-4o"
          enable_continuation(on_failure: :skip)
        end
      }.to raise_error(RAAF::InvalidConfigurationError, /Invalid on_failure mode: skip/)
    end

    it "raises error for invalid max_attempts (negative)" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "NegativeAttemptsAgent"
          model "gpt-4o"
          enable_continuation(max_attempts: -10)
        end
      }.to raise_error(RAAF::InvalidConfigurationError, /max_attempts must be a positive integer/)
    end

    it "raises error for invalid output_format (:xml)" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "XmlFormatAgent"
          model "gpt-4o"
          enable_continuation(output_format: :xml)
        end
      }.to raise_error(RAAF::InvalidConfigurationError, /Invalid output_format: xml/)
    end

    it "raises error for invalid on_failure mode" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "InvalidOnFailureAgent"
          model "gpt-4o"
          enable_continuation(on_failure: :ignore)
        end
      }.to raise_error(RAAF::InvalidConfigurationError, /Invalid on_failure mode: ignore/)
    end

    it "accepts valid configuration combinations" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "ValidCombinationAgent"
          model "gpt-4o"
          enable_continuation(
            max_attempts: 20,
            output_format: :markdown,
            on_failure: :return_partial
          )
        end
      }.not_to raise_error
    end
  end

  describe "Default Values" do
    let(:default_agent) { BasicContinuationAgent }
    let(:default_config) { default_agent._continuation_config }

    it "defaults max_attempts to 10" do
      expect(default_config[:max_attempts]).to eq(10)
    end

    it "defaults output_format to :auto" do
      expect(default_config[:output_format]).to eq(:auto)
    end

    it "defaults on_failure to :return_partial" do
      expect(default_config[:on_failure]).to eq(:return_partial)
    end

    it "defaults merge_strategy to nil (internal)" do
      expect(default_config[:merge_strategy]).to be_nil
    end

    it "applies defaults when options not specified" do
      config = BasicContinuationAgent._continuation_config
      expect(config).to include(
        max_attempts: 10,
        output_format: :auto,
        on_failure: :return_partial
      )
    end

    it "allows overriding defaults" do
      config = PartialConfigAgent._continuation_config
      expect(config[:max_attempts]).to eq(5) # Overridden
      expect(config[:output_format]).to eq(:auto) # Default
      expect(config[:on_failure]).to eq(:return_partial) # Default
    end
  end

  describe "Edge Cases" do
    it "handles nil values gracefully" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "NilValueAgent"
          model "gpt-4o"
          enable_continuation(max_attempts: nil)
        end
      }.to raise_error(RAAF::InvalidConfigurationError, /max_attempts must be a positive integer/)
    end

    it "handles empty strings" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "EmptyStringAgent"
          model "gpt-4o"
          enable_continuation(output_format: "")
        end
      }.to raise_error(RAAF::InvalidConfigurationError, /Invalid output_format/)
    end

    it "handles type mismatches (string instead of symbol)" do
      # Should convert strings to symbols for known options
      agent = Class.new(RAAF::DSL::Agent) do
        agent_name "StringSymbolAgent"
        model "gpt-4o"
        enable_continuation(
          output_format: "csv",
          on_failure: "raise_error"
        )
      end

      config = agent._continuation_config
      expect(config[:output_format]).to eq(:csv)
      expect(config[:on_failure]).to eq(:raise_error)
    end

    it "handles missing options" do
      agent = Class.new(RAAF::DSL::Agent) do
        agent_name "MissingOptionsAgent"
        model "gpt-4o"
        enable_continuation # No options provided
      end

      config = agent._continuation_config
      expect(config).to include(
        max_attempts: 10,
        output_format: :auto,
        on_failure: :return_partial
      )
    end

    it "handles extra unknown options" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "ExtraOptionsAgent"
          model "gpt-4o"
          enable_continuation(
            max_attempts: 10,
            unknown_option: "value"
          )
        end
      }.to raise_error(RAAF::InvalidConfigurationError, /Unknown continuation option: unknown_option/)
    end

    it "validates all combinations of valid options" do
      valid_formats = [:csv, :markdown, :json, :auto]
      valid_failures = [:return_partial, :raise_error]
      valid_attempts = [1, 10, 25, 50]

      # Test a sampling of combinations
      valid_formats.each do |format|
        valid_failures.each do |failure|
          attempts = valid_attempts.sample

          expect {
            Class.new(RAAF::DSL::Agent) do
              agent_name "ComboTestAgent"
              model "gpt-4o"
              enable_continuation(
                max_attempts: attempts,
                output_format: format,
                on_failure: failure
              )
            end
          }.not_to raise_error
        end
      end
    end
  end

  describe "Invalid Configuration Error Handling" do
    it "raises InvalidConfigurationError for format: :xml" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "XmlErrorAgent"
          model "gpt-4o"
          enable_continuation(output_format: :xml)
        end
      }.to raise_error(RAAF::InvalidConfigurationError) do |error|
        expect(error.message).to include("Invalid output_format: xml")
        expect(error.message).to include("Valid options are: :csv, :markdown, :json, :auto")
      end
    end

    it "raises InvalidConfigurationError for negative max_attempts" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "NegativeErrorAgent"
          model "gpt-4o"
          enable_continuation(max_attempts: -5)
        end
      }.to raise_error(RAAF::InvalidConfigurationError) do |error|
        expect(error.message).to include("max_attempts must be a positive integer")
      end
    end

    it "raises InvalidConfigurationError for max_attempts > 50" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "TooManyErrorAgent"
          model "gpt-4o"
          enable_continuation(max_attempts: 100)
        end
      }.to raise_error(RAAF::InvalidConfigurationError) do |error|
        expect(error.message).to include("max_attempts cannot exceed 50")
      end
    end

    it "raises InvalidConfigurationError for on_failure: :skip" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "SkipErrorAgent"
          model "gpt-4o"
          enable_continuation(on_failure: :skip)
        end
      }.to raise_error(RAAF::InvalidConfigurationError) do |error|
        expect(error.message).to include("Invalid on_failure mode: skip")
        expect(error.message).to include("Valid options are: :return_partial, :raise_error")
      end
    end

    it "raises InvalidConfigurationError for max_attempts: 0" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "ZeroAttemptsAgent"
          model "gpt-4o"
          enable_continuation(max_attempts: 0)
        end
      }.to raise_error(RAAF::InvalidConfigurationError) do |error|
        expect(error.message).to include("max_attempts must be a positive integer")
      end
    end

    it "provides helpful error messages" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "HelpfulErrorAgent"
          model "gpt-4o"
          enable_continuation(output_format: :yaml)
        end
      }.to raise_error(RAAF::InvalidConfigurationError) do |error|
        expect(error.message).to include("Invalid output_format: yaml")
        expect(error.message).to include("Valid options are:")
      end
    end

    it "includes suggestion for similar valid options" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "SuggestionAgent"
          model "gpt-4o"
          enable_continuation(on_failure: :return_partials) # Note the 's'
        end
      }.to raise_error(RAAF::InvalidConfigurationError) do |error|
        expect(error.message).to include("Invalid on_failure mode: return_partials")
        expect(error.message).to include("Did you mean: :return_partial")
      end
    end
  end

  describe "Configuration Propagation" do
    it "stores configuration in agent class metadata" do
      expect(ConfiguredContinuationAgent._continuation_config).to be_a(Hash)
      expect(ConfiguredContinuationAgent._continuation_config[:max_attempts]).to eq(15)
    end

    it "makes configuration accessible to runner" do
      agent = ConfiguredContinuationAgent.new
      # Configuration should be accessible via class methods
      config = agent.class._continuation_config
      expect(config[:max_attempts]).to eq(15)
    end

    it "passes configuration to provider" do
      # This would be tested in integration tests with actual provider
      agent = ConfiguredContinuationAgent.new
      expect(agent.class._continuation_config).to include(
        max_attempts: 15,
        output_format: :csv,
        on_failure: :raise_error
      )
    end

    it "preserves configuration across agent instances" do
      agent1 = ConfiguredContinuationAgent.new
      agent2 = ConfiguredContinuationAgent.new

      expect(agent1.class._continuation_config).to eq(agent2.class._continuation_config)
    end

    it "allows different agents to have different configurations" do
      basic_config = BasicContinuationAgent._continuation_config
      configured_config = ConfiguredContinuationAgent._continuation_config

      expect(basic_config[:max_attempts]).to eq(10)
      expect(configured_config[:max_attempts]).to eq(15)

      expect(basic_config[:output_format]).to eq(:auto)
      expect(configured_config[:output_format]).to eq(:csv)
    end
  end

  describe "DSL Helper Methods" do
    it "provides enable_continuation method" do
      expect(RAAF::DSL::Agent).to respond_to(:enable_continuation)
    end

    it "supports method chaining (if desired)" do
      # Test if enable_continuation returns the class for chaining
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ChainedAgent"
        model "gpt-4o"
      end

      result = agent_class.enable_continuation(max_attempts: 5)
      expect(result).to eq(agent_class) # Should return class for chaining
    end

    it "works with other DSL methods" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "CompleteAgent"
          model "gpt-4o"
          temperature 0.7
          max_turns 5

          enable_continuation(max_attempts: 10)

          static_instructions "Multi-featured agent"

          schema do
            field :result, type: :string
          end
        end
      }.not_to raise_error
    end

    it "validates configuration when method called" do
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "ValidationAgent"
          model "gpt-4o"
          enable_continuation(output_format: :invalid)
        end
      }.to raise_error(RAAF::InvalidConfigurationError)
    end
  end

  describe "Integration with Existing Features" do
    it "continuation config does not interfere with other configurations" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "IntegrationAgent"
        model "gpt-4o"
        temperature 0.5
        max_turns 3

        enable_continuation(max_attempts: 8)

        schema do
          field :data, type: :array
        end
      end

      expect(agent_class._model).to eq("gpt-4o")
      expect(agent_class._temperature).to eq(0.5)
      expect(agent_class._max_turns).to eq(3)
      expect(agent_class._continuation_config[:max_attempts]).to eq(8)
    end

    it "works with context configuration" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ContextIntegrationAgent"
        model "gpt-4o"

        enable_continuation(output_format: :json)

        context do
          required :input_data
          optional batch_size: 100
        end
      end

      expect(agent_class._continuation_config[:output_format]).to eq(:json)
      expect(agent_class._context_config).not_to be_nil
    end

    it "can be used with tool configurations" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "ToolIntegrationAgent"
        model "gpt-4o"

        enable_continuation(on_failure: :raise_error)

        tool :web_search
      end

      expect(agent_class._continuation_config[:on_failure]).to eq(:raise_error)
      expect(agent_class._tools_config).not_to be_empty
    end
  end

  describe "No Continuation Configuration" do
    it "returns nil for agents without continuation enabled" do
      expect(NoContinuationAgent._continuation_config).to be_nil
    end

    it "does not affect agents that don't use continuation" do
      agent = NoContinuationAgent.new
      expect(agent.class._continuation_config).to be_nil
    end
  end
end