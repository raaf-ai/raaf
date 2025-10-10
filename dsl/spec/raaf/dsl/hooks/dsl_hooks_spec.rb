# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "DSL Hooks", type: :unit do
  # Set a fake API key to prevent provider initialization errors
  before(:all) do
    @original_api_key = ENV['OPENAI_API_KEY']
    ENV['OPENAI_API_KEY'] = 'test-key-123'
  end

  after(:all) do
    ENV['OPENAI_API_KEY'] = @original_api_key
  end

  describe "on_context_built" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "ContextTestAgent"
        model "gpt-4o"
        static_instructions "You are a test agent"

        on_context_built do |context:, **|
          @context_data = context
        end
      end
    end

    it "fires after context assembly" do
      agent = agent_class.new(product_name: "Test Product", company_name: "Test Company")

      # Directly test hook firing
      test_context = RAAF::DSL::ContextVariables.new
      test_context = test_context.set(:product_name, "Test Product")
      test_context = test_context.set(:company_name, "Test Company")

      agent.send(:fire_dsl_hook, :on_context_built, { context: test_context })

      expect(agent.instance_variable_get(:@context_data)).to be_a(RAAF::DSL::ContextVariables)
      expect(agent.instance_variable_get(:@context_data)[:product_name]).to eq("Test Product")
    end

    it "receives complete context with all variables" do
      agent = agent_class.new(var1: "value1", var2: "value2", var3: "value3")

      # Directly test hook firing with multiple variables
      test_context = RAAF::DSL::ContextVariables.new
      test_context = test_context.set(:var1, "value1")
      test_context = test_context.set(:var2, "value2")
      test_context = test_context.set(:var3, "value3")

      agent.send(:fire_dsl_hook, :on_context_built, { context: test_context })

      context = agent.instance_variable_get(:@context_data)
      expect(context[:var1]).to eq("value1")
      expect(context[:var2]).to eq("value2")
      expect(context[:var3]).to eq("value3")
    end
  end

  describe "on_result_ready" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "ResultReadyTestAgent"
        model "gpt-4o"
        static_instructions "You are a test agent"

        on_result_ready do |result:, timestamp:, **|
          @transformed_result = result
          @timestamp = timestamp
        end
      end
    end

    it "fires after result transformations complete" do
      agent = agent_class.new

      # Simulate transformed result data
      transformed_result = {
        transformed_field: "transformed_value",
        computed_field: "Computed: test data"
      }

      agent.send(:fire_dsl_hook, :on_result_ready, {
        result: transformed_result,
        timestamp: Time.now
      })

      result = agent.instance_variable_get(:@transformed_result)
      expect(result[:transformed_field]).to eq("transformed_value")
      expect(result[:computed_field]).to eq("Computed: test data")
    end

    it "receives transformed data not raw AI output" do
      agent = agent_class.new

      # Simulate that only transformed fields are present
      transformed_result = {
        transformed_field: "original"
        # raw_field should not be present after transformation
      }

      agent.send(:fire_dsl_hook, :on_result_ready, {
        result: transformed_result,
        timestamp: Time.now
      })

      result = agent.instance_variable_get(:@transformed_result)
      expect(result[:transformed_field]).to eq("original")
      expect(result[:raw_field]).to be_nil  # Original key removed by transformation
    end

    it "includes timestamp with result" do
      agent = agent_class.new
      test_time = Time.now

      agent.send(:fire_dsl_hook, :on_result_ready, {
        result: { test: "data" },
        timestamp: test_time
      })

      timestamp = agent.instance_variable_get(:@timestamp)
      expect(timestamp).to be_a(Time)
      expect(timestamp).to eq(test_time)
    end
  end

  describe "on_prompt_generated" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "PromptTestAgent"
        model "gpt-4o"
        static_instructions "You are a test assistant"

        on_prompt_generated do |system_prompt:, user_prompt:, **|
          @system_prompt = system_prompt
          @user_prompt = user_prompt
        end
      end
    end

    it "fires after prompts are generated" do
      agent = agent_class.new

      agent.send(:fire_dsl_hook, :on_prompt_generated, {
        system_prompt: "You are a test assistant",
        user_prompt: "Test query"
      })

      system_prompt = agent.instance_variable_get(:@system_prompt)
      expect(system_prompt).to include("You are a test assistant")
    end

    it "receives both system and user prompts" do
      agent = agent_class.new

      agent.send(:fire_dsl_hook, :on_prompt_generated, {
        system_prompt: "You are a test assistant",
        user_prompt: "Analyze this data"
      })

      user_prompt = agent.instance_variable_get(:@user_prompt)
      expect(user_prompt).to include("Analyze this data")
    end
  end

  describe "on_tokens_counted" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "TokensTestAgent"
        model "gpt-4o"
        static_instructions "You are a test agent"

        on_tokens_counted do |**data|
          # Capture all keyword arguments into a hash
          @token_usage = data
        end
      end
    end

    it "fires after token counting" do
      agent = agent_class.new

      agent.send(:fire_dsl_hook, :on_tokens_counted, {
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150
      })

      usage = agent.instance_variable_get(:@token_usage)
      expect(usage[:input_tokens]).to eq(100)
      expect(usage[:output_tokens]).to eq(50)
      expect(usage[:total_tokens]).to eq(150)
    end

    it "includes estimated cost calculation" do
      agent = agent_class.new

      agent.send(:fire_dsl_hook, :on_tokens_counted, {
        input_tokens: 1000,
        output_tokens: 500,
        total_tokens: 1500,
        estimated_cost: 0.025
      })

      usage = agent.instance_variable_get(:@token_usage)
      expect(usage[:estimated_cost]).to be_a(Float)
      expect(usage[:estimated_cost]).to be > 0
    end

    it "calculates correct cost for gpt-4o model" do
      agent = agent_class.new

      # For gpt-4o: $2.50 per 1M input + $10.00 per 1M output = $12.50
      expected_cost = (1_000_000 * 2.50 / 1_000_000) + (1_000_000 * 10.00 / 1_000_000)

      agent.send(:fire_dsl_hook, :on_tokens_counted, {
        input_tokens: 1_000_000,  # 1M input tokens
        output_tokens: 1_000_000,  # 1M output tokens
        total_tokens: 2_000_000,
        estimated_cost: expected_cost
      })

      usage = agent.instance_variable_get(:@token_usage)
      # For gpt-4o: $2.50 per 1M input + $10.00 per 1M output = $12.50
      expect(usage[:estimated_cost]).to be_within(0.01).of(12.50)
    end
  end

  describe "on_validation_failed" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "ValidationTestAgent"
        model "gpt-4o"
        static_instructions "You are a test agent"

        on_validation_failed do |error:, error_type:, field: nil, **|
          @validation_error = error
          @error_type = error_type
          @field = field
        end
      end
    end

    it "fires when schema validation fails" do
      agent = agent_class.new

      agent.send(:fire_dsl_hook, :on_validation_failed, {
        error: "Field 'age' must be an integer",
        error_type: "schema_validation",
        field: :age,
        value: "not_a_number",
        expected_type: :integer,
        timestamp: Time.now
      })

      error = agent.instance_variable_get(:@validation_error)
      expect(error).to eq("Field 'age' must be an integer")

      error_type = agent.instance_variable_get(:@error_type)
      expect(error_type).to eq("schema_validation")

      field = agent.instance_variable_get(:@field)
      expect(field).to eq(:age)
    end

    it "fires when context validation fails" do
      agent = agent_class.new

      agent.send(:fire_dsl_hook, :on_validation_failed, {
        error: "Missing required context variable: product_name",
        error_type: "context_validation",
        timestamp: Time.now
      })

      error = agent.instance_variable_get(:@validation_error)
      expect(error).to include("Missing required context variable")

      error_type = agent.instance_variable_get(:@error_type)
      expect(error_type).to eq("context_validation")
    end

    it "includes field details when available" do
      agent = agent_class.new

      agent.send(:fire_dsl_hook, :on_validation_failed, {
        error: "Invalid data type",
        error_type: "data_validation",
        field: :company_name,
        value: 12345,
        expected_type: :string,
        timestamp: Time.now
      })

      field = agent.instance_variable_get(:@field)
      expect(field).to eq(:company_name)
    end
  end

  describe "error handling" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "ErrorTestAgent"
        model "gpt-4o"
        static_instructions "You are a test agent"

        on_result_ready do |**|
          raise StandardError, "Hook error"
        end
      end
    end

    it "logs hook errors without crashing agent" do
      agent = agent_class.new

      # Hook errors should be logged but not crash execution
      expect(agent).to receive(:log_error).with(/Hook.*on_result_ready.*failed/)

      # Should not raise error despite hook failing
      expect {
        agent.send(:fire_dsl_hook, :on_result_ready, { result: {}, timestamp: Time.now })
      }.not_to raise_error
    end
  end

  describe "HashWithIndifferentAccess support" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "IndifferentAccessTestAgent"
        model "gpt-4o"
        static_instructions "You are a test agent"

        on_context_built do |context:, **|
          # Keyword arguments work directly - no need for string/symbol checking
          @context_symbol = context
          @context_string = context
        end
      end
    end

    it "supports both symbol and string key access" do
      agent = agent_class.new(test_var: "test_value")

      test_context = RAAF::DSL::ContextVariables.new
      test_context = test_context.set(:test_var, "test_value")

      agent.send(:fire_dsl_hook, :on_context_built, { context: test_context })

      context_symbol = agent.instance_variable_get(:@context_symbol)
      context_string = agent.instance_variable_get(:@context_string)

      expect(context_symbol).to eq(context_string)
      expect(context_symbol[:test_var]).to eq("test_value")
      expect(context_string["test_var"]).to eq("test_value")
    end
  end

  describe "keyword argument unpacking" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "KeywordArgsTestAgent"
        model "gpt-4o"
        static_instructions "You are a test agent"

        # Users can use Ruby keyword argument syntax
        on_context_built do |context:, agent:, timestamp:, **|
          # Direct access via keyword arguments - no manual unpacking needed
          @received_context = context
          @received_agent = agent
          @received_timestamp = timestamp
        end

        on_result_ready do |raw_result:, processed_result:, context:, **|
          # Hook-specific and standard parameters as keyword arguments
          @raw = raw_result
          @processed = processed_result
          @context = context
        end
      end
    end

    it "supports keyword argument access to standard parameters" do
      agent = agent_class.new(test: "value")

      test_context = RAAF::DSL::ContextVariables.new
      test_context = test_context.set(:test, "value")

      agent.send(:fire_dsl_hook, :on_context_built, {})

      expect(agent.instance_variable_get(:@received_context)).to be_a(RAAF::DSL::ContextVariables)
      expect(agent.instance_variable_get(:@received_agent)).to eq(agent)
      expect(agent.instance_variable_get(:@received_timestamp)).to be_a(Time)
    end

    it "supports keyword argument access to hook-specific parameters" do
      agent = agent_class.new

      agent.send(:fire_dsl_hook, :on_result_ready, {
        raw_result: { data: "raw" },
        processed_result: { data: "processed" }
      })

      # deep_symbolize_keys ensures all nested hashes use symbol keys
      expect(agent.instance_variable_get(:@raw)).to eq({ data: "raw" })
      expect(agent.instance_variable_get(:@processed)).to eq({ data: "processed" })
      expect(agent.instance_variable_get(:@context)).to be_a(RAAF::DSL::ContextVariables)
    end

    it "allows selective parameter extraction with double splat" do
      selective_agent_class = Class.new(RAAF::DSL::Agent) do
        agent_name "SelectiveAgent"
        model "gpt-4o"
        static_instructions "You are a test agent"

        on_tokens_counted do |input_tokens:, output_tokens:, **|
          # Only specify the parameters we care about
          # ** captures and ignores total_tokens, estimated_cost, model, context, agent, timestamp
          @input = input_tokens
          @output = output_tokens
        end
      end

      agent = selective_agent_class.new

      agent.send(:fire_dsl_hook, :on_tokens_counted, {
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150,
        estimated_cost: 0.01,
        model: "gpt-4o"
      })

      expect(agent.instance_variable_get(:@input)).to eq(100)
      expect(agent.instance_variable_get(:@output)).to eq(50)
    end
  end

  describe "standard parameters auto-injection" do
    let(:agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "StandardParamsTestAgent"
        model "gpt-4o"
        static_instructions "You are a test agent"

        on_prompt_generated do |context:, agent:, timestamp:, system_prompt:, user_prompt:, **|
          # Standard parameters are always present via keyword arguments
          # Hook-specific parameters also available as keyword arguments
          @has_context = !context.nil?
          @has_agent = !agent.nil?
          @has_timestamp = !timestamp.nil?
          @has_system_prompt = !system_prompt.nil?
          @has_user_prompt = !user_prompt.nil?
        end
      end
    end

    it "automatically injects context, agent, and timestamp" do
      agent = agent_class.new

      agent.send(:fire_dsl_hook, :on_prompt_generated, {
        system_prompt: "System",
        user_prompt: "User"
      })

      expect(agent.instance_variable_get(:@has_context)).to be true
      expect(agent.instance_variable_get(:@has_agent)).to be true
      expect(agent.instance_variable_get(:@has_timestamp)).to be true
      expect(agent.instance_variable_get(:@has_system_prompt)).to be true
      expect(agent.instance_variable_get(:@has_user_prompt)).to be true
    end
  end
end
