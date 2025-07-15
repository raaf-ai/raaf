# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenAIAgents::StructuredOutput" do
  describe "BaseSchema" do
    let(:schema) do
      {
        type: "object",
        properties: {
          name: { type: "string" },
          age: { type: "integer", minimum: 0, maximum: 150 }
        },
        required: ["name"],
        additionalProperties: false
      }
    end

    let(:base_schema) { OpenAIAgents::StructuredOutput::BaseSchema.new(schema) }

    describe "#initialize" do
      it "creates a schema with valid JSON schema" do
        expect(base_schema.schema).to eq(schema)
      end

      it "raises SchemaError for invalid schema" do
        expect do
          OpenAIAgents::StructuredOutput::BaseSchema.new(nil)
        end.to raise_error(OpenAIAgents::StructuredOutput::SchemaError, "Schema must be a hash")
      end
    end

    describe "#validate" do
      it "validates correct data" do
        valid_data = { "name" => "Alice", "age" => 25 }
        result = base_schema.validate(valid_data)
        expect(result).to eq(valid_data)
      end

      it "raises ValidationError for missing required fields" do
        invalid_data = { "age" => 25 }
        expect do
          base_schema.validate(invalid_data)
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /Missing required field 'name'/)
      end

      it "raises ValidationError for wrong type" do
        invalid_data = { "name" => "Alice", "age" => "twenty-five" }
        expect do
          base_schema.validate(invalid_data)
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /Expected number.*got String/)
      end

      it "raises ValidationError for out of range values" do
        invalid_data = { "name" => "Alice", "age" => 200 }
        expect do
          base_schema.validate(invalid_data)
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /greater than maximum 150/)
      end

      it "raises ValidationError for additional properties when not allowed" do
        invalid_data = { "name" => "Alice", "age" => 25, "city" => "Seattle" }
        expect do
          base_schema.validate(invalid_data)
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /Additional property 'city' not allowed/)
      end
    end

    describe "#to_h" do
      it "returns schema as hash" do
        expect(base_schema.to_h).to eq(schema)
      end
    end

    describe "#to_json" do
      it "returns schema as JSON string" do
        json = base_schema.to_json
        parsed = JSON.parse(json)
        # JSON.parse converts all keys to strings, including nested ones
        expect(parsed).to be_a(Hash)
        expect(parsed["type"]).to eq("object")
        expect(parsed["properties"]).to include("name", "age")
        expect(parsed["required"]).to eq(["name"])
      end
    end
  end

  describe "ObjectSchema" do
    describe "#initialize" do
      it "creates object schema with properties" do
        properties = { name: { type: "string" }, age: { type: "integer" } }
        schema = OpenAIAgents::StructuredOutput::ObjectSchema.new(properties: properties)
        
        expect(schema.schema[:type]).to eq("object")
        expect(schema.schema[:properties]).to eq(properties)
      end

      it "sets required fields" do
        schema = OpenAIAgents::StructuredOutput::ObjectSchema.new(
          properties: { name: { type: "string" } },
          required: ["name"]
        )
        
        expect(schema.schema[:required]).to eq(["name"])
      end

      it "sets additionalProperties" do
        schema = OpenAIAgents::StructuredOutput::ObjectSchema.new(
          properties: { name: { type: "string" } },
          additional_properties: false
        )
        
        expect(schema.schema[:additionalProperties]).to be false
      end
    end

    describe ".build" do
      it "creates schema using builder pattern" do
        schema = OpenAIAgents::StructuredOutput::ObjectSchema.build do
          string :name, minLength: 1
          integer :age, minimum: 0, maximum: 150
          boolean :active
          array :tags, items: { type: "string" }, minItems: 1
          
          required :name, :active
          no_additional_properties
        end

        expect(schema.schema[:type]).to eq("object")
        expect(schema.schema[:properties]).to include(
          name: { type: "string", minLength: 1 },
          age: { type: "integer", minimum: 0, maximum: 150 },
          active: { type: "boolean" },
          tags: { type: "array", items: { type: "string" }, minItems: 1 }
        )
        expect(schema.schema[:required]).to contain_exactly(:name, :active)
        expect(schema.schema[:additionalProperties]).to be false
      end

      it "supports nested objects" do
        schema = OpenAIAgents::StructuredOutput::ObjectSchema.build do
          string :name
          object :address, properties: {
            street: { type: "string" },
            city: { type: "string" }
          }, required: ["city"]
        end

        address_props = schema.schema[:properties][:address]
        expect(address_props[:type]).to eq("object")
        expect(address_props[:properties]).to include(
          street: { type: "string" },
          city: { type: "string" }
        )
        expect(address_props[:required]).to eq(["city"])
      end

      it "supports enum constraints" do
        schema = OpenAIAgents::StructuredOutput::ObjectSchema.build do
          string :status, enum: %w[active inactive pending]
        end

        expect(schema.schema[:properties][:status][:enum]).to eq(%w[active inactive pending])
      end
    end
  end

  describe "ArraySchema" do
    describe "#initialize" do
      it "creates array schema with item type" do
        schema = OpenAIAgents::StructuredOutput::ArraySchema.new(
          items: { type: "string" },
          min_items: 1,
          max_items: 10
        )

        expect(schema.schema[:type]).to eq("array")
        expect(schema.schema[:items]).to eq(type: "string")
        expect(schema.schema[:minItems]).to eq(1)
        expect(schema.schema[:maxItems]).to eq(10)
      end
    end

    describe "#validate" do
      let(:array_schema) do
        OpenAIAgents::StructuredOutput::ArraySchema.new(
          items: { type: "string" },
          min_items: 1,
          max_items: 3
        )
      end

      it "validates correct array" do
        valid_data = %w[item1 item2]
        result = array_schema.validate(valid_data)
        expect(result).to eq(valid_data)
      end

      it "raises ValidationError for non-array" do
        expect do
          array_schema.validate("not an array")
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /Expected array/)
      end

      it "raises ValidationError for too few items" do
        expect do
          array_schema.validate([])
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /has fewer than 1 items/)
      end

      it "raises ValidationError for too many items" do
        expect do
          array_schema.validate(%w[a b c d])
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /has more than 3 items/)
      end

      it "raises ValidationError for wrong item type" do
        expect do
          array_schema.validate(["string", 123])
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /Expected string/)
      end
    end
  end

  describe "StringSchema" do
    describe "#initialize" do
      it "creates string schema with constraints" do
        schema = OpenAIAgents::StructuredOutput::StringSchema.new(
          min_length: 1,
          max_length: 50,
          pattern: "^[A-Za-z]+$",
          enum: %w[admin user guest]
        )

        expect(schema.schema[:type]).to eq("string")
        expect(schema.schema[:minLength]).to eq(1)
        expect(schema.schema[:maxLength]).to eq(50)
        expect(schema.schema[:pattern]).to eq("^[A-Za-z]+$")
        expect(schema.schema[:enum]).to eq(%w[admin user guest])
      end
    end

    describe "#validate" do
      let(:string_schema) do
        OpenAIAgents::StructuredOutput::StringSchema.new(
          min_length: 2,
          max_length: 10,
          pattern: "^[A-Za-z]+$"
        )
      end

      it "validates correct string" do
        valid_data = "Alice"
        result = string_schema.validate(valid_data)
        expect(result).to eq(valid_data)
      end

      it "raises ValidationError for non-string" do
        expect do
          string_schema.validate(123)
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /Expected string/)
      end

      it "raises ValidationError for too short string" do
        expect do
          string_schema.validate("A")
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /is shorter than 2 characters/)
      end

      it "raises ValidationError for too long string" do
        expect do
          string_schema.validate("VeryLongName")
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /is longer than 10 characters/)
      end

      it "raises ValidationError for pattern mismatch" do
        expect do
          string_schema.validate("Alice123")
        end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /doesn't match pattern/)
      end

      context "with enum constraint" do
        let(:enum_schema) do
          OpenAIAgents::StructuredOutput::StringSchema.new(
            enum: %w[red green blue]
          )
        end

        it "validates enum values" do
          result = enum_schema.validate("red")
          expect(result).to eq("red")
        end

        it "raises ValidationError for invalid enum value" do
          expect do
            enum_schema.validate("yellow")
          end.to raise_error(OpenAIAgents::StructuredOutput::ValidationError, /is not one of/)
        end
      end
    end
  end

  describe "ResponseFormatter" do
    let(:schema) do
      {
        type: "object",
        properties: {
          name: { type: "string" },
          age: { type: "integer" }
        },
        required: ["name"],
        additionalProperties: false
      }
    end

    let(:formatter) { OpenAIAgents::StructuredOutput::ResponseFormatter.new(schema) }

    describe "#format_response" do
      it "formats valid data" do
        data = { "name" => "Alice", "age" => 25 }
        result = formatter.format_response(data)
        expect(result[:data]).to eq(data)
        expect(result[:valid]).to be true
        expect(result[:schema]).to eq(schema)
      end

      it "returns error for invalid data" do
        data = { "age" => 25 } # missing required name
        result = formatter.format_response(data)
        expect(result[:data]).to eq(data)
        expect(result[:valid]).to be false
        expect(result[:error]).to include("Missing required field")
      end
    end

    describe "#validate_and_format" do
      it "parses JSON and validates" do
        json_string = '{"name": "Alice", "age": 25}'
        result = formatter.validate_and_format(json_string)
        expect(result[:data]).to eq({ "name" => "Alice", "age" => 25 })
        expect(result[:valid]).to be true
      end

      it "returns error for invalid JSON" do
        invalid_json = '{"name": "Alice", "age":'
        result = formatter.validate_and_format(invalid_json)
        expect(result[:data]).to eq(invalid_json)
        expect(result[:valid]).to be false
        expect(result[:error]).to include("Invalid JSON")
      end

      it "returns error for schema violation" do
        json_string = '{"age": 25}' # missing required name
        result = formatter.validate_and_format(json_string)
        expect(result[:data]).to eq({ "age" => 25 })
        expect(result[:valid]).to be false
        expect(result[:error]).to include("Missing required field")
      end
    end
  end
end