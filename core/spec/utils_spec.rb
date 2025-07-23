# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Utils do
  describe ".deep_symbolize_keys" do
    it "converts string keys to symbols in simple hash" do
      input = { "name" => "John", "age" => 30 }
      result = described_class.deep_symbolize_keys(input)
      
      expect(result).to eq(name: "John", age: 30)
    end

    it "converts keys recursively in nested hashes" do
      input = {
        "user" => {
          "profile" => {
            "name" => "John",
            "settings" => {
              "theme" => "dark"
            }
          }
        }
      }
      
      result = described_class.deep_symbolize_keys(input)
      
      expect(result).to eq(
        user: {
          profile: {
            name: "John",
            settings: {
              theme: "dark"
            }
          }
        }
      )
    end

    it "processes arrays with hashes recursively" do
      input = [
        { "id" => 1, "name" => "First" },
        { "id" => 2, "name" => "Second" }
      ]
      
      result = described_class.deep_symbolize_keys(input)
      
      expect(result).to eq([
        { id: 1, name: "First" },
        { id: 2, name: "Second" }
      ])
    end

    it "handles mixed nested arrays and hashes" do
      input = {
        "items" => [
          {
            "data" => {
              "values" => [1, 2, { "nested" => "value" }]
            }
          }
        ]
      }
      
      result = described_class.deep_symbolize_keys(input)
      
      expect(result).to eq(
        items: [
          {
            data: {
              values: [1, 2, { nested: "value" }]
            }
          }
        ]
      )
    end

    it "leaves non-hash, non-array objects unchanged" do
      inputs = [
        "string",
        42,
        3.14,
        true,
        false,
        nil,
        :symbol,
        Object.new
      ]
      
      inputs.each do |input|
        result = described_class.deep_symbolize_keys(input)
        expect(result).to eq(input)
      end
    end

    it "handles empty collections" do
      expect(described_class.deep_symbolize_keys({})).to eq({})
      expect(described_class.deep_symbolize_keys([])).to eq([])
    end

    it "preserves original object (creates new objects)" do
      input = { "name" => "John" }
      original_input = input.dup
      
      result = described_class.deep_symbolize_keys(input)
      
      expect(input).to eq(original_input) # Original unchanged
      expect(result).not_to be(input) # New object created
    end

    it "converts symbol keys to symbols (no-op)" do
      input = { name: "John", age: 30 }
      result = described_class.deep_symbolize_keys(input)
      
      expect(result).to eq(input)
    end

    it "handles mixed string and symbol keys" do
      input = { "name" => "John", :age => 30, "profile" => { :theme => "dark" } }
      result = described_class.deep_symbolize_keys(input)
      
      expect(result).to eq(name: "John", age: 30, profile: { theme: "dark" })
    end
  end

  describe ".deep_stringify_keys" do
    it "converts symbol keys to strings in simple hash" do
      input = { name: "John", age: 30 }
      result = described_class.deep_stringify_keys(input)
      
      expect(result).to eq("name" => "John", "age" => 30)
    end

    it "converts keys recursively in nested hashes" do
      input = {
        user: {
          profile: {
            name: "John",
            settings: {
              theme: "dark"
            }
          }
        }
      }
      
      result = described_class.deep_stringify_keys(input)
      
      expect(result).to eq(
        "user" => {
          "profile" => {
            "name" => "John",
            "settings" => {
              "theme" => "dark"
            }
          }
        }
      )
    end

    it "processes arrays with hashes recursively" do
      input = [
        { id: 1, name: "First" },
        { id: 2, name: "Second" }
      ]
      
      result = described_class.deep_stringify_keys(input)
      
      expect(result).to eq([
        { "id" => 1, "name" => "First" },
        { "id" => 2, "name" => "Second" }
      ])
    end

    it "handles mixed nested arrays and hashes" do
      input = {
        items: [
          {
            data: {
              values: [1, 2, { nested: "value" }]
            }
          }
        ]
      }
      
      result = described_class.deep_stringify_keys(input)
      
      expect(result).to eq(
        "items" => [
          {
            "data" => {
              "values" => [1, 2, { "nested" => "value" }]
            }
          }
        ]
      )
    end

    it "leaves non-hash, non-array objects unchanged" do
      inputs = [
        "string",
        42,
        3.14,
        true,
        false,
        nil,
        :symbol,
        Object.new
      ]
      
      inputs.each do |input|
        result = described_class.deep_stringify_keys(input)
        expect(result).to eq(input)
      end
    end

    it "handles empty collections" do
      expect(described_class.deep_stringify_keys({})).to eq({})
      expect(described_class.deep_stringify_keys([])).to eq([])
    end

    it "preserves original object (creates new objects)" do
      input = { name: "John" }
      original_input = input.dup
      
      result = described_class.deep_stringify_keys(input)
      
      expect(input).to eq(original_input) # Original unchanged
      expect(result).not_to be(input) # New object created
    end

    it "converts string keys to strings (no-op)" do
      input = { "name" => "John", "age" => 30 }
      result = described_class.deep_stringify_keys(input)
      
      expect(result).to eq(input)
    end

    it "handles mixed string and symbol keys" do
      input = { "name" => "John", :age => 30, "profile" => { :theme => "dark" } }
      result = described_class.deep_stringify_keys(input)
      
      expect(result).to eq("name" => "John", "age" => 30, "profile" => { "theme" => "dark" })
    end
  end

  describe ".prepare_for_openai" do
    it "correctly converts all keys to strings" do
      input = { model: "gpt-4", messages: [{ role: :user, content: "Hello" }] }
      
      result = described_class.prepare_for_openai(input)
      
      expect(result).to eq(
        "model" => "gpt-4",
        "messages" => [{ "role" => :user, "content" => "Hello" }]
      )
    end

    it "prepares typical OpenAI request format" do
      request = {
        model: "gpt-4o",
        messages: [
          { role: :system, content: "You are helpful" },
          { role: :user, content: "Hello" }
        ],
        temperature: 0.7,
        max_tokens: 1000
      }
      
      result = described_class.prepare_for_openai(request)
      
      expect(result).to eq(
        "model" => "gpt-4o",
        "messages" => [
          { "role" => :system, "content" => "You are helpful" },
          { "role" => :user, "content" => "Hello" }
        ],
        "temperature" => 0.7,
        "max_tokens" => 1000
      )
      expect(result.keys).to all(be_a(String))
    end

    it "prepares function definition format" do
      function_def = {
        name: "get_weather",
        description: "Get weather info",
        parameters: {
          type: :object,
          properties: {
            location: { type: :string },
            unit: { type: :string, enum: [:celsius, :fahrenheit] }
          },
          required: [:location]
        }
      }
      
      result = described_class.prepare_for_openai(function_def)
      
      expect(result).to eq(
        "name" => "get_weather",
        "description" => "Get weather info",
        "parameters" => {
          "type" => :object,
          "properties" => {
            "location" => { "type" => :string },
            "unit" => { "type" => :string, "enum" => [:celsius, :fahrenheit] }
          },
          "required" => [:location]
        }
      )
    end
  end

  describe ".normalize_response" do
    it "correctly converts all keys to symbols" do
      response = { "id" => "chatcmpl-123", "choices" => [] }
      
      result = described_class.normalize_response(response)
      
      expect(result).to eq(id: "chatcmpl-123", choices: [])
    end

    it "normalizes typical OpenAI response format" do
      api_response = {
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "choices" => [{
          "index" => 0,
          "message" => {
            "role" => "assistant",
            "content" => "Hello! How can I help you?"
          },
          "finish_reason" => "stop"
        }],
        "usage" => {
          "prompt_tokens" => 15,
          "completion_tokens" => 10,
          "total_tokens" => 25
        }
      }
      
      result = described_class.normalize_response(api_response)
      
      expect(result).to eq(
        id: "chatcmpl-123",
        object: "chat.completion",
        choices: [{
          index: 0,
          message: {
            role: "assistant",
            content: "Hello! How can I help you?"
          },
          finish_reason: "stop"
        }],
        usage: {
          prompt_tokens: 15,
          completion_tokens: 10,
          total_tokens: 25
        }
      )
      expect(result.keys).to all(be_a(Symbol))
    end

    it "normalizes error responses" do
      error_response = {
        "error" => {
          "message" => "Invalid API key",
          "type" => "invalid_request_error",
          "code" => "invalid_api_key"
        }
      }
      
      result = described_class.normalize_response(error_response)
      
      expect(result).to eq(
        error: {
          message: "Invalid API key",
          type: "invalid_request_error",
          code: "invalid_api_key"
        }
      )
    end
  end

  describe ".prepare_schema_for_openai" do
    before do
      # Mock StrictSchema to avoid dependency issues in tests
      allow(RAAF::StrictSchema).to receive(:ensure_strict_json_schema) do |schema|
        described_class.deep_stringify_keys(schema)
      end
    end

    it "delegates to StrictSchema.ensure_strict_json_schema" do
      schema = { type: :object, properties: { name: { type: :string } } }
      
      expect(RAAF::StrictSchema).to receive(:ensure_strict_json_schema).with(schema)
      described_class.prepare_schema_for_openai(schema)
    end

    it "prepares schema for OpenAI strict mode" do
      schema = {
        type: :object,
        properties: {
          name: { type: :string, description: "User name" },
          age: { type: :integer, minimum: 0 }
        },
        required: [:name]
      }
      
      result = described_class.prepare_schema_for_openai(schema)
      
      # With our mock, this should return stringified keys
      expect(result).to be_a(Hash)
      expect(result.keys).to all(be_a(String))
    end
  end

  describe ".snake_case" do
    it "converts PascalCase to snake_case" do
      expect(described_class.snake_case("CompanyDiscoveryAgent")).to eq("company_discovery_agent")
      expect(described_class.snake_case("UserProfile")).to eq("user_profile")
      expect(described_class.snake_case("SimpleClass")).to eq("simple_class")
    end

    it "converts camelCase to snake_case" do
      expect(described_class.snake_case("companyDiscoveryAgent")).to eq("company_discovery_agent")
      expect(described_class.snake_case("userProfile")).to eq("user_profile")
      expect(described_class.snake_case("simpleMethod")).to eq("simple_method")
    end

    it "handles acronyms correctly" do
      expect(described_class.snake_case("XMLParser")).to eq("xml_parser")
      expect(described_class.snake_case("HTTPRequest")).to eq("http_request")
      expect(described_class.snake_case("JSONSchema")).to eq("json_schema")
      expect(described_class.snake_case("XMLHTTPRequest")).to eq("xmlhttp_request")
    end

    it "handles mixed acronyms and words" do
      expect(described_class.snake_case("XMLParserAgent")).to eq("xml_parser_agent")
      expect(described_class.snake_case("HTTPSConnection")).to eq("https_connection")
      expect(described_class.snake_case("PDFConverter")).to eq("pdf_converter")
    end

    it "handles spaces and special characters" do
      expect(described_class.snake_case("Customer Service Agent")).to eq("customer_service_agent")
      expect(described_class.snake_case("Special-Characters!@#")).to eq("special_characters")
      expect(described_class.snake_case("Mixed_Characters & Symbols")).to eq("mixed_characters_symbols")
    end

    it "preserves already snake_case strings" do
      expect(described_class.snake_case("already_snake_case")).to eq("already_snake_case")
      expect(described_class.snake_case("simple_name")).to eq("simple_name")
      expect(described_class.snake_case("user_profile_data")).to eq("user_profile_data")
    end

    it "handles edge cases" do
      expect(described_class.snake_case("")).to eq("")
      expect(described_class.snake_case("A")).to eq("a")
      expect(described_class.snake_case("AB")).to eq("ab")
      expect(described_class.snake_case("ABC")).to eq("abc")
      expect(described_class.snake_case("123")).to eq("123")
      expect(described_class.snake_case("A123B")).to eq("a123_b")
    end

    it "removes leading and trailing underscores" do
      expect(described_class.snake_case("_LeadingUnderscore")).to eq("leading_underscore")
      expect(described_class.snake_case("TrailingUnderscore_")).to eq("trailing_underscore")
      expect(described_class.snake_case("_BothEnds_")).to eq("both_ends")
    end

    it "collapses multiple underscores" do
      expect(described_class.snake_case("Multiple___Underscores")).to eq("multiple_underscores")
      expect(described_class.snake_case("Too____Many_____Underscores")).to eq("too_many_underscores")
    end

    it "handles numbers in various positions" do
      expect(described_class.snake_case("Version2Agent")).to eq("version2_agent")
      expect(described_class.snake_case("Agent2Version")).to eq("agent2_version")
      expect(described_class.snake_case("HTTP2Protocol")).to eq("http2_protocol")
      expect(described_class.snake_case("Model3GPT")).to eq("model3_gpt")
    end

    it "converts symbols to strings first" do
      expect(described_class.snake_case(:CompanyAgent)).to eq("company_agent")
      expect(described_class.snake_case(:userProfile)).to eq("user_profile")
    end
  end

  describe ".sanitize_identifier" do
    it "delegates to snake_case" do
      input = "My Identifier!"
      
      expect(described_class).to receive(:snake_case).with(input).and_call_original
      result = described_class.sanitize_identifier(input)
      
      expect(result).to eq("my_identifier")
    end

    it "sanitizes table names" do
      expect(described_class.sanitize_identifier("My Table Name!")).to eq("my_table_name")
      expect(described_class.sanitize_identifier("User-Profile Data")).to eq("user_profile_data")
    end

    it "sanitizes tool names" do
      expect(described_class.sanitize_identifier("Special Characters & Spaces")).to eq("special_characters_spaces")
      expect(described_class.sanitize_identifier("Web Search Tool v2.0")).to eq("web_search_tool_v2_0")
    end

    it "handles database identifiers" do
      expect(described_class.sanitize_identifier("user profiles")).to eq("user_profiles")
      expect(described_class.sanitize_identifier("Order Items (Latest)")).to eq("order_items_latest")
    end
  end

  describe ".parse_json" do
    it "parses valid JSON with symbolized keys" do
      json_string = '{"name": "John", "age": 30}'
      result = described_class.parse_json(json_string)
      
      expect(result).to eq(name: "John", age: 30)
    end

    it "parses JSON arrays with symbolized keys" do
      json_string = '[{"id": 1, "name": "First"}, {"id": 2, "name": "Second"}]'
      result = described_class.parse_json(json_string)
      
      expect(result).to eq([
        { id: 1, name: "First" },
        { id: 2, name: "Second" }
      ])
    end

    it "parses nested JSON structures" do
      json_string = '{
        "user": {
          "profile": {
            "name": "John",
            "settings": ["theme", "notifications"]
          }
        }
      }'
      
      result = described_class.parse_json(json_string)
      
      expect(result).to eq(
        user: {
          profile: {
            name: "John",
            settings: ["theme", "notifications"]
          }
        }
      )
    end

    it "raises JSON::ParserError for invalid JSON" do
      expect {
        described_class.parse_json('invalid json')
      }.to raise_error(JSON::ParserError)
    end

    it "handles primitive JSON values" do
      expect(described_class.parse_json('"string"')).to eq("string")
      expect(described_class.parse_json('42')).to eq(42)
      expect(described_class.parse_json('true')).to eq(true)
      expect(described_class.parse_json('false')).to eq(false)
      expect(described_class.parse_json('null')).to be_nil
    end
  end

  describe ".safe_parse_json" do
    it "parses valid JSON successfully" do
      json_string = '{"name": "John", "age": 30}'
      result = described_class.safe_parse_json(json_string)
      
      expect(result).to eq(name: "John", age: 30)
    end

    it "returns nil for invalid JSON by default" do
      result = described_class.safe_parse_json('invalid json')
      expect(result).to be_nil
    end

    it "returns specified default for invalid JSON" do
      default_value = { error: "parsing_failed" }
      result = described_class.safe_parse_json('invalid json', default_value)
      
      expect(result).to eq(default_value)
    end

    it "returns different default types" do
      expect(described_class.safe_parse_json('invalid', {})).to eq({})
      expect(described_class.safe_parse_json('invalid', [])).to eq([])
      expect(described_class.safe_parse_json('invalid', "error")).to eq("error")
      expect(described_class.safe_parse_json('invalid', 0)).to eq(0)
      expect(described_class.safe_parse_json('invalid', false)).to eq(false)
    end

    it "handles various types of invalid JSON" do
      invalid_jsons = [
        'invalid json',
        '{invalid}',
        '{"unclosed": "string}',
        '{"trailing": "comma",}',
        '{duplicate": "key", "duplicate": "key"}',
        '',
        'undefined',
        'NaN'
      ]
      
      invalid_jsons.each do |invalid_json|
        result = described_class.safe_parse_json(invalid_json, "default")
        expect(result).to eq("default")
      end
    end

    it "delegates to parse_json for valid JSON" do
      json_string = '{"test": true}'
      
      expect(described_class).to receive(:parse_json).with(json_string).and_call_original
      described_class.safe_parse_json(json_string)
    end
  end

  describe ".format_number" do
    it "formats integers with thousands separators" do
      expect(described_class.format_number(1234567)).to eq("1,234,567")
      expect(described_class.format_number(1000)).to eq("1,000")
      expect(described_class.format_number(12345)).to eq("12,345")
    end

    it "formats floats with thousands separators" do
      expect(described_class.format_number(1234.56)).to eq("1,234.56")
      expect(described_class.format_number(1234567.89)).to eq("1,234,567.89")
      expect(described_class.format_number(1000.0)).to eq("1,000.0")
    end

    it "handles small numbers without separators" do
      expect(described_class.format_number(123)).to eq("123")
      expect(described_class.format_number(99)).to eq("99")
      expect(described_class.format_number(1)).to eq("1")
      expect(described_class.format_number(0)).to eq("0")
    end

    it "handles negative numbers" do
      expect(described_class.format_number(-1234567)).to eq("-1,234,567")
      expect(described_class.format_number(-1234.56)).to eq("-1,234.56")
      expect(described_class.format_number(-1000)).to eq("-1,000")
    end

    it "handles edge cases" do
      expect(described_class.format_number(0)).to eq("0")
      expect(described_class.format_number(0.0)).to eq("0.0")
      expect(described_class.format_number(1.0)).to eq("1.0")
    end

    it "handles very large numbers" do
      expect(described_class.format_number(1234567890123)).to eq("1,234,567,890,123")
      expect(described_class.format_number(999999999999999)).to eq("999,999,999,999,999")
    end

    it "converts input to string first" do
      # Should work with various numeric types
      expect(described_class.format_number(1234567)).to eq("1,234,567")
      expect(described_class.format_number(1234567.0)).to eq("1,234,567.0")
    end
  end

  describe ".normalize_whitespace" do
    it "removes extra whitespace from text" do
      expect(described_class.normalize_whitespace("  Hello    world  \n\n  ")).to eq("Hello world")
      expect(described_class.normalize_whitespace("Too   many    spaces")).to eq("Too many spaces")
    end

    it "normalizes various types of whitespace" do
      text_with_mixed_whitespace = "Text\t\twith\n\nmixed\r\nwhitespace"
      result = described_class.normalize_whitespace(text_with_mixed_whitespace)
      
      expect(result).to eq("Text with mixed whitespace")
    end

    it "strips leading and trailing whitespace" do
      expect(described_class.normalize_whitespace("   leading")).to eq("leading")
      expect(described_class.normalize_whitespace("trailing   ")).to eq("trailing")
      expect(described_class.normalize_whitespace("   both   ")).to eq("both")
    end

    it "handles empty and whitespace-only strings" do
      expect(described_class.normalize_whitespace("")).to eq("")
      expect(described_class.normalize_whitespace("   ")).to eq("")
      expect(described_class.normalize_whitespace("\n\t  \r\n")).to eq("")
    end

    it "preserves single spaces between words" do
      expect(described_class.normalize_whitespace("single space")).to eq("single space")
      expect(described_class.normalize_whitespace("already normalized")).to eq("already normalized")
    end

    it "handles newlines and line breaks" do
      multiline_text = "Line one\n\nLine two\n\n\nLine three"
      result = described_class.normalize_whitespace(multiline_text)
      
      expect(result).to eq("Line one Line two Line three")
    end

    it "converts input to string first" do
      expect(described_class.normalize_whitespace(nil)).to eq("")
      expect(described_class.normalize_whitespace(123)).to eq("123")
      expect(described_class.normalize_whitespace(:symbol)).to eq("symbol")
    end

    it "handles special characters mixed with whitespace" do
      text = "  Special!@#$%  characters   with   spaces  "
      result = described_class.normalize_whitespace(text)
      
      expect(result).to eq("Special!@#$% characters with spaces")
    end
  end

  describe "roundtrip conversions" do
    it "maintains data integrity through symbolize -> stringify roundtrip" do
      original = {
        user: {
          profile: {
            name: "John",
            metadata: [{ id: 1, active: true }]
          }
        }
      }
      
      stringified = described_class.deep_stringify_keys(original)
      symbolized_again = described_class.deep_symbolize_keys(stringified)
      
      expect(symbolized_again).to eq(original)
    end

    it "maintains data integrity through stringify -> symbolize roundtrip" do
      original = {
        "user" => {
          "profile" => {
            "name" => "John",
            "metadata" => [{ "id" => 1, "active" => true }]
          }
        }
      }
      
      symbolized = described_class.deep_symbolize_keys(original)
      stringified_again = described_class.deep_stringify_keys(symbolized)
      
      expect(stringified_again).to eq(original)
    end
  end

  describe "performance considerations" do
    it "handles deeply nested structures without stack overflow" do
      # Create a deeply nested structure
      deep_hash = { "level0" => {} }
      current = deep_hash["level0"]
      
      100.times do |i|
        current["level#{i + 1}"] = {}
        current = current["level#{i + 1}"]
      end
      current["value"] = "deep"
      
      # Should not raise stack overflow
      expect {
        result = described_class.deep_symbolize_keys(deep_hash)
        expect(result.dig(*Array.new(101) { |i| "level#{i}".to_sym }).merge(value: "deep")).to include(value: "deep")
      }.not_to raise_error
    end

    it "handles large arrays efficiently" do
      large_array = Array.new(1000) { |i| { "item_#{i}" => i } }
      
      result = described_class.deep_symbolize_keys(large_array)
      
      expect(result).to be_an(Array)
      expect(result.length).to eq(1000)
      expect(result[0]).to have_key(:"item_0")
      expect(result[999]).to have_key(:"item_999")
    end
  end

  describe "integration scenarios" do
    it "supports typical API request/response cycle" do
      # Prepare request for OpenAI API
      request = {
        model: "gpt-4o",
        messages: [
          { role: :system, content: "You are helpful" },
          { role: :user, content: "Hello" }
        ],
        temperature: 0.7
      }
      
      api_request = described_class.prepare_for_openai(request)
      expect(api_request.keys).to all(be_a(String))
      
      # Simulate API response
      api_response = {
        "id" => "chatcmpl-123",
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => "Hello! How can I help?"
          }
        }]
      }
      
      normalized_response = described_class.normalize_response(api_response)
      expect(normalized_response.keys).to all(be_a(Symbol))
      
      # Verify data integrity
      expect(normalized_response[:choices][0][:message][:content]).to eq("Hello! How can I help?")
    end

    it "supports agent name normalization workflow" do
      agent_names = [
        "CustomerServiceAgent",
        "XML Parser Agent",
        "Web-Search Tool v2",
        "Special Characters & Symbols!"
      ]
      
      normalized_names = agent_names.map do |name|
        described_class.snake_case(name)
      end
      
      expect(normalized_names).to eq([
        "customer_service_agent",
        "xml_parser_agent",
        "web_search_tool_v2",
        "special_characters_symbols"
      ])
    end

    it "supports safe JSON processing in error scenarios" do
      # Simulate various JSON inputs that might come from external sources
      json_inputs = [
        '{"valid": "json"}',      # Valid
        'invalid json',           # Invalid
        '',                       # Empty
        '{"partial"',            # Incomplete
        'null',                   # Null value
        '[]'                      # Empty array
      ]
      
      results = json_inputs.map do |json|
        described_class.safe_parse_json(json, { error: "parse_failed" })
      end
      
      expect(results[0]).to eq(valid: "json")
      expect(results[1]).to eq(error: "parse_failed")
      expect(results[2]).to eq(error: "parse_failed")
      expect(results[3]).to eq(error: "parse_failed")
      expect(results[4]).to be_nil
      expect(results[5]).to eq([])
    end
  end
end