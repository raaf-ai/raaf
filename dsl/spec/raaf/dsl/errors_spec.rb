# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Error do
  it "inherits from StandardError" do
    expect(described_class).to be < StandardError
  end

  it "can be instantiated with default message" do
    error = described_class.new
    expect(error).to be_a(StandardError)
    expect(error.message).to be_a(String)
  end

  it "can be instantiated with custom message" do
    error = described_class.new("Custom error message")
    expect(error.message).to eq("Custom error message")
  end
end

RSpec.describe RAAF::DSL::ParseError do
  it "inherits from RAAF::DSL::Error" do
    expect(described_class).to be < RAAF::DSL::Error
  end

  describe "#initialize" do
    it "uses default message when no message provided" do
      error = described_class.new
      expect(error.message).to eq("Failed to parse AI response")
    end

    it "accepts custom message" do
      error = described_class.new("Custom parse error")
      expect(error.message).to eq("Custom parse error")
    end
  end
end

RSpec.describe RAAF::DSL::ValidationError do
  it "inherits from RAAF::DSL::Error" do
    expect(described_class).to be < RAAF::DSL::Error
  end

  describe "#initialize" do
    it "accepts message only" do
      error = described_class.new("Validation failed")
      expect(error.message).to eq("Validation failed")
      expect(error.field).to be_nil
      expect(error.value).to be_nil
      expect(error.expected_type).to be_nil
    end

    it "accepts message with field details" do
      error = described_class.new(
        "Invalid field value",
        field: :name,
        value: 123,
        expected_type: String
      )

      expect(error.message).to eq("Invalid field value")
      expect(error.field).to eq(:name)
      expect(error.value).to eq(123)
      expect(error.expected_type).to eq(String)
    end
  end

  describe "attribute readers" do
    let(:error) do
      described_class.new(
        "Test error",
        field: :email,
        value: "invalid-email",
        expected_type: "valid email format"
      )
    end

    it "provides access to field" do
      expect(error.field).to eq(:email)
    end

    it "provides access to value" do
      expect(error.value).to eq("invalid-email")
    end

    it "provides access to expected_type" do
      expect(error.expected_type).to eq("valid email format")
    end
  end
end

RSpec.describe RAAF::DSL::SchemaError do
  it "inherits from RAAF::DSL::ValidationError" do
    expect(described_class).to be < RAAF::DSL::ValidationError
  end

  describe "#initialize" do
    it "uses default message when no message provided" do
      error = described_class.new
      expect(error.message).to eq("Response does not match expected schema")
    end

    it "accepts custom message" do
      error = described_class.new("Schema validation failed for field 'data'")
      expect(error.message).to eq("Schema validation failed for field 'data'")
    end
  end
end

RSpec.describe "Backward compatibility" do
  it "makes ParseError available at RAAF module level" do
    expect(RAAF::ParseError).to eq(RAAF::DSL::ParseError)
  end

  it "makes ValidationError available at RAAF module level" do
    expect(RAAF::ValidationError).to eq(RAAF::DSL::ValidationError)
  end

  it "makes SchemaError available at RAAF module level" do
    expect(RAAF::SchemaError).to eq(RAAF::DSL::SchemaError)
  end

  it "allows raising errors using RAAF:: namespace" do
    expect { raise RAAF::ParseError.new("Test") }.to raise_error(RAAF::DSL::ParseError, "Test")
    expect { raise RAAF::ValidationError.new("Test") }.to raise_error(RAAF::DSL::ValidationError, "Test")
    expect { raise RAAF::SchemaError.new("Test") }.to raise_error(RAAF::DSL::SchemaError, "Test")
  end
end

RSpec.describe "Error inheritance chain" do
  it "allows catching all DSL errors with base class" do
    expect {
      raise RAAF::DSL::ParseError.new("Parse failed")
    }.to raise_error(RAAF::DSL::Error)

    expect {
      raise RAAF::DSL::ValidationError.new("Validation failed")
    }.to raise_error(RAAF::DSL::Error)

    expect {
      raise RAAF::DSL::SchemaError.new("Schema failed")
    }.to raise_error(RAAF::DSL::Error)
  end

  it "allows catching validation errors with ValidationError" do
    expect {
      raise RAAF::DSL::SchemaError.new("Schema failed")
    }.to raise_error(RAAF::DSL::ValidationError)
  end

  it "allows catching all errors with StandardError" do
    expect {
      raise RAAF::DSL::ParseError.new("Any error")
    }.to raise_error(StandardError)
  end
end