# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Guardrails do
  describe "GuardrailError hierarchy" do
    it "defines custom error classes" do
      expect(RAAF::Guardrails::GuardrailError).to be < RAAF::Error
      expect(RAAF::Guardrails::TripwireException).to be < RAAF::Guardrails::GuardrailError
      expect(RAAF::Guardrails::InputGuardrailTripwireTriggered).to be < RAAF::Guardrails::TripwireException
      expect(RAAF::Guardrails::OutputGuardrailTripwireTriggered).to be < RAAF::Guardrails::TripwireException
    end
  end

  describe RAAF::Guardrails::InputGuardrail do
    let(:guardrail_function) { proc { |_context, _agent, _input| RAAF::Guardrails::GuardrailFunctionOutput.new(tripwire_triggered: false) } }
    let(:guardrail) { described_class.new(guardrail_function, name: "test_guardrail") }

    describe "#initialize" do
      it "accepts a guardrail function and name" do
        expect(guardrail.guardrail_function).to eq(guardrail_function)
        expect(guardrail.name).to eq("test_guardrail")
      end

      it "raises error for invalid guardrail function" do
        expect { described_class.new("not_callable") }.to raise_error(ArgumentError, "Guardrail function must respond to :call")
      end

      it "generates name from function if not provided" do
        guardrail = described_class.new(guardrail_function)
        expect(guardrail.get_name).to eq("guardrail")
      end
    end

    describe "#run" do
      let(:context) { double("context") }
      let(:agent) { double("agent") }
      let(:input) { "test input" }

      it "calls the guardrail function with correct arguments" do
        expect(guardrail_function).to receive(:call).with(context, agent, input).and_return(
          RAAF::Guardrails::GuardrailFunctionOutput.new(tripwire_triggered: false)
        )
        result = guardrail.run(context, agent, input)
        expect(result).to be_a(RAAF::Guardrails::InputGuardrailResult)
      end

      it "wraps the result in InputGuardrailResult" do
        result = guardrail.run(context, agent, input)
        expect(result).to be_a(RAAF::Guardrails::InputGuardrailResult)
        expect(result.tripwire_triggered?).to be false
      end
    end

    describe "#get_name" do
      it "returns the guardrail name" do
        expect(guardrail.get_name).to eq("test_guardrail")
      end
    end
  end

  describe RAAF::Guardrails::OutputGuardrail do
    let(:guardrail_function) { proc { |_context, _agent, _output| RAAF::Guardrails::GuardrailFunctionOutput.new(tripwire_triggered: false) } }
    let(:guardrail) { described_class.new(guardrail_function, name: "test_output_guardrail") }

    describe "#initialize" do
      it "accepts a guardrail function and name" do
        expect(guardrail.guardrail_function).to eq(guardrail_function)
        expect(guardrail.name).to eq("test_output_guardrail")
      end

      it "raises error for invalid guardrail function" do
        expect { described_class.new("not_callable") }.to raise_error(ArgumentError, "Guardrail function must respond to :call")
      end
    end

    describe "#run" do
      let(:context) { double("context") }
      let(:agent) { double("agent") }
      let(:output) { "test output" }

      it "calls the guardrail function with correct arguments" do
        expect(guardrail_function).to receive(:call).with(context, agent, output).and_return(
          RAAF::Guardrails::GuardrailFunctionOutput.new(tripwire_triggered: false)
        )
        result = guardrail.run(context, agent, output)
        expect(result).to be_a(RAAF::Guardrails::OutputGuardrailResult)
      end
    end

    describe "#get_name" do
      it "returns the guardrail name" do
        expect(guardrail.get_name).to eq("test_output_guardrail")
      end
    end
  end

  describe RAAF::Guardrails::GuardrailFunctionOutput do
    describe "#initialize" do
      it "accepts output_info and tripwire_triggered" do
        output = described_class.new(
          output_info: { status: "ok" },
          tripwire_triggered: false
        )
        expect(output.output_info).to eq({ status: "ok" })
        expect(output.tripwire_triggered).to be false
      end

      it "defaults tripwire_triggered to false" do
        output = described_class.new
        expect(output.tripwire_triggered).to be false
      end
    end
  end

  describe RAAF::Guardrails::InputGuardrailResult do
    let(:guardrail) { RAAF::Guardrails::InputGuardrail.new(proc { |_, _, _| RAAF::Guardrails::GuardrailFunctionOutput.new(tripwire_triggered: true) }) }
    let(:output) { RAAF::Guardrails::GuardrailFunctionOutput.new(tripwire_triggered: true) }
    let(:result) { described_class.new(guardrail: guardrail, output: output) }

    describe "#initialize" do
      it "accepts a guardrail and GuardrailFunctionOutput" do
        expect(result.guardrail).to eq(guardrail)
        expect(result.output).to eq(output)
      end
    end

    describe "#tripwire_triggered?" do
      it "delegates to the output" do
        expect(result.tripwire_triggered?).to be true
      end
    end
  end

  describe RAAF::Guardrails::OutputGuardrailResult do
    let(:guardrail) { RAAF::Guardrails::OutputGuardrail.new(proc { |_, _, _| RAAF::Guardrails::GuardrailFunctionOutput.new(tripwire_triggered: true) }) }
    let(:agent) { double("agent") }
    let(:agent_output) { "test output" }
    let(:output) { RAAF::Guardrails::GuardrailFunctionOutput.new(tripwire_triggered: true) }
    let(:result) { described_class.new(guardrail: guardrail, agent: agent, agent_output: agent_output, output: output) }

    describe "#initialize" do
      it "accepts all required parameters" do
        expect(result.guardrail).to eq(guardrail)
        expect(result.agent).to eq(agent)
        expect(result.agent_output).to eq(agent_output)
        expect(result.output).to eq(output)
      end
    end

    describe "#tripwire_triggered?" do
      it "delegates to the output" do
        expect(result.tripwire_triggered?).to be true
      end
    end
  end

  describe "Convenience methods" do
    describe ".profanity_guardrail" do
      it "creates a profanity guardrail" do
        guardrail = RAAF::Guardrails.profanity_guardrail
        expect(guardrail).to be_a(RAAF::Guardrails::BuiltIn::ProfanityGuardrail)
      end
    end

    describe ".pii_guardrail" do
      it "creates a PII guardrail" do
        guardrail = RAAF::Guardrails.pii_guardrail
        expect(guardrail).to be_a(RAAF::Guardrails::BuiltIn::PIIGuardrail)
      end
    end

    describe ".length_guardrail" do
      it "creates a length guardrail" do
        guardrail = RAAF::Guardrails.length_guardrail(max_length: 100)
        expect(guardrail).to be_a(RAAF::Guardrails::BuiltIn::LengthGuardrail)
      end
    end
  end
end