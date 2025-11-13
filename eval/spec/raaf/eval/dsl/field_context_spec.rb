# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Eval::DSL::FieldContext do
  let(:result_hash) do
    {
      output: "This is the AI output",
      baseline_output: "This is the baseline output",
      usage: {
        total_tokens: 150,
        prompt_tokens: 50,
        completion_tokens: 100
      },
      baseline_usage: {
        total_tokens: 120,
        prompt_tokens: 40,
        completion_tokens: 80
      },
      configuration: {
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000
      },
      latency_ms: 250.5,
      metadata: {
        version: "1.0",
        timestamp: "2025-01-01T00:00:00Z"
      }
    }
  end

  describe "field value extraction with nested paths" do
    it "extracts simple field values" do
      context = described_class.new("output", result_hash)
      expect(context.value).to eq("This is the AI output")
    end

    it "extracts nested field values using dot notation" do
      context = described_class.new("usage.total_tokens", result_hash)
      expect(context.value).to eq(150)
    end

    it "extracts deeply nested field values" do
      context = described_class.new("metadata.timestamp", result_hash)
      expect(context.value).to eq("2025-01-01T00:00:00Z")
    end
  end

  describe "baseline_value auto-detection" do
    it "automatically detects baseline_ prefixed fields" do
      context = described_class.new("output", result_hash)
      expect(context.baseline_value).to eq("This is the baseline output")
    end

    it "detects baseline values for nested fields" do
      context = described_class.new("usage.total_tokens", result_hash)
      expect(context.baseline_value).to eq(120)
    end

    it "returns nil when no baseline field exists" do
      context = described_class.new("metadata.version", result_hash)
      expect(context.baseline_value).to be_nil
    end
  end

  describe "delta calculation for numeric fields" do
    context "with numeric values" do
      it "calculates absolute delta" do
        context = described_class.new("usage.total_tokens", result_hash)
        expect(context.delta).to eq(30)  # 150 - 120
      end

      it "calculates percentage delta" do
        context = described_class.new("usage.total_tokens", result_hash)
        expect(context.delta_percentage).to eq(25.0)  # ((150 - 120) / 120.0) * 100
      end

      it "returns nil delta when baseline is missing" do
        context = described_class.new("latency_ms", result_hash)
        expect(context.delta).to be_nil
        expect(context.delta_percentage).to be_nil
      end
    end

    context "with non-numeric values" do
      it "returns nil for delta on string fields" do
        context = described_class.new("output", result_hash)
        expect(context.delta).to be_nil
        expect(context.delta_percentage).to be_nil
      end
    end
  end

  describe "convenience accessors" do
    it "provides output accessor" do
      context = described_class.new("usage.total_tokens", result_hash)
      expect(context.output).to eq("This is the AI output")
    end

    it "provides baseline_output accessor" do
      context = described_class.new("usage.total_tokens", result_hash)
      expect(context.baseline_output).to eq("This is the baseline output")
    end

    it "provides usage accessor" do
      context = described_class.new("output", result_hash)
      expect(context.usage).to eq(result_hash[:usage])
    end

    it "provides baseline_usage accessor" do
      context = described_class.new("output", result_hash)
      expect(context.baseline_usage).to eq(result_hash[:baseline_usage])
    end

    it "provides latency_ms accessor" do
      context = described_class.new("output", result_hash)
      expect(context.latency_ms).to eq(250.5)
    end

    it "provides configuration accessor" do
      context = described_class.new("output", result_hash)
      expect(context.configuration).to eq(result_hash[:configuration])
    end
  end

  describe "field_exists? method" do
    it "returns true for existing fields" do
      context = described_class.new("output", result_hash)
      expect(context.field_exists?("output")).to be true
      expect(context.field_exists?("usage.total_tokens")).to be true
    end

    it "returns false for non-existing fields" do
      context = described_class.new("output", result_hash)
      expect(context.field_exists?("nonexistent")).to be false
      expect(context.field_exists?("usage.nonexistent")).to be false
    end
  end

  describe "error handling for missing fields" do
    it "raises clear error when field is missing" do
      expect {
        described_class.new("missing_field", result_hash)
      }.to raise_error(RAAF::Eval::DSL::FieldNotFoundError, /Field 'missing_field' not found/)
    end

    it "raises error for missing nested field" do
      expect {
        described_class.new("usage.missing_tokens", result_hash)
      }.to raise_error(RAAF::Eval::DSL::FieldNotFoundError, /Field 'usage.missing_tokens' not found/)
    end
  end

  describe "[] and full_result methods" do
    let(:context) { described_class.new("output", result_hash) }

    it "provides [] method to access any field" do
      expect(context[:output]).to eq("This is the AI output")
      expect(context[:usage]).to eq(result_hash[:usage])
      expect(context["configuration"]).to eq(result_hash[:configuration])
    end

    it "supports nested paths in [] method" do
      expect(context["usage.total_tokens"]).to eq(150)
      expect(context["metadata.version"]).to eq("1.0")
    end

    it "returns full_result hash" do
      expect(context.full_result).to eq(result_hash)
    end
  end

  describe "HashWithIndifferentAccess support" do
    let(:indifferent_hash) do
      ActiveSupport::HashWithIndifferentAccess.new(result_hash)
    end

    it "works with HashWithIndifferentAccess" do
      context = described_class.new("output", indifferent_hash)
      expect(context.value).to eq("This is the AI output")
      expect(context[:usage][:total_tokens]).to eq(150)
    end

    it "handles symbol and string field names interchangeably" do
      context = described_class.new(:output, indifferent_hash)
      expect(context.value).to eq("This is the AI output")

      context2 = described_class.new("output", indifferent_hash)
      expect(context2.value).to eq("This is the AI output")
    end
  end
end