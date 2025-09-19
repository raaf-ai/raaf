# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::PipelineDSL::FieldMismatchError do
  describe "#initialize" do
    it "accepts message and context details" do
      error = described_class.new(
        "Field mismatch detected",
        agent: "TestAgent",
        expected_fields: [:name, :age],
        actual_fields: [:name, :email],
        missing_fields: [:age],
        extra_fields: [:email]
      )

      expect(error.message).to eq("Field mismatch detected")
      expect(error.agent).to eq("TestAgent")
      expect(error.expected_fields).to eq([:name, :age])
      expect(error.actual_fields).to eq([:name, :email])
      expect(error.missing_fields).to eq([:age])
      expect(error.extra_fields).to eq([:email])
    end

    it "accepts message only" do
      error = described_class.new("Simple error message")
      expect(error.message).to eq("Simple error message")
      expect(error.agent).to be_nil
      expect(error.expected_fields).to be_nil
      expect(error.actual_fields).to be_nil
      expect(error.missing_fields).to be_nil
      expect(error.extra_fields).to be_nil
    end

    it "has default message when none provided" do
      error = described_class.new(nil, agent: "TestAgent")
      expect(error.message).to include("Field mismatch")
      expect(error.agent).to eq("TestAgent")
    end
  end

  describe "attribute readers" do
    let(:error) do
      described_class.new(
        "Test error",
        agent: "DataProcessor",
        expected_fields: [:id, :name, :status],
        actual_fields: [:id, :description],
        missing_fields: [:name, :status],
        extra_fields: [:description]
      )
    end

    it "provides access to agent name" do
      expect(error.agent).to eq("DataProcessor")
    end

    it "provides access to expected fields" do
      expect(error.expected_fields).to eq([:id, :name, :status])
    end

    it "provides access to actual fields" do
      expect(error.actual_fields).to eq([:id, :description])
    end

    it "provides access to missing fields" do
      expect(error.missing_fields).to eq([:name, :status])
    end

    it "provides access to extra fields" do
      expect(error.extra_fields).to eq([:description])
    end
  end

  describe "inheritance" do
    it "inherits from StandardError" do
      expect(described_class).to be < StandardError
    end

    it "can be caught as StandardError" do
      expect {
        raise described_class.new("Test error")
      }.to raise_error(StandardError, "Test error")
    end

    it "can be caught specifically" do
      expect {
        raise described_class.new("Test error")
      }.to raise_error(described_class, "Test error")
    end
  end

  describe "error context" do
    it "provides helpful context for debugging" do
      error = described_class.new(
        "Pipeline validation failed",
        agent: "DataValidator",
        expected_fields: [:user_id, :email, :name],
        actual_fields: [:user_id, :username],
        missing_fields: [:email, :name],
        extra_fields: [:username]
      )

      # Error should contain all relevant debugging information
      expect(error.agent).to eq("DataValidator")
      expect(error.missing_fields).to include(:email, :name)
      expect(error.extra_fields).to include(:username)
    end

    it "handles empty field arrays" do
      error = described_class.new(
        "No field mismatches",
        agent: "PerfectAgent",
        expected_fields: [:id, :name],
        actual_fields: [:id, :name],
        missing_fields: [],
        extra_fields: []
      )

      expect(error.missing_fields).to eq([])
      expect(error.extra_fields).to eq([])
    end

    it "handles nil field arrays" do
      error = described_class.new(
        "Unknown field state",
        agent: "UnknownAgent",
        expected_fields: nil,
        actual_fields: nil,
        missing_fields: nil,
        extra_fields: nil
      )

      expect(error.expected_fields).to be_nil
      expect(error.actual_fields).to be_nil
      expect(error.missing_fields).to be_nil
      expect(error.extra_fields).to be_nil
    end
  end

  describe "usage in pipeline validation" do
    it "can be raised with comprehensive field analysis" do
      # Simulate a pipeline validation scenario
      expected = [:id, :name, :email, :status]
      actual = [:id, :name, :description, :created_at]
      missing = expected - actual
      extra = actual - expected

      expect {
        raise described_class.new(
          "Agent output fields don't match pipeline requirements",
          agent: "UserProcessor",
          expected_fields: expected,
          actual_fields: actual,
          missing_fields: missing,
          extra_fields: extra
        )
      }.to raise_error(described_class) do |error|
        expect(error.missing_fields).to include(:email, :status)
        expect(error.extra_fields).to include(:description, :created_at)
      end
    end

    it "supports pipeline debugging workflows" do
      # Create error as if from pipeline validation
      validation_error = described_class.new(
        "Field validation failed in pipeline step 2",
        agent: "DataEnricher",
        expected_fields: [:user_data, :enriched_data],
        actual_fields: [:user_data, :raw_enrichment],
        missing_fields: [:enriched_data],
        extra_fields: [:raw_enrichment]
      )

      # Error should provide everything needed for debugging
      expect(validation_error.agent).to eq("DataEnricher")
      expect(validation_error.missing_fields).to eq([:enriched_data])
      expect(validation_error.extra_fields).to eq([:raw_enrichment])

      # Should be able to construct helpful debug messages
      debug_info = {
        step: "Pipeline Step 2",
        agent: validation_error.agent,
        issue: "Missing required fields: #{validation_error.missing_fields.join(', ')}",
        suggestion: "Check agent output schema"
      }

      expect(debug_info[:agent]).to eq("DataEnricher")
      expect(debug_info[:issue]).to include("enriched_data")
    end
  end

  describe "string representation" do
    let(:detailed_error) do
      described_class.new(
        "Complex validation error",
        agent: "ComplexAgent",
        expected_fields: [:a, :b, :c],
        actual_fields: [:a, :d],
        missing_fields: [:b, :c],
        extra_fields: [:d]
      )
    end

    it "includes error message in string representation" do
      expect(detailed_error.to_s).to include("Complex validation error")
    end

    it "provides useful inspect output" do
      inspect_output = detailed_error.inspect
      expect(inspect_output).to include("FieldMismatchError")
      expect(inspect_output).to include("ComplexAgent")
    end
  end

  describe "edge cases" do
    it "handles very long field lists" do
      long_expected = (1..100).map { |i| "field_#{i}".to_sym }
      long_actual = (50..150).map { |i| "field_#{i}".to_sym }
      missing = long_expected - long_actual
      extra = long_actual - long_expected

      error = described_class.new(
        "Large field mismatch",
        expected_fields: long_expected,
        actual_fields: long_actual,
        missing_fields: missing,
        extra_fields: extra
      )

      expect(error.missing_fields.size).to eq(49) # fields 1-49
      expect(error.extra_fields.size).to eq(49)   # fields 101-150
    end

    it "handles special characters in field names" do
      error = described_class.new(
        "Special char test",
        expected_fields: [:"field-with-dashes", :"field_with_underscores", :"field.with.dots"],
        actual_fields: [:"field-with-dashes", :"field with spaces"],
        missing_fields: [:"field_with_underscores", :"field.with.dots"],
        extra_fields: [:"field with spaces"]
      )

      expect(error.missing_fields).to include(:"field_with_underscores", :"field.with.dots")
      expect(error.extra_fields).to include(:"field with spaces")
    end
  end
end