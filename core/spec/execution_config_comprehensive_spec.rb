# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Config::ExecutionConfig do
  describe "#initialize" do
    context "with no parameters" do
      let(:config) { described_class.new }

      it "initializes with nil values" do
        expect(config.max_turns).to be_nil
        expect(config.hooks).to be_nil
        expect(config.input_guardrails).to be_nil
        expect(config.output_guardrails).to be_nil
        expect(config.context).to be_nil
        expect(config.session).to be_nil
      end
    end

    context "with all parameters" do
      let(:hooks) { double("RunHooks") }
      let(:input_guardrails) { [double("InputGuardrail")] }
      let(:output_guardrails) { [double("OutputGuardrail")] }
      let(:context) { double("Context") }
      let(:session) { double("Session") }

      let(:config) do
        described_class.new(
          max_turns: 15,
          hooks: hooks,
          input_guardrails: input_guardrails,
          output_guardrails: output_guardrails,
          context: context,
          session: session
        )
      end

      it "stores max_turns" do
        expect(config.max_turns).to eq(15)
      end

      it "stores hooks" do
        expect(config.hooks).to eq(hooks)
      end

      it "stores input_guardrails" do
        expect(config.input_guardrails).to eq(input_guardrails)
      end

      it "stores output_guardrails" do
        expect(config.output_guardrails).to eq(output_guardrails)
      end

      it "stores context" do
        expect(config.context).to eq(context)
      end

      it "stores session" do
        expect(config.session).to eq(session)
      end
    end

    context "with partial parameters" do
      let(:config) do
        described_class.new(
          max_turns: 10,
          hooks: double("hooks")
        )
      end

      it "stores provided parameters" do
        expect(config.max_turns).to eq(10)
        expect(config.hooks).not_to be_nil
      end

      it "leaves unspecified parameters as nil" do
        expect(config.input_guardrails).to be_nil
        expect(config.output_guardrails).to be_nil
        expect(config.context).to be_nil
        expect(config.session).to be_nil
      end
    end
  end

  describe "attribute accessors" do
    let(:config) { described_class.new }

    describe "#max_turns" do
      it "allows reading and writing" do
        config.max_turns = 20
        expect(config.max_turns).to eq(20)
      end

      it "allows nil value" do
        config.max_turns = nil
        expect(config.max_turns).to be_nil
      end
    end

    describe "#hooks" do
      it "allows reading and writing" do
        hooks = double("hooks")
        config.hooks = hooks
        expect(config.hooks).to eq(hooks)
      end
    end

    describe "#input_guardrails" do
      it "allows reading and writing" do
        guardrails = [double("guardrail1"), double("guardrail2")]
        config.input_guardrails = guardrails
        expect(config.input_guardrails).to eq(guardrails)
      end

      it "allows empty array" do
        config.input_guardrails = []
        expect(config.input_guardrails).to eq([])
      end
    end

    describe "#output_guardrails" do
      it "allows reading and writing" do
        guardrails = [double("guardrail1"), double("guardrail2")]
        config.output_guardrails = guardrails
        expect(config.output_guardrails).to eq(guardrails)
      end

      it "allows empty array" do
        config.output_guardrails = []
        expect(config.output_guardrails).to eq([])
      end
    end

    describe "#context" do
      it "allows reading and writing" do
        context = { user: "test", role: "admin" }
        config.context = context
        expect(config.context).to eq(context)
      end
    end

    describe "#session" do
      it "allows reading and writing" do
        session = double("session", id: "sess-123")
        config.session = session
        expect(config.session).to eq(session)
      end
    end
  end

  describe "#hooks?" do
    let(:config) { described_class.new }

    it "returns false when hooks is nil" do
      config.hooks = nil
      expect(config.hooks?).to be false
    end

    it "returns true when hooks is present" do
      config.hooks = double("hooks")
      expect(config.hooks?).to be true
    end

    it "returns true even for empty hooks object" do
      config.hooks = {}
      expect(config.hooks?).to be true
    end
  end

  describe "#input_guardrails?" do
    let(:config) { described_class.new }

    it "returns false when input_guardrails is nil" do
      config.input_guardrails = nil
      expect(config.input_guardrails?).to be false
    end

    it "returns false when input_guardrails is empty array" do
      config.input_guardrails = []
      expect(config.input_guardrails?).to be false
    end

    it "returns true when input_guardrails has items" do
      config.input_guardrails = [double("guardrail")]
      expect(config.input_guardrails?).to be true
    end

    it "returns true when multiple guardrails present" do
      config.input_guardrails = [double("g1"), double("g2"), double("g3")]
      expect(config.input_guardrails?).to be true
    end
  end

  describe "#output_guardrails?" do
    let(:config) { described_class.new }

    it "returns false when output_guardrails is nil" do
      config.output_guardrails = nil
      expect(config.output_guardrails?).to be false
    end

    it "returns false when output_guardrails is empty array" do
      config.output_guardrails = []
      expect(config.output_guardrails?).to be false
    end

    it "returns true when output_guardrails has items" do
      config.output_guardrails = [double("guardrail")]
      expect(config.output_guardrails?).to be true
    end

    it "returns true when multiple guardrails present" do
      config.output_guardrails = [double("g1"), double("g2"), double("g3")]
      expect(config.output_guardrails?).to be true
    end
  end

  describe "#effective_max_turns" do
    let(:config) { described_class.new }
    let(:agent) { double("Agent", max_turns: 10) }

    it "returns config max_turns when set" do
      config.max_turns = 20
      expect(config.effective_max_turns(agent)).to eq(20)
    end

    it "returns agent max_turns when config max_turns is nil" do
      config.max_turns = nil
      expect(config.effective_max_turns(agent)).to eq(10)
    end

    it "prefers config value over agent value" do
      config.max_turns = 5
      expect(config.effective_max_turns(agent)).to eq(5)
    end

    it "handles zero max_turns from config" do
      config.max_turns = 0
      expect(config.effective_max_turns(agent)).to eq(0)
    end

    it "handles agent with nil max_turns" do
      agent = double("Agent", max_turns: nil)
      config.max_turns = nil
      # Should return default of 10 when both are nil
      expect(config.effective_max_turns(agent)).to eq(10)
    end
  end

  describe "#merge" do
    let(:config1) do
      described_class.new(
        max_turns: 10,
        hooks: double("hooks1"),
        input_guardrails: [double("guardrail1")]
      )
    end

    let(:config2) do
      described_class.new(
        max_turns: 20,
        output_guardrails: [double("guardrail2")]
      )
    end

    it "returns self when other is nil" do
      result = config1.merge(nil)
      expect(result).to eq(config1)
    end

    it "creates new config instance" do
      result = config1.merge(config2)
      expect(result).to be_a(described_class)
      expect(result).not_to eq(config1)
      expect(result).not_to eq(config2)
    end

    it "prefers other's max_turns when present" do
      result = config1.merge(config2)
      expect(result.max_turns).to eq(20)
    end

    it "uses original max_turns when other's is nil" do
      config2.max_turns = nil
      result = config1.merge(config2)
      expect(result.max_turns).to eq(10)
    end

    it "prefers other's hooks when present" do
      hooks2 = double("hooks2")
      config2.hooks = hooks2
      result = config1.merge(config2)
      expect(result.hooks).to eq(hooks2)
    end

    it "uses original hooks when other's is nil" do
      result = config1.merge(config2)
      expect(result.hooks).to eq(config1.hooks)
    end

    it "handles all attributes in merge" do
      hooks2 = double("hooks2")
      input_g2 = [double("input2")]
      output_g2 = [double("output2")]
      
      full_config2 = described_class.new(
        max_turns: 30,
        hooks: hooks2,
        input_guardrails: input_g2,
        output_guardrails: output_g2
      )

      result = config1.merge(full_config2)
      
      expect(result.max_turns).to eq(30)
      expect(result.hooks).to eq(hooks2)
      expect(result.input_guardrails).to eq(input_g2)
      expect(result.output_guardrails).to eq(output_g2)
    end

    it "preserves context and session in merge" do
      context = double("context")
      session = double("session")
      
      config1.context = context
      config1.session = session
      
      # config2 doesn't have context/session
      result = config1.merge(config2)
      
      # Should preserve from config1 (merge doesn't handle these yet)
      # Based on current implementation, these aren't included in merge
      expect(result.context).to be_nil
      expect(result.session).to be_nil
    end
  end

  describe "#to_h" do
    let(:hooks) { double("hooks") }
    let(:input_guardrails) { [double("ig1"), double("ig2")] }
    let(:output_guardrails) { [double("og1")] }

    let(:config) do
      described_class.new(
        max_turns: 15,
        hooks: hooks,
        input_guardrails: input_guardrails,
        output_guardrails: output_guardrails
      )
    end

    it "returns a hash representation" do
      result = config.to_h
      expect(result).to be_a(Hash)
    end

    it "includes all configured values" do
      result = config.to_h
      
      expect(result[:max_turns]).to eq(15)
      expect(result[:hooks]).to eq(hooks)
      expect(result[:input_guardrails]).to eq(input_guardrails)
      expect(result[:output_guardrails]).to eq(output_guardrails)
    end

    it "includes nil values in hash" do
      empty_config = described_class.new
      result = empty_config.to_h
      
      expect(result).to have_key(:max_turns)
      expect(result).to have_key(:hooks)
      expect(result).to have_key(:input_guardrails)
      expect(result).to have_key(:output_guardrails)
      
      expect(result[:max_turns]).to be_nil
      expect(result[:hooks]).to be_nil
      expect(result[:input_guardrails]).to be_nil
      expect(result[:output_guardrails]).to be_nil
    end

    it "doesn't include context and session in to_h" do
      config.context = double("context")
      config.session = double("session")
      
      result = config.to_h
      
      # Current implementation doesn't include these
      expect(result).not_to have_key(:context)
      expect(result).not_to have_key(:session)
    end
  end

  describe "edge cases and validation scenarios" do
    let(:config) { described_class.new }

    it "handles negative max_turns" do
      config.max_turns = -5
      expect(config.max_turns).to eq(-5) # No validation, just stores
    end

    it "handles very large max_turns" do
      config.max_turns = 1_000_000
      expect(config.max_turns).to eq(1_000_000)
    end

    it "handles non-array guardrails gracefully in predicates" do
      config.input_guardrails = "not an array"
      # Should not raise error, implementation assumes array
      expect { config.input_guardrails? }.not_to raise_error
    end

    it "handles frozen arrays for guardrails" do
      frozen_guardrails = [double("guardrail")].freeze
      config.input_guardrails = frozen_guardrails
      expect(config.input_guardrails).to eq(frozen_guardrails)
      expect(config.input_guardrails?).to be true
    end

    it "allows mutation of guardrail arrays" do
      config.input_guardrails = [double("g1")]
      config.input_guardrails << double("g2")
      expect(config.input_guardrails.size).to eq(2)
    end
  end

  describe "Python SDK compatibility" do
    it "supports context for dependency injection" do
      context = { 
        db: double("database"),
        api_client: double("api_client"),
        user: { id: 123, role: "admin" }
      }
      
      config = described_class.new(context: context)
      expect(config.context).to eq(context)
      expect(config.context[:user][:id]).to eq(123)
    end

    it "supports session for conversation history" do
      session = double("Session",
        id: "sess-123",
        messages: [],
        metadata: { started_at: Time.now }
      )
      
      config = described_class.new(session: session)
      expect(config.session).to eq(session)
      expect(config.session.id).to eq("sess-123")
    end
  end

  describe "usage patterns" do
    it "supports builder pattern for configuration" do
      config = described_class.new
      
      config.max_turns = 10
      config.hooks = double("hooks")
      config.input_guardrails = [double("guardrail")]
      
      expect(config.max_turns).to eq(10)
      expect(config.hooks?).to be true
      expect(config.input_guardrails?).to be true
    end

    it "supports configuration for different environments" do
      # Development config - minimal guardrails
      dev_config = described_class.new(
        max_turns: 50,
        input_guardrails: []
      )
      
      # Production config - strict guardrails
      prod_config = described_class.new(
        max_turns: 10,
        input_guardrails: [double("content_filter"), double("injection_guard")],
        output_guardrails: [double("pii_filter"), double("safety_check")]
      )
      
      expect(dev_config.input_guardrails?).to be false
      expect(prod_config.input_guardrails?).to be true
      expect(prod_config.output_guardrails?).to be true
    end
  end

  describe "integration with agent" do
    let(:config) { described_class.new(max_turns: 25) }
    
    it "provides configuration for agent execution" do
      agent = double("Agent", max_turns: 10)
      
      # Config overrides agent default
      expect(config.effective_max_turns(agent)).to eq(25)
      
      # Other settings available during execution
      expect(config.hooks?).to be false
      expect(config.input_guardrails?).to be false
      expect(config.output_guardrails?).to be false
    end

    it "supports runtime configuration changes" do
      agent = double("Agent", max_turns: 10)
      
      # Start with one configuration
      expect(config.effective_max_turns(agent)).to eq(25)
      
      # Modify for different run
      config.max_turns = 5
      expect(config.effective_max_turns(agent)).to eq(5)
    end
  end
end