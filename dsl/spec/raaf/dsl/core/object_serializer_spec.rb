# frozen_string_literal: true

require "spec_helper"
require "benchmark"
require_relative "../../../../lib/raaf/dsl/core/object_serializer"

RSpec.describe RAAF::DSL::ObjectSerializer do
  # Test classes
  class TestProduct
    attr_accessor :id, :name, :price, :category, :tags
    attr_reader :created_at
    
    def initialize(id: 1, name: "Test Product", price: 99.99, category: nil, tags: [])
      @id = id
      @name = name
      @price = price
      @category = category
      @tags = tags
      @created_at = Time.now
      @internal_state = "secret"
    end
    
    def calculated_price
      price * 1.1
    end
    
    def to_s
      "Product: #{name}"
    end
    
    private
    
    def internal_method
      "internal"
    end
  end
  
  class TestCategory
    attr_accessor :id, :name, :parent, :products
    
    def initialize(id: 1, name: "Electronics", parent: nil)
      @id = id
      @name = name
      @parent = parent
      @products = []
    end
  end
  
  # Test struct
  TestStruct = Struct.new(:name, :value, :nested) do
    def custom_method
      "#{name}: #{value}"
    end
  end
  
  # Mock ActiveRecord-like class
  class MockActiveRecord
    attr_accessor :id, :name, :created_at, :updated_at
    
    def initialize(attrs = {})
      @id = attrs[:id] || 1
      @name = attrs[:name] || "Record"
      @created_at = attrs[:created_at] || Time.now
      @updated_at = attrs[:updated_at] || Time.now
      @persisted = true
    end
    
    def persisted?
      @persisted
    end
    
    def attributes
      {
        "id" => id,
        "name" => name,
        "created_at" => created_at,
        "updated_at" => updated_at
      }
    end
    
    def self.name
      "MockActiveRecord"
    end
    
    # Make it respond to ActiveRecord-like methods
    def self.respond_to?(method)
      method == :connection || super
    end
  end
  
  describe "#serialize" do
    context "with plain objects (PORO)" do
      it "serializes basic attributes" do
        product = TestProduct.new(id: 42, name: "Widget", price: 19.99)
        
        result = described_class.serialize(product)
        
        expect(result).to be_a(Hash)
        expect(result).to include(
          "id" => 42,
          "name" => "Widget",
          "price" => 19.99,
          "created_at" => be_a(Time)
        )
      end
      
      it "excludes private instance variables" do
        product = TestProduct.new
        result = described_class.serialize(product)
        
        expect(result).not_to have_key("internal_state")
        expect(result).not_to have_key("@internal_state")
      end
      
      it "respects :only option" do
        product = TestProduct.new(id: 42, name: "Widget", price: 19.99)
        
        result = described_class.serialize(product, only: [:id, :name])
        
        expect(result.keys).to match_array(["id", "name"])
        expect(result).not_to have_key("price")
      end
      
      it "respects :except option" do
        product = TestProduct.new(id: 42, name: "Widget", price: 19.99)
        
        result = described_class.serialize(product, except: [:price, :created_at])
        
        expect(result).to have_key("id")
        expect(result).to have_key("name")
        expect(result).not_to have_key("price")
        expect(result).not_to have_key("created_at")
      end
      
      it "includes methods when specified" do
        product = TestProduct.new(price: 100)
        
        result = described_class.serialize(product, methods: [:calculated_price])
        
        expect(result).to have_key("calculated_price")
        expect(result["calculated_price"]).to eq(110.0)
      end
      
      it "does not include private methods" do
        product = TestProduct.new
        
        result = described_class.serialize(product, methods: [:internal_method])
        
        expect(result).not_to have_key("internal_method")
      end
    end
    
    context "with Struct objects" do
      it "serializes struct attributes" do
        struct = TestStruct.new("test", 42, nil)
        
        result = described_class.serialize(struct)
        
        expect(result).to eq({
          "name" => "test",
          "value" => 42,
          "nested" => nil
        })
      end
      
      it "includes struct methods when specified" do
        struct = TestStruct.new("test", 42)
        
        result = described_class.serialize(struct, methods: [:custom_method])
        
        expect(result).to include("custom_method" => "test: 42")
      end
    end
    
    context "with OpenStruct objects" do
      it "serializes OpenStruct attributes" do
        require 'ostruct'
        ostruct = OpenStruct.new(name: "test", value: 42, active: true)
        
        result = described_class.serialize(ostruct)
        
        expect(result).to eq({
          "name" => "test",
          "value" => 42,
          "active" => true
        })
      end
    end
    
    context "with ActiveRecord-like objects" do
      it "uses attributes method when available" do
        record = MockActiveRecord.new(id: 123, name: "Test Record")
        
        result = described_class.serialize(record)
        
        expect(result).to include(
          "id" => 123,
          "name" => "Test Record",
          "created_at" => be_a(Time),
          "updated_at" => be_a(Time)
        )
      end
      
      it "respects :only option with ActiveRecord objects" do
        record = MockActiveRecord.new(id: 123, name: "Test Record")
        
        result = described_class.serialize(record, only: [:id, :name])
        
        expect(result.keys).to match_array(["id", "name"])
      end
    end
    
    context "with Hash objects" do
      it "returns a copy of the hash" do
        hash = { id: 1, name: "test", nested: { value: 42 } }
        
        result = described_class.serialize(hash)
        
        expect(result).to eq({
          "id" => 1,
          "name" => "test",
          "nested" => { "value" => 42 }
        })
        expect(result).not_to be(hash) # Different object
      end
    end
    
    context "with Array objects" do
      it "serializes array of objects" do
        products = [
          TestProduct.new(id: 1, name: "Product 1"),
          TestProduct.new(id: 2, name: "Product 2")
        ]
        
        result = described_class.serialize(products, only: [:id, :name])
        
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        expect(result[0]).to include("id" => 1, "name" => "Product 1")
        expect(result[1]).to include("id" => 2, "name" => "Product 2")
      end
      
      it "handles mixed arrays" do
        mixed = [1, "string", { key: "value" }, TestStruct.new("test", 42)]
        
        result = described_class.serialize(mixed)
        
        expect(result).to eq([
          1,
          "string",
          { "key" => "value" },
          { "name" => "test", "value" => 42, "nested" => nil }
        ])
      end
    end
    
    context "with nested objects" do
      it "serializes nested objects up to max depth" do
        category = TestCategory.new(id: 10, name: "Electronics")
        product = TestProduct.new(id: 1, name: "Laptop", category: category)
        category.products << product
        
        result = described_class.serialize(product, max_depth: 2)
        
        expect(result["category"]).to be_a(Hash)
        expect(result["category"]["name"]).to eq("Electronics")
        expect(result["category"]["products"]).to be_an(Array)
        expect(result["category"]["products"][0]).to be_a(String) # Depth exceeded
      end
      
      it "prevents infinite recursion with circular references" do
        parent = TestCategory.new(id: 1, name: "Parent")
        child = TestCategory.new(id: 2, name: "Child", parent: parent)
        parent.products << child
        
        result = described_class.serialize(parent)
        
        expect(result).to be_a(Hash)
        expect(result["products"]).to be_an(Array)
        # Should not crash or recurse infinitely
      end
      
      it "respects max_depth option" do
        cat1 = TestCategory.new(id: 1, name: "Level 1")
        cat2 = TestCategory.new(id: 2, name: "Level 2", parent: cat1)
        cat3 = TestCategory.new(id: 3, name: "Level 3", parent: cat2)
        
        result = described_class.serialize(cat3, max_depth: 2)
        
        expect(result["parent"]["name"]).to eq("Level 2")
        expect(result["parent"]["parent"]).to be_a(String) # Depth exceeded
      end
    end
    
    context "with primitive types" do
      it "returns primitives as-is" do
        expect(described_class.serialize(42)).to eq(42)
        expect(described_class.serialize("string")).to eq("string")
        expect(described_class.serialize(true)).to eq(true)
        expect(described_class.serialize(nil)).to eq(nil)
        expect(described_class.serialize(3.14)).to eq(3.14)
      end
      
      it "converts symbols to strings" do
        expect(described_class.serialize(:symbol)).to eq("symbol")
      end
      
      it "converts dates and times to ISO strings" do
        time = Time.new(2024, 1, 15, 10, 30, 0)
        date = Date.new(2024, 1, 15)
        
        expect(described_class.serialize(time)).to match(/2024-01-15T10:30:00/)
        expect(described_class.serialize(date)).to eq("2024-01-15")
      end
    end
    
    context "with custom serialization" do
      it "uses to_h if available" do
        obj = Object.new
        def obj.to_h
          { custom: "serialization" }
        end
        
        result = described_class.serialize(obj)
        
        expect(result).to eq({ "custom" => "serialization" })
      end
      
      it "uses as_json if available" do
        obj = Object.new
        def obj.as_json(options = {})
          { json: "format", options: options }
        end
        
        result = described_class.serialize(obj)
        
        expect(result).to include("json" => "format")
      end
      
      it "falls back to to_s for unknown objects" do
        obj = Object.new
        def obj.to_s
          "CustomObject"
        end
        
        result = described_class.serialize(obj)
        
        expect(result).to eq("CustomObject")
      end
    end
    
    context "with options propagation" do
      it "propagates options to nested serialization" do
        category = TestCategory.new(id: 10, name: "Electronics")
        product = TestProduct.new(id: 1, name: "Laptop", category: category, price: 999.99)
        
        result = described_class.serialize(product, only: [:id, :name, :category])
        
        expect(result.keys).to match_array(["id", "name", "category"])
        expect(result["category"]).to be_a(Hash)
        expect(result).not_to have_key("price")
      end
    end
    
    context "error handling" do
      it "handles objects that raise errors during serialization" do
        obj = Object.new
        def obj.name
          raise "Serialization error"
        end
        def obj.id
          1
        end
        
        result = described_class.serialize(obj)
        
        expect(result).to include("id" => 1)
        # Should handle the error gracefully and skip the problematic attribute
      end
      
      it "handles nil gracefully" do
        expect(described_class.serialize(nil)).to eq(nil)
      end
    end
  end
  
  describe "circular reference detection" do
    it "detects direct circular references" do
      cat1 = TestCategory.new(id: 1, name: "Category")
      cat1.parent = cat1 # Direct circular reference
      
      result = described_class.serialize(cat1)
      
      expect(result["parent"]).to match(/circular reference/)
    end
    
    it "detects indirect circular references" do
      cat1 = TestCategory.new(id: 1, name: "Cat1")
      cat2 = TestCategory.new(id: 2, name: "Cat2", parent: cat1)
      cat1.parent = cat2 # Indirect circular reference
      
      result = described_class.serialize(cat1)
      
      expect(result).to be_a(Hash)
      # Should complete without stack overflow
    end
  end
  
  describe "performance considerations" do
    it "handles large collections efficiently" do
      products = 100.times.map do |i|
        TestProduct.new(id: i, name: "Product #{i}", price: i * 10)
      end
      
      result = nil
      time = Benchmark.realtime do
        result = described_class.serialize(products, only: [:id, :name])
      end
      
      expect(result.size).to eq(100)
      expect(time).to be < 0.1 # Should be fast
    end
  end
end