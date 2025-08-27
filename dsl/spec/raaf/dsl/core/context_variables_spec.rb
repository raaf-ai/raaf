# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::ContextVariables do
  describe "basic functionality" do
    it "initializes with empty variables by default" do
      context = described_class.new
      expect(context.size).to eq(0)
      expect(context.empty?).to be true
    end

    it "initializes with provided variables" do
      context = described_class.new(name: "John", age: 30)
      expect(context.size).to eq(2)
      expect(context[:name]).to eq("John")
      expect(context[:age]).to eq(30)
    end

    it "supports indifferent access at top level" do
      context = described_class.new(user_name: "John")
      
      expect(context[:user_name]).to eq("John")
      expect(context["user_name"]).to eq("John")
    end
  end

  describe "nested hash support with indifferent access" do
    let(:nested_data) do
      {
        user: { name: "John", profile: { age: 30, location: "NYC" } },
        preferences: { theme: "dark", notifications: { email: true, sms: false } }
      }
    end

    let(:context) { described_class.new(nested_data) }

    it "supports indifferent access for nested hashes" do
      user = context[:user]
      expect(user[:name]).to eq("John")
      expect(user["name"]).to eq("John")
    end

    it "supports indifferent access for deeply nested hashes" do
      profile = context[:user][:profile]
      expect(profile[:age]).to eq(30)
      expect(profile["age"]).to eq(30)
      expect(profile[:location]).to eq("NYC")
      expect(profile["location"]).to eq("NYC")
    end

    it "supports mixed key access patterns" do
      # Mix of symbol and string access at different levels
      expect(context["user"]["profile"]["age"]).to eq(30)
      expect(context[:user][:profile][:age]).to eq(30)
      expect(context["user"][:profile]["age"]).to eq(30)
      expect(context[:user]["profile"][:age]).to eq(30)
    end

    it "supports indifferent access in complex nested structures" do
      prefs = context[:preferences]
      notifications = prefs[:notifications]
      
      expect(notifications[:email]).to be true
      expect(notifications["email"]).to be true
      expect(notifications[:sms]).to be false
      expect(notifications["sms"]).to be false
    end
  end

  describe "array handling with nested hashes" do
    let(:array_data) do
      {
        users: [
          { name: "John", details: { age: 30, city: "NYC" } },
          { name: "Jane", details: { age: 25, city: "LA" } }
        ],
        items: [
          { id: 1, metadata: { type: "document", tags: ["important", "draft"] } },
          { id: 2, metadata: { type: "image", tags: ["photo", "vacation"] } }
        ]
      }
    end

    let(:context) { described_class.new(array_data) }

    it "supports indifferent access for hashes within arrays" do
      first_user = context[:users].first
      expect(first_user[:name]).to eq("John")
      expect(first_user["name"]).to eq("John")
    end

    it "supports indifferent access for deeply nested hashes in arrays" do
      first_user_details = context[:users].first[:details]
      expect(first_user_details[:age]).to eq(30)
      expect(first_user_details["age"]).to eq(30)
      expect(first_user_details[:city]).to eq("NYC")
      expect(first_user_details["city"]).to eq("NYC")
    end

    it "handles complex nested arrays with mixed access" do
      first_item = context["items"][0]
      metadata = first_item["metadata"]
      
      expect(metadata["type"]).to eq("document")
      expect(metadata[:type]).to eq("document")
      expect(metadata["tags"]).to eq(["important", "draft"])
      expect(metadata[:tags]).to eq(["important", "draft"])
    end
  end

  describe "update method with nested structures" do
    let(:context) { described_class.new(existing: "data") }

    it "applies deep indifferent access to updated nested hashes" do
      updated = context.update(
        user: { name: "John", profile: { age: 30 } }
      )

      user = updated[:user]
      expect(user[:name]).to eq("John")
      expect(user["name"]).to eq("John")
      
      profile = user[:profile]
      expect(profile[:age]).to eq(30)
      expect(profile["age"]).to eq(30)
    end

    it "applies deep indifferent access to arrays with hashes" do
      updated = context.update(
        items: [
          { id: 1, data: { value: "test" } },
          { id: 2, data: { value: "example" } }
        ]
      )

      first_item = updated[:items].first
      expect(first_item[:id]).to eq(1)
      expect(first_item["id"]).to eq(1)
      
      first_data = first_item[:data]
      expect(first_data[:value]).to eq("test")
      expect(first_data["value"]).to eq("test")
    end
  end

  describe "set method with nested structures" do
    let(:context) { described_class.new }

    it "applies deep indifferent access to set nested hashes" do
      updated = context.set(:user, { profile: { settings: { theme: "dark" } } })
      
      settings = updated[:user][:profile][:settings]
      expect(settings[:theme]).to eq("dark")
      expect(settings["theme"]).to eq("dark")
    end
  end

  describe "get_nested method" do
    let(:nested_data) do
      {
        level1: {
          level2: {
            level3: { value: "deep_value" }
          }
        }
      }
    end
    
    let(:context) { described_class.new(nested_data) }

    it "retrieves deeply nested values using mixed key types" do
      expect(context.get_nested([:level1, :level2, :level3, :value])).to eq("deep_value")
      expect(context.get_nested(["level1", "level2", "level3", "value"])).to eq("deep_value")
      expect(context.get_nested([:level1, "level2", :level3, "value"])).to eq("deep_value")
    end

    it "returns default for non-existent nested paths" do
      expect(context.get_nested([:level1, :missing, :path], "default")).to eq("default")
    end
  end

  describe "edge cases and compatibility" do
    it "handles empty hashes and arrays" do
      context = described_class.new(
        empty_hash: {},
        empty_array: [],
        mixed: { empty: {}, arr: [] }
      )

      expect(context[:empty_hash]).to eq({})
      expect(context["empty_hash"]).to eq({})
      expect(context[:empty_array]).to eq([])
      expect(context["empty_array"]).to eq([])
    end

    it "preserves non-hash, non-array values" do
      context = described_class.new(
        string: "test",
        number: 42,
        boolean: true,
        nil_value: nil
      )

      expect(context[:string]).to eq("test")
      expect(context["string"]).to eq("test")
      expect(context[:number]).to eq(42)
      expect(context["number"]).to eq(42)
      expect(context[:boolean]).to be true
      expect(context["boolean"]).to be true
      expect(context[:nil_value]).to be_nil
      expect(context["nil_value"]).to be_nil
    end

    it "handles mixed data types in arrays" do
      context = described_class.new(
        mixed_array: [
          "string",
          42,
          { key: "value" },
          [{ nested: "array_hash" }]
        ]
      )

      array = context[:mixed_array]
      expect(array[0]).to eq("string")
      expect(array[1]).to eq(42)
      expect(array[2][:key]).to eq("value")
      expect(array[2]["key"]).to eq("value")
      expect(array[3].first[:nested]).to eq("array_hash")
      expect(array[3].first["nested"]).to eq("array_hash")
    end
  end
end
