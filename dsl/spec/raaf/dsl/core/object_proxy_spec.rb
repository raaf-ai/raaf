# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/dsl/core/object_proxy"
require_relative "../../../../lib/raaf/dsl/core/object_serializer"

RSpec.describe RAAF::DSL::ObjectProxy do
  # Test classes
  class TestProduct
    attr_accessor :id, :name, :price, :category
    attr_reader :created_at
    
    def initialize(id: 1, name: "Test Product", price: 99.99, category: nil)
      @id = id
      @name = name
      @price = price
      @category = category
      @created_at = Time.now
      @secret_key = "secret123"
    end
    
    def calculated_price
      price * 1.1
    end
    
    def formatted_name
      "Product: #{name}"
    end
    
    private
    
    def internal_method
      "internal"
    end
  end
  
  class TestCategory
    attr_accessor :id, :name, :products
    
    def initialize(id: 1, name: "Electronics")
      @id = id
      @name = name
      @products = []
    end
  end
  
  # Test struct for proxy
  ProxyProxyTestStruct = Struct.new(:name, :value)
  
  describe "#initialize" do
    it "creates a proxy for any object" do
      product = TestProduct.new
      proxy = described_class.new(product)
      
      expect(proxy).to be_a(described_class)
      expect(proxy.__target__).to eq(product)
    end
    
    it "accepts configuration options" do
      product = TestProduct.new
      proxy = described_class.new(product, only: [:id, :name], cache: false)
      
      expect(proxy.__options__).to eq(only: [:id, :name], cache: false)
    end
  end
  
  describe "attribute access" do
    let(:product) { TestProduct.new(id: 42, name: "Widget", price: 19.99) }
    let(:proxy) { described_class.new(product) }
    
    it "provides lazy access to attributes" do
      expect(proxy.id).to eq(42)
      expect(proxy.name).to eq("Widget")
      expect(proxy.price).to eq(19.99)
    end
    
    it "provides access to methods" do
      expect(proxy.calculated_price).to be_within(0.01).of(21.99)
      expect(proxy.formatted_name).to eq("Product: Widget")
    end
    
    it "tracks accessed attributes" do
      proxy.id
      proxy.name
      
      expect(proxy.__accessed__).to include(:id, :name)
      expect(proxy.__accessed__).not_to include(:price)
    end
    
    it "prevents access to private methods" do
      expect { proxy.internal_method }.to raise_error(NoMethodError)
    end
    
    it "prevents access to underscore-prefixed methods" do
      expect { proxy._secret_key }.to raise_error(NoMethodError)
    end
  end
  
  describe "caching" do
    let(:product) { TestProduct.new }
    
    context "with caching enabled (default)" do
      let(:proxy) { described_class.new(product) }
      
      it "caches simple attribute access" do
        expect(product).to receive(:name).once.and_return("Cached")
        
        expect(proxy.name).to eq("Cached")
        expect(proxy.name).to eq("Cached") # Should use cache
      end
      
      it "does not cache method calls with arguments" do
        allow(product).to receive(:some_method).and_return("result")
        
        expect(product).to receive(:some_method).twice
        proxy.some_method("arg")
        proxy.some_method("arg")
      end
    end
    
    context "with caching disabled" do
      let(:proxy) { described_class.new(product, cache: false) }
      
      it "does not cache attribute access" do
        expect(product).to receive(:name).twice.and_return("Not Cached")
        
        proxy.name
        proxy.name
      end
    end
  end
  
  describe "access control" do
    let(:product) { TestProduct.new }
    
    context "with :only option" do
      let(:proxy) { described_class.new(product, only: [:id, :name]) }
      
      it "allows whitelisted attributes" do
        expect(proxy.id).to eq(1)
        expect(proxy.name).to eq("Test Product")
      end
      
      it "denies non-whitelisted attributes" do
        expect { proxy.price }.to raise_error(NoMethodError, /not allowed/)
      end
    end
    
    context "with :except option" do
      let(:proxy) { described_class.new(product, except: [:price]) }
      
      it "allows non-blacklisted attributes" do
        expect(proxy.id).to eq(1)
        expect(proxy.name).to eq("Test Product")
      end
      
      it "denies blacklisted attributes" do
        expect { proxy.price }.to raise_error(NoMethodError, /not allowed/)
      end
    end
    
    context "with :methods option" do
      let(:proxy) { described_class.new(product, only: [:id], methods: [:calculated_price]) }
      
      it "allows specified methods even with restrictive :only" do
        expect(proxy.id).to eq(1)
        expect(proxy.calculated_price).to be_within(0.01).of(109.99)
      end
      
      it "still denies non-specified attributes" do
        expect { proxy.name }.to raise_error(NoMethodError)
      end
    end
  end
  
  describe "nested object proxying" do
    let(:category) { TestCategory.new }
    let(:product) { TestProduct.new(category: category) }
    
    context "with sufficient depth" do
      let(:proxy) { described_class.new(product, depth: 2) }
      
      it "wraps nested objects in proxies" do
        category_proxy = proxy.category
        expect(category_proxy).to be_a(described_class)
        expect(category_proxy.__target__).to eq(category)
      end
      
      it "allows access to nested object attributes" do
        expect(proxy.category.name).to eq("Electronics")
      end
    end
    
    context "with depth limit reached" do
      let(:proxy) { described_class.new(product, depth: 1) }
      
      it "returns raw objects when depth is exhausted" do
        # With depth 1, the product is wrapped but its associations aren't
        category_result = proxy.category
        expect(category_result).to eq(category)
        expect(category_result).not_to be_a(described_class)
      end
    end
  end
  
  describe "#to_serialized_hash" do
    let(:product) { TestProduct.new(id: 42, name: "Widget", price: 19.99) }
    let(:proxy) { described_class.new(product, only: [:id, :name]) }
    
    it "serializes the proxied object" do
      serialized = proxy.to_serialized_hash
      
      expect(serialized).to be_a(Hash)
      expect(serialized).to include("id" => 42, "name" => "Widget")
      expect(serialized).not_to include("price")
    end
    
    it "respects proxy options during serialization" do
      proxy_with_methods = described_class.new(product, 
        only: [:id], 
        methods: [:calculated_price]
      )
      
      serialized = proxy_with_methods.to_serialized_hash
      expect(serialized).to include("id" => 42)
      expect(serialized).to include("calculated_price")
      expect(serialized).not_to include("name")
    end
  end
  
  describe "#proxy?" do
    let(:product) { TestProduct.new }
    let(:proxy) { described_class.new(product) }
    
    it "returns true for proxy objects" do
      expect(proxy.proxy?).to be true
    end
    
    it "allows distinguishing proxies from regular objects" do
      expect(product.respond_to?(:proxy?)).to be false
      expect(proxy.respond_to?(:proxy?)).to be true
    end
  end
  
  describe "#class" do
    let(:product) { TestProduct.new }
    let(:proxy) { described_class.new(product) }
    
    it "returns the class of the proxied object" do
      expect(proxy.class).to eq(TestProduct)
    end
  end
  
  describe "#__getobj__" do
    let(:product) { TestProduct.new }
    let(:proxy) { described_class.new(product) }
    
    it "provides access to the raw target object" do
      expect(proxy.__getobj__).to eq(product)
      expect(proxy.__getobj__).to be_a(TestProduct)
    end
  end
  
  describe "#to_s" do
    let(:product) { TestProduct.new(name: "Custom Product") }
    let(:proxy) { described_class.new(product) }
    
    it "delegates to target's to_s if available" do
      allow(product).to receive(:to_s).and_return("Custom String")
      expect(proxy.to_s).to eq("Custom String")
    end
  end
  
  describe "#inspect" do
    let(:product) { TestProduct.new }
    let(:proxy) { described_class.new(product) }
    
    it "provides debugging information" do
      proxy.name # Access something to track it
      
      inspect_output = proxy.inspect
      expect(inspect_output).to include("RAAF::DSL::ObjectProxy")
      expect(inspect_output).to include("TestProduct")
      expect(inspect_output).to include("@accessed=[:name]")
    end
  end
  
  describe "edge cases" do
    it "handles nil target gracefully" do
      proxy = described_class.new(nil)
      expect { proxy.any_method }.to raise_error(NoMethodError)
    end
    
    it "handles method_missing chains" do
      product = TestProduct.new
      proxy = described_class.new(product)
      
      # This should raise NoMethodError with helpful message
      expect { proxy.non_existent_method }.to raise_error(NoMethodError, /TestProduct proxy/)
    end
    
    it "handles respond_to_missing? correctly" do
      product = TestProduct.new
      proxy = described_class.new(product, only: [:id, :name])
      
      expect(proxy.respond_to?(:id)).to be true
      expect(proxy.respond_to?(:name)).to be true
      expect(proxy.respond_to?(:price)).to be false
      expect(proxy.respond_to?(:internal_method)).to be false
    end
  end
  
  describe "with various object types" do
    it "works with structs" do
      struct = ProxyTestStruct.new("test", 42)
      proxy = described_class.new(struct)
      
      expect(proxy.name).to eq("test")
      expect(proxy.value).to eq(42)
    end
    
    it "works with OpenStruct" do
      require 'ostruct'
      ostruct = OpenStruct.new(name: "test", value: 42)
      proxy = described_class.new(ostruct)
      
      expect(proxy.name).to eq("test")
      expect(proxy.value).to eq(42)
    end
    
    it "works with plain hashes through delegation" do
      hash = { name: "test", value: 42 }
      proxy = described_class.new(hash)
      
      expect(proxy[:name]).to eq("test")
      expect(proxy[:value]).to eq(42)
    end
  end
  
  describe "performance characteristics" do
    let(:product) { TestProduct.new }
    
    it "has minimal overhead for attribute access" do
      proxy = described_class.new(product)
      
      # Warm up
      1000.times { proxy.name }
      
      # This is more of a smoke test to ensure it doesn't blow up
      # Real performance testing would be more sophisticated
      expect { 1000.times { proxy.name } }.to perform_under(0.1).sec
    end
  end
end