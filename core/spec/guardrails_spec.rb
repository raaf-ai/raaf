# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::Guardrails" do
  describe "LengthInputGuardrail" do
    let(:guardrail) { RAAF::Guardrails::LengthInputGuardrail.new(max_length: 10) }

    it "allows short input" do
      result = guardrail.run(nil, nil, "short")
      expect(result.tripwire_triggered?).to be false
    end

    it "blocks long input" do
      result = guardrail.run(nil, nil, "this is a very long input that exceeds the limit")
      expect(result.tripwire_triggered?).to be true
      expect(result.output.output_info[:blocked_reason]).to match(/Input too long/)
    end
  end

  describe "ProfanityOutputGuardrail" do
    let(:guardrail) { RAAF::Guardrails::ProfanityOutputGuardrail.new }

    it "filters profanity from output" do
      result = guardrail.run(nil, nil, "This is a damn good example")
      expect(result.tripwire_triggered?).to be false
      expect(result.output.output_info[:filtered_output]).to eq("This is a [filtered] good example")
    end

    it "passes clean output unchanged" do
      result = guardrail.run(nil, nil, "This is a good example")
      expect(result.tripwire_triggered?).to be false
      expect(result.output.output_info).to be_empty
    end
  end

  describe "InputGuardrail with custom block" do
    let(:guardrail) do
      RAAF::Guardrails::InputGuardrail.new(name: "TestGuardrail") do |input|
        "Input contains blocked content" if input.include?("blocked")
      end
    end

    it "allows normal input" do
      result = guardrail.run(nil, nil, "normal input")
      expect(result.tripwire_triggered?).to be false
    end

    it "blocks flagged input" do
      result = guardrail.run(nil, nil, "this is blocked content")
      expect(result.tripwire_triggered?).to be true
      expect(result.output.output_info[:blocked_reason]).to eq("Input contains blocked content")
    end
  end
end
