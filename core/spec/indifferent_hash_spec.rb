# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::IndifferentHash do
  describe "#initialize" do
    it "creates an empty hash with no arguments" do
      hash = described_class.new
      expect(hash).to be_empty
    end

    it "creates hash from existing hash data" do
      data = { name: "John", age: 30 }
      hash = described_class.new(data)
      
      expect(hash[:name]).to eq("John")
      expect(hash["name"]).to eq("John")
      expect(hash[:age]).to eq(30)
      expect(hash["age"]).to eq(30)
    end

    it "handles mixed string and symbol keys" do
      data = { "name" => "John", :age => 30 }
      hash = described_class.new(data)
      
      expect(hash[:name]).to eq("John")
      expect(hash["name"]).to eq("John")
      expect(hash[:age]).to eq(30)
      expect(hash["age"]).to eq(30)
    end

    it "converts nested hashes recursively" do
      data = {
        user: {
          profile: { name: "John" },
          settings: { "theme" => "dark" }
        }
      }
      hash = described_class.new(data)
      
      expect(hash[:user][:profile][:name]).to eq("John")
      expect(hash["user"]["profile"]["name"]).to eq("John")
      expect(hash[:user][:settings][:theme]).to eq("dark")
      expect(hash["user"]["settings"]["theme"]).to eq("dark")
    end

    it "converts arrays with hashes recursively" do
      data = {
        items: [
          { id: 1, name: "First" },
          { "id" => 2, "name" => "Second" }
        ]
      }
      hash = described_class.new(data)
      
      expect(hash[:items][0][:id]).to eq(1)
      expect(hash["items"][0]["id"]).to eq(1)
      expect(hash[:items][1][:name]).to eq("Second")
      expect(hash["items"][1]["name"]).to eq("Second")
    end
  end

  describe "indifferent key access" do
    let(:hash) { described_class.new(name: "John", age: 30) }

    it "allows access with symbol keys" do
      expect(hash[:name]).to eq("John")
      expect(hash[:age]).to eq(30)
    end

    it "allows access with string keys" do
      expect(hash["name"]).to eq("John")
      expect(hash["age"]).to eq(30)
    end

    it "returns same value for symbol and string keys" do
      expect(hash[:name]).to eq(hash["name"])
      expect(hash[:age]).to eq(hash["age"])
    end
  end

  describe "#[]=" do
    let(:hash) { described_class.new }

    it "stores values with symbol keys" do
      hash[:name] = "John"
      expect(hash[:name]).to eq("John")
      expect(hash["name"]).to eq("John")
    end

    it "stores values with string keys" do
      hash["name"] = "John"
      expect(hash[:name]).to eq("John")
      expect(hash["name"]).to eq("John")
    end

    it "overwrites values regardless of key type" do
      hash[:name] = "John"
      hash["name"] = "Jane"
      expect(hash[:name]).to eq("Jane")
      expect(hash["name"]).to eq("Jane")
    end

    it "converts nested hashes to IndifferentHash" do
      hash[:user] = { profile: { name: "John" } }
      expect(hash[:user]).to be_a(described_class)
      expect(hash[:user][:profile]).to be_a(described_class)
      expect(hash["user"]["profile"]["name"]).to eq("John")
    end

    it "converts arrays with hashes recursively" do
      hash[:items] = [{ id: 1 }, { name: "Test" }]
      expect(hash[:items][0]).to be_a(described_class)
      expect(hash["items"][0]["id"]).to eq(1)
      expect(hash["items"][1]["name"]).to eq("Test")
    end
  end

  describe "#key?" do
    let(:hash) { described_class.new(name: "John") }

    it "returns true for symbol keys" do
      expect(hash.key?(:name)).to be true
    end

    it "returns true for string keys" do
      expect(hash.key?("name")).to be true
    end

    it "returns false for missing keys" do
      expect(hash.key?(:missing)).to be false
      expect(hash.key?("missing")).to be false
    end

    it "has aliases for key?" do
      expect(hash.has_key?(:name)).to be true
      expect(hash.include?("name")).to be true
      expect(hash.member?(:name)).to be true
    end
  end

  describe "#fetch" do
    let(:hash) { described_class.new(name: "John") }

    it "fetches values with symbol keys" do
      expect(hash.fetch(:name)).to eq("John")
    end

    it "fetches values with string keys" do
      expect(hash.fetch("name")).to eq("John")
    end

    it "returns default for missing keys" do
      expect(hash.fetch(:missing, "default")).to eq("default")
      expect(hash.fetch("missing", "default")).to eq("default")
    end

    it "supports block defaults" do
      result = hash.fetch(:missing) { "block default" }
      expect(result).to eq("block default")
    end

    it "raises KeyError for missing keys without default" do
      expect { hash.fetch(:missing) }.to raise_error(KeyError)
    end
  end

  describe "#delete" do
    let(:hash) { described_class.new(name: "John", age: 30) }

    it "deletes with symbol keys" do
      expect(hash.delete(:name)).to eq("John")
      expect(hash.key?(:name)).to be false
      expect(hash.key?("name")).to be false
    end

    it "deletes with string keys" do
      expect(hash.delete("age")).to eq(30)
      expect(hash.key?(:age)).to be false
      expect(hash.key?("age")).to be false
    end

    it "returns nil for missing keys" do
      expect(hash.delete(:missing)).to be nil
    end
  end

  describe "#update and #merge!" do
    let(:hash) { described_class.new(name: "John") }

    it "updates with symbol keys" do
      hash.update(age: 30, city: "NYC")
      expect(hash[:age]).to eq(30)
      expect(hash["city"]).to eq("NYC")
    end

    it "updates with string keys" do
      hash.update("age" => 30, "city" => "NYC")
      expect(hash[:age]).to eq(30)
      expect(hash["city"]).to eq("NYC")
    end

    it "overwrites existing values" do
      hash.update(name: "Jane")
      expect(hash[:name]).to eq("Jane")
    end

    it "converts values to IndifferentHash" do
      hash.update(user: { profile: { age: 25 } })
      expect(hash[:user][:profile][:age]).to eq(25)
      expect(hash["user"]["profile"]["age"]).to eq(25)
    end

    it "returns self for chaining" do
      result = hash.update(age: 30)
      expect(result).to be(hash)
    end
  end

  describe "#merge" do
    let(:hash) { described_class.new(name: "John") }

    it "returns new IndifferentHash" do
      result = hash.merge(age: 30)
      expect(result).to be_a(described_class)
      expect(result).not_to be(hash)
    end

    it "preserves original hash" do
      hash.merge(age: 30)
      expect(hash.key?(:age)).to be false
    end

    it "creates merged hash with indifferent access" do
      result = hash.merge(age: 30, user: { name: "Jane" })
      expect(result[:age]).to eq(30)
      expect(result["age"]).to eq(30)
      expect(result[:user][:name]).to eq("Jane")
      expect(result["user"]["name"]).to eq("Jane")
    end
  end

  describe "#dup" do
    let(:hash) { described_class.new(name: "John", user: { age: 30 }) }

    it "creates a new IndifferentHash" do
      duplicate = hash.dup
      expect(duplicate).to be_a(described_class)
      expect(duplicate).not_to be(hash)
    end

    it "duplicates all data" do
      duplicate = hash.dup
      expect(duplicate[:name]).to eq("John")
      expect(duplicate["name"]).to eq("John")
      expect(duplicate[:user][:age]).to eq(30)
      expect(duplicate["user"]["age"]).to eq(30)
    end

    it "creates independent copy" do
      duplicate = hash.dup
      duplicate[:name] = "Jane"
      expect(hash[:name]).to eq("John")
      expect(duplicate[:name]).to eq("Jane")
    end
  end

  describe "#to_hash" do
    let(:hash) do
      described_class.new(
        name: "John",
        user: described_class.new(age: 30),
        items: [described_class.new(id: 1)]
      )
    end

    it "converts to regular Hash with string keys" do
      result = hash.to_hash
      expect(result).to be_a(Hash)
      expect(result).not_to be_a(described_class)
    end

    it "converts nested IndifferentHash objects" do
      result = hash.to_hash
      expect(result["user"]).to be_a(Hash)
      expect(result["user"]).not_to be_a(described_class)
      expect(result["user"]["age"]).to eq(30)
    end

    it "converts IndifferentHash objects in arrays" do
      result = hash.to_hash
      expect(result["items"][0]).to be_a(Hash)
      expect(result["items"][0]).not_to be_a(described_class)
      expect(result["items"][0]["id"]).to eq(1)
    end
  end

  describe "#to_h" do
    it "returns self" do
      hash = described_class.new(name: "John")
      expect(hash.to_h).to be(hash)
    end
  end

  describe "#inspect" do
    it "shows class name and content" do
      hash = described_class.new(name: "John")
      result = hash.inspect
      expect(result).to include("RAAF::IndifferentHash")
      expect(result).to include(hash.object_id.to_s(16))
    end
  end

  describe "Hash compatibility" do
    let(:hash) { described_class.new(name: "John", age: 30) }

    it "supports each iteration" do
      keys = []
      values = []
      hash.each do |k, v|
        keys << k
        values << v
      end
      
      expect(keys).to contain_exactly("name", "age")
      expect(values).to contain_exactly("John", 30)
    end

    it "supports keys method" do
      expect(hash.keys).to contain_exactly("name", "age")
    end

    it "supports values method" do
      expect(hash.values).to contain_exactly("John", 30)
    end

    it "supports size and length" do
      expect(hash.size).to eq(2)
      expect(hash.length).to eq(2)
    end

    it "supports empty? check" do
      expect(hash.empty?).to be false
      expect(described_class.new.empty?).to be true
    end
  end

  describe "edge cases" do
    it "handles nil values" do
      hash = described_class.new(name: nil)
      expect(hash[:name]).to be nil
      expect(hash["name"]).to be nil
    end

    it "handles empty string keys" do
      hash = described_class.new("" => "empty")
      expect(hash[""]).to eq("empty")
      expect(hash[:""]).to eq("empty")
    end

    it "handles numeric-like string keys" do
      hash = described_class.new("123" => "numeric")
      expect(hash["123"]).to eq("numeric")
      expect(hash[:"123"]).to eq("numeric")
    end

    it "handles complex nested structures" do
      data = {
        users: [
          { 
            profile: { 
              settings: { 
                notifications: { 
                  email: true 
                } 
              } 
            } 
          }
        ]
      }
      
      hash = described_class.new(data)
      expect(hash[:users][0][:profile][:settings][:notifications][:email]).to be true
      expect(hash["users"][0]["profile"]["settings"]["notifications"]["email"]).to be true
    end
  end
end