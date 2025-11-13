# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::DSL::EvaluationResult do
  let(:field_results) do
    {
      "output" => {
        passed: true,
        score: 0.9,
        details: { quality: "high" },
        message: "Output quality is high"
      },
      "usage.total_tokens" => {
        passed: false,
        score: 0.4,
        details: { efficiency: "low" },
        message: "Token usage is inefficient"
      }
    }
  end

  let(:configuration) do
    {
      name: "baseline",
      model: "gpt-4",
      temperature: 0.7,
      max_tokens: 1000
    }
  end

  let(:metadata) do
    {
      execution_time_ms: 1250.5,
      timestamp: "2025-01-01T00:00:00Z",
      evaluator_name: "quality_evaluator"
    }
  end

  describe "passed? method" do
    it "returns true when all fields passed" do
      all_passed_results = {
        "output" => { passed: true, score: 0.9 },
        "tokens" => { passed: true, score: 0.8 }
      }
      result = described_class.new(field_results: all_passed_results)
      expect(result.passed?).to be true
    end

    it "returns false when any field failed" do
      result = described_class.new(field_results: field_results)
      expect(result.passed?).to be false
    end

    it "returns true when there are no field results" do
      result = described_class.new(field_results: {})
      expect(result.passed?).to be true
    end
  end

  describe "field_results access" do
    let(:result) { described_class.new(field_results: field_results) }

    it "provides access to all field results" do
      expect(result.field_results).to eq(field_results)
    end

    it "provides access to individual field results" do
      expect(result.field_result("output")).to eq(field_results["output"])
      expect(result.field_result("usage.total_tokens")).to eq(field_results["usage.total_tokens"])
    end

    it "returns nil for non-existent field" do
      expect(result.field_result("non_existent")).to be_nil
    end

    it "provides passed fields list" do
      expect(result.passed_fields).to eq(["output"])
    end

    it "provides failed fields list" do
      expect(result.failed_fields).to eq(["usage.total_tokens"])
    end
  end

  describe "configuration access" do
    let(:result) do
      described_class.new(
        field_results: field_results,
        configuration: configuration
      )
    end

    it "stores and retrieves configuration" do
      expect(result.configuration).to eq(configuration)
    end

    it "provides configuration name accessor" do
      expect(result.configuration_name).to eq("baseline")
    end

    it "returns nil configuration name when not set" do
      result_no_config = described_class.new(field_results: field_results)
      expect(result_no_config.configuration_name).to be_nil
    end
  end

  describe "result metadata storage" do
    let(:result) do
      described_class.new(
        field_results: field_results,
        configuration: configuration,
        metadata: metadata
      )
    end

    it "stores execution metadata" do
      expect(result.metadata).to eq(metadata)
    end

    it "provides execution_time accessor" do
      expect(result.execution_time_ms).to eq(1250.5)
    end

    it "provides timestamp accessor" do
      expect(result.timestamp).to eq("2025-01-01T00:00:00Z")
    end

    it "provides evaluator_name accessor" do
      expect(result.evaluator_name).to eq("quality_evaluator")
    end

    it "returns nil for missing metadata fields" do
      result_no_meta = described_class.new(field_results: field_results)
      expect(result_no_meta.execution_time_ms).to be_nil
      expect(result_no_meta.timestamp).to be_nil
    end
  end

  describe "aggregate score calculation" do
    let(:result) { described_class.new(field_results: field_results) }

    it "calculates average score across all fields" do
      # (0.9 + 0.4) / 2 = 0.65
      expect(result.average_score).to eq(0.65)
    end

    it "returns nil when no scores available" do
      result_no_scores = described_class.new(field_results: {
        "field1" => { passed: true },
        "field2" => { passed: false }
      })
      expect(result_no_scores.average_score).to be_nil
    end

    it "calculates minimum score" do
      expect(result.min_score).to eq(0.4)
    end

    it "calculates maximum score" do
      expect(result.max_score).to eq(0.9)
    end
  end

  describe "summary generation" do
    let(:result) do
      described_class.new(
        field_results: field_results,
        configuration: configuration,
        metadata: metadata
      )
    end

    it "generates a summary hash" do
      summary = result.summary

      expect(summary).to include(
        passed: false,
        passed_fields: 1,
        failed_fields: 1,
        total_fields: 2,
        average_score: 0.65,
        configuration_name: "baseline",
        execution_time_ms: 1250.5
      )
    end
  end
end