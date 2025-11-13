# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/dsl_engine/progress_event"

RSpec.describe RAAF::Eval::DslEngine::ProgressEvent do
  describe "#initialize" do
    it "creates a valid start event" do
      event = described_class.new(
        type: :start,
        progress: 0.0,
        status: :running,
        metadata: { total_configurations: 3 }
      )

      expect(event.type).to eq(:start)
      expect(event.progress).to eq(0.0)
      expect(event.status).to eq(:running)
      expect(event.metadata[:total_configurations]).to eq(3)
      expect(event.timestamp).to be_a(Time)
    end

    it "creates a valid config_start event" do
      event = described_class.new(
        type: :config_start,
        progress: 33.3,
        status: :running,
        metadata: {
          configuration_name: :low_temp,
          configuration_index: 0,
          total_configurations: 3
        }
      )

      expect(event.type).to eq(:config_start)
      expect(event.progress).to eq(33.3)
      expect(event.metadata[:configuration_name]).to eq(:low_temp)
    end

    it "creates a valid evaluator_end event" do
      event = described_class.new(
        type: :evaluator_end,
        progress: 40.0,
        status: :completed,
        metadata: {
          evaluator_name: :semantic_similarity,
          evaluator_result: { passed: true, score: 0.92 },
          duration_ms: 245.67
        }
      )

      expect(event.type).to eq(:evaluator_end)
      expect(event.metadata[:evaluator_result][:passed]).to be true
      expect(event.metadata[:duration_ms]).to eq(245.67)
    end

    it "raises error for invalid event type" do
      expect {
        described_class.new(type: :invalid, progress: 0.0, status: :running)
      }.to raise_error(RAAF::Eval::DslEngine::InvalidEventTypeError)
    end

    it "raises error for invalid status" do
      expect {
        described_class.new(type: :start, progress: 0.0, status: :invalid)
      }.to raise_error(RAAF::Eval::DslEngine::InvalidEventStatusError)
    end

    it "raises error for progress < 0.0" do
      expect {
        described_class.new(type: :start, progress: -1.0, status: :running)
      }.to raise_error(RAAF::Eval::DslEngine::InvalidProgressError)
    end

    it "raises error for progress > 100.0" do
      expect {
        described_class.new(type: :start, progress: 101.0, status: :running)
      }.to raise_error(RAAF::Eval::DslEngine::InvalidProgressError)
    end
  end

  describe "#to_h" do
    it "converts event to hash with all fields" do
      event = described_class.new(
        type: :start,
        progress: 0.0,
        status: :running,
        metadata: { total_configurations: 3 }
      )

      hash = event.to_h

      expect(hash[:type]).to eq(:start)
      expect(hash[:progress]).to eq(0.0)
      expect(hash[:status]).to eq(:running)
      expect(hash[:timestamp]).to be_a(Time)
      expect(hash[:metadata][:total_configurations]).to eq(3)
    end

    it "includes empty metadata when none provided" do
      event = described_class.new(
        type: :start,
        progress: 0.0,
        status: :running
      )

      hash = event.to_h
      expect(hash[:metadata]).to be_empty
    end
  end

  describe "EVENT_TYPES constant" do
    it "includes all 6 event types" do
      expect(described_class::EVENT_TYPES).to contain_exactly(
        :start, :config_start, :evaluator_start, :evaluator_end, :config_end, :end
      )
    end
  end

  describe "STATUSES constant" do
    it "includes all valid statuses" do
      expect(described_class::STATUSES).to contain_exactly(
        :pending, :running, :completed, :failed
      )
    end
  end

  describe "metadata with indifferent access" do
    it "allows symbol access" do
      event = described_class.new(
        type: :start,
        progress: 0.0,
        status: :running,
        metadata: { "total_configurations" => 3 }
      )

      expect(event.metadata[:total_configurations]).to eq(3)
    end

    it "allows string access" do
      event = described_class.new(
        type: :start,
        progress: 0.0,
        status: :running,
        metadata: { total_configurations: 3 }
      )

      expect(event.metadata["total_configurations"]).to eq(3)
    end
  end
end
