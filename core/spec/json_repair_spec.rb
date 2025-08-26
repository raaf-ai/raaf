# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/raaf/json_repair'

RSpec.describe RAAF::JsonRepair do
  describe ".repair" do
    context "with valid JSON" do
      it "returns parsed hash for valid JSON string" do
        valid_json = '{"name": "John", "age": 30}'
        result = described_class.repair(valid_json)
        
        expect(result).to eq(name: "John", age: 30)
      end

      it "returns hash as-is when passed a hash" do
        hash = { name: "John", age: 30 }
        result = described_class.repair(hash)
        
        expect(result).to eq(hash)
      end
    end

    context "with malformed JSON" do
      it "fixes trailing commas in objects" do
        malformed = '{"name": "John", "age": 30,}'
        result = described_class.repair(malformed)
        
        expect(result).to eq(name: "John", age: 30)
      end

      it "fixes trailing commas in arrays" do
        malformed = '{"items": ["a", "b", "c",]}'
        result = described_class.repair(malformed)
        
        expect(result).to eq(items: ["a", "b", "c"])
      end

      it "fixes single quotes in keys" do
        malformed = "{'name': \"John\", 'age': 30}"
        result = described_class.repair(malformed)
        
        expect(result).to eq(name: "John", age: 30)
      end

      it "fixes single quotes in values" do
        malformed = '{"name": \'John\', "age": 30}'
        result = described_class.repair(malformed)
        
        expect(result).to eq(name: "John", age: 30)
      end

      it "removes newlines from JSON" do
        malformed = <<~JSON
          {
            "name": "John",
            "age": 30
          }
        JSON
        result = described_class.repair(malformed)
        
        expect(result).to eq(name: "John", age: 30)
      end

      it "fixes unquoted keys" do
        malformed = '{name: "John", age: 30}'
        result = described_class.repair(malformed)
        
        expect(result).to eq(name: "John", age: 30)
      end

      it "fixes quoted numbers that should be numeric" do
        malformed = '{"name": "John", "age": "30", "score": "123.45"}'
        result = described_class.repair(malformed)
        
        expect(result).to eq(name: "John", age: 30, score: 123.45)
      end

      it "fixes quoted booleans and null" do
        malformed = '{"active": "true", "verified": "false", "data": "null"}'
        result = described_class.repair(malformed)
        
        expect(result).to eq(active: true, verified: false, data: nil)
      end
    end

    context "with JSON in markdown" do
      it "extracts JSON from ```json blocks" do
        markdown = <<~MD
          Here's some JSON:
          ```json
          {"name": "John", "age": 30}
          ```
          That was the JSON.
        MD
        result = described_class.repair(markdown)
        
        expect(result).to eq(name: "John", age: 30)
      end

      it "extracts JSON from generic ``` blocks" do
        markdown = <<~MD
          ```
          {"name": "John", "age": 30}
          ```
        MD
        result = described_class.repair(markdown)
        
        expect(result).to eq(name: "John", age: 30)
      end

      it "extracts malformed JSON from markdown and repairs it" do
        markdown = <<~MD
          ```json
          {"name": "John", "age": 30,}
          ```
        MD
        result = described_class.repair(markdown)
        
        expect(result).to eq(name: "John", age: 30)
      end
    end

    context "with JSON-like structures in text" do
      it "extracts simple JSON objects from mixed content" do
        text = 'The result is {"status": "success", "count": 5} and that\'s it.'
        result = described_class.repair(text)
        
        expect(result).to eq(status: "success", count: 5)
      end

      it "extracts simple JSON arrays from mixed content" do
        text = 'The items are ["apple", "banana", "orange"] from the store.'
        result = described_class.repair(text)
        
        expect(result).to eq(["apple", "banana", "orange"])
      end

      it "extracts the longest/most complete JSON structure" do
        text = <<~TEXT
          Small object: {"a": 1}
          Larger object: {"name": "John", "details": {"age": 30, "city": "NYC"}}
          Another: {"b": 2}
        TEXT
        result = described_class.repair(text)
        
        # Should pick the largest/most complex structure
        expect(result).to eq(name: "John", details: { age: 30, city: "NYC" })
      end
    end

    context "with completely invalid input" do
      it "returns nil for non-string, non-hash input" do
        result = described_class.repair(123)
        expect(result).to be_nil
      end

      it "returns nil for empty string" do
        result = described_class.repair("")
        expect(result).to be_nil
      end

      it "returns nil for unparseable text" do
        result = described_class.repair("This is just regular text with no JSON")
        expect(result).to be_nil
      end

      it "returns nil for heavily malformed JSON that can't be repaired" do
        result = described_class.repair('{"broken": json, missing: quotes, 123: invalid}')
        expect(result).to be_nil
      end
    end

    context "with complex nested structures" do
      it "handles nested objects with repairs" do
        malformed = <<~JSON
          {
            "user": {
              "name": "John",
              "details": {
                "age": 30,
                "hobbies": ["reading", "coding",],
              },
            },
            "active": true,
          }
        JSON
        result = described_class.repair(malformed)
        
        expect(result).to eq(
          user: {
            name: "John", 
            details: {
              age: 30,
              hobbies: ["reading", "coding"]
            }
          },
          active: true
        )
      end

      it "handles mixed quote types in nested structures" do
        malformed = <<~JSON
          {
            'user': {
              "name": 'John O\'Brien',
              "settings": {
                'theme': "dark",
                'notifications': true,
              }
            }
          }
        JSON
        result = described_class.repair(malformed)
        
        expect(result[:user][:name]).to eq("John O'Brien")
        expect(result[:user][:settings][:theme]).to eq("dark")
        expect(result[:user][:settings][:notifications]).to be true
      end
    end
  end

  describe ".extract_json_from_content" do
    it "finds the first valid JSON structure in mixed content" do
      content = <<~TEXT
        This is some text before.
        {"first": "object", "valid": true}
        More text here.
        {"second": "object"}
        Even more text.
      TEXT
      
      result = described_class.extract_json_from_content(content)
      expect(result).to eq(first: "object", valid: true)
    end

    it "handles nested JSON structures" do
      content = <<~TEXT
        The configuration is: {
          "database": {"host": "localhost", "port": 5432},
          "cache": {"enabled": true, "ttl": 300}
        }
      TEXT
      
      result = described_class.extract_json_from_content(content)
      expect(result).to eq(
        database: { host: "localhost", port: 5432 },
        cache: { enabled: true, ttl: 300 }
      )
    end

    it "returns nil when no valid JSON found" do
      content = "This is just plain text with no JSON structures."
      result = described_class.extract_json_from_content(content)
      expect(result).to be_nil
    end

    it "prefers objects over arrays when both are present" do
      content = '["array", "first"] {"object": "second"}'
      result = described_class.extract_json_from_content(content)
      expect(result).to eq(object: "second")
    end
  end
end