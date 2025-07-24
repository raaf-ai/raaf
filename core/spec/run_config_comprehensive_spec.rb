# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::RunConfig do
  describe "#initialize" do
    context "with no parameters" do
      let(:config) { described_class.new }

      it "creates config with default model config" do
        expect(config.model).to be_a(RAAF::Config::ModelConfig)
        expect(config.model.temperature).to be_nil
        expect(config.model.max_tokens).to be_nil
      end

      it "creates config with default tracing config" do
        expect(config.tracing).to be_a(RAAF::Config::TracingConfig)
        expect(config.tracing.trace_id).to be_nil
        expect(config.tracing.tracing_disabled).to be false
      end

      it "creates config with default execution config" do
        expect(config.execution).to be_a(RAAF::Config::ExecutionConfig)
        expect(config.execution.max_turns).to be_nil
        expect(config.execution.hooks).to be_nil
      end
    end

    context "with config objects" do
      let(:model_config) { RAAF::Config::ModelConfig.new(temperature: 0.7) }
      let(:tracing_config) { RAAF::Config::TracingConfig.new(trace_id: "custom-123") }
      let(:execution_config) { RAAF::Config::ExecutionConfig.new(max_turns: 10) }

      let(:config) do
        described_class.new(
          model: model_config,
          tracing: tracing_config,
          execution: execution_config
        )
      end

      it "uses provided model config" do
        expect(config.model).to eq(model_config)
        expect(config.temperature).to eq(0.7)
      end

      it "uses provided tracing config" do
        expect(config.tracing).to eq(tracing_config)
        expect(config.trace_id).to eq("custom-123")
      end

      it "uses provided execution config" do
        expect(config.execution).to eq(execution_config)
        expect(config.max_turns).to eq(10)
      end
    end

    context "with backwards-compatible parameters" do
      let(:config) do
        described_class.new(
          temperature: 0.8,
          max_tokens: 1000,
          trace_id: "trace-456",
          max_turns: 15,
          metadata: { user: "test" }
        )
      end

      it "extracts model parameters" do
        expect(config.temperature).to eq(0.8)
        expect(config.max_tokens).to eq(1000)
      end

      it "extracts tracing parameters" do
        expect(config.trace_id).to eq("trace-456")
        expect(config.metadata).to eq({ user: "test" })
      end

      it "extracts execution parameters" do
        expect(config.max_turns).to eq(15)
      end
    end

    context "with mixed config objects and parameters" do
      let(:model_config) { RAAF::Config::ModelConfig.new(temperature: 0.5) }

      let(:config) do
        described_class.new(
          model: model_config,
          trace_id: "mixed-123",
          max_turns: 20
        )
      end

      it "uses provided model config" do
        expect(config.model).to eq(model_config)
        expect(config.temperature).to eq(0.5)
      end

      it "creates tracing config from parameters" do
        expect(config.trace_id).to eq("mixed-123")
      end

      it "creates execution config from parameters" do
        expect(config.max_turns).to eq(20)
      end
    end

    context "with model_kwargs parameter" do
      let(:config) do
        described_class.new(
          temperature: 0.9,
          model_kwargs: {
            top_p: 0.95,
            frequency_penalty: 0.5
          }
        )
      end

      it "merges model_kwargs into model config" do
        expect(config.model.temperature).to eq(0.9)
        expect(config.model.top_p).to eq(0.95)
        expect(config.model.frequency_penalty).to eq(0.5)
      end
    end
  end

  describe "model config delegation" do
    let(:config) { described_class.new }

    describe "#temperature" do
      it "delegates read to model config" do
        config.model.temperature = 0.7
        expect(config.temperature).to eq(0.7)
      end

      it "delegates write to model config" do
        config.temperature = 0.8
        expect(config.model.temperature).to eq(0.8)
      end
    end

    describe "#max_tokens" do
      it "delegates read to model config" do
        config.model.max_tokens = 500
        expect(config.max_tokens).to eq(500)
      end

      it "delegates write to model config" do
        config.max_tokens = 1000
        expect(config.model.max_tokens).to eq(1000)
      end
    end

    describe "#stream" do
      it "delegates read to model config" do
        config.model.stream = true
        expect(config.stream).to be true
      end

      it "delegates write to model config" do
        config.stream = false
        expect(config.model.stream).to be false
      end
    end

    describe "#previous_response_id" do
      it "delegates read to model config" do
        config.model.previous_response_id = "resp-123"
        expect(config.previous_response_id).to eq("resp-123")
      end

      it "delegates write to model config" do
        config.previous_response_id = "resp-456"
        expect(config.model.previous_response_id).to eq("resp-456")
      end
    end
  end

  describe "tracing config delegation" do
    let(:config) { described_class.new }

    describe "#trace_id" do
      it "delegates read to tracing config" do
        config.tracing.trace_id = "trace-789"
        expect(config.trace_id).to eq("trace-789")
      end

      it "delegates write to tracing config" do
        config.trace_id = "trace-999"
        expect(config.tracing.trace_id).to eq("trace-999")
      end
    end

    describe "#tracing_disabled" do
      it "delegates read to tracing config" do
        config.tracing.tracing_disabled = true
        expect(config.tracing_disabled).to be true
      end

      it "delegates write to tracing config" do
        config.tracing_disabled = false
        expect(config.tracing.tracing_disabled).to be false
      end
    end

    describe "#trace_include_sensitive_data" do
      it "delegates read to tracing config" do
        config.tracing.trace_include_sensitive_data = true
        expect(config.trace_include_sensitive_data).to be true
      end

      it "delegates write to tracing config" do
        config.trace_include_sensitive_data = false
        expect(config.tracing.trace_include_sensitive_data).to be false
      end
    end

    describe "#metadata" do
      it "delegates read to tracing config" do
        config.tracing.metadata = { key: "value" }
        expect(config.metadata).to eq({ key: "value" })
      end

      it "delegates write to tracing config" do
        config.metadata = { new: "data" }
        expect(config.tracing.metadata).to eq({ new: "data" })
      end
    end

    describe "#workflow_name" do
      it "delegates read to tracing config" do
        config.tracing.workflow_name = "test-workflow"
        expect(config.workflow_name).to eq("test-workflow")
      end

      it "delegates write to tracing config" do
        config.workflow_name = "new-workflow"
        expect(config.tracing.workflow_name).to eq("new-workflow")
      end
    end

    describe "#group_id" do
      it "delegates read to tracing config" do
        config.tracing.group_id = "group-123"
        expect(config.group_id).to eq("group-123")
      end

      it "delegates write to tracing config" do
        config.group_id = "group-456"
        expect(config.tracing.group_id).to eq("group-456")
      end
    end
  end

  describe "execution config delegation" do
    let(:config) { described_class.new }

    describe "#max_turns" do
      it "delegates read to execution config" do
        config.execution.max_turns = 25
        expect(config.max_turns).to eq(25)
      end

      it "delegates write to execution config" do
        config.max_turns = 30
        expect(config.execution.max_turns).to eq(30)
      end
    end

    describe "#hooks" do
      let(:hooks) { double("hooks") }

      it "delegates read to execution config" do
        config.execution.hooks = hooks
        expect(config.hooks).to eq(hooks)
      end

      it "delegates write to execution config" do
        config.hooks = hooks
        expect(config.execution.hooks).to eq(hooks)
      end
    end

    describe "#input_guardrails" do
      let(:guardrails) { [double("guardrail")] }

      it "delegates read to execution config" do
        config.execution.input_guardrails = guardrails
        expect(config.input_guardrails).to eq(guardrails)
      end

      it "delegates write to execution config" do
        config.input_guardrails = guardrails
        expect(config.execution.input_guardrails).to eq(guardrails)
      end
    end

    describe "#output_guardrails" do
      let(:guardrails) { [double("guardrail")] }

      it "delegates read to execution config" do
        config.execution.output_guardrails = guardrails
        expect(config.output_guardrails).to eq(guardrails)
      end

      it "delegates write to execution config" do
        config.output_guardrails = guardrails
        expect(config.execution.output_guardrails).to eq(guardrails)
      end
    end

    describe "#context" do
      let(:context) { double("context") }

      it "delegates read to execution config" do
        config.execution.context = context
        expect(config.context).to eq(context)
      end

      it "delegates write to execution config" do
        config.context = context
        expect(config.execution.context).to eq(context)
      end
    end

    describe "#session" do
      let(:session) { double("session") }

      it "delegates read to execution config" do
        config.execution.session = session
        expect(config.session).to eq(session)
      end

      it "delegates write to execution config" do
        config.session = session
        expect(config.execution.session).to eq(session)
      end
    end
  end

  describe "#to_model_params" do
    let(:config) do
      described_class.new(
        temperature: 0.7,
        max_tokens: 1000,
        top_p: 0.95
      )
    end

    it "delegates to model config" do
      expect(config.model).to receive(:to_model_params).and_return({ temperature: 0.7 })
      expect(config.to_model_params).to eq({ temperature: 0.7 })
    end

    it "returns model parameters hash" do
      params = config.to_model_params
      expect(params).to be_a(Hash)
      expect(params[:temperature]).to eq(0.7)
      expect(params[:max_tokens]).to eq(1000)
    end
  end

  describe "#merge" do
    let(:config1) do
      described_class.new(
        temperature: 0.7,
        trace_id: "trace-1",
        max_turns: 10
      )
    end

    let(:config2) do
      described_class.new(
        temperature: 0.9,
        metadata: { user: "test" },
        hooks: double("hooks")
      )
    end

    it "returns self when other is nil" do
      expect(config1.merge(nil)).to eq(config1)
    end

    it "creates new config with merged values" do
      merged = config1.merge(config2)

      expect(merged).to be_a(described_class)
      expect(merged).not_to eq(config1)
      expect(merged).not_to eq(config2)
    end

    it "merges model configs with other taking precedence" do
      merged = config1.merge(config2)
      expect(merged.temperature).to eq(0.9)
    end

    it "merges tracing configs" do
      merged = config1.merge(config2)
      expect(merged.trace_id).to eq("trace-1") # config2 doesn't have trace_id
      expect(merged.metadata).to eq({ user: "test" })
    end

    it "merges execution configs" do
      merged = config1.merge(config2)
      expect(merged.max_turns).to eq(10) # config2 doesn't have max_turns
      expect(merged.hooks).to eq(config2.hooks)
    end
  end

  describe "#to_h" do
    let(:config) do
      described_class.new(
        temperature: 0.8,
        max_tokens: 500,
        trace_id: "test-trace",
        tracing_disabled: true,
        max_turns: 20,
        metadata: { app: "test" }
      )
    end

    it "returns complete configuration as hash" do
      hash = config.to_h

      expect(hash).to be_a(Hash)
      expect(hash[:temperature]).to eq(0.8)
      expect(hash[:max_tokens]).to eq(500)
      expect(hash[:trace_id]).to eq("test-trace")
      expect(hash[:tracing_disabled]).to be true
      expect(hash[:max_turns]).to eq(20)
      expect(hash[:metadata]).to eq({ app: "test" })
    end

    it "merges all sub-config hashes" do
      model_hash = { temperature: 0.8 }
      tracing_hash = { trace_id: "test" }
      execution_hash = { max_turns: 20 }

      allow(config.model).to receive(:to_h).and_return(model_hash)
      allow(config.tracing).to receive(:to_h).and_return(tracing_hash)
      allow(config.execution).to receive(:to_h).and_return(execution_hash)

      expect(config.to_h).to eq(model_hash.merge(tracing_hash).merge(execution_hash))
    end
  end

  describe "#with_configs" do
    let(:original) do
      described_class.new(
        temperature: 0.7,
        trace_id: "original",
        max_turns: 10
      )
    end

    it "creates copy with same configs when no changes" do
      copy = original.with_configs

      expect(copy).not_to eq(original)
      expect(copy.model).to eq(original.model)
      expect(copy.tracing).to eq(original.tracing)
      expect(copy.execution).to eq(original.execution)
    end

    it "replaces model config when provided" do
      new_model = RAAF::Config::ModelConfig.new(temperature: 0.9)
      copy = original.with_configs(model: new_model)

      expect(copy.model).to eq(new_model)
      expect(copy.tracing).to eq(original.tracing)
      expect(copy.execution).to eq(original.execution)
      expect(copy.temperature).to eq(0.9)
    end

    it "replaces tracing config when provided" do
      new_tracing = RAAF::Config::TracingConfig.new(trace_id: "new-trace")
      copy = original.with_configs(tracing: new_tracing)

      expect(copy.model).to eq(original.model)
      expect(copy.tracing).to eq(new_tracing)
      expect(copy.execution).to eq(original.execution)
      expect(copy.trace_id).to eq("new-trace")
    end

    it "replaces execution config when provided" do
      new_execution = RAAF::Config::ExecutionConfig.new(max_turns: 25)
      copy = original.with_configs(execution: new_execution)

      expect(copy.model).to eq(original.model)
      expect(copy.tracing).to eq(original.tracing)
      expect(copy.execution).to eq(new_execution)
      expect(copy.max_turns).to eq(25)
    end

    it "replaces multiple configs at once" do
      new_model = RAAF::Config::ModelConfig.new(temperature: 0.9)
      new_execution = RAAF::Config::ExecutionConfig.new(max_turns: 30)

      copy = original.with_configs(model: new_model, execution: new_execution)

      expect(copy.model).to eq(new_model)
      expect(copy.tracing).to eq(original.tracing)
      expect(copy.execution).to eq(new_execution)
    end
  end

  describe "parameter extraction" do
    describe "#extract_model_params" do
      let(:config) { described_class.new }

      it "extracts model-specific parameters" do
        kwargs = {
          temperature: 0.7,
          max_tokens: 1000,
          model: "gpt-4",
          top_p: 0.95,
          stop: ["\n"],
          frequency_penalty: 0.5,
          presence_penalty: 0.5,
          user: "test-user",
          stream: true,
          previous_response_id: "resp-123",
          parallel_tool_calls: false,
          # Non-model params
          trace_id: "trace-123",
          max_turns: 10
        }

        params = config.send(:extract_model_params, kwargs)

        expect(params[:temperature]).to eq(0.7)
        expect(params[:max_tokens]).to eq(1000)
        expect(params[:model]).to eq("gpt-4")
        expect(params[:top_p]).to eq(0.95)
        expect(params[:stop]).to eq(["\n"])
        expect(params[:frequency_penalty]).to eq(0.5)
        expect(params[:presence_penalty]).to eq(0.5)
        expect(params[:user]).to eq("test-user")
        expect(params[:stream]).to be true
        expect(params[:previous_response_id]).to eq("resp-123")
        expect(params[:parallel_tool_calls]).to be false

        # Should not include non-model params
        expect(params).not_to have_key(:trace_id)
        expect(params).not_to have_key(:max_turns)
      end

      it "merges model_kwargs when present" do
        kwargs = {
          temperature: 0.7,
          model_kwargs: {
            top_p: 0.9,
            custom_param: "value"
          }
        }

        params = config.send(:extract_model_params, kwargs)

        expect(params[:temperature]).to eq(0.7)
        expect(params[:top_p]).to eq(0.9)
        expect(params[:custom_param]).to eq("value")
      end
    end

    describe "#extract_tracing_params" do
      let(:config) { described_class.new }

      it "extracts tracing-specific parameters" do
        kwargs = {
          trace_id: "trace-456",
          group_id: "group-789",
          metadata: { user: "test" },
          tracing_disabled: true,
          trace_include_sensitive_data: false,
          workflow_name: "test-workflow",
          # Non-tracing params
          temperature: 0.7,
          max_turns: 10
        }

        params = config.send(:extract_tracing_params, kwargs)

        expect(params[:trace_id]).to eq("trace-456")
        expect(params[:group_id]).to eq("group-789")
        expect(params[:metadata]).to eq({ user: "test" })
        expect(params[:tracing_disabled]).to be true
        expect(params[:trace_include_sensitive_data]).to be false
        expect(params[:workflow_name]).to eq("test-workflow")

        # Should not include non-tracing params
        expect(params).not_to have_key(:temperature)
        expect(params).not_to have_key(:max_turns)
      end
    end

    describe "#extract_execution_params" do
      let(:config) { described_class.new }
      let(:hooks) { double("hooks") }
      let(:input_guardrails) { [double("input_guardrail")] }
      let(:output_guardrails) { [double("output_guardrail")] }
      let(:context) { double("context") }
      let(:session) { double("session") }

      it "extracts execution-specific parameters" do
        kwargs = {
          max_turns: 15,
          hooks: hooks,
          input_guardrails: input_guardrails,
          output_guardrails: output_guardrails,
          context: context,
          session: session,
          # Non-execution params
          temperature: 0.7,
          trace_id: "trace-123"
        }

        params = config.send(:extract_execution_params, kwargs)

        expect(params[:max_turns]).to eq(15)
        expect(params[:hooks]).to eq(hooks)
        expect(params[:input_guardrails]).to eq(input_guardrails)
        expect(params[:output_guardrails]).to eq(output_guardrails)
        expect(params[:context]).to eq(context)
        expect(params[:session]).to eq(session)

        # Should not include non-execution params
        expect(params).not_to have_key(:temperature)
        expect(params).not_to have_key(:trace_id)
      end
    end
  end

  describe "edge cases" do
    it "handles empty initialization" do
      config = described_class.new

      expect(config.model).not_to be_nil
      expect(config.tracing).not_to be_nil
      expect(config.execution).not_to be_nil
    end

    it "handles nil values in delegation" do
      config = described_class.new

      config.temperature = nil
      expect(config.temperature).to be_nil

      config.trace_id = nil
      expect(config.trace_id).to be_nil

      config.max_turns = nil
      expect(config.max_turns).to be_nil
    end

    it "handles all parameter types together" do
      config = described_class.new(
        # Model params
        temperature: 0.7,
        max_tokens: 1000,
        top_p: 0.95,
        stream: true,
        # Tracing params
        trace_id: "full-trace",
        group_id: "full-group",
        metadata: { full: true },
        tracing_disabled: false,
        # Execution params
        max_turns: 25,
        hooks: double("hooks"),
        input_guardrails: [double("guard")],
        # model_kwargs
        model_kwargs: {
          custom: "param"
        }
      )

      # Model params
      expect(config.temperature).to eq(0.7)
      expect(config.max_tokens).to eq(1000)
      expect(config.model.top_p).to eq(0.95)
      expect(config.stream).to be true
      expect(config.model.model_kwargs[:custom]).to eq("param")

      # Tracing params
      expect(config.trace_id).to eq("full-trace")
      expect(config.group_id).to eq("full-group")
      expect(config.metadata).to eq({ full: true })
      expect(config.tracing_disabled).to be false

      # Execution params
      expect(config.max_turns).to eq(25)
      expect(config.hooks).not_to be_nil
      expect(config.input_guardrails).not_to be_empty
    end
  end
end
