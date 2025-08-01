# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::DataAccessHelper do
  # Test class that includes the module
  class TestDataAccess
    include RAAF::DSL::DataAccessHelper
  end

  let(:helper) { TestDataAccess.new }

  describe "#safe_get" do
    context "with string keys" do
      let(:hash) { { "name" => "John", "age" => 30 } }

      it "retrieves value using string key" do
        expect(helper.safe_get(hash, "name")).to eq("John")
      end

      it "retrieves value using symbol key" do
        expect(helper.safe_get(hash, :name)).to eq("John")
      end

      it "returns default for missing key" do
        expect(helper.safe_get(hash, :missing, "default")).to eq("default")
      end
    end

    context "with symbol keys" do
      let(:hash) { { name: "Jane", age: 25 } }

      it "retrieves value using symbol key" do
        expect(helper.safe_get(hash, :name)).to eq("Jane")
      end

      it "retrieves value using string key" do
        expect(helper.safe_get(hash, "name")).to eq("Jane")
      end
    end

    context "with mixed keys" do
      let(:hash) { { "name" => "John", age: 30 } }

      it "retrieves both types of keys" do
        expect(helper.safe_get(hash, :name)).to eq("John")
        expect(helper.safe_get(hash, "age")).to eq(30)
      end
    end

    context "with edge cases" do
      it "returns default for nil hash" do
        expect(helper.safe_get(nil, :key, "default")).to eq("default")
      end

      it "returns default for non-hash" do
        expect(helper.safe_get("not a hash", :key, "default")).to eq("default")
      end

      it "returns nil as default when not specified" do
        expect(helper.safe_get({}, :missing)).to be_nil
      end

      it "handles false and nil values correctly" do
        hash = { active: false, deleted: nil }
        expect(helper.safe_get(hash, :active)).to eq(false)
        expect(helper.safe_get(hash, :deleted)).to be_nil
      end
    end
  end

  describe "#safe_dig" do
    context "with simple nested hash" do
      let(:hash) { { "user" => { name: "John" } } }

      it "digs through mixed key types" do
        expect(helper.safe_dig(hash, :user, :name)).to eq("John")
        expect(helper.safe_dig(hash, "user", "name")).to eq("John")
      end
    end

    context "with deeply nested hash" do
      let(:hash) do
        {
          "data" => {
            company: {
              "address" => {
                city: "NYC"
              }
            }
          }
        }
      end

      it "digs through multiple levels" do
        expect(helper.safe_dig(hash, :data, :company, :address, :city)).to eq("NYC")
        expect(helper.safe_dig(hash, "data", "company", "address", "city")).to eq("NYC")
      end
    end

    context "with missing paths" do
      let(:hash) { { user: { name: "John" } } }

      it "returns nil for missing intermediate keys" do
        expect(helper.safe_dig(hash, :user, :address, :city)).to be_nil
      end

      it "returns nil for missing root key" do
        expect(helper.safe_dig(hash, :missing, :path)).to be_nil
      end
    end

    context "with edge cases" do
      it "returns nil for nil hash" do
        expect(helper.safe_dig(nil, :key)).to be_nil
      end

      it "returns nil for empty path" do
        expect(helper.safe_dig({ key: "value" })).to be_nil
      end

      it "returns the hash for no keys" do
        hash = { key: "value" }
        expect(helper.safe_dig(hash)).to be_nil
      end

      it "handles non-hash intermediate values" do
        hash = { data: "string value" }
        expect(helper.safe_dig(hash, :data, :nested)).to be_nil
      end
    end
  end

  describe "#safe_key?" do
    let(:hash) { { "name" => "John", age: 30 } }

    it "checks for string key presence" do
      expect(helper.safe_key?(hash, "name")).to be true
      expect(helper.safe_key?(hash, :name)).to be true
    end

    it "checks for symbol key presence" do
      expect(helper.safe_key?(hash, :age)).to be true
      expect(helper.safe_key?(hash, "age")).to be true
    end

    it "returns false for missing keys" do
      expect(helper.safe_key?(hash, :missing)).to be false
    end

    it "returns false for nil hash" do
      expect(helper.safe_key?(nil, :key)).to be false
    end

    it "returns false for non-hash" do
      expect(helper.safe_key?("not a hash", :key)).to be false
    end
  end

  describe "#safe_fetch_all" do
    let(:hash) { { "name" => "John", age: 30, "role" => "admin" } }

    it "fetches multiple keys" do
      result = helper.safe_fetch_all(hash, [:name, :age, :role])
      
      expect(result).to eq(
        name: "John",
        age: 30,
        role: "admin"
      )
    end

    it "uses defaults for missing keys" do
      result = helper.safe_fetch_all(
        hash, 
        [:name, :missing], 
        missing: "default"
      )
      
      expect(result).to eq(
        name: "John",
        missing: "default"
      )
    end

    it "returns empty hash for nil input" do
      expect(helper.safe_fetch_all(nil, [:key])).to eq({})
    end

    it "returns nil for missing keys without defaults" do
      result = helper.safe_fetch_all(hash, [:name, :missing])
      
      expect(result[:name]).to eq("John")
      expect(result[:missing]).to be_nil
    end
  end

  describe "#symbolize_keys_deep" do
    it "converts all keys to symbols" do
      input = {
        "name" => "John",
        "address" => {
          "city" => "NYC",
          "coords" => {
            "lat" => 40.7,
            "lng" => -74.0
          }
        }
      }
      
      result = helper.symbolize_keys_deep(input)
      
      expect(result).to eq(
        name: "John",
        address: {
          city: "NYC",
          coords: {
            lat: 40.7,
            lng: -74.0
          }
        }
      )
    end

    it "handles arrays of hashes" do
      input = {
        "users" => [
          { "name" => "John", "age" => 30 },
          { "name" => "Jane", "age" => 25 }
        ]
      }
      
      result = helper.symbolize_keys_deep(input)
      
      expect(result[:users]).to eq([
        { name: "John", age: 30 },
        { name: "Jane", age: 25 }
      ])
    end

    it "preserves non-hash values" do
      input = { "string" => "value", "number" => 42, "boolean" => true }
      result = helper.symbolize_keys_deep(input)
      
      expect(result).to eq(string: "value", number: 42, boolean: true)
    end
  end

  describe "#stringify_keys_deep" do
    it "converts all keys to strings" do
      input = {
        name: "John",
        address: {
          city: "NYC",
          coords: {
            lat: 40.7,
            lng: -74.0
          }
        }
      }
      
      result = helper.stringify_keys_deep(input)
      
      expect(result).to eq(
        "name" => "John",
        "address" => {
          "city" => "NYC",
          "coords" => {
            "lat" => 40.7,
            "lng" => -74.0
          }
        }
      )
    end
  end

  describe "#safe_merge" do
    let(:base) { { "name" => "John", age: 30 } }
    let(:other) { { name: "Jane", "role" => "admin" } }

    it "merges hashes preserving key types" do
      result = helper.safe_merge(base, other)
      
      expect(result["name"]).to eq("Jane")  # String key preserved
      expect(result[:age]).to eq(30)        # Symbol key preserved
      expect(result["role"]).to eq("admin") # New string key added
    end

    it "symbolizes all keys when requested" do
      result = helper.safe_merge(base, other, symbolize: true)
      
      expect(result).to eq(
        name: "Jane",
        age: 30,
        role: "admin"
      )
    end

    it "handles nil other hash" do
      expect(helper.safe_merge(base, nil)).to eq(base)
    end

    it "updates existing keys with same type" do
      base = { "name" => "John", "age" => 30 }
      other = { "name" => "Jane", "age" => 25 }
      
      result = helper.safe_merge(base, other)
      
      expect(result).to eq("name" => "Jane", "age" => 25)
    end
  end

  describe "#safe_slice" do
    let(:hash) { { "name" => "John", age: 30, "role" => "admin", city: "NYC" } }

    it "extracts requested keys preserving types" do
      result = helper.safe_slice(hash, [:name, :age])
      
      expect(result).to eq("name" => "John", age: 30)
    end

    it "symbolizes keys when requested" do
      result = helper.safe_slice(hash, [:name, :age, :role], symbolize: true)
      
      expect(result).to eq(name: "John", age: 30, role: "admin")
    end

    it "ignores missing keys" do
      result = helper.safe_slice(hash, [:name, :missing])
      
      expect(result).to eq("name" => "John")
    end

    it "returns empty hash for nil input" do
      expect(helper.safe_slice(nil, [:key])).to eq({})
    end
  end

  describe "#safe_transform_keys" do
    let(:hash) { { "company_name" => "Acme", "company_size" => 100, "founded" => 2000 } }
    let(:mapping) do
      {
        company_name: :name,
        company_size: :employee_count,
        company_location: :headquarters  # Missing in hash
      }
    end

    it "transforms keys according to mapping" do
      result = helper.safe_transform_keys(hash, mapping)
      
      expect(result).to eq(
        name: "Acme",
        employee_count: 100
      )
    end

    it "handles mixed key types in source" do
      mixed_hash = { "company_name" => "Acme", company_size: 100 }
      
      result = helper.safe_transform_keys(mixed_hash, mapping)
      
      expect(result).to eq(
        name: "Acme",
        employee_count: 100
      )
    end

    it "skips nil values" do
      hash_with_nil = { "company_name" => nil, "company_size" => 100 }
      
      result = helper.safe_transform_keys(hash_with_nil, mapping)
      
      expect(result).to eq(employee_count: 100)
    end

    it "returns empty hash for nil input" do
      expect(helper.safe_transform_keys(nil, mapping)).to eq({})
    end
  end

  describe "module usage" do
    it "can be used as module methods" do
      expect(RAAF::DSL::DataAccessHelper.safe_get({ name: "John" }, :name)).to eq("John")
    end

    it "can be included in classes" do
      expect(helper).to respond_to(:safe_get)
      expect(helper).to respond_to(:safe_dig)
      expect(helper).to respond_to(:safe_key?)
    end
  end

  describe "real-world usage patterns" do
    it "handles API response with mixed keys" do
      api_response = {
        "data" => {
          "results" => [
            { "company_name" => "Acme", id: 123 },
            { company_name: "Corp", "id" => 456 }
          ],
          meta: {
            "total" => 2,
            page: 1
          }
        }
      }
      
      # Safe access to nested data
      results = helper.safe_dig(api_response, :data, :results)
      expect(results).to be_an(Array)
      expect(results.size).to eq(2)
      
      # Transform each result
      companies = results.map do |result|
        {
          name: helper.safe_get(result, :company_name),
          id: helper.safe_get(result, :id)
        }
      end
      
      expect(companies).to eq([
        { name: "Acme", id: 123 },
        { name: "Corp", id: 456 }
      ])
      
      # Access metadata
      total = helper.safe_dig(api_response, :data, :meta, :total)
      page = helper.safe_dig(api_response, :data, :meta, :page)
      
      expect(total).to eq(2)
      expect(page).to eq(1)
    end

    it "handles search results with inconsistent formats" do
      search_data = [
        {
          "query" => "market analysis",
          "results" => [
            { "title" => "Result 1", "url" => "http://example1.com" }
          ]
        },
        {
          query: "competitor research",
          results: [
            { title: "Result 2", url: "http://example2.com" }
          ]
        }
      ]
      
      # Process each search result safely
      processed = search_data.map do |search|
        {
          query: helper.safe_get(search, :query),
          results: helper.safe_get(search, :results, []).map do |result|
            {
              title: helper.safe_get(result, :title),
              url: helper.safe_get(result, :url)
            }
          end
        }
      end
      
      expect(processed).to eq([
        {
          query: "market analysis",
          results: [{ title: "Result 1", url: "http://example1.com" }]
        },
        {
          query: "competitor research",
          results: [{ title: "Result 2", url: "http://example2.com" }]
        }
      ])
    end
  end
end