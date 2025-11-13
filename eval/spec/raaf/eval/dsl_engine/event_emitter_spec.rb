# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/dsl_engine/event_emitter"
require "raaf/eval/dsl_engine/callback_manager"
require "raaf/eval/dsl_engine/progress_calculator"

RSpec.describe RAAF::Eval::DslEngine::EventEmitter do
  let(:callback_manager) { RAAF::Eval::DslEngine::CallbackManager.new }
  let(:progress_calculator) { RAAF::Eval::DslEngine::ProgressCalculator.new(3, 2, 5) }
  let(:emitter) { described_class.new(callback_manager, progress_calculator) }
  let(:events) { [] }

  before do
    callback_manager.register { |event| events << event }
  end

  describe "#emit_start" do
    it "emits start event with metadata" do
      emitter.emit_start(
        total_configurations: 3,
        total_fields: 2,
        total_evaluators: 5,
        has_baseline: true
      )

      event = events.first
      expect(event.type).to eq(:start)
      expect(event.progress).to eq(0.0)
      expect(event.status).to eq(:running)
      expect(event.metadata[:total_configurations]).to eq(3)
      expect(event.metadata[:total_fields]).to eq(2)
      expect(event.metadata[:total_evaluators]).to eq(5)
      expect(event.metadata[:has_baseline]).to be true
    end

    it "invokes registered callbacks" do
      expect(events).to be_empty

      emitter.emit_start

      expect(events.size).to eq(1)
    end
  end

  describe "#emit_config_start" do
    it "emits config_start event with config info" do
      emitter.emit_config_start(:low_temp, 0, 3, temperature: 0.3)

      event = events.first
      expect(event.type).to eq(:config_start)
      expect(event.progress).to eq(0.0)
      expect(event.status).to eq(:running)
      expect(event.metadata[:configuration_name]).to eq(:low_temp)
      expect(event.metadata[:configuration_index]).to eq(0)
      expect(event.metadata[:total_configurations]).to eq(3)
      expect(event.metadata[:configuration_params][:temperature]).to eq(0.3)
    end

    it "calculates progress based on config index" do
      emitter.emit_config_start(:second_config, 1, 3)

      event = events.first
      expect(event.progress).to eq(33.33)
    end
  end

  describe "#emit_evaluator_start" do
    it "emits evaluator_start event" do
      emitter.emit_evaluator_start(:low_temp, :output, :semantic_similarity, 0, 3)

      event = events.first
      expect(event.type).to eq(:evaluator_start)
      expect(event.status).to eq(:running)
      expect(event.metadata[:configuration_name]).to eq(:low_temp)
      expect(event.metadata[:field_name]).to eq(:output)
      expect(event.metadata[:evaluator_name]).to eq(:semantic_similarity)
      expect(event.metadata[:evaluator_index]).to eq(0)
      expect(event.metadata[:total_evaluators_for_field]).to eq(3)
    end

    it "calculates progress for evaluator" do
      emitter.emit_evaluator_start(:config, :field, :evaluator, 1, 5)

      event = events.first
      expect(event.progress).to be > 0.0
      expect(event.progress).to be < 33.33
    end
  end

  describe "#emit_evaluator_end" do
    it "emits evaluator_end event with result and duration" do
      result = { passed: true, score: 0.92 }

      emitter.emit_evaluator_end(:low_temp, :output, :semantic_similarity, result, 245.67)

      event = events.first
      expect(event.type).to eq(:evaluator_end)
      expect(event.status).to eq(:completed)
      expect(event.metadata[:configuration_name]).to eq(:low_temp)
      expect(event.metadata[:field_name]).to eq(:output)
      expect(event.metadata[:evaluator_name]).to eq(:semantic_similarity)
      expect(event.metadata[:evaluator_result][:passed]).to be true
      expect(event.metadata[:evaluator_result][:score]).to eq(0.92)
      expect(event.metadata[:duration_ms]).to eq(245.67)
    end

    it "uses failed status when result is not passed" do
      result = { passed: false, score: 0.45 }

      emitter.emit_evaluator_end(:config, :field, :evaluator, result, 100)

      event = events.first
      expect(event.status).to eq(:failed)
    end
  end

  describe "#emit_config_end" do
    it "emits config_end event with aggregated result" do
      # Call emit_start first to initialize timing
      emitter.emit_start
      events.clear # Clear start event

      # Mock result object
      result = double("result", passed?: true, aggregate_score: 0.85)

      emitter.emit_config_end(:low_temp, result, 5)

      event = events.first
      expect(event.type).to eq(:config_end)
      expect(event.status).to eq(:completed)
      expect(event.metadata[:configuration_name]).to eq(:low_temp)
      expect(event.metadata[:configuration_result][:passed]).to be true
      expect(event.metadata[:configuration_result][:aggregate_score]).to eq(0.85)
      expect(event.metadata[:evaluators_run]).to eq(5)
      expect(event.metadata[:duration_ms]).to be >= 0
    end

    it "uses failed status when result is not passed" do
      result = double("result", passed?: false, aggregate_score: 0.45)

      emitter.emit_config_end(:config, result, 5)

      event = events.first
      expect(event.status).to eq(:failed)
    end
  end

  describe "#emit_end" do
    it "emits end event with overall stats" do
      # Call emit_start first to initialize timing
      emitter.emit_start
      events.clear # Clear start event

      emitter.emit_end(3, 15, true)

      event = events.first
      expect(event.type).to eq(:end)
      expect(event.progress).to eq(100.0)
      expect(event.status).to eq(:completed)
      expect(event.metadata[:configurations_completed]).to eq(3)
      expect(event.metadata[:total_evaluators_run]).to eq(15)
      expect(event.metadata[:overall_passed]).to be true
      expect(event.metadata[:total_duration_ms]).to be >= 0
    end

    it "uses failed status when not passed" do
      emitter.emit_end(3, 15, false)

      event = events.first
      expect(event.status).to eq(:failed)
    end
  end

  describe "event timing" do
    it "tracks duration from start to end" do
      emitter.emit_start

      sleep 0.01 # Small delay

      emitter.emit_end(1, 5, true)

      end_event = events.last
      expect(end_event.metadata[:total_duration_ms]).to be > 0
    end
  end

  describe "multiple callbacks" do
    it "invokes all registered callbacks for each event" do
      events2 = []
      callback_manager.register { |event| events2 << event }

      emitter.emit_start

      expect(events.size).to eq(1)
      expect(events2.size).to eq(1)
      expect(events.first.type).to eq(:start)
      expect(events2.first.type).to eq(:start)
    end
  end
end
