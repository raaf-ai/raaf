# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/raaf/dsl/schema_validator'

RSpec.describe RAAF::DSL::SchemaValidator do
  let(:basic_schema) do
    {
      type: "object",
      properties: {
        name: { type: "string" },
        age: { type: "integer" },
        active: { type: "boolean" }
      },
      required: ["name"],
      additionalProperties: false
    }
  end

  let(:tolerant_schema) do
    {
      type: "object",
      properties: {
        title: { type: "string", default: "Untitled" },
        priority: { type: "string", enum: ["low", "med", "high"], default: "med" },
        description: { type: "string", flexible: true },
        metadata: { type: "object", passthrough: true },
        count: { type: "integer", default: 0 }
      },
      required: ["title"],
      additionalProperties: true
    }
  end

  describe "#initialize" do
    it "sets default mode to tolerant" do
      validator = described_class.new(basic_schema)
      expect(validator.mode).to eq(:tolerant)
    end

    it "accepts custom mode and repair attempts" do
      validator = described_class.new(basic_schema, mode: :strict, repair_attempts: 5)
      expect(validator.mode).to eq(:strict)
      expect(validator.repair_attempts).to eq(5)
    end

    it "raises error for invalid mode" do
      expect {
        described_class.new(basic_schema, mode: :invalid)
      }.to raise_error(ArgumentError, /Unknown validation mode/)
    end
  end

  describe "#validate - strict mode" do
    let(:validator) { described_class.new(basic_schema, mode: :strict) }

    context "with valid data" do
      it "validates successfully" do
        data = { name: "John", age: 30, active: true }
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:data]).to eq(name: "John", age: 30, active: true)
        expect(result[:errors]).to be_empty
      end
    end

    context "with missing required field" do
      it "fails validation" do
        data = { age: 30, active: true }
        result = validator.validate(data)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include("Missing required field: name")
      end
    end

    context "with type mismatch" do
      it "fails validation" do
        data = { name: "John", age: "thirty", active: true }
        result = validator.validate(data)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(/Field age type mismatch/)
      end
    end

    context "with unknown field when additionalProperties is false" do
      it "fails validation" do
        data = { name: "John", unknown_field: "value" }
        result = validator.validate(data)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include("Unknown field not allowed: unknown_field")
      end
    end
  end

  describe "#validate - tolerant mode" do
    let(:validator) { described_class.new(tolerant_schema, mode: :tolerant) }

    context "with all valid data" do
      it "validates successfully" do
        data = { title: "Test", priority: "high", description: "A test item" }
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:data][:title]).to eq("Test")
        expect(result[:data][:priority]).to eq("high")
        expect(result[:warnings]).to be_empty
      end
    end

    context "with missing required field but default available" do
      it "uses default value" do
        data = { priority: "low" }
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:data][:title]).to eq("Untitled")
        expect(result[:warnings]).to include(/Using default value for required field/)
      end
    end

    context "with missing optional fields" do
      it "adds defaults for missing optional fields" do
        data = { title: "Test" }
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:data][:title]).to eq("Test")
        expect(result[:data][:priority]).to eq("med")
        expect(result[:data][:count]).to eq(0)
      end
    end

    context "with flexible field type coercion" do
      it "accepts flexible fields with type mismatch" do
        schema = {
          type: "object",
          properties: {
            name: { type: "string" },
            score: { type: "integer", flexible: true }
          },
          required: ["name"]
        }
        validator = described_class.new(schema, mode: :tolerant)
        
        data = { name: "Test", score: "123" }
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:data][:score]).to eq("123")
        expect(result[:warnings]).to include(/type mismatch, using as-is/)
      end
    end

    context "with passthrough fields" do
      it "accepts any structure for passthrough fields" do
        data = { 
          title: "Test",
          metadata: { 
            complex: { nested: { data: ["array", "of", "items"] } },
            tags: ["tag1", "tag2"]
          }
        }
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:data][:metadata]).to eq(data[:metadata])
      end
    end

    context "with unknown fields when additionalProperties is true" do
      it "captures unknown fields with warnings" do
        data = { title: "Test", unknown_field: "value", another_field: 123 }
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:data][:unknown_field]).to eq("value")
        expect(result[:data][:another_field]).to eq(123)
        expect(result[:warnings]).to include("Unknown field captured: unknown_field")
        expect(result[:warnings]).to include("Unknown field captured: another_field")
      end
    end

    context "with enum validation" do
      it "warns about invalid enum values in tolerant mode" do
        data = { title: "Test", priority: "invalid_priority" }
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:data][:priority]).to eq("invalid_priority")
        expect(result[:warnings]).to include(/value not in enum/)
      end
    end
  end

  describe "#validate - partial mode" do
    let(:validator) { described_class.new(tolerant_schema, mode: :partial) }

    context "with mixed valid and invalid data" do
      it "includes valid fields and warns about invalid ones" do
        data = { 
          title: "Test",
          priority: "invalid",
          description: 123,  # Wrong type but will be included
          invalid_field: "should be included"
        }
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:partial]).to be true
        expect(result[:data][:title]).to eq("Test")
        expect(result[:data][:priority]).to eq("invalid")
        expect(result[:data][:description]).to eq(123)
        expect(result[:data][:invalid_field]).to eq("should be included")
        expect(result[:warnings]).to_not be_empty
      end
    end

    context "with missing required fields" do
      it "provides defaults when available" do
        data = { priority: "high" }
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:partial]).to be true
        expect(result[:data][:title]).to eq("Untitled")
        expect(result[:data][:priority]).to eq("high")
        expect(result[:warnings]).to include(/Using default for missing required field/)
      end

      it "warns about missing required fields without defaults" do
        schema = {
          type: "object",
          properties: { name: { type: "string" } },
          required: ["name"]
        }
        validator = described_class.new(schema, mode: :partial)
        
        data = { other_field: "value" }
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:partial]).to be true
        expect(result[:warnings]).to include(/Missing required field with no default: name/)
      end
    end
  end

  describe "#validate with JSON strings" do
    let(:validator) { described_class.new(basic_schema, mode: :tolerant) }

    it "parses valid JSON strings" do
      json_string = '{"name": "John", "age": 30}'
      result = validator.validate(json_string)
      
      expect(result[:valid]).to be true
      expect(result[:data][:name]).to eq("John")
      expect(result[:data][:age]).to eq(30)
    end

    it "handles malformed JSON with repair" do
      # JSON with trailing comma (common error)
      json_string = '{"name": "John", "age": 30,}'
      result = validator.validate(json_string)
      
      expect(result[:valid]).to be true
      expect(result[:data][:name]).to eq("John")
      expect(result[:data][:age]).to eq(30)
    end

    it "fails gracefully with unparseable JSON" do
      invalid_json = 'this is not json at all'
      result = validator.validate(invalid_json)
      
      expect(result[:valid]).to be false
      expect(result[:errors]).to include("Unable to parse JSON from input")
    end
  end

  describe "#statistics" do
    let(:validator) { described_class.new(basic_schema, mode: :tolerant) }

    it "tracks validation statistics" do
      # Valid data
      validator.validate({ name: "John" })
      
      # Invalid data requiring repair
      validator.validate('{"name": "Jane",}')  # Trailing comma
      
      # Failed validation
      validator.validate('invalid json')
      
      stats = validator.statistics
      
      expect(stats[:total_attempts]).to eq(3)
      expect(stats[:success_rate]).to be > 0
      expect(stats[:mode]).to eq(:tolerant)
      expect(stats).to have_key(:repair_rate)
      expect(stats).to have_key(:partial_rate)
    end

    it "returns no_data flag when no attempts made" do
      stats = validator.statistics
      expect(stats[:no_data]).to be true
    end
  end

  describe "value coercion" do
    let(:flexible_schema) do
      {
        type: "object",
        properties: {
          string_field: { type: "string" },
          integer_field: { type: "integer", flexible: true },
          number_field: { type: "number", flexible: true },
          boolean_field: { type: "boolean", flexible: true },
          array_field: { type: "array", flexible: true }
        },
        required: []
      }
    end
    
    let(:validator) { described_class.new(flexible_schema, mode: :tolerant) }

    it "coerces string numbers to integers for flexible integer fields" do
      data = { integer_field: "123" }
      result = validator.validate(data)
      
      expect(result[:valid]).to be true
      expect(result[:data][:integer_field]).to eq(123)
    end

    it "coerces string numbers to floats for flexible number fields" do
      data = { number_field: "123.45" }
      result = validator.validate(data)
      
      expect(result[:valid]).to be true
      expect(result[:data][:number_field]).to eq(123.45)
    end

    it "coerces string booleans to actual booleans for flexible boolean fields" do
      data = { boolean_field: "true" }
      result = validator.validate(data)
      
      expect(result[:valid]).to be true
      expect(result[:data][:boolean_field]).to be true
    end

    it "converts single values to arrays for flexible array fields" do
      data = { array_field: "single_value" }
      result = validator.validate(data)
      
      expect(result[:valid]).to be true
      expect(result[:data][:array_field]).to eq(["single_value"])
    end
  end

  describe "repair attempts" do
    let(:schema) do
      {
        type: "object",
        properties: { name: { type: "string", default: "Default Name" } },
        required: ["name"]
      }
    end
    
    let(:validator) { described_class.new(schema, mode: :tolerant, repair_attempts: 2) }

    it "attempts repair for missing required fields" do
      # Data missing required field, but has default - should repair successfully
      data = { other_field: "value" }
      result = validator.validate(data)
      
      expect(result[:valid]).to be true
      expect(result[:data][:name]).to eq("Default Name")
    end
  end
end