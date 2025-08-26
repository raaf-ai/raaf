# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/raaf/schema_validator'

RSpec.describe RAAF::SchemaValidator do
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
        company_name: { type: "string" },
        employee_count: { type: "integer" },
        market_sector: { type: "string" },
        annual_revenue: { type: "number" }
      },
      required: ["company_name"],
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
  end

  describe "#validate - tolerant mode" do
    let(:validator) { described_class.new(tolerant_schema, mode: :tolerant) }

    context "with key normalization" do
      it "normalizes field names from natural language to schema format" do
        # LLM returns natural language field names
        data = {
          "Company Name" => "ACME Corp",
          "Employee Count" => 500,
          "Market Sector" => "technology",
          "Annual Revenue" => 50000000
        }
        
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:data][:company_name]).to eq("ACME Corp")
        expect(result[:data][:employee_count]).to eq(500)
        expect(result[:data][:market_sector]).to eq("technology")
        expect(result[:data][:annual_revenue]).to eq(50000000)
      end

      it "handles various key formats" do
        data = {
          "Company-Name" => "ACME Corp",
          "employee_count" => 500,
          "Market Sector" => "tech",
          "annualRevenue" => 50000000
        }
        
        result = validator.validate(data)
        
        expect(result[:valid]).to be true
        expect(result[:data][:company_name]).to eq("ACME Corp")
        expect(result[:data][:employee_count]).to eq(500)
        expect(result[:data][:market_sector]).to eq("tech")
        expect(result[:data][:annual_revenue]).to eq(50000000)
      end
    end

    context "with JSON string input" do
      it "parses and validates JSON strings" do
        json_string = '{"Company Name": "ACME Corp", "Employee Count": 500}'
        result = validator.validate(json_string)
        
        expect(result[:valid]).to be true
        expect(result[:data][:company_name]).to eq("ACME Corp")
        expect(result[:data][:employee_count]).to eq(500)
      end

      it "handles malformed JSON with repair" do
        malformed_json = '{"Company Name": "ACME Corp", "Employee Count": 500,}'
        result = validator.validate(malformed_json)
        
        expect(result[:valid]).to be true
        expect(result[:data][:company_name]).to eq("ACME Corp")
        expect(result[:data][:employee_count]).to eq(500)
      end

      it "handles JSON wrapped in markdown" do
        markdown_json = <<~MD
          Here's the company data:
          ```json
          {"Company Name": "ACME Corp", "Employee Count": 500}
          ```
        MD
        result = validator.validate(markdown_json)
        
        expect(result[:valid]).to be true
        expect(result[:data][:company_name]).to eq("ACME Corp")
        expect(result[:data][:employee_count]).to eq(500)
      end
    end
  end

  describe "#validate - partial mode" do
    let(:validator) { described_class.new(tolerant_schema, mode: :partial) }

    it "accepts whatever fields validate and ignores invalid ones" do
      data = {
        "Company Name" => "ACME Corp",
        "Employee Count" => "not_a_number",  # Invalid
        "Market Sector" => "technology",
        "Invalid Field" => { "complex": "data" }
      }
      
      result = validator.validate(data)
      
      expect(result[:valid]).to be true
      expect(result[:partial]).to be true
      expect(result[:data][:company_name]).to eq("ACME Corp")
      expect(result[:data][:market_sector]).to eq("technology")
      expect(result[:warnings]).to include(/Field Employee Count/)
    end
  end

  describe "#normalize_data_keys" do
    let(:validator) { described_class.new(tolerant_schema) }

    it "normalizes various key formats to match schema" do
      data = {
        "Company Name" => "ACME",
        "company-name" => "should not override",  # Won't override because first match wins
        "EMPLOYEE_COUNT" => 100,
        "marketSector" => "tech",
        "Annual-Revenue" => 1000000
      }
      
      normalized = validator.normalize_data_keys(data)
      
      expect(normalized[:company_name]).to eq("ACME")  # First match wins
      expect(normalized[:employee_count]).to eq(100)
      expect(normalized[:market_sector]).to eq("tech")
      expect(normalized[:annual_revenue]).to eq(1000000)
    end

    it "handles nested objects recursively" do
      nested_schema = {
        properties: {
          user_details: {
            type: "object",
            properties: {
              first_name: { type: "string" },
              last_name: { type: "string" }
            }
          }
        }
      }
      
      validator = described_class.new(nested_schema)
      data = {
        "User Details" => {
          "First Name" => "John",
          "Last Name" => "Doe"
        }
      }
      
      normalized = validator.normalize_data_keys(data)
      
      expect(normalized[:user_details][:first_name]).to eq("John")
      expect(normalized[:user_details][:last_name]).to eq("Doe")
    end
  end

  describe "#statistics" do
    let(:validator) { described_class.new(basic_schema) }

    it "tracks validation metrics" do
      # Perform some validations
      validator.validate({ name: "John" })  # Success
      validator.validate({ age: 30 })       # Failure (missing required field)
      
      stats = validator.statistics
      
      expect(stats[:total_attempts]).to eq(2)
      expect(stats[:success_rate]).to eq(0.5)  # 1 success out of 2 attempts
    end

    it "returns no_data flag when no attempts made" do
      stats = validator.statistics
      expect(stats[:no_data]).to be true
    end
  end

  describe "underscore_string method" do
    let(:validator) { described_class.new(basic_schema) }

    it "converts various string formats to underscore" do
      # Test the private method indirectly through normalize_data_keys
      test_data = {
        "CamelCase" => 1,
        "kebab-case" => 2,
        "snake_case" => 3,
        "Space Separated" => 4,
        "HTTPResponse" => 5,
        "XMLHttpRequest" => 6
      }
      
      # We'll test this by checking that different formats get normalized to the same key
      schema_with_various_keys = {
        properties: {
          camel_case: { type: "integer" },
          kebab_case: { type: "integer" },
          snake_case: { type: "integer" },
          space_separated: { type: "integer" },
          http_response: { type: "integer" },
          xml_http_request: { type: "integer" }
        }
      }
      
      validator = described_class.new(schema_with_various_keys)
      normalized = validator.normalize_data_keys(test_data)
      
      expect(normalized.keys).to include(:camel_case, :kebab_case, :snake_case, :space_separated)
    end
  end
end