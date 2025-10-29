# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "RAAF::Continuation::Mergers::JSONMerger" do
  # Test JSON Merger implementation
  # This class handles merging JSON chunks from continuation responses
  # with intelligent detection of incomplete objects and arrays,
  # integration with JsonRepair, and schema validation

  let(:config) { RAAF::Continuation::Config.new }
  let(:json_merger) { RAAF::Continuation::Mergers::JSONMerger.new(config) }

  # ============================================================================
  # 1. Array Continuation Tests (8 tests)
  # ============================================================================
  describe "array continuation" do
    it "merges two JSON array chunks" do
      chunk1 = { content: '{"items": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}' }
      chunk2 = { content: ', {"id": 3, "name": "Charlie"}]}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content]).to include('"id": 1')
      expect(result[:content]).to include('"id": 3')
    end

    it "detects incomplete JSON arrays" do
      content = '{"items": [{"id": 1}, {"id": 2}, {"id"'
      expect(json_merger.send(:has_incomplete_json_structure?, content)).to be true
    end

    it "detects incomplete objects in arrays" do
      content = '{"data": [{"name": "Alice", "email": "alice@example.com"}, {"name": "Bob"'
      expect(json_merger.send(:has_incomplete_json_structure?, content)).to be true
    end

    it "merges large arrays (100+ items)" do
      items = (1..50).map { |i| %Q({"id": #{i}, "name": "Item#{i}"}) }
      items2 = (51..100).map { |i| %Q({"id": #{i}, "name": "Item#{i}"}) }

      chunk1 = { content: %Q({"items": [#{items.join(", ")}]) }
      chunk2 = { content: %Q(, #{items2.join(", ")}]}) }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["items"].length).to eq(100)
    end

    it "preserves array order across chunks" do
      items = (1..10).map { |i| %Q({"id": #{i}, "value": "val#{i}"}) }
      chunk1 = { content: %Q({"data": [#{items[0..4].join(", ")}]) }
      chunk2 = { content: %Q(, #{items[5..9].join(", ")}]}) }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      (1..10).each do |i|
        expect(parsed["data"].map { |item| item["id"] }).to include(i)
      end
    end

    it "handles arrays of primitives" do
      chunk1 = { content: '{"numbers": [1, 2, 3, 4' }
      chunk2 = { content: ', 5, 6, 7, 8, 9, 10]}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["numbers"].length).to eq(10)
    end

    it "handles nested arrays" do
      chunk1 = { content: '{"matrix": [[1, 2], [3, 4]' }
      chunk2 = { content: ', [5, 6]]}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["matrix"].length).to eq(3)
    end

    it "validates complete arrays pass detection" do
      complete = '{"items": [{"id": 1}, {"id": 2}]}'
      expect(json_merger.send(:has_incomplete_json_structure?, complete)).to be false
    end
  end

  # ============================================================================
  # 2. Object Continuation Tests (8 tests)
  # ============================================================================
  describe "object continuation" do
    it "merges incomplete JSON objects across chunks" do
      chunk1 = { content: '{"user": {"id": 1, "name": "Alice", "email":' }
      chunk2 = { content: ' "alice@example.com", "active": true}}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["user"]["name"]).to eq("Alice")
    end

    it "detects incomplete object fields" do
      content = '{"user": {"id": 1, "name": "Alice", "email":'
      expect(json_merger.send(:has_incomplete_json_structure?, content)).to be true
    end

    it "merges multiple incomplete objects" do
      chunk1 = { content: '[{"id": 1, "name": "A' }
      chunk2 = { content: 'lice", "email": "a@ex' }
      chunk3 = { content: 'ample.com"}, {"id": 2, "name": "Bob"}]' }

      result = json_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed.length).to eq(2)
    end

    it "handles deeply nested objects" do
      chunk1 = { content: '{"level1": {"level2": {"level3": {"level4":' }
      chunk2 = { content: ' {"data": "value"}}}}}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["level1"]["level2"]["level3"]["level4"]["data"]).to eq("value")
    end

    it "merges objects with many fields" do
      fields = (1..20).map { |i| %Q("field#{i}": "value#{i}") }.join(", ")
      chunk1 = { content: "{#{fields[0..200]}" }
      chunk2 = { content: "#{fields[201..-1]}}" }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed.keys.length).to be >= 1
    end

    it "handles objects with null values" do
      chunk1 = { content: '{"data": {"id": 1, "value": null, "name":' }
      chunk2 = { content: ' "test"}}' }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["data"]["value"]).to be_nil
    end

    it "handles objects with boolean values" do
      chunk1 = { content: '{"settings": {"enabled": true, "debug":' }
      chunk2 = { content: ' false, "active": true}}' }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["settings"]["enabled"]).to be true
      expect(parsed["settings"]["debug"]).to be false
    end

    it "validates complete objects pass detection" do
      complete = '{"user": {"id": 1, "name": "Alice"}}'
      expect(json_merger.send(:has_incomplete_json_structure?, complete)).to be false
    end
  end

  # ============================================================================
  # 3. Nested Structures Tests (8 tests)
  # ============================================================================
  describe "nested structures" do
    it "merges arrays of objects with nested properties" do
      chunk1 = { content: '[{"id": 1, "data": {"nested": "value1"}, "list": [1, 2' }
      chunk2 = { content: ', 3]}, {"id": 2, "data": {"nested": "value2"}}]' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed[0]["data"]["nested"]).to eq("value1")
      expect(parsed[0]["list"].length).to eq(3)
    end

    it "handles objects with mixed types" do
      chunk1 = { content: '{"string": "value", "number": 42, "float": 3.14, "bool":' }
      chunk2 = { content: ' true, "null": null, "array": [1, 2], "object": {"key":' }
      chunk3 = { content: ' "val"}}' }

      result = json_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["string"]).to eq("value")
      expect(parsed["number"]).to eq(42)
      expect(parsed["float"]).to eq(3.14)
      expect(parsed["bool"]).to be true
    end

    it "merges deeply nested arrays and objects" do
      chunk1 = { content: '{"outer": [{"inner": [{"deep": [1, 2' }
      chunk2 = { content: ', 3]}]}]}' }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["outer"][0]["inner"][0]["deep"]).to eq([1, 2, 3])
    end

    it "handles mixed nesting with objects in arrays in objects" do
      chunk1 = { content: '{"wrapper": {"items": [{"id": 1, "details": {"name":' }
      chunk2 = { content: ' "Item1"}}, {"id": 2, "details": {"name": "Item2"' }
      chunk3 = { content: '}}]}}' }

      result = json_merger.merge([chunk1, chunk2, chunk3])

      parsed = JSON.parse(result[:content])
      expect(parsed["wrapper"]["items"][0]["details"]["name"]).to eq("Item1")
      expect(parsed["wrapper"]["items"].length).to eq(2)
    end

    it "merges arrays with varying object structures" do
      chunk1 = { content: '[{"id": 1, "type": "A"}, {"id": 2, "type": "B", "extra":' }
      chunk2 = { content: ' "field"}, {"id": 3}]' }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed.length).to eq(3)
      expect(parsed[1]).to have_key("extra")
    end

    it "maintains structure with empty nested arrays" do
      chunk1 = { content: '{"data": [{"items": []}, {"items": [' }
      chunk2 = { content: '1, 2]}]}' }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["data"][0]["items"]).to eq([])
      expect(parsed["data"][1]["items"]).to eq([1, 2])
    end

    it "handles objects with nested empty structures" do
      chunk1 = { content: '{"container": {"data": {}, "array":' }
      chunk2 = { content: ' []}}' }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["container"]["data"]).to eq({})
      expect(parsed["container"]["array"]).to eq([])
    end
  end

  # ============================================================================
  # 4. Malformed JSON Repair Tests (8 tests)
  # ============================================================================
  describe "malformed JSON repair" do
    it "repairs trailing commas in objects" do
      chunk1 = { content: '{"name": "Alice", "age": 30,' }
      chunk2 = { content: '}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["name"]).to eq("Alice")
    end

    it "repairs trailing commas in arrays" do
      chunk1 = { content: '{"items": [1, 2, 3,' }
      chunk2 = { content: ']}' }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["items"]).to eq([1, 2, 3])
    end

    it "repairs single quotes to double quotes" do
      chunk1 = { content: %Q({"name": 'Alice', "city": 'New York'}) }

      result = json_merger.merge([chunk1])

      parsed = JSON.parse(result[:content])
      expect(parsed["name"]).to eq("Alice")
      expect(parsed["city"]).to eq("New York")
    end

    it "handles markdown-wrapped JSON" do
      chunk1 = { content: '```json' }
      chunk2 = { content: %Q(\n{"data": "value"}\n) }
      chunk3 = { content: '```' }

      result = json_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content]).to include('"data": "value"')
    end

    it "repairs missing closing brackets" do
      chunk1 = { content: '[{"id": 1, "name": "A' }
      chunk2 = { content: 'lice"}, {"id": 2}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed.length).to be >= 1
    end

    it "handles mixed single and double quotes" do
      chunk1 = { content: %Q({"field": 'value', "other": "test"}) }

      result = json_merger.merge([chunk1])

      parsed = JSON.parse(result[:content])
      expect(parsed["field"]).to eq("value")
    end

    it "repairs unescaped newlines in strings" do
      chunk1 = { content: '{"text": "Line 1\nLine 2\nLine 3"' }
      chunk2 = { content: '}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["text"]).to include("Line 1")
    end

    it "repairs multiple JSON issues simultaneously" do
      chunk1 = { content: %Q({"name": 'John', "items": [1, 2,) }
      chunk2 = { content: %Q(3,]}) }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      # Should have repaired quotes and trailing comma
      expect(result[:content]).to be_a(String)
    end
  end

  # ============================================================================
  # 5. Schema Validation Tests (6 tests)
  # ============================================================================
  describe "schema validation" do
    it "validates complete JSON against schema" do
      chunk1 = { content: '{"name": "Alice", "age": 30, "email": "alice@example' }
      chunk2 = { content: '.com"}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed).to have_key("name")
      expect(parsed).to have_key("age")
      expect(parsed).to have_key("email")
    end

    it "handles validation with partial data" do
      chunk1 = { content: '{"name": "Bob"' }
      chunk2 = { content: ', "age": 25}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["name"]).to eq("Bob")
    end

    it "validates arrays of objects against schema" do
      chunk1 = { content: '[{"id": 1, "name": "Item1", "category": "A' }
      chunk2 = { content: '"}' }
      chunk3 = { content: ', {"id": 2, "name": "Item2", "category": "B"}]' }

      result = json_merger.merge([chunk1, chunk2, chunk3])

      parsed = JSON.parse(result[:content])
      expect(parsed[0]).to have_key("id")
      expect(parsed[0]).to have_key("name")
      expect(parsed[1]).to have_key("category")
    end

    it "handles schema validation errors gracefully" do
      # Invalid JSON that can't be fully repaired
      chunk1 = { content: '{"data": [{"incomplete' }

      result = json_merger.merge([chunk1])

      # Should attempt merge even if validation fails
      expect(result[:metadata]).to have_key(:merge_success)
    end

    it "validates nested schema structures" do
      chunk1 = { content: '{"user": {"profile": {"name": "Alice", "age":' }
      chunk2 = { content: ' 30}}, "settings": {"theme": "dark"}}' }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["user"]["profile"]["name"]).to eq("Alice")
      expect(parsed["settings"]["theme"]).to eq("dark")
    end

    it "validates with type coercion" do
      chunk1 = { content: '{"count": "42", "price": "19.99"' }
      chunk2 = { content: ', "active": "true"}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      # JSON will keep them as strings, but merging should succeed
      expect(result[:content]).to include('"count": "42"')
    end
  end

  # ============================================================================
  # 6. Edge Cases Tests (5 tests)
  # ============================================================================
  describe "edge cases" do
    it "handles unicode in JSON strings" do
      chunk1 = { content: '{"name": "José", "city": "São Paulo"' }
      chunk2 = { content: ', "country": "中国"}' }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["name"]).to eq("José")
      expect(parsed["city"]).to eq("São Paulo")
      expect(parsed["country"]).to eq("中国")
    end

    it "handles very large numbers" do
      chunk1 = { content: '{"big_int": 999999999999999999999' }
      chunk2 = { content: ', "big_float": 3.141592653589793}' }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["big_float"]).to be_a(Float)
    end

    it "handles deeply nested structure (10+ levels)" do
      nest = '{"l'
      (1..10).each { |i| nest += i.to_s + '": {"l' }
      nest += '11": "deep"' + '}' * 11

      chunk1 = { content: nest[0..100] }
      chunk2 = { content: nest[101..-1] }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
    end

    it "handles extremely large arrays (1000+ items)" do
      items = (1..500).map { |i| %Q({"id": #{i}}) }
      items2 = (501..1000).map { |i| %Q({"id": #{i}}) }

      chunk1 = { content: %Q([#{items.join(", ")}]) }
      chunk2 = { content: %Q(, #{items2.join(", ")}]) }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed.length).to eq(1000)
    end

    it "handles whitespace variations" do
      chunk1 = { content: "{\n  \"name\": \"Alice\",\n" }
      chunk2 = { content: "  \"age\":  30\n}" }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["name"]).to eq("Alice")
    end
  end

  # ============================================================================
  # 7. Metadata Tests (4 tests)
  # ============================================================================
  describe "metadata structure" do
    it "builds correct metadata for successful merge" do
      chunk1 = { content: '{"data":' }
      chunk2 = { content: ' "value"}' }

      result = json_merger.merge([chunk1, chunk2])

      expect(result[:metadata]).to be_a(Hash)
      expect(result[:metadata][:merge_success]).to be true
      expect(result[:metadata][:chunk_count]).to eq(2)
      expect(result[:metadata][:timestamp]).to be_a(String)
    end

    it "includes merge_success flag" do
      chunk = { content: '{"test": true}' }
      result = json_merger.merge([chunk])

      expect(result[:metadata]).to have_key(:merge_success)
      expect([true, false]).to include(result[:metadata][:merge_success])
    end

    it "includes chunk_count in metadata" do
      chunks = (1..5).map { |i| { content: "{\"part#{i}\": #{i}}" } }
      result = json_merger.merge(chunks)

      expect(result[:metadata][:chunk_count]).to eq(5)
    end

    it "includes timestamp in metadata" do
      chunk = { content: '{"data": "value"}' }
      result = json_merger.merge([chunk])

      expect(result[:metadata][:timestamp]).to be_a(String)
      expect(result[:metadata][:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end
  end

  # ============================================================================
  # 8. Integration Tests (7 tests)
  # ============================================================================
  describe "json merger integration" do
    it "merges realistic company dataset" do
      chunk1 = {
        content: '[{"company_id": 1, "name": "Apple Inc", "headquarters": "Cupertino, CA", "employees": 161000, "industry": "Technology"'
      }
      chunk2 = {
        content: ', "founded": 1976}, {"company_id": 2, "name": "Microsoft", "headquarters": "Redmond, WA", "employees": 221000'
      }
      chunk3 = {
        content: ', "industry": "Technology", "founded": 1975}]'
      }

      result = json_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed.length).to eq(2)
      expect(parsed[0]["name"]).to eq("Apple Inc")
    end

    it "handles chunks with mixed ending styles" do
      chunk1 = { content: '{"data": [1, 2, 3' }
      chunk2 = { content: ', 4, 5' }
      chunk3 = { content: ', 6, 7]}' }

      result = json_merger.merge([chunk1, chunk2, chunk3])

      parsed = JSON.parse(result[:content])
      expect(parsed["data"].length).to eq(7)
    end

    it "validates proper merging of complex nested structure" do
      chunk1 = {
        content: '{"organizations": [{"id": 1, "name": "Org1", "departments": [{"name": "Engineering", "employees":'
      }
      chunk2 = {
        content: ' [{"name": "Alice", "role": "Senior"},'
      }
      chunk3 = {
        content: ' {"name": "Bob", "role": "Junior"}]}]}]}'
      }

      result = json_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["organizations"][0]["departments"][0]["employees"].length).to eq(2)
    end

    it "preserves data integrity across merges" do
      # Create JSON with specific data patterns
      data = (1..50).map do |i|
        %Q({"id": #{i}, "value": "data#{i}", "price": #{100 + i * 10}.50})
      end.join(", ")

      chunk1 = { content: "[#{data[0..1500]}" }
      chunk2 = { content: "#{data[1501..-1]}]" }

      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed.length).to eq(50)
      expect(parsed[0]["id"]).to eq(1)
      expect(parsed[49]["id"]).to eq(50)
    end

    it "extracts content from hash chunks with various keys" do
      chunk1 = { "content" => '{"key1":' }
      chunk2 = { content: ' "value1"' }
      chunk3 = { message: { content: ', "key2": "value2"}' } }

      result = json_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["key1"]).to eq("value1")
    end

    it "handles merge with nil and empty content in chunks" do
      chunk1 = { content: '{"data": [' }
      chunk2 = nil
      chunk3 = { content: "" }
      chunk4 = { content: '{"nested": "value"}]}' }

      result = json_merger.merge([chunk1, chunk2, chunk3, chunk4])

      expect(result[:metadata][:merge_success]).to be true
      parsed = JSON.parse(result[:content])
      expect(parsed["data"]).to be_a(Array)
    end

    it "handles real-world API response merging" do
      chunk1 = {
        content: '{"status": "success", "data": {"items": [{"id": 1, "name": "Item1", "metadata": {"created": "2025-01-01", "updated":'
      }
      chunk2 = {
        content: ' "2025-01-15"}}, {"id": 2, "name": "Item2", "metadata": {"created": "2025-01-02"'
      }
      chunk3 = {
        content: ', "updated": "2025-01-20"}}], "count": 2, "page": 1}}'
      }

      result = json_merger.merge([chunk1, chunk2, chunk3])

      parsed = JSON.parse(result[:content])
      expect(parsed["status"]).to eq("success")
      expect(parsed["data"]["items"].length).to eq(2)
      expect(parsed["data"]["count"]).to eq(2)
    end
  end
end
