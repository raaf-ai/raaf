# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing do
  # enable!/disable! mutate the TraceProvider singleton, and enable! also
  # installs the default processors - which send spans to the OpenAI API.
  # Leaving that on leaked into every later example in the suite.
  around do |example|
    provider = RAAF::Tracing::TraceProvider.instance
    was_disabled = provider.disabled?
    processors = provider.processors.dup
    begin
      example.run
    ensure
      provider.set_processors(*processors)
      was_disabled ? provider.disable! : provider.enable!
    end
  end

  describe ".tracer" do
    it "returns a tracer instance" do
      tracer = described_class.tracer
      # When tracing is disabled, returns NoOpTracer; otherwise SpanTracer
      if ENV["RAAF_DISABLE_TRACING"] == "true"
        expect(tracer).to be_a(RAAF::Tracing::NoOpTracer)
      else
        expect(tracer).to be_a(RAAF::Tracing::SpanTracer)
      end
    end
  end

  describe ".trace" do
    it "creates a trace context" do
      expect(RAAF::Tracing::Trace).to receive(:create).with("test workflow")
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
