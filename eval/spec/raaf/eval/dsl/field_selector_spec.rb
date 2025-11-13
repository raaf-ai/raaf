# frozen_string_literal: true

require "spec_helper"
require "raaf/eval/dsl/field_selector"
require "raaf/eval/dsl/field_context"

RSpec.describe RAAF::Eval::DSL::FieldSelector do
  describe "2.1 - nested path parsing" do
    let(:selector) { described_class.new }

    it "parses single-level field names" do
      parsed = selector.parse_path("output")
      expect(parsed).to eq(["output"])
    end

    it "parses dot notation paths (usage.total_tokens)" do
      parsed = selector.parse_path("usage.total_tokens")
      expect(parsed).to eq(["usage", "total_tokens"])
    end

    it "parses deeply nested paths (a.b.c.d)" do
      parsed = selector.parse_path("result.metrics.quality.score")
      expect(parsed).to eq(["result", "metrics", "quality", "score"])
    end

    it "handles symbol field names" do
      parsed = selector.parse_path(:output)
      expect(parsed).to eq(["output"])
    end

    it "handles nested symbol paths" do
      parsed = selector.parse_path(:"usage.total_tokens")
      expect(parsed).to eq(["usage", "total_tokens"])
    end

    it "raises error for invalid path formats (empty string)" do
      expect { selector.parse_path("") }.to raise_error(
        RAAF::Eval::DSL::InvalidPathError,
        /empty or invalid/
      )
    end

    it "raises error for invalid path formats (nil)" do
      expect { selector.parse_path(nil) }.to raise_error(
        RAAF::Eval::DSL::InvalidPathError,
        /empty or invalid/
      )
    end

    it "caches parsed paths for performance" do
      # Parse same path twice
      parsed1 = selector.parse_path("usage.total_tokens")
      parsed2 = selector.parse_path("usage.total_tokens")
      
      # Should return same object (cached)
      expect(parsed1).to be(parsed2)
    end
  end

  describe "2.3 - field extraction" do
    let(:selector) { described_class.new }
    let(:result) do
      {
        output: "Generated text",
        usage: {
          total_tokens: 150,
          prompt_tokens: 50,
          completion_tokens: 100
        },
        deeply: {
          nested: {
            field: {
              value: "deep_value"
            }
          }
        }
      }
    end

    it "extracts single field values" do
      value = selector.extract_value("output", result)
      expect(value).to eq("Generated text")
    end

    it "extracts nested field values using dig" do
      value = selector.extract_value("usage.total_tokens", result)
      expect(value).to eq(150)
    end

    it "extracts deeply nested values" do
      value = selector.extract_value("deeply.nested.field.value", result)
      expect(value).to eq("deep_value")
    end

    it "raises clear error when field is missing" do
      expect { selector.extract_value("missing_field", result) }.to raise_error(
        RAAF::Eval::DSL::FieldNotFoundError,
        /Field 'missing_field' not found/
      )
    end

    it "raises clear error when nested field is missing" do
      expect { selector.extract_value("usage.missing_tokens", result) }.to raise_error(
        RAAF::Eval::DSL::FieldNotFoundError,
        /Field 'usage.missing_tokens' not found/
      )
    end

    it "handles missing intermediate keys gracefully" do
      expect { selector.extract_value("nonexistent.path.field", result) }.to raise_error(
        RAAF::Eval::DSL::FieldNotFoundError,
        /Field 'nonexistent.path.field' not found/
      )
    end

    it "extracts from HashWithIndifferentAccess" do
      indifferent_result = ActiveSupport::HashWithIndifferentAccess.new(result)
      value = selector.extract_value("usage.total_tokens", indifferent_result)
      expect(value).to eq(150)
    end

    it "extracts from complex result structures with arrays" do
      complex_result = {
        items: [
          { name: "first", value: 10 },
          { name: "second", value: 20 }
        ]
      }
      
      # Note: Array indexing not supported in this implementation
      # This tests that we handle it appropriately
      expect { selector.extract_value("items.0.value", complex_result) }.to raise_error(
        RAAF::Eval::DSL::FieldNotFoundError
      )
    end
  end

  describe "2.5 - field aliasing" do
    let(:selector) { described_class.new }

    it "assigns aliases with as: parameter" do
      selector.add_field("usage.total_tokens", as: :tokens)
      
      expect(selector.fields).to include("usage.total_tokens")
      expect(selector.aliases[:tokens]).to eq("usage.total_tokens")
    end

    it "allows alias usage in field context" do
      selector.add_field("usage.total_tokens", as: :tokens)
      
      # Get the original path for an alias
      original_path = selector.resolve_alias(:tokens)
      expect(original_path).to eq("usage.total_tokens")
    end

    it "detects duplicate aliases" do
      selector.add_field("usage.total_tokens", as: :tokens)
      
      expect { 
        selector.add_field("usage.prompt_tokens", as: :tokens) 
      }.to raise_error(
        RAAF::Eval::DSL::DuplicateAliasError,
        /Alias 'tokens' is already assigned/
      )
    end

    it "allows multiple fields without aliases" do
      selector.add_field("output")
      selector.add_field("usage.total_tokens")
      
      expect(selector.fields).to contain_exactly("output", "usage.total_tokens")
      expect(selector.aliases).to be_empty
    end

    it "allows same field to be selected multiple times with different aliases" do
      selector.add_field("usage.total_tokens", as: :tokens)
      selector.add_field("usage.total_tokens", as: :total)
      
      expect(selector.aliases[:tokens]).to eq("usage.total_tokens")
      expect(selector.aliases[:total]).to eq("usage.total_tokens")
    end

    it "stores fields in order of addition" do
      selector.add_field("first")
      selector.add_field("second")
      selector.add_field("third")
      
      expect(selector.fields).to eq(["first", "second", "third"])
    end

    it "resolves non-aliased fields to themselves" do
      selector.add_field("output")
      
      resolved = selector.resolve_alias("output")
      expect(resolved).to eq("output")
    end

    it "converts symbol aliases to strings internally" do
      selector.add_field("usage.total_tokens", as: :tokens)
      
      # Should work with both string and symbol
      expect(selector.resolve_alias(:tokens)).to eq("usage.total_tokens")
      expect(selector.resolve_alias("tokens")).to eq("usage.total_tokens")
    end
  end

  describe "2.7 - validation" do
    let(:selector) { described_class.new }

    it "validates field paths at selection time" do
      # Should not raise for valid path format
      expect { selector.add_field("usage.total_tokens") }.not_to raise_error
    end

    it "detects missing fields during extraction" do
      result = { output: "text" }
      
      selector.add_field("missing_field")
      
      expect { 
        selector.extract_value("missing_field", result) 
      }.to raise_error(
        RAAF::Eval::DSL::FieldNotFoundError,
        /Field 'missing_field' not found/
      )
    end

    it "detects invalid path formats at selection time" do
      expect { 
        selector.add_field("") 
      }.to raise_error(
        RAAF::Eval::DSL::InvalidPathError,
        /empty or invalid/
      )
    end

    it "provides clear error messages with field name and path" do
      result = { usage: { prompt_tokens: 50 } }
      
      selector.add_field("usage.total_tokens")
      
      expect { 
        selector.extract_value("usage.total_tokens", result) 
      }.to raise_error(
        RAAF::Eval::DSL::FieldNotFoundError,
        /Field 'usage.total_tokens' not found in result/
      )
    end

    it "validates that fields are strings or symbols" do
      expect { selector.add_field(123) }.to raise_error(
        RAAF::Eval::DSL::InvalidPathError,
        /must be a string or symbol/
      )
    end

    it "validates paths don't have consecutive dots" do
      expect { 
        selector.add_field("usage..tokens") 
      }.to raise_error(
        RAAF::Eval::DSL::InvalidPathError,
        /Invalid path format/
      )
    end

    it "validates paths don't start or end with dots" do
      expect { 
        selector.add_field(".usage.tokens") 
      }.to raise_error(
        RAAF::Eval::DSL::InvalidPathError,
        /Invalid path format/
      )
      
      expect { 
        selector.add_field("usage.tokens.") 
      }.to raise_error(
        RAAF::Eval::DSL::InvalidPathError,
        /Invalid path format/
      )
    end

    it "creates FieldContext objects successfully for valid fields" do
      result = { 
        output: "text", 
        usage: { total_tokens: 100 } 
      }
      
      selector.add_field("output")
      selector.add_field("usage.total_tokens", as: :tokens)
      
      # Should create FieldContext without errors
      context1 = selector.create_field_context("output", result)
      expect(context1).to be_a(RAAF::Eval::DSL::FieldContext)
      expect(context1.value).to eq("text")
      
      # Should work with alias
      context2 = selector.create_field_context(:tokens, result)
      expect(context2).to be_a(RAAF::Eval::DSL::FieldContext)
      expect(context2.value).to eq(100)
    end
  end
end
