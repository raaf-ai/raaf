# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Config::ModelConfig do
  describe "#initialize" do
    it "initializes with default values" do
      config = described_class.new

      expect(config.temperature).to be_nil
      expect(config.max_tokens).to be_nil
      expect(config.model).to be_nil
      expect(config.top_p).to be_nil
      expect(config.stop).to be_nil
      expect(config.frequency_penalty).to be_nil
      expect(config.presence_penalty).to be_nil
      expect(config.user).to be_nil
      expect(config.stream).to be false
      expect(config.model_kwargs).to eq({})
      expect(config.previous_response_id).to be_nil
      expect(config.parallel_tool_calls).to be_nil
    end

    it "initializes with provided values" do
      config = described_class.new(
        temperature: 0.7,
        max_tokens: 1000,
        model: "gpt-4o",
        top_p: 0.9,
        stop: ["END", "STOP"],
        frequency_penalty: 0.5,
        presence_penalty: 0.3,
        user: "user123",
        stream: true,
        previous_response_id: "response-456",
        parallel_tool_calls: false
      )

      expect(config.temperature).to eq(0.7)
      expect(config.max_tokens).to eq(1000)
      expect(config.model).to eq("gpt-4o")
      expect(config.top_p).to eq(0.9)
      expect(config.stop).to eq(["END", "STOP"])
      expect(config.frequency_penalty).to eq(0.5)
      expect(config.presence_penalty).to eq(0.3)
      expect(config.user).to eq("user123")
      expect(config.stream).to be true
      expect(config.previous_response_id).to eq("response-456")
      expect(config.parallel_tool_calls).to be false
    end

    it "accepts additional model kwargs" do
      config = described_class.new(
        temperature: 0.5,
        custom_param: "custom_value",
        another_param: 42
      )

      expect(config.temperature).to eq(0.5)
      expect(config.model_kwargs).to eq(custom_param: "custom_value", another_param: 42)
    end

    it "handles edge case values" do
      config = described_class.new(
        temperature: 0.0,
        max_tokens: 1,
        frequency_penalty: -2.0,
        presence_penalty: 2.0
      )

      expect(config.temperature).to eq(0.0)
      expect(config.max_tokens).to eq(1)
      expect(config.frequency_penalty).to eq(-2.0)
      expect(config.presence_penalty).to eq(2.0)
    end
  end

  describe "#to_model_params" do
    it "converts basic parameters to model params" do
      config = described_class.new(
        temperature: 0.8,
        max_tokens: 500,
        stream: true
      )

      params = config.to_model_params

      expect(params).to eq(
        temperature: 0.8,
        max_tokens: 500,
        stream: true
      )
    end

    it "excludes nil and falsy values" do
      config = described_class.new(
        temperature: 0.7,
        max_tokens: nil,
        model: "gpt-4o",
        top_p: nil,
        stream: false  # false is falsy, so excluded
      )

      params = config.to_model_params

      expect(params).to eq(
        temperature: 0.7
      )
      expect(params).not_to include(:max_tokens, :top_p, :model, :stream)
    end

    it "includes all non-nil and truthy standard parameters" do
      config = described_class.new(
        temperature: 0.5,
        max_tokens: 1000,
        top_p: 0.9,
        stop: ["STOP"],
        frequency_penalty: 0.1,
        presence_penalty: 0.2,
        user: "user456",
        stream: true,
        parallel_tool_calls: true  # Must be truthy to be included
      )

      params = config.to_model_params

      expect(params).to eq(
        temperature: 0.5,
        max_tokens: 1000,
        top_p: 0.9,
        stop: ["STOP"],
        frequency_penalty: 0.1,
        presence_penalty: 0.2,
        user: "user456",
        stream: true,
        parallel_tool_calls: true
      )
    end

    it "includes model_kwargs in output" do
      config = described_class.new(
        temperature: 0.7,
        custom_param: "value1",
        another_param: 123
      )

      params = config.to_model_params

      expect(params).to eq(
        temperature: 0.7,
        custom_param: "value1",
        another_param: 123
      )
    end

    it "handles empty model_kwargs" do
      config = described_class.new(temperature: 0.5)
      config.instance_variable_set(:@model_kwargs, {})

      params = config.to_model_params

      expect(params).to eq(
        temperature: 0.5
      )
    end

    it "handles nil model_kwargs" do
      config = described_class.new(temperature: 0.5)
      config.instance_variable_set(:@model_kwargs, nil)

      params = config.to_model_params

      expect(params).to eq(
        temperature: 0.5
      )
    end

    it "excludes model parameter from API params" do
      config = described_class.new(
        model: "gpt-4o",
        temperature: 0.7
      )

      params = config.to_model_params

      # Model is stored but not included in API parameters
      expect(config.model).to eq("gpt-4o")
      expect(params).not_to include(:model)
      expect(params).to include(temperature: 0.7)
    end

    it "excludes previous_response_id parameter from API params" do
      config = described_class.new(
        previous_response_id: "resp-123",
        temperature: 0.7
      )

      params = config.to_model_params

      # previous_response_id is stored but not included in model API parameters
      expect(config.previous_response_id).to eq("resp-123")
      expect(params).not_to include(:previous_response_id)
      expect(params).to include(temperature: 0.7)
    end

    it "excludes falsy stream parameter" do
      config = described_class.new(stream: false)

      params = config.to_model_params

      # false is falsy, so stream is excluded
      expect(params).to eq({})
    end

    it "includes zero values for numeric parameters" do
      config = described_class.new(
        temperature: 0.0,
        frequency_penalty: 0.0,
        presence_penalty: 0.0
      )

      params = config.to_model_params

      # Zero is truthy in Ruby, so these should be included
      expect(params).to eq(
        temperature: 0.0,
        frequency_penalty: 0.0,
        presence_penalty: 0.0
      )
    end
  end

  describe "#merge" do
    let(:base_config) do
      described_class.new(
        temperature: 0.5,
        max_tokens: 1000,
        model: "gpt-4",
        stream: false,
        custom_param: "base_value"
      )
    end

    it "merges with another config, other taking precedence" do
      other_config = described_class.new(
        temperature: 0.8,
        top_p: 0.9,
        model: "gpt-4o"
      )

      merged = base_config.merge(other_config)

      expect(merged.temperature).to eq(0.8)  # Overridden
      expect(merged.max_tokens).to eq(1000)  # From base
      expect(merged.model).to eq("gpt-4o")   # Overridden
      expect(merged.top_p).to eq(0.9)        # New from other
      expect(merged.stream).to be false      # From base
    end

    it "returns self when merging with nil" do
      merged = base_config.merge(nil)

      expect(merged).to be(base_config)
    end

    it "preserves base values when other has nil values" do
      other_config = described_class.new(
        temperature: nil,
        max_tokens: 2000,
        model: nil
      )

      merged = base_config.merge(other_config)

      expect(merged.temperature).to eq(0.5)    # Preserved from base (other is nil)
      expect(merged.max_tokens).to eq(2000)    # Overridden by other
      expect(merged.model).to eq("gpt-4")      # Preserved from base (other is nil)
    end

    it "handles stream parameter correctly" do
      # Test when other.stream is explicitly false
      other_config = described_class.new(stream: false)
      base_config_true = described_class.new(stream: true)

      merged = base_config_true.merge(other_config)
      expect(merged.stream).to be false

      # Test when other.stream is explicitly true
      other_config_true = described_class.new(stream: true)
      merged_true = base_config.merge(other_config_true)
      expect(merged_true.stream).to be true

      # Test when other.stream is nil (should preserve base)
      other_config_nil = described_class.new(temperature: 0.7)
      merged_nil = base_config.merge(other_config_nil)
      expect(merged_nil.stream).to eq(base_config.stream)
    end

    it "merges model_kwargs correctly" do
      other_config = described_class.new(
        temperature: 0.9,
        custom_param: "other_value",
        new_param: "new_value"
      )

      merged = base_config.merge(other_config)

      expect(merged.temperature).to eq(0.9)
      expect(merged.model_kwargs).to eq(
        custom_param: "other_value",  # Overridden
        new_param: "new_value"        # Added
      )
    end

    it "handles nil model_kwargs in other config" do
      other_config = described_class.new(temperature: 0.9)
      other_config.instance_variable_set(:@model_kwargs, nil)

      merged = base_config.merge(other_config)

      expect(merged.model_kwargs).to eq(custom_param: "base_value")
    end

    it "creates a new instance, not modifying originals" do
      other_config = described_class.new(temperature: 0.9)

      merged = base_config.merge(other_config)

      expect(merged).not_to be(base_config)
      expect(merged).not_to be(other_config)
      expect(base_config.temperature).to eq(0.5)  # Original unchanged
    end

    it "merges all parameters correctly" do
      other_config = described_class.new(
        temperature: 1.0,
        max_tokens: 2000,
        model: "gpt-4o",
        top_p: 0.8,
        stop: ["NEW_STOP"],
        frequency_penalty: 1.0,
        presence_penalty: 0.8,
        user: "new_user",
        stream: true,
        previous_response_id: "new-response-123",
        parallel_tool_calls: true,
        extra_param: "extra_value"
      )

      merged = base_config.merge(other_config)

      expect(merged.temperature).to eq(1.0)
      expect(merged.max_tokens).to eq(2000)
      expect(merged.model).to eq("gpt-4o")
      expect(merged.top_p).to eq(0.8)
      expect(merged.stop).to eq(["NEW_STOP"])
      expect(merged.frequency_penalty).to eq(1.0)
      expect(merged.presence_penalty).to eq(0.8)
      expect(merged.user).to eq("new_user")
      expect(merged.stream).to be true
      expect(merged.previous_response_id).to eq("new-response-123")
      # parallel_tool_calls is not handled by merge method
      expect(merged.parallel_tool_calls).to be_nil
      expect(merged.model_kwargs).to include(
        custom_param: "base_value",
        extra_param: "extra_value"
      )
    end
  end

  describe "#to_h" do
    it "converts to hash with all parameters" do
      config = described_class.new(
        temperature: 0.7,
        max_tokens: 1000,
        model: "gpt-4o",
        top_p: 0.9,
        stop: ["STOP"],
        frequency_penalty: 0.1,
        presence_penalty: 0.2,
        user: "user123",
        stream: true,
        previous_response_id: "resp-456",
        custom_param: "value"
      )

      hash = config.to_h

      expect(hash).to eq(
        temperature: 0.7,
        max_tokens: 1000,
        model: "gpt-4o",
        top_p: 0.9,
        stop: ["STOP"],
        frequency_penalty: 0.1,
        presence_penalty: 0.2,
        user: "user123",
        stream: true,
        model_kwargs: { custom_param: "value" },
        previous_response_id: "resp-456"
      )
    end

    it "includes nil values in hash" do
      config = described_class.new

      hash = config.to_h

      expect(hash).to eq(
        temperature: nil,
        max_tokens: nil,
        model: nil,
        top_p: nil,
        stop: nil,
        frequency_penalty: nil,
        presence_penalty: nil,
        user: nil,
        stream: false,
        model_kwargs: {},
        previous_response_id: nil
      )
    end

    it "does not include parallel_tool_calls in to_h output" do
      config = described_class.new(parallel_tool_calls: true)

      hash = config.to_h

      expect(hash).not_to include(:parallel_tool_calls)
    end
  end

  describe "attribute accessors" do
    let(:config) { described_class.new }

    it "allows setting and getting temperature" do
      config.temperature = 1.5
      expect(config.temperature).to eq(1.5)
    end

    it "allows setting and getting max_tokens" do
      config.max_tokens = 2000
      expect(config.max_tokens).to eq(2000)
    end

    it "allows setting and getting model" do
      config.model = "gpt-3.5-turbo"
      expect(config.model).to eq("gpt-3.5-turbo")
    end

    it "allows setting and getting all parameters" do
      config.top_p = 0.95
      config.stop = ["END"]
      config.frequency_penalty = 1.0
      config.presence_penalty = -1.0
      config.user = "test_user"
      config.stream = true
      config.model_kwargs = { test: "value" }
      config.previous_response_id = "prev-123"
      config.parallel_tool_calls = true

      expect(config.top_p).to eq(0.95)
      expect(config.stop).to eq(["END"])
      expect(config.frequency_penalty).to eq(1.0)
      expect(config.presence_penalty).to eq(-1.0)
      expect(config.user).to eq("test_user")
      expect(config.stream).to be true
      expect(config.model_kwargs).to eq({ test: "value" })
      expect(config.previous_response_id).to eq("prev-123")
      expect(config.parallel_tool_calls).to be true
    end
  end

  describe "integration scenarios" do
    it "supports typical chat completion scenario" do
      config = described_class.new(
        model: "gpt-4o",
        temperature: 0.7,
        max_tokens: 1000,
        stream: false
      )

      api_params = config.to_model_params

      expect(api_params).to eq(
        temperature: 0.7,
        max_tokens: 1000
      )
      # stream: false is excluded because false is falsy
      expect(api_params).not_to include(:model) # Model handled separately
    end

    it "supports streaming scenario with custom parameters" do
      config = described_class.new(
        temperature: 0.9,
        stream: true,
        stop: ["Human:", "AI:"],
        presence_penalty: 0.1,
        custom_engine: "davinci"
      )

      api_params = config.to_model_params

      expect(api_params).to eq(
        temperature: 0.9,
        stream: true,
        stop: ["Human:", "AI:"],
        presence_penalty: 0.1,
        custom_engine: "davinci"
      )
    end

    it "supports configuration inheritance and override" do
      base = described_class.new(
        temperature: 0.5,
        max_tokens: 500,
        model: "gpt-4"
      )

      specialized = base.merge(described_class.new(
        temperature: 0.9,
        stream: true
      ))

      expect(specialized.temperature).to eq(0.9)
      expect(specialized.max_tokens).to eq(500)  # Inherited
      expect(specialized.model).to eq("gpt-4")   # Inherited
      expect(specialized.stream).to be true      # New
    end
  end
end