# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::AgentOutputSchemaBase do
  let(:schema) { described_class.new }

  describe "abstract interface" do
    it "raises NotImplementedError for plain_text?" do
      expect { schema.plain_text? }.to raise_error(NotImplementedError, "Subclasses must implement #plain_text?")
    end

    it "raises NotImplementedError for name" do
      expect { schema.name }.to raise_error(NotImplementedError, "Subclasses must implement #name")
    end

    it "raises NotImplementedError for json_schema" do
      expect { schema.json_schema }.to raise_error(NotImplementedError, "Subclasses must implement #json_schema")
    end

    it "raises NotImplementedError for strict_json_schema?" do
      expect { schema.strict_json_schema? }.to raise_error(NotImplementedError, "Subclasses must implement #strict_json_schema?")
    end

    it "raises NotImplementedError for validate_json" do
      expect { schema.validate_json("test") }.to raise_error(NotImplementedError, "Subclasses must implement #validate_json")
    end
  end
end

RSpec.describe RAAF::AgentOutputSchema do
  describe "#initialize" do
    it "initializes with nil output type" do
      schema = described_class.new(nil)
      expect(schema.output_type).to be_nil
      expect(schema.plain_text?).to be true
      expect(schema.strict_json_schema?).to be true
    end

    it "initializes with String output type" do
      schema = described_class.new(String)
      expect(schema.output_type).to eq(String)
      expect(schema.plain_text?).to be true
    end

    it "initializes with Hash output type" do
      schema = described_class.new(Hash, strict_json_schema: false)
      expect(schema.output_type).to eq(Hash)
      expect(schema.plain_text?).to be false
    end

    it "allows disabling strict JSON schema" do
      schema = described_class.new(String, strict_json_schema: false)
      expect(schema.strict_json_schema?).to be false
    end
  end

  describe "#plain_text?" do
    it "returns true for nil type" do
      schema = described_class.new(nil)
      expect(schema.plain_text?).to be true
    end

    it "returns true for String type" do
      schema = described_class.new(String)
      expect(schema.plain_text?).to be true
    end

    it "returns false for Hash type" do
      schema = described_class.new(Hash, strict_json_schema: false)
      expect(schema.plain_text?).to be false
    end

    it "returns false for Integer type" do
      schema = described_class.new(Integer)
      expect(schema.plain_text?).to be false
    end
  end

  describe "#name" do
    it "returns 'nil' for nil type" do
      schema = described_class.new(nil)
      expect(schema.name).to eq("nil")
    end

    it "returns class name for defined types" do
      schema = described_class.new(String)
      expect(schema.name).to eq("String")
    end

    it "returns string representation for custom types" do
      custom_class = Class.new
      allow(custom_class).to receive(:name).and_return("CustomClass")
      schema = described_class.new(custom_class, strict_json_schema: false)
      expect(schema.name).to eq("CustomClass")
    end
  end

  describe "#json_schema" do
    it "raises UserError for plain text types" do
      schema = described_class.new(String)
      expect { schema.json_schema }.to raise_error(RAAF::Errors::UserError, "Output type is plain text, so no JSON schema is available")
    end

    it "returns schema for Hash type" do
      schema = described_class.new(Hash, strict_json_schema: false)
      expect(schema.json_schema).to include(type: "object", additionalProperties: true)
    end

    it "returns schema for Integer type" do
      schema = described_class.new(Integer, strict_json_schema: false)
      json_schema = schema.json_schema
      expect(json_schema[:type]).to eq("object")
      expect(json_schema[:properties][described_class::WRAPPER_DICT_KEY][:type]).to eq("integer")
    end

    it "returns schema for Array type" do
      schema = described_class.new(Array, strict_json_schema: false)
      json_schema = schema.json_schema
      expect(json_schema[:type]).to eq("object")
      expect(json_schema[:properties][described_class::WRAPPER_DICT_KEY]).to include(type: "array")
    end

    context "with custom class having json_schema method" do
      let(:custom_class) do
        Class.new do
          def self.json_schema
            { type: "object", properties: { custom: { type: "string" } } }
          end

          def self.name
            "CustomSchemaClass"
          end
        end
      end

      it "uses the class's json_schema method" do
        schema = described_class.new(custom_class, strict_json_schema: false)
        json_schema = schema.json_schema
        # Custom class with json_schema method is NOT wrapped, so it returns the schema directly
        expect(json_schema).to include(
          type: "object",
          properties: { custom: { type: "string" } }
        )
      end
    end
  end

  describe "#validate_json" do
    context "with plain text output" do
      let(:schema) { described_class.new(String) }

      it "returns input string directly" do
        expect(schema.validate_json("hello world")).to eq("hello world")
      end

      it "returns input for any string" do
        expect(schema.validate_json("123")).to eq("123")
      end
    end

    context "with Hash output" do
      let(:schema) { described_class.new(Hash, strict_json_schema: false) }

      it "parses and returns valid JSON hash" do
        json_str = '{"name": "John", "age": 30}'
        result = schema.validate_json(json_str)
        expect(result).to eq("name" => "John", "age" => 30)
      end

      it "raises ModelBehaviorError for invalid JSON" do
        expect { schema.validate_json("{invalid json}") }
          .to raise_error(RAAF::Errors::ModelBehaviorError, /Invalid JSON:/)
      end

      it "raises ModelBehaviorError for non-Hash JSON" do
        expect { schema.validate_json('"just a string"') }
          .to raise_error(RAAF::Errors::ModelBehaviorError, /Expected Hash/)
      end
    end

    context "with Integer output (wrapped)" do
      let(:schema) { described_class.new(Integer) }

      it "parses wrapped integer correctly" do
        json_str = '{"response": 42}'
        result = schema.validate_json(json_str)
        expect(result).to eq(42)
      end

      it "raises error for missing wrapper key" do
        json_str = '{"value": 42}'
        expect { schema.validate_json(json_str) }
          .to raise_error(RAAF::Errors::ModelBehaviorError, /Could not find key 'response'/)
      end

      it "raises error for non-Hash input" do
        json_str = '"42"'
        expect { schema.validate_json(json_str) }
          .to raise_error(RAAF::Errors::ModelBehaviorError, /Expected a Hash/)
      end
    end

    context "with Array output (wrapped)" do
      let(:schema) { described_class.new(Array) }

      it "parses wrapped array correctly" do
        json_str = '{"response": [1, 2, 3]}'
        result = schema.validate_json(json_str)
        expect(result).to eq([1, 2, 3])
      end
    end

    context "with custom class" do
      let(:person_class) do
        Class.new do
          attr_reader :name, :age

          def initialize(hash_or_name = nil, age: nil)
            if hash_or_name.is_a?(Hash)
              @name = hash_or_name["name"] || hash_or_name[:name]
              @age = hash_or_name["age"] || hash_or_name[:age]
            else
              @name = hash_or_name
              @age = age
            end
          end

          def self.name
            "Person"
          end
        end
      end

      let(:schema) { described_class.new(person_class, strict_json_schema: false) }

      it "constructs custom object from JSON" do
        json_str = '{"response": {"name": "Alice", "age": 25}}'
        result = schema.validate_json(json_str)
        expect(result).to be_a(person_class)
        expect(result.name).to eq("Alice")
        expect(result.age).to eq(25)
      end
    end

    context "with type conversion" do
      it "converts string to integer for Integer type" do
        schema = described_class.new(Integer)
        json_str = '{"response": "123"}'
        result = schema.validate_json(json_str)
        expect(result).to eq(123)
      end

      it "converts value to string for String type" do
        schema = described_class.new(String)
        result = schema.validate_json("123")
        expect(result).to eq("123")
      end

      it "raises error for invalid integer conversion" do
        schema = described_class.new(Integer)
        json_str = '{"response": "not a number"}'
        expect { schema.validate_json(json_str) }
          .to raise_error(RAAF::Errors::ModelBehaviorError, /Type validation failed/)
      end
    end
  end

  describe "strict JSON schema" do
    it "applies strict schema by default" do
      schema = described_class.new(Integer) # Use Integer to avoid Hash strictness issues
      expect(schema.strict_json_schema?).to be true
    end

    it "can disable strict schema" do
      schema = described_class.new(Hash, strict_json_schema: false)
      expect(schema.strict_json_schema?).to be false
    end

    context "with invalid type for strict schema" do
      let(:complex_class) do
        Class.new do
          def self.name
            "ComplexClass"
          end
        end
      end

      it "raises UserError when strict schema cannot be applied" do
        allow(RAAF::StrictSchema).to receive(:ensure_strict_json_schema).and_raise(StandardError, "Cannot make strict")
        
        expect { described_class.new(complex_class) }
          .to raise_error(RAAF::Errors::UserError, /Strict JSON schema is enabled, but the output type is not valid/)
      end
    end
  end

  describe "private methods" do
    let(:schema) { described_class.new(Hash, strict_json_schema: false) }

    describe "#subclass_of_hash_or_structured?" do
      it "returns true for Hash subclass" do
        hash_subclass = Class.new(Hash)
        result = schema.send(:subclass_of_hash_or_structured?, hash_subclass)
        expect(result).to be true
      end

      it "returns true for class with json_schema method" do
        class_with_schema = Class.new do
          def self.json_schema
            { type: "object" }
          end
        end
        result = schema.send(:subclass_of_hash_or_structured?, class_with_schema)
        expect(result).to be true
      end

      it "returns false for basic classes" do
        result = schema.send(:subclass_of_hash_or_structured?, String)
        expect(result).to be false
      end
    end

    describe "#infer_schema_from_class" do
      it "infers schema from class with to_h method" do
        inferrable_class = Class.new do
          def initialize
            @name = "test"
            @age = 25
          end

          def to_h
            { name: @name, age: @age }
          end

          def self.name
            "InferrableClass"
          end
        end

        result = schema.send(:infer_schema_from_class, inferrable_class)
        expect(result).to include(type: "object")
        expect(result[:properties]).to include("name", "age")
      end

      it "handles classes that can't be instantiated" do
        problematic_class = Class.new do
          def initialize
            raise "Cannot instantiate"
          end

          def self.name
            "ProblematicClass"
          end
        end

        result = schema.send(:infer_schema_from_class, problematic_class)
        expect(result).to eq({
          type: "object",
          properties: {},
          additionalProperties: true
        })
      end
    end

    describe "#validate_custom_type" do
      context "with from_json method" do
        let(:json_class) do
          Class.new do
            attr_reader :data

            def initialize(data)
              @data = data
            end

            def self.from_json(json_data)
              new(json_data)
            end

            def self.name
              "JsonClass"
            end
          end
        end

        it "uses from_json method when available" do
          schema = described_class.new(json_class, strict_json_schema: false)
          result = schema.send(:validate_custom_type, { "key" => "value" })
          expect(result).to be_a(json_class)
          expect(result.data).to eq({ "key" => "value" })
        end
      end

      it "falls back to data as-is for unknown types" do
        unknown_class = Class.new
        schema = described_class.new(unknown_class, strict_json_schema: false)
        data = { "test" => "value" }
        result = schema.send(:validate_custom_type, data)
        expect(result).to eq(data)
      end
    end
  end
end

RSpec.describe RAAF::TypeAdapter do
  describe "#initialize" do
    it "stores the provided type" do
      adapter = described_class.new(String)
      expect(adapter.type).to eq(String)
    end
  end

  describe "#validate" do
    it "validates String type correctly" do
      adapter = described_class.new(String)
      expect(adapter.validate("hello")).to eq("hello")
    end

    it "raises TypeError for wrong type" do
      adapter = described_class.new(String)
      expect { adapter.validate(123) }.to raise_error(TypeError, "Expected String, got Integer")
    end

    it "validates Integer type correctly" do
      adapter = described_class.new(Integer)
      expect(adapter.validate(42)).to eq(42)
    end

    it "validates custom class correctly" do
      custom_class = Class.new
      instance = custom_class.new
      adapter = described_class.new(custom_class)
      expect(adapter.validate(instance)).to eq(instance)
    end
  end

  describe "#json_schema" do
    it "returns string schema for String" do
      adapter = described_class.new(String)
      expect(adapter.json_schema).to eq({ type: "string" })
    end

    it "returns integer schema for Integer" do
      adapter = described_class.new(Integer)
      expect(adapter.json_schema).to eq({ type: "integer" })
    end

    it "returns number schema for Float" do
      adapter = described_class.new(Float)
      expect(adapter.json_schema).to eq({ type: "number" })
    end

    it "returns boolean schema for TrueClass" do
      adapter = described_class.new(TrueClass)
      expect(adapter.json_schema).to eq({ type: "boolean" })
    end

    it "returns array schema for Array" do
      adapter = described_class.new(Array)
      expect(adapter.json_schema).to eq({ type: "array", items: {} })
    end

    it "returns object schema for Hash" do
      adapter = described_class.new(Hash)
      expect(adapter.json_schema).to eq({ type: "object", additionalProperties: true })
    end

    it "uses custom json_schema method when available" do
      custom_class = Class.new do
        def self.json_schema
          { type: "custom", properties: { special: { type: "string" } } }
        end
      end

      adapter = described_class.new(custom_class)
      expect(adapter.json_schema).to eq({
        type: "custom",
        properties: { special: { type: "string" } }
      })
    end

    it "returns default object schema for unknown types" do
      custom_class = Class.new
      adapter = described_class.new(custom_class)
      expect(adapter.json_schema).to eq({ type: "object", additionalProperties: true })
    end
  end
end