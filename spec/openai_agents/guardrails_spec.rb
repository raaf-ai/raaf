# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenAIAgents::Guardrails do
  describe "GuardrailError hierarchy" do
    it "defines custom error classes" do
      expect(OpenAIAgents::Guardrails::GuardrailError).to be < OpenAIAgents::Error
      expect(OpenAIAgents::Guardrails::ValidationError).to be < OpenAIAgents::Guardrails::GuardrailError
      expect(OpenAIAgents::Guardrails::SecurityError).to be < OpenAIAgents::Guardrails::GuardrailError
    end
  end

  describe OpenAIAgents::Guardrails::BaseGuardrail do
    let(:guardrail) { described_class.new }

    describe "#initialize" do
      it "accepts options" do
        options = { setting: "value" }
        guardrail = described_class.new(options)

        expect(guardrail.instance_variable_get(:@options)).to eq(options)
      end

      it "defaults to empty options" do
        guardrail = described_class.new

        expect(guardrail.instance_variable_get(:@options)).to eq({})
      end
    end

    describe "abstract methods" do
      it "raises NotImplementedError for validate_input" do
        expect { guardrail.validate_input("test") }.to raise_error(NotImplementedError)
      end

      it "raises NotImplementedError for validate_output" do
        expect { guardrail.validate_output("test") }.to raise_error(NotImplementedError)
      end
    end

    describe "#fail_validation" do
      it "raises ValidationError by default" do
        expect do
          guardrail.send(:fail_validation,
                         "Error message")
        end.to raise_error(OpenAIAgents::Guardrails::ValidationError, "Error message")
      end

      it "raises SecurityError when type is :security" do
        expect do
          guardrail.send(:fail_validation, "Security issue",
                         type: :security)
        end.to raise_error(OpenAIAgents::Guardrails::SecurityError, "Security issue")
      end
    end
  end

  describe OpenAIAgents::Guardrails::ContentSafetyGuardrail do
    let(:guardrail) { described_class.new }

    describe "#validate_input" do
      it "passes safe content" do
        safe_input = "Hello, how can I help you today?"

        expect(guardrail.validate_input(safe_input)).to be true
      end

      it "blocks violent content" do
        violent_input = "How to kill someone"

        expect do
          guardrail.validate_input(violent_input)
        end.to raise_error(OpenAIAgents::Guardrails::SecurityError, /harmful material/)
      end

      it "blocks illegal content" do
        illegal_input = "How to buy illegal drugs"

        expect do
          guardrail.validate_input(illegal_input)
        end.to raise_error(OpenAIAgents::Guardrails::SecurityError, /harmful material/)
      end

      it "blocks hate speech" do
        hate_input = "I hate people of that race"

        expect do
          guardrail.validate_input(hate_input)
        end.to raise_error(OpenAIAgents::Guardrails::SecurityError, /harmful material/)
      end

      it "blocks sexual content" do
        sexual_input = "explicit sexual content"

        expect do
          guardrail.validate_input(sexual_input)
        end.to raise_error(OpenAIAgents::Guardrails::SecurityError, /harmful material/)
      end

      it "blocks personal information" do
        pii_input = "My SSN is 123-45-6789"

        expect do
          guardrail.validate_input(pii_input)
        end.to raise_error(OpenAIAgents::Guardrails::SecurityError, /harmful material/)
      end

      it "handles hash input" do
        safe_hash = { message: "Hello", user: "John" }

        expect(guardrail.validate_input(safe_hash)).to be true
      end

      it "handles array input" do
        safe_array = %w[Hello How are you]

        expect(guardrail.validate_input(safe_array)).to be true
      end

      it "blocks harmful content in hash values" do
        harmful_hash = { message: "violence is bad", instruction: "kill the process" }

        expect { guardrail.validate_input(harmful_hash) }.to raise_error(OpenAIAgents::Guardrails::SecurityError)
      end
    end

    describe "#validate_output" do
      it "passes safe output" do
        safe_output = "I'm here to help you with information."

        expect(guardrail.validate_output(safe_output)).to be true
      end

      it "blocks harmful output" do
        harmful_output = "Here's how to commit violence"

        expect do
          guardrail.validate_output(harmful_output)
        end.to raise_error(OpenAIAgents::Guardrails::SecurityError, /harmful material/)
      end
    end

    describe "content extraction" do
      it "extracts content from strings" do
        content = guardrail.send(:extract_content, "test string")
        expect(content).to eq("test string")
      end

      it "extracts content from hashes" do
        content = guardrail.send(:extract_content, { a: "hello", b: "world" })
        expect(content).to eq("hello world")
      end

      it "extracts content from arrays" do
        content = guardrail.send(:extract_content, %w[hello world])
        expect(content).to eq("hello world")
      end

      it "converts other types to string" do
        content = guardrail.send(:extract_content, 123)
        expect(content).to eq("123")
      end
    end
  end

  describe OpenAIAgents::Guardrails::LengthGuardrail do
    let(:guardrail) { described_class.new(max_input_length: 10, max_output_length: 5) }

    describe "#initialize" do
      it "accepts custom length limits" do
        guardrail = described_class.new(max_input_length: 100, max_output_length: 50)

        expect(guardrail.instance_variable_get(:@max_input_length)).to eq(100)
        expect(guardrail.instance_variable_get(:@max_output_length)).to eq(50)
      end

      it "uses default length limits" do
        guardrail = described_class.new

        expect(guardrail.instance_variable_get(:@max_input_length)).to eq(10_000)
        expect(guardrail.instance_variable_get(:@max_output_length)).to eq(5000)
      end
    end

    describe "#validate_input" do
      it "passes short input" do
        short_input = "hello"

        expect(guardrail.validate_input(short_input)).to be true
      end

      it "blocks long input" do
        long_input = "a" * 11

        expect do
          guardrail.validate_input(long_input)
        end.to raise_error(OpenAIAgents::Guardrails::ValidationError,
                           /exceeds maximum length/)
      end

      it "handles exactly at limit" do
        limit_input = "a" * 10

        expect(guardrail.validate_input(limit_input)).to be true
      end

      it "handles non-string input" do
        hash_input = { a: "b" }

        # Should convert to string representation (short enough to pass)
        expect { guardrail.validate_input(hash_input) }.not_to raise_error
      end
    end

    describe "#validate_output" do
      it "passes short output" do
        short_output = "hi"

        expect(guardrail.validate_output(short_output)).to be true
      end

      it "blocks long output" do
        long_output = "a" * 6

        expect do
          guardrail.validate_output(long_output)
        end.to raise_error(OpenAIAgents::Guardrails::ValidationError,
                           /exceeds maximum length/)
      end
    end

    describe "content extraction" do
      it "handles different data types" do
        expect(guardrail.send(:extract_content, "string")).to eq("string")
        expect(guardrail.send(:extract_content, { a: 1 })).to eq("{:a=>1}")
        expect(guardrail.send(:extract_content, [1, 2, 3])).to eq("[1, 2, 3]")
        expect(guardrail.send(:extract_content, 123)).to eq("123")
      end
    end
  end

  describe OpenAIAgents::Guardrails::RateLimitGuardrail do
    let(:guardrail) { described_class.new(max_requests_per_minute: 3) }

    describe "#initialize" do
      it "accepts custom rate limit" do
        guardrail = described_class.new(max_requests_per_minute: 10)

        expect(guardrail.instance_variable_get(:@max_requests_per_minute)).to eq(10)
      end

      it "uses default rate limit" do
        guardrail = described_class.new

        expect(guardrail.instance_variable_get(:@max_requests_per_minute)).to eq(60)
      end

      it "initializes empty requests array" do
        expect(guardrail.instance_variable_get(:@requests)).to eq([])
      end
    end

    describe "#validate_input" do
      it "allows requests under limit" do
        expect(guardrail.validate_input("request 1")).to be true
        expect(guardrail.validate_input("request 2")).to be true
        expect(guardrail.validate_input("request 3")).to be true
      end

      it "blocks requests over limit" do
        3.times { |i| guardrail.validate_input("request #{i + 1}") }

        expect do
          guardrail.validate_input("request 4")
        end.to raise_error(OpenAIAgents::Guardrails::ValidationError,
                           /Rate limit exceeded/)
      end

      it "cleans up old requests" do
        # Add requests from more than a minute ago
        old_time = Time.now - 70
        requests = guardrail.instance_variable_get(:@requests)
        3.times { requests << old_time }

        # Should allow new request after cleanup
        expect(guardrail.validate_input("new request")).to be true
      end

      it "tracks request timestamps" do
        guardrail.validate_input("test")

        requests = guardrail.instance_variable_get(:@requests)
        expect(requests.length).to eq(1)
        expect(requests.first).to be_a(Time)
      end
    end

    describe "#validate_output" do
      it "always passes output validation" do
        expect(guardrail.validate_output("any output")).to be true
      end
    end
  end

  describe OpenAIAgents::Guardrails::SchemaGuardrail do
    let(:input_schema) do
      {
        type: "object",
        properties: {
          name: { type: "string", minLength: 1 },
          age: { type: "integer", minimum: 0 }
        },
        required: ["name"]
      }
    end
    let(:output_schema) do
      {
        type: "object",
        properties: {
          response: { type: "string", maxLength: 100 }
        },
        required: ["response"]
      }
    end
    let(:guardrail) { described_class.new(input_schema: input_schema, output_schema: output_schema) }

    describe "#initialize" do
      it "accepts input and output schemas" do
        expect(guardrail.instance_variable_get(:@input_schema)).to eq(input_schema)
        expect(guardrail.instance_variable_get(:@output_schema)).to eq(output_schema)
      end

      it "works with nil schemas" do
        guardrail = described_class.new

        expect(guardrail.instance_variable_get(:@input_schema)).to be_nil
        expect(guardrail.instance_variable_get(:@output_schema)).to be_nil
      end
    end

    describe "#validate_input" do
      it "passes valid input" do
        valid_input = { name: "John", age: 30 }

        expect(guardrail.validate_input(valid_input)).to be true
      end

      it "validates required fields" do
        invalid_input = { age: 30 }

        expect do
          guardrail.validate_input(invalid_input)
        end.to raise_error(OpenAIAgents::Guardrails::ValidationError,
                           /Missing required field/)
      end

      it "validates string properties" do
        invalid_input = { name: "" }

        expect do
          guardrail.validate_input(invalid_input)
        end.to raise_error(OpenAIAgents::Guardrails::ValidationError,
                           /shorter than minimum/)
      end

      it "validates number properties" do
        invalid_input = { name: "John", age: -1 }

        expect do
          guardrail.validate_input(invalid_input)
        end.to raise_error(OpenAIAgents::Guardrails::ValidationError,
                           /less than minimum/)
      end

      it "skips validation when no schema provided" do
        guardrail = described_class.new

        expect(guardrail.validate_input("anything")).to be true
      end

      it "accepts string keys" do
        valid_input = { "name" => "John", "age" => 30 }

        expect(guardrail.validate_input(valid_input)).to be true
      end
    end

    describe "#validate_output" do
      it "passes valid output" do
        valid_output = { response: "Hello world" }

        expect(guardrail.validate_output(valid_output)).to be true
      end

      it "validates output schema" do
        invalid_output = { response: "a" * 101 }

        expect do
          guardrail.validate_output(invalid_output)
        end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /longer than/)
      end

      it "skips validation when no schema provided" do
        guardrail = described_class.new

        expect(guardrail.validate_output("anything")).to be true
      end
    end

    describe "type validation" do
      describe "object validation" do
        let(:schema) { { type: "object", properties: { name: { type: "string" } }, required: ["name"] } }
        let(:guardrail) { described_class.new(input_schema: schema) }

        it "validates object type" do
          expect do
            guardrail.validate_input("not an object")
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError,
                             /Expected object/)
        end

        it "validates required properties" do
          expect do
            guardrail.validate_input({})
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /Missing required field/)
        end

        it "validates nested properties" do
          nested_schema = {
            type: "object",
            properties: {
              user: {
                type: "object",
                properties: { name: { type: "string" } },
                required: ["name"]
              }
            },
            required: ["user"]
          }
          guardrail = described_class.new(input_schema: nested_schema)

          expect do
            guardrail.validate_input({ user: {} })
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError,
                             /Missing required field/)
        end
      end

      describe "array validation" do
        let(:schema) { { type: "array", items: { type: "string" }, minItems: 1, maxItems: 3 } }
        let(:guardrail) { described_class.new(input_schema: schema) }

        it "validates array type" do
          expect do
            guardrail.validate_input("not an array")
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /Expected array/)
        end

        it "validates minimum items" do
          expect do
            guardrail.validate_input([])
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /fewer than/)
        end

        it "validates maximum items" do
          expect do
            guardrail.validate_input(%w[a b c d])
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /more than/)
        end

        it "validates item types" do
          expect do
            guardrail.validate_input([123])
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /Expected string/)
        end
      end

      describe "string validation" do
        let(:schema) { { type: "string", minLength: 2, maxLength: 10, pattern: "^[a-z]+$" } }
        let(:guardrail) { described_class.new(input_schema: schema) }

        it "validates string type" do
          expect do
            guardrail.validate_input(123)
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /Expected string/)
        end

        it "validates minimum length" do
          expect do
            guardrail.validate_input("a")
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /shorter than/)
        end

        it "validates maximum length" do
          expect do
            guardrail.validate_input("a" * 11)
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /longer than/)
        end

        it "validates pattern" do
          expect do
            guardrail.validate_input("ABC")
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /doesn't match pattern/)
        end
      end

      describe "number validation" do
        let(:schema) { { type: "number", minimum: 0, maximum: 100 } }
        let(:guardrail) { described_class.new(input_schema: schema) }

        it "validates number type" do
          expect do
            guardrail.validate_input("not a number")
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /Expected number/)
        end

        it "validates minimum value" do
          expect do
            guardrail.validate_input(-1)
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /less than minimum/)
        end

        it "validates maximum value" do
          expect do
            guardrail.validate_input(101)
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /greater than maximum/)
        end
      end

      describe "boolean validation" do
        let(:schema) { { type: "boolean" } }
        let(:guardrail) { described_class.new(input_schema: schema) }

        it "validates boolean type" do
          expect do
            guardrail.validate_input("not a boolean")
          end.to raise_error(OpenAIAgents::Guardrails::ValidationError,
                             /Expected boolean/)
        end

        it "accepts true" do
          expect(guardrail.validate_input(true)).to be true
        end

        it "accepts false" do
          expect(guardrail.validate_input(false)).to be true
        end
      end

      it "raises error for unknown schema type" do
        schema = { type: "unknown" }
        guardrail = described_class.new(input_schema: schema)

        expect do
          guardrail.validate_input("anything")
        end.to raise_error(OpenAIAgents::Guardrails::ValidationError, /Unknown schema type/)
      end
    end
  end

  describe OpenAIAgents::Guardrails::GuardrailManager do
    let(:manager) { described_class.new }
    let(:content_guardrail) { OpenAIAgents::Guardrails::ContentSafetyGuardrail.new }
    let(:length_guardrail) do
      OpenAIAgents::Guardrails::LengthGuardrail.new(max_input_length: 20, max_output_length: 10)
    end

    describe "#initialize" do
      it "initializes with empty guardrails array" do
        expect(manager.guardrails).to be_empty
      end
    end

    describe "#add_guardrail" do
      it "adds valid guardrails" do
        manager.add_guardrail(content_guardrail)

        expect(manager.guardrails).to include(content_guardrail)
      end

      it "raises error for invalid guardrails" do
        expect do
          manager.add_guardrail("not a guardrail")
        end.to raise_error(ArgumentError, /must inherit from BaseGuardrail/)
      end

      it "accumulates multiple guardrails" do
        manager.add_guardrail(content_guardrail)
        manager.add_guardrail(length_guardrail)

        expect(manager.guardrails.size).to eq(2)
        expect(manager.guardrails).to include(content_guardrail, length_guardrail)
      end
    end

    describe "#validate_input" do
      before do
        manager.add_guardrail(content_guardrail)
        manager.add_guardrail(length_guardrail)
      end

      it "runs all guardrails on input" do
        safe_short_input = "Hello"

        expect(manager.validate_input(safe_short_input)).to be true
      end

      it "fails if any guardrail fails - content safety" do
        harmful_input = "violence and hate"

        expect { manager.validate_input(harmful_input) }.to raise_error(OpenAIAgents::Guardrails::SecurityError)
      end

      it "fails if any guardrail fails - length" do
        long_safe_input = "a" * 25

        expect do
          manager.validate_input(long_safe_input)
        end.to raise_error(OpenAIAgents::Guardrails::ValidationError,
                           /exceeds maximum length/)
      end

      it "works with no guardrails" do
        empty_manager = described_class.new

        expect(empty_manager.validate_input("anything")).to be true
      end
    end

    describe "#validate_output" do
      before do
        manager.add_guardrail(content_guardrail)
        manager.add_guardrail(length_guardrail)
      end

      it "runs all guardrails on output" do
        safe_short_output = "Hi"

        expect(manager.validate_output(safe_short_output)).to be true
      end

      it "fails if any guardrail fails" do
        long_output = "a" * 15

        expect do
          manager.validate_output(long_output)
        end.to raise_error(OpenAIAgents::Guardrails::ValidationError,
                           /exceeds maximum length/)
      end
    end

    describe "#clear" do
      it "removes all guardrails" do
        manager.add_guardrail(content_guardrail)
        manager.add_guardrail(length_guardrail)

        manager.clear

        expect(manager.guardrails).to be_empty
      end
    end
  end
end
