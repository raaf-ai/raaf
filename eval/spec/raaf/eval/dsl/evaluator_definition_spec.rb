# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::DSL::EvaluatorDefinition do
  describe "evaluator definition creation" do
    it "creates an empty definition" do
      definition = described_class.new
      expect(definition).to be_a(described_class)
      expect(definition.selected_fields).to be_empty
      expect(definition.field_evaluators).to be_empty
    end

    it "accepts a name parameter" do
      definition = described_class.new(name: "my_evaluator")
      expect(definition.name).to eq("my_evaluator")
    end
  end

  describe "field selection storage" do
    let(:definition) { described_class.new }

    it "stores selected fields" do
      definition.add_field("output")
      definition.add_field("usage.total_tokens", as: "tokens")

      expect(definition.selected_fields).to eq([
        { path: "output", alias: nil },
        { path: "usage.total_tokens", alias: "tokens" }
      ])
    end

    it "retrieves field by path" do
      definition.add_field("output", as: "result")
      field = definition.get_field("output")
      expect(field).to eq({ path: "output", alias: "result" })
    end

    it "retrieves field by alias" do
      definition.add_field("usage.total_tokens", as: "tokens")
      field = definition.get_field_by_alias("tokens")
      expect(field).to eq({ path: "usage.total_tokens", alias: "tokens" })
    end
  end

  describe "field evaluator attachment" do
    let(:definition) { described_class.new }

    it "stores field evaluator configurations" do
      evaluator_config = {
        evaluators: [
          { name: :semantic_similarity, options: { threshold: 0.8 } },
          { name: :token_efficiency, options: {} }
        ],
        combine_with: :AND
      }

      definition.add_field_evaluator("output", evaluator_config)

      expect(definition.field_evaluators["output"]).to eq(evaluator_config)
    end

    it "retrieves evaluator configuration for a field" do
      config = { evaluators: [{ name: :quality }], combine_with: :AND }
      definition.add_field_evaluator("output", config)

      retrieved = definition.get_field_evaluator("output")
      expect(retrieved).to eq(config)
    end

    it "supports multiple fields with evaluators" do
      definition.add_field_evaluator("output", { evaluators: [{ name: :quality }] })
      definition.add_field_evaluator("usage.total_tokens", { evaluators: [{ name: :efficiency }] })

      expect(definition.field_evaluators.keys).to contain_exactly("output", "usage.total_tokens")
    end
  end

  describe "progress callback registration" do
    let(:definition) { described_class.new }

    it "registers progress callbacks" do
      callback1 = ->(event) { puts event }
      callback2 = ->(event) { log(event) }

      definition.add_progress_callback(&callback1)
      definition.add_progress_callback(&callback2)

      expect(definition.progress_callbacks).to contain_exactly(callback1, callback2)
    end

    it "executes progress callbacks" do
      events = []
      definition.add_progress_callback { |event| events << event }

      event = { status: "start", progress: 0 }
      definition.trigger_progress(event)

      expect(events).to eq([event])
    end
  end

  describe "history configuration" do
    let(:definition) { described_class.new }

    it "stores history configuration settings" do
      history_config = {
        auto_save: true,
        retention_days: 30,
        retention_count: 100,
        tags: ["production", "v1.0"]
      }

      definition.configure_history(history_config)
      expect(definition.history_config).to eq(history_config)
    end

    it "provides default history configuration" do
      expect(definition.history_config).to eq({
        auto_save: false,
        retention_days: nil,
        retention_count: nil,
        tags: []
      })
    end

    it "merges partial history configuration" do
      definition.configure_history(auto_save: true, tags: ["test"])

      expect(definition.history_config).to include(
        auto_save: true,
        tags: ["test"],
        retention_days: nil,
        retention_count: nil
      )
    end
  end

  describe "accessor methods for stored data" do
    let(:definition) { described_class.new(name: "test_evaluator") }

    it "provides read access to all stored data" do
      definition.add_field("output", as: "result")
      definition.add_field_evaluator("output", { evaluators: [{ name: :quality }] })
      definition.configure_history(auto_save: true)

      expect(definition.name).to eq("test_evaluator")
      expect(definition.selected_fields).not_to be_empty
      expect(definition.field_evaluators).to have_key("output")
      expect(definition.history_config[:auto_save]).to be true
    end
  end
end