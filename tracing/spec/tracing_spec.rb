# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenAIAgents::Tracing do
  describe ".tracer" do
    it "returns a tracer instance" do
      tracer = described_class.tracer
      # When tracing is disabled, returns NoOpTracer; otherwise SpanTracer
      if ENV["OPENAI_AGENTS_DISABLE_TRACING"] == "true"
        expect(tracer).to be_a(OpenAIAgents::Tracing::NoOpTracer)
      else
        expect(tracer).to be_a(OpenAIAgents::Tracing::SpanTracer)
      end
    end
  end

  describe ".trace" do
    it "creates a trace context" do
      expect(OpenAIAgents::Tracing::Trace).to receive(:create).with("test workflow")
      described_class.trace("test workflow")
    end
  end

  describe ".disabled?" do
    it "returns the disabled status" do
      expect(described_class.disabled?).to be_a(TrueClass).or be_a(FalseClass)
    end
  end

  describe ".disable!" do
    it "disables tracing" do
      described_class.disable!
      expect(described_class.disabled?).to be true
    end
  end

  describe ".enable!" do
    it "enables tracing" do
      described_class.enable!
      expect(described_class.disabled?).to be false
    end
  end
end