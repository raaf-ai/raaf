# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/eval/evaluators/structural/json_validity"
require_relative "../../../../lib/raaf/eval/evaluators/structural/schema_match"
require_relative "../../../../lib/raaf/eval/evaluators/structural/format_compliance"

RSpec.describe "Structural Evaluators" do
  let(:result) { {} }
  let(:field_context) { RAAF::Eval::DSL::FieldContext.new(:output, result) }

  describe RAAF::Eval::Evaluators::Structural::JsonValidity do
    let(:evaluator) { described_class.new }

    context "with valid JSON" do
      let(:result) { { output: '{"name": "test", "value": 42}' } }

      it "returns label 'good'" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:label]).to eq("good")
        expect(result[:score]).to eq(1.0)
        expect(result[:message]).to include("Valid JSON")
      end
    end

    context "with invalid JSON" do
      let(:result) { { output: '{"name": "test", "value": }' } }

      it "returns label 'bad'" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:label]).to eq("bad")
        expect(result[:score]).to eq(0.0)
        expect(result[:message]).to include("Invalid JSON")
      end
    end

    context "with Ruby hash" do
      let(:result) { { output: { name: "test", value: 42 } } }

      it "converts and validates" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:label]).to eq("good")
        expect(result[:score]).to eq(1.0)
      end
    end
  end

  describe RAAF::Eval::Evaluators::Structural::SchemaMatch do
    let(:evaluator) { described_class.new }

    context "with matching schema" do
      let(:result) { { output: { name: "test", age: 30 } } }
      let(:schema) do
        {
          type: "object",
          required: ["name", "age"],
          properties: {
            name: { type: "string" },
            age: { type: "integer" }
          }
        }
      end

      it "returns label 'good'" do
        result = evaluator.evaluate(field_context, schema: schema)
        
        expect(result[:label]).to eq("good")
        expect(result[:score]).to eq(1.0)
        expect(result[:message]).to include("Matches schema")
      end
    end

    context "with schema violations" do
      let(:result) { { output: { name: "test" } } }
      let(:schema) do
        {
          type: "object",
          required: ["name", "age"]
        }
      end

      it "fails with missing fields" do
        result = evaluator.evaluate(field_context, schema: schema)
        
        expect(result[:label]).to eq("bad")
        expect(result[:details][:validation_errors]).to include("missing required field: age")
      end
    end

    context "without schema" do
      let(:result) { { output: { name: "test" } } }

      it "fails without schema parameter" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:label]).to eq("bad")
        expect(result[:message]).to include("requires :schema")
      end
    end
  end

  describe RAAF::Eval::Evaluators::Structural::FormatCompliance do
    let(:evaluator) { described_class.new }

    context "with email format" do
      it "passes valid email" do
        result = { output: "test@example.com" }
        context = RAAF::Eval::DSL::FieldContext.new(:output, result)
        
        result = evaluator.evaluate(context, format: :email)
        
        expect(result[:label]).to eq("good")
        expect(result[:score]).to eq(1.0)
      end

      it "fails invalid email" do
        result = { output: "not-an-email" }
        context = RAAF::Eval::DSL::FieldContext.new(:output, result)
        
        result = evaluator.evaluate(context, format: :email)
        
        expect(result[:label]).to eq("bad")
        expect(result[:details][:violations]).to include("invalid email format")
      end
    end

    context "with URL format" do
      it "passes valid URL" do
        result = { output: "https://example.com/path" }
        context = RAAF::Eval::DSL::FieldContext.new(:output, result)
        
        result = evaluator.evaluate(context, format: :url)
        
        expect(result[:label]).to eq("good")
      end

      it "fails invalid URL" do
        result = { output: "not a url" }
        context = RAAF::Eval::DSL::FieldContext.new(:output, result)
        
        result = evaluator.evaluate(context, format: :url)
        
        expect(result[:label]).to eq("bad")
      end
    end

    context "with custom format" do
      let(:result) { { output: "ABC123" } }
      let(:custom_format) do
        {
          pattern: '^[A-Z]{3}[0-9]{3}$',
          min_length: 6,
          max_length: 6
        }
      end

      it "validates against custom pattern" do
        result = evaluator.evaluate(field_context, format: custom_format)
        
        expect(result[:label]).to eq("good")
        expect(result[:score]).to eq(1.0)
      end
    end

    context "without format" do
      let(:result) { { output: "anything" } }

      it "fails without format parameter" do
        result = evaluator.evaluate(field_context)
        
        expect(result[:label]).to eq("bad")
        expect(result[:message]).to include("requires :format")
      end
    end
  end
end
