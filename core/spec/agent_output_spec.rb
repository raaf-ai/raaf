# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF Agent Output Schemas" do
  describe RAAF::AgentOutputSchemaBase do
    let(:schema) { described_class.new }

    describe "abstract interface" do
      it "raises NotImplementedError for plain_text?" do
        expect { schema.plain_text? }.to raise_error(NotImplementedError, "Subclasses must implement #plain_text?")
      end

      it "raises NotImplementedError for name" do
        expect { schema.name }.to raise_error(NotImplementedError, "Subclasses must implement #name")
      end

      it "raises NotImplementedError for validate_response" do
        expect { schema.validate_response("test") }.to raise_error(NotImplementedError, "Subclasses must implement #validate_response")
      end

      it "raises NotImplementedError for validate_json" do
        expect { schema.validate_json("test") }.to raise_error(NotImplementedError, "Subclasses must implement #validate_json")
      end
    end
  end

  describe RAAF::AgentOutputSchema do
    describe "#initialize" do
      it "initializes with nil output type" do
        schema = described_class.new(nil)
        expect(schema.output_type).to be_nil
        expect(schema.plain_text?).to be true
      end

      it "initializes with String output type" do
        schema = described_class.new(String)
        expect(schema.output_type).to eq(String)
        expect(schema.plain_text?).to be true
      end

      it "initializes with custom output type" do
        custom_class = Class.new
        schema = described_class.new(custom_class)
        expect(schema.output_type).to eq(custom_class)
        expect(schema.plain_text?).to be false
      end

      it "initializes with hash output type" do
        schema = described_class.new(Hash)
        expect(schema.output_type).to eq(Hash)
        expect(schema.plain_text?).to be false
      end

      it "initializes with array output type" do
        schema = described_class.new(Array)
        expect(schema.output_type).to eq(Array)
        expect(schema.plain_text?).to be false
      end

      it "defaults strict_json_schema to true" do
        schema = described_class.new(String)
        expect(schema.instance_variable_get(:@strict_json_schema)).to be true
      end

      it "allows setting strict_json_schema to false" do
        schema = described_class.new(String, strict_json_schema: false)
        expect(schema.instance_variable_get(:@strict_json_schema)).to be false
      end
    end

    describe "#name" do
      it "returns 'text' for nil output type" do
        schema = described_class.new(nil)
        expect(schema.name).to eq("text")
      end

      it "returns 'text' for String output type" do
        schema = described_class.new(String)
        expect(schema.name).to eq("text")
      end

      it "returns class name for custom output type" do
        custom_class = Class.new
        schema = described_class.new(custom_class)
        expect(schema.name).to eq(custom_class.name)
      end

      it "returns 'Hash' for Hash output type" do
        schema = described_class.new(Hash)
        expect(schema.name).to eq("Hash")
      end

      it "returns 'Array' for Array output type" do
        schema = described_class.new(Array)
        expect(schema.name).to eq("Array")
      end
    end

    describe "#plain_text?" do
      it "returns true for nil output type" do
        schema = described_class.new(nil)
        expect(schema.plain_text?).to be true
      end

      it "returns true for String output type" do
        schema = described_class.new(String)
        expect(schema.plain_text?).to be true
      end

      it "returns false for Hash output type" do
        schema = described_class.new(Hash)
        expect(schema.plain_text?).to be false
      end

      it "returns false for Array output type" do
        schema = described_class.new(Array)
        expect(schema.plain_text?).to be false
      end

      it "returns false for custom output type" do
        custom_class = Class.new
        schema = described_class.new(custom_class)
        expect(schema.plain_text?).to be false
      end
    end

    describe "#json_schema" do
      it "returns nil for nil output type" do
        schema = described_class.new(nil)
        expect(schema.json_schema).to be_nil
      end

      it "returns nil for String output type" do
        schema = described_class.new(String)
        expect(schema.json_schema).to be_nil
      end

      it "returns object schema for Hash output type" do
        schema = described_class.new(Hash, strict_json_schema: false)
        expect(schema.json_schema).to eq({
                                           type: "object",
                                           additionalProperties: true
                                         })
      end

      it "returns array schema for Array output type" do
        schema = described_class.new(Array)
        expect(schema.json_schema).to eq({
                                           type: "array",
                                           items: {}
                                         })
      end

      it "returns custom schema for class with json_schema method" do
        custom_class = Class.new do
          def self.json_schema
            { type: "custom", properties: { name: { type: "string" } } }
          end
        end

        schema = described_class.new(custom_class)
        expect(schema.json_schema).to eq({
                                           type: "custom",
                                           properties: { name: { type: "string" } }
                                         })
      end

      it "returns wrapped object schema for unknown custom types" do
        custom_class = Class.new
        schema = described_class.new(custom_class, strict_json_schema: false)
        expect(schema.json_schema).to eq({
                                           type: "object",
                                           properties: {
                                             response: {
                                               type: "object",
                                               additionalProperties: true,
                                               properties: {}
                                             }
                                           },
                                           required: ["response"],
                                           additionalProperties: false
                                         })
      end
    end

    describe "#validate_response" do
      context "with plain text response" do
        it "validates string response for nil output type" do
          schema = described_class.new(nil)
          result = schema.validate_response("Hello")
          expect(result).to eq("Hello")
        end

        it "validates string response for String output type" do
          schema = described_class.new(String)
          result = schema.validate_response("Hello")
          expect(result).to eq("Hello")
        end

        it "raises error for non-string response with String output type" do
          schema = described_class.new(String)
          expect do
            schema.validate_response({ message: "Hello" })
          end.to raise_error(ArgumentError, /Expected String, got Hash/)
        end
      end

      context "with structured response" do
        it "validates hash response for Hash output type" do
          schema = described_class.new(Hash)
          data = { message: "Hello", status: "success" }
          result = schema.validate_response(data)
          expect(result).to eq(data)
        end

        it "validates array response for Array output type" do
          schema = described_class.new(Array)
          data = %w[item1 item2 item3]
          result = schema.validate_response(data)
          expect(result).to eq(data)
        end

        it "raises error for wrong type with Hash output type" do
          schema = described_class.new(Hash)
          expect do
            schema.validate_response("Not a hash")
          end.to raise_error(RAAF::Errors::ModelBehaviorError, /Expected Hash, got String/)
        end

        it "raises error for wrong type with Array output type" do
          schema = described_class.new(Array)
          expect do
            schema.validate_response({ not: "array" })
          end.to raise_error(RAAF::Errors::ModelBehaviorError, /Expected Array, got Hash/)
        end
      end

      context "with custom output type" do
        let(:custom_class) do
          Class.new do
            attr_accessor :name, :value

            def initialize(name: nil, value: nil)
              @name = name
              @value = value
            end

            def self.from_hash(hash)
              new(name: hash[:name] || hash["name"],
                  value: hash[:value] || hash["value"])
            end

            def ==(other)
              other.is_a?(self.class) && name == other.name && value == other.value
            end
          end
        end

        it "validates custom object with from_hash method" do
          schema = described_class.new(custom_class)
          data = { name: "test", value: 42 }
          result = schema.validate_response(data)

          expect(result).to be_a(custom_class)
          expect(result.name).to eq("test")
          expect(result.value).to eq(42)
        end

        it "passes through already correct custom type" do
          schema = described_class.new(custom_class)
          instance = custom_class.new(name: "existing", value: 100)
          result = schema.validate_response(instance)

          expect(result).to eq(instance)
        end

        it "raises error for incompatible type" do
          schema = described_class.new(custom_class)
          expect do
            schema.validate_response("incompatible")
          end.to raise_error(ArgumentError)
        end
      end
    end

    describe "#validate_json" do
      context "with strict JSON schema validation" do
        it "validates JSON string against Hash schema" do
          schema = described_class.new(Hash, strict_json_schema: true)
          json_string = '{"message": "Hello", "status": "success"}'
          result = schema.validate_json(json_string)

          expect(result).to eq({ "message" => "Hello", "status" => "success" })
        end

        it "validates JSON string against Array schema" do
          schema = described_class.new(Array, strict_json_schema: true)
          json_string = '["item1", "item2", "item3"]'
          result = schema.validate_json(json_string)

          expect(result).to eq(%w[item1 item2 item3])
        end

        it "raises error for invalid JSON" do
          schema = described_class.new(Hash, strict_json_schema: true)
          expect do
            schema.validate_json("invalid json")
          end.to raise_error(RAAF::Errors::ModelBehaviorError, /Invalid JSON/)
        end

        it "raises error for JSON type mismatch" do
          schema = described_class.new(Hash, strict_json_schema: true)
          json_string = '["not", "a", "hash"]'
          expect do
            schema.validate_json(json_string)
          end.to raise_error(RAAF::Errors::ModelBehaviorError, /Expected Hash, got Array/)
        end
      end

      context "with non-strict JSON schema validation" do
        it "passes through parsed JSON for any structure" do
          schema = described_class.new(Hash, strict_json_schema: false)
          json_string = '["not", "a", "hash"]'
          result = schema.validate_json(json_string)

          expect(result).to eq(%w[not a hash])
        end

        it "still raises error for invalid JSON" do
          schema = described_class.new(Hash, strict_json_schema: false)
          expect do
            schema.validate_json("invalid json")
          end.to raise_error(RAAF::Errors::ModelBehaviorError, /Invalid JSON/)
        end
      end

      context "with plain text schema" do
        it "returns JSON string as-is for nil output type" do
          schema = described_class.new(nil)
          json_string = '{"message": "Hello"}'
          result = schema.validate_json(json_string)

          expect(result).to eq(json_string)
        end

        it "returns JSON string as-is for String output type" do
          schema = described_class.new(String)
          json_string = '{"message": "Hello"}'
          result = schema.validate_json(json_string)

          expect(result).to eq(json_string)
        end
      end
    end

    describe "private methods" do
      describe "#validate_type_match" do
        it "passes validation for matching types" do
          schema = described_class.new(String)
          expect do
            schema.send(:validate_type_match, "test", String)
          end.not_to raise_error
        end

        it "raises error for mismatched types" do
          schema = described_class.new(String)
          expect do
            schema.send(:validate_type_match, 123, String)
          end.to raise_error(ArgumentError, /Expected String, got Integer/)
        end
      end

      describe "#validate_custom_type" do
        let(:custom_class) do
          Class.new do
            def self.from_hash(_hash)
              new
            end
          end
        end

        it "calls from_hash on custom class for hash data" do
          schema = described_class.new(custom_class)
          data = { test: "value" }
          expect(custom_class).to receive(:from_hash).with(data).and_call_original

          schema.send(:validate_custom_type, data)
        end

        it "returns data as-is if already correct type" do
          schema = described_class.new(custom_class)
          instance = custom_class.new
          result = schema.send(:validate_custom_type, instance)

          expect(result).to eq(instance)
        end

        it "raises error if custom class doesn't have from_hash method" do
          unknown_class = Class.new
          schema = described_class.new(unknown_class)
          expect do
            schema.send(:validate_custom_type, { test: "value" })
          end.to raise_error(ArgumentError, /Cannot convert Hash to/)
        end

        it "handles non-strict mode for unknown custom types" do
          unknown_class = Class.new
          schema = described_class.new(unknown_class, strict_json_schema: false)
          data = { "test" => "value" }
          result = schema.send(:validate_custom_type, data)
          expect(result).to eq(data)
        end
      end
    end
  end

  describe RAAF::TypeAdapter do
    describe "#initialize" do
      it "stores the provided type" do
        adapter = described_class.new(String)
        expect(adapter.type).to eq(String)
      end
    end

    describe "#validate" do
      it "validates String type correctly" do
        adapter = described_class.new(String)
        result = adapter.validate("test")
        expect(result).to eq("test")
      end

      it "validates Integer type correctly" do
        adapter = described_class.new(Integer)
        result = adapter.validate(42)
        expect(result).to eq(42)
      end

      it "validates Float type correctly" do
        adapter = described_class.new(Float)
        result = adapter.validate(3.14)
        expect(result).to eq(3.14)
      end

      it "validates Boolean types correctly" do
        adapter = described_class.new(TrueClass)
        result = adapter.validate(true)
        expect(result).to be(true)

        adapter = described_class.new(FalseClass)
        result = adapter.validate(false)
        expect(result).to be(false)
      end

      it "validates Array type correctly" do
        adapter = described_class.new(Array)
        result = adapter.validate([1, 2, 3])
        expect(result).to eq([1, 2, 3])
      end

      it "validates Hash type correctly" do
        adapter = described_class.new(Hash)
        result = adapter.validate({ key: "value" })
        expect(result).to eq({ key: "value" })
      end

      it "raises error for type mismatch" do
        adapter = described_class.new(String)
        expect do
          adapter.validate(123)
        end.to raise_error(ArgumentError, /Expected String, got Integer/)
      end
    end

    describe "#json_schema" do
      it "returns string schema for String type" do
        adapter = described_class.new(String)
        expect(adapter.json_schema).to eq({ type: "string" })
      end

      it "returns number schema for Integer type" do
        adapter = described_class.new(Integer)
        expect(adapter.json_schema).to eq({ type: "integer" })
      end

      it "returns number schema for Float type" do
        adapter = described_class.new(Float)
        expect(adapter.json_schema).to eq({ type: "number" })
      end

      it "returns boolean schema for Boolean types" do
        adapter = described_class.new(TrueClass)
        expect(adapter.json_schema).to eq({ type: "boolean" })

        adapter = described_class.new(FalseClass)
        expect(adapter.json_schema).to eq({ type: "boolean" })
      end

      it "returns array schema for Array type" do
        adapter = described_class.new(Array)
        expect(adapter.json_schema).to eq({ type: "array", items: {} })
      end

      it "returns custom schema for type with json_schema method" do
        custom_type = Class.new do
          def self.json_schema
            { type: "custom", properties: { id: { type: "integer" } } }
          end
        end

        adapter = described_class.new(custom_type)
        expect(adapter.json_schema).to eq({
                                            type: "custom",
                                            properties: { id: { type: "integer" } }
                                          })
      end

      it "returns default object schema for unknown types" do
        custom_class = Class.new
        adapter = described_class.new(custom_class)
        expect(adapter.json_schema).to eq({ type: "object", additionalProperties: true })
      end
    end
  end
end
