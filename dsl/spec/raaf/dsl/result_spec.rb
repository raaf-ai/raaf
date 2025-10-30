# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Result do
  let(:sample_data) do
    {
      success: true,
      message: "Operation completed",
      data: { items: [1, 2, 3] },
      metadata: { timestamp: Time.now }
    }
  end

  describe "#initialize" do
    it "accepts hash data" do
      result = described_class.new(sample_data)
      expect(result.data).to eq(sample_data)
    end

    it "accepts keyword arguments" do
      result = described_class.new(success: true, message: "Test")
      expect(result.data).to eq(success: true, message: "Test")
    end

    it "initializes with empty hash when no data provided" do
      result = described_class.new
      expect(result.data).to eq({})
    end

    it "converts string keys to symbols for consistency" do
      string_data = { "success" => true, "message" => "test" }
      result = described_class.new(string_data)
      expect(result.data).to have_key(:success)
      expect(result.data).to have_key(:message)
    end
  end

  describe "#[]" do
    let(:result) { described_class.new(sample_data) }

    it "provides access to data fields" do
      expect(result[:success]).to eq(true)
      expect(result[:message]).to eq("Operation completed")
      expect(result[:data]).to eq({ items: [1, 2, 3] })
    end

    it "returns nil for non-existent keys" do
      expect(result[:non_existent]).to be_nil
    end
  end

  describe "#[]=" do
    let(:result) { described_class.new(sample_data) }

    it "allows setting data fields" do
      result[:new_field] = "new value"
      expect(result[:new_field]).to eq("new value")
    end

    it "allows updating existing fields" do
      result[:success] = false
      expect(result[:success]).to eq(false)
    end
  end

  describe "#fetch" do
    let(:result) { described_class.new(sample_data) }

    it "returns value for existing key" do
      expect(result.fetch(:success)).to eq(true)
    end

    it "returns default value for non-existent key" do
      expect(result.fetch(:missing, "default")).to eq("default")
    end

    it "raises KeyError for non-existent key without default" do
      expect { result.fetch(:missing) }.to raise_error(KeyError)
    end

    it "yields block for non-existent key" do
      value = result.fetch(:missing) { "computed default" }
      expect(value).to eq("computed default")
    end
  end

  describe "#key?" do
    let(:result) { described_class.new(sample_data) }

    it "returns true for existing keys" do
      expect(result.key?(:success)).to eq(true)
      expect(result.key?(:message)).to eq(true)
    end

    it "returns false for non-existent keys" do
      expect(result.key?(:missing)).to eq(false)
    end
  end

  describe "#keys" do
    let(:result) { described_class.new(sample_data) }

    it "returns array of keys" do
      keys = result.keys
      expect(keys).to include(:success, :message, :data, :metadata)
    end
  end

  describe "#values" do
    let(:result) { described_class.new(success: true, count: 5) }

    it "returns array of values" do
      values = result.values
      expect(values).to include(true, 5)
    end
  end

  describe "#each" do
    let(:result) { described_class.new(a: 1, b: 2) }

    it "iterates over key-value pairs" do
      pairs = []
      result.each { |k, v| pairs << [k, v] }
      expect(pairs).to include([:a, 1], [:b, 2])
    end

    it "returns enumerator when no block given" do
      enumerator = result.each
      expect(enumerator).to be_a(Enumerator)
    end
  end

  describe "#merge" do
    let(:result) { described_class.new(a: 1, b: 2) }

    it "returns new result with merged data" do
      merged = result.merge(c: 3, b: 20)
      expect(merged).to be_a(described_class)
      expect(merged[:a]).to eq(1)
      expect(merged[:b]).to eq(20)
      expect(merged[:c]).to eq(3)
    end

    it "does not modify original result" do
      original_b = result[:b]
      result.merge(b: 99)
      expect(result[:b]).to eq(original_b)
    end
  end

  describe "#merge!" do
    let(:result) { described_class.new(a: 1, b: 2) }

    it "updates result with merged data" do
      result.merge!(c: 3, b: 20)
      expect(result[:a]).to eq(1)
      expect(result[:b]).to eq(20)
      expect(result[:c]).to eq(3)
    end

    it "returns self" do
      returned = result.merge!(d: 4)
      expect(returned).to eq(result)
    end
  end

  describe "#to_h" do
    let(:result) { described_class.new(sample_data) }

    it "returns hash representation" do
      hash = result.to_h
      expect(hash).to eq(sample_data)
      expect(hash).to be_a(Hash)
    end

    it "returns copy of data, not reference" do
      hash = result.to_h
      hash[:new_key] = "new_value"
      expect(result[:new_key]).to be_nil
    end
  end

  describe "#to_json" do
    let(:result) { described_class.new(name: "test", count: 5) }

    it "returns JSON representation" do
      json = result.to_json
      parsed = JSON.parse(json)
      expect(parsed).to eq("name" => "test", "count" => 5)
    end
  end

  describe "#inspect" do
    let(:result) { described_class.new(simple: "value") }

    it "returns readable representation" do
      inspection = result.inspect
      expect(inspection).to include("RAAF::DSL::Result")
      expect(inspection).to include("simple")
      expect(inspection).to include("value")
    end
  end

  describe "#empty?" do
    it "returns true for empty result" do
      result = described_class.new
      expect(result.empty?).to eq(true)
    end

    it "returns false for non-empty result" do
      result = described_class.new(data: "value")
      expect(result.empty?).to eq(false)
    end
  end

  describe "#size" do
    it "returns number of key-value pairs" do
      result = described_class.new(a: 1, b: 2, c: 3)
      expect(result.size).to eq(3)
    end
  end

  describe "success helper methods" do
    describe "#success?" do
      it "returns true when success is true" do
        result = described_class.new(success: true)
        expect(result.success?).to eq(true)
      end

      it "returns false when success is false" do
        result = described_class.new(success: false)
        expect(result.success?).to eq(false)
      end

      it "returns false when success is not set" do
        result = described_class.new(other: "value")
        expect(result.success?).to eq(false)
      end
    end

    describe "#error?" do
      it "returns true when success is false" do
        result = described_class.new(success: false)
        expect(result.error?).to eq(true)
      end

      it "returns false when success is true" do
        result = described_class.new(success: true)
        expect(result.error?).to eq(false)
      end

      it "returns true when error field is present" do
        result = described_class.new(error: "Something went wrong")
        expect(result.error?).to eq(true)
      end
    end
  end

  describe "equality" do
    it "compares results based on data content" do
      result1 = described_class.new(a: 1, b: 2)
      result2 = described_class.new(a: 1, b: 2)
      result3 = described_class.new(a: 1, b: 3)

      expect(result1).to eq(result2)
      expect(result1).not_to eq(result3)
    end

    it "equals equivalent hash" do
      result = described_class.new(a: 1, b: 2)
      hash = { a: 1, b: 2 }

      expect(result).to eq(hash)
    end
  end

  describe "method delegation" do
    let(:result) { described_class.new(sample_data) }

    it "delegates missing methods to data hash" do
      # Test a Hash method that's not explicitly defined
      expect(result.length).to eq(sample_data.length)
    end

    it "responds to hash methods" do
      expect(result.respond_to?(:length)).to eq(true)
      expect(result.respond_to?(:has_key?)).to eq(true)
    end
  end

  describe "#parsed_data" do
    context "with valid JSON string" do
      it "parses JSON successfully" do
        # Create result with JSON string as message content
        result = described_class.new({ messages: [{ role: "assistant", content: '{"name":"John","age":30}' }] })

        parsed = result.send(:parsed_data)
        expect(parsed).to be_a(Hash)
        expect(parsed["name"]).to eq("John")
        expect(parsed["age"]).to eq(30)
      end

      it "handles nested JSON structures" do
        json_str = '{"user":{"name":"Jane","profile":{"role":"admin"}}}'
        result = described_class.new({ messages: [{ role: "assistant", content: json_str }] })

        parsed = result.send(:parsed_data)
        expect(parsed).to be_a(Hash)
        expect(parsed["user"]["name"]).to eq("Jane")
        expect(parsed["user"]["profile"]["role"]).to eq("admin")
      end
    end

    context "with plain text string (non-JSON)" do
      it "returns raw text without parsing" do
        plain_text = "This is plain text, not JSON"
        result = described_class.new({ messages: [{ role: "assistant", content: plain_text }] })

        parsed = result.send(:parsed_data)
        expect(parsed).to eq(plain_text)
      end

      it "handles CSV format text" do
        csv_text = "name,location,country\n\"Company A\",\"City\",\"Country\""
        result = described_class.new({ messages: [{ role: "assistant", content: csv_text }] })

        parsed = result.send(:parsed_data)
        expect(parsed).to eq(csv_text)
      end

      it "handles markdown format text" do
        markdown = "# Heading\n\nSome **bold** text"
        result = described_class.new({ messages: [{ role: "assistant", content: markdown }] })

        parsed = result.send(:parsed_data)
        expect(parsed).to eq(markdown)
      end
    end

    context "with already-parsed Hash" do
      it "returns hash as-is" do
        hash_data = { name: "Test", value: 123 }
        result = described_class.new({ messages: [{ role: "assistant", content: hash_data }] })

        parsed = result.send(:parsed_data)
        expect(parsed).to eq(hash_data)
      end
    end

    context "with already-parsed Array" do
      it "returns array as-is" do
        array_data = [{ id: 1 }, { id: 2 }, { id: 3 }]
        result = described_class.new({ messages: [{ role: "assistant", content: array_data }] })

        parsed = result.send(:parsed_data)
        expect(parsed).to eq(array_data)
      end
    end

    context "with empty string" do
      it "returns empty string" do
        result = described_class.new({ messages: [{ role: "assistant", content: "" }] })

        parsed = result.send(:parsed_data)
        expect(parsed).to eq("")
      end

      it "returns whitespace-only string" do
        result = described_class.new({ messages: [{ role: "assistant", content: "   \n  " }] })

        parsed = result.send(:parsed_data)
        expect(parsed).to eq("   \n  ")
      end
    end

    context "edge cases" do
      it "handles JSON-like but invalid format" do
        invalid_json = "{name: 'John'}"  # Single quotes, not valid JSON
        result = described_class.new({ messages: [{ role: "assistant", content: invalid_json }] })

        parsed = result.send(:parsed_data)
        expect(parsed).to eq(invalid_json)  # Returns raw text
      end

      it "handles partial JSON fragments" do
        fragment = '{"incomplete": '
        result = described_class.new({ messages: [{ role: "assistant", content: fragment }] })

        parsed = result.send(:parsed_data)
        expect(parsed).to eq(fragment)  # Returns raw text
      end
    end
  end
end