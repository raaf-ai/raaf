# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/dsl/context/smart_builder"

RSpec.describe RAAF::DSL::Context::SmartBuilder do
  # Test objects
  class TestProduct
    attr_accessor :id, :name, :price, :category
    
    def initialize(id: 1, name: "Product", price: 99.99, category: nil)
      @id = id
      @name = name
      @price = price
      @category = category
    end
    
    def calculated_price
      price * 1.1
    end
    
    def sensitive_data
      "secret"
    end
  end
  
  class TestCompany
    attr_accessor :id, :name, :products
    
    def initialize(id: 1, name: "Company")
      @id = id
      @name = name
      @products = []
    end
    
    def market_segment
      "Enterprise"
    end
  end
  
  let(:product) { TestProduct.new(id: 42, name: "Widget", price: 19.99) }
  let(:company) { TestCompany.new(id: 1, name: "Acme Corp") }
  
  describe ".build" do
    it "creates a context using declarative syntax" do
      context = described_class.build do
        proxy :product, product, only: [:id, :name]
        proxy :company, company
        set :analysis_depth, "detailed"
      end
      
      expect(context).to be_a(RAAF::DSL::ContextVariables)
      expect(context.get(:product).name).to eq("Widget")
      expect(context.get(:company).name).to eq("Acme Corp")
      expect(context.get(:analysis_depth)).to eq("detailed")
    end
  end
  
  describe "#proxy" do
    it "proxies objects with default configuration" do
      builder = described_class.new
      builder.proxy(:product, product)
      context = builder.finalize
      
      proxied_product = context.get(:product)
      expect(proxied_product.proxy?).to be true
      expect(proxied_product.name).to eq("Widget")
    end
    
    it "applies access control with :only option" do
      builder = described_class.new
      builder.proxy(:product, product, only: [:id, :name])
      context = builder.finalize
      
      proxied_product = context.get(:product)
      expect(proxied_product.id).to eq(42)
      expect(proxied_product.name).to eq("Widget")
      expect { proxied_product.price }.to raise_error(NoMethodError, /not allowed/)
    end
    
    it "applies access control with :except option" do
      builder = described_class.new
      builder.proxy(:product, product, except: [:sensitive_data, :price])
      context = builder.finalize
      
      proxied_product = context.get(:product)
      expect(proxied_product.name).to eq("Widget")
      expect { proxied_product.price }.to raise_error(NoMethodError, /not allowed/)
      expect { proxied_product.sensitive_data }.to raise_error(NoMethodError, /not allowed/)
    end
    
    it "includes methods when specified" do
      builder = described_class.new
      builder.proxy(:product, product, only: [:id], with_methods: [:calculated_price])
      context = builder.finalize
      
      proxied_product = context.get(:product)
      expect(proxied_product.calculated_price).to be_within(0.01).of(21.99)
    end
    
    it "handles nil objects gracefully" do
      builder = described_class.new
      builder.proxy(:missing_product, nil)
      context = builder.finalize
      
      expect(context.get(:missing_product)).to be_nil
    end
  end
  
  describe "#proxy_all" do
    it "proxies hash of objects" do
      builder = described_class.new
      builder.proxy_all({ product: product, company: company }, only: [:id, :name])
      context = builder.finalize
      
      expect(context.get(:product).name).to eq("Widget")
      expect(context.get(:company).name).to eq("Acme Corp")
      expect { context.get(:product).price }.to raise_error(NoMethodError)
    end
    
    it "proxies array of objects with custom key" do
      products = [product, TestProduct.new(id: 2, name: "Gadget")]
      
      builder = described_class.new
      builder.proxy_all(products, as: :products, only: [:id, :name])
      context = builder.finalize
      
      proxied_products = context.get(:products)
      expect(proxied_products).to be_an(Array)
      expect(proxied_products.length).to eq(2)
    end
    
    it "proxies array of objects with indexed keys" do
      products = [product, TestProduct.new(id: 2, name: "Gadget")]
      
      builder = described_class.new
      builder.proxy_all(products, only: [:name])
      context = builder.finalize
      
      expect(context.get(:item_0).name).to eq("Widget")
      expect(context.get(:item_1).name).to eq("Gadget")
    end
  end
  
  describe "#proxy_if" do
    it "proxies when condition is true" do
      builder = described_class.new
      builder.proxy_if(true, :product, product)
      context = builder.finalize
      
      expect(context.get(:product).name).to eq("Widget")
    end
    
    it "skips proxy when condition is false" do
      builder = described_class.new
      builder.proxy_if(false, :product, product)
      context = builder.finalize
      
      expect(context.get(:product)).to be_nil
    end
    
    it "evaluates proc conditions" do
      should_include = -> { product.price > 10 }
      
      builder = described_class.new
      builder.proxy_if(should_include, :product, product)
      context = builder.finalize
      
      expect(context.get(:product).name).to eq("Widget")
    end
  end
  
  describe "#set and #set_all" do
    it "sets simple values" do
      builder = described_class.new
      builder.set(:key, "value")
      builder.set_all({ key2: "value2", key3: 42 })
      context = builder.finalize
      
      expect(context.get(:key)).to eq("value")
      expect(context.get(:key2)).to eq("value2")
      expect(context.get(:key3)).to eq(42)
    end
  end
  
  describe "#set_if" do
    it "sets value when condition is true" do
      builder = described_class.new
      builder.set_if(true, :conditional_key, "conditional_value")
      context = builder.finalize
      
      expect(context.get(:conditional_key)).to eq("conditional_value")
    end
    
    it "skips setting when condition is false" do
      builder = described_class.new
      builder.set_if(false, :conditional_key, "conditional_value")
      context = builder.finalize
      
      expect(context.get(:conditional_key)).to be_nil
    end
  end
  
  describe "#requires" do
    it "validates required keys are present" do
      builder = described_class.new
      builder.proxy(:product, product)
      builder.requires(:product, :company)
      
      expect {
        builder.finalize
      }.to raise_error(ArgumentError, /Required context keys missing: company/)
    end
    
    it "passes validation when all required keys present" do
      builder = described_class.new
      builder.proxy(:product, product)
      builder.proxy(:company, company)
      builder.requires(:product, :company)
      
      expect { builder.finalize }.not_to raise_error
    end
  end
  
  describe "#validates" do
    it "validates type requirements" do
      builder = described_class.new
      builder.set(:score, "not a number")
      builder.validates(:score, type: Integer)
      
      expect {
        builder.finalize
      }.to raise_error(ArgumentError, /must be Integer but was String/)
    end
    
    it "validates range requirements" do
      builder = described_class.new
      builder.set(:score, 150)
      builder.validates(:score, range: 0..100)
      
      expect {
        builder.finalize
      }.to raise_error(ArgumentError, /must be between 0 and 100/)
    end
    
    it "validates presence requirements" do
      builder = described_class.new
      builder.set(:data, nil)
      builder.validates(:data, presence: true)
      
      expect {
        builder.finalize
      }.to raise_error(ArgumentError, /is required but missing/)
    end
    
    it "validates object attribute presence" do
      incomplete_product = TestProduct.new(name: nil)
      
      builder = described_class.new
      builder.proxy(:product, incomplete_product)
      builder.validates(:product, presence: [:name, :price])
      
      expect {
        builder.finalize
      }.to raise_error(ArgumentError, /missing required attributes: name/)
    end
    
    it "validates with custom proc" do
      builder = described_class.new
      builder.set(:email, "invalid-email")
      builder.validates(:email, validate: ->(v) { v.include?("@") })
      
      expect {
        builder.finalize
      }.to raise_error(ArgumentError, /failed custom validation/)
    end
  end
  
  describe "#debug_mode" do
    it "enables debug logging" do
      expect(RAAF::Logging).to receive(:debug).with(
        "[SmartBuilder] Context built successfully",
        hash_including(category: :context)
      )
      
      builder = described_class.new
      builder.debug_mode(true)
      builder.proxy(:product, product)
      builder.finalize
    end
  end
  
  describe "#merge" do
    it "merges another context" do
      existing_context = RAAF::DSL::ContextVariables.new(existing_key: "existing_value")
      
      builder = described_class.new
      builder.proxy(:product, product)
      builder.merge(existing_context)
      context = builder.finalize
      
      expect(context.get(:product).name).to eq("Widget")
      expect(context.get(:existing_key)).to eq("existing_value")
    end
    
    it "merges hash" do
      builder = described_class.new
      builder.proxy(:product, product)
      builder.merge(existing_key: "existing_value")
      context = builder.finalize
      
      expect(context.get(:product).name).to eq("Widget")
      expect(context.get(:existing_key)).to eq("existing_value")
    end
  end
  
  describe "#with_object_context" do
    it "provides object context for implicit resolution" do
      object_context = { product: product, company: company }
      
      builder = described_class.new
      builder.with_object_context(object_context) do |b|
        b.proxy(:product)  # Should resolve from object_context
        b.proxy(:company)
      end
      context = builder.finalize
      
      expect(context.get(:product).name).to eq("Widget")
      expect(context.get(:company).name).to eq("Acme Corp")
    end
  end
  
  describe "#snapshot" do
    it "provides builder state information" do
      builder = described_class.new
      builder.proxy(:product, product)
      builder.requires(:product)
      builder.validates(:product, type: TestProduct)
      
      snapshot = builder.snapshot
      
      expect(snapshot[:proxy_configs]).to have_key(:product)
      expect(snapshot[:required_keys]).to include(:product)
      expect(snapshot[:validation_rules]).to have_key(:product)
    end
  end
  
  describe "error handling" do
    it "handles proxy creation errors gracefully" do
      # This would be in a real scenario where ObjectProxy isn't available
      builder = described_class.new
      allow(builder).to receive(:require_relative).and_raise(LoadError)
      
      expect {
        builder.proxy(:product, product)
        builder.finalize
      }.to raise_error(LoadError)
    end
  end
  
  describe "integration with RAAF::DSL::Context" do
    it "provides smart_build class method" do
      context = RAAF::DSL::Context.smart_build do
        proxy :product, product, only: [:name]
        set :version, "1.0"
      end
      
      expect(context.get(:product).name).to eq("Widget")
      expect(context.get(:version)).to eq("1.0")
    end
    
    it "provides traditional build method" do
      context = RAAF::DSL::Context.build({ initial: "data" })
      
      expect(context).to be_a(RAAF::DSL::ContextBuilder)
    end
  end
  
  describe "complex scenarios" do
    it "handles complex context with multiple features" do
      products = [product, TestProduct.new(id: 2, name: "Gadget")]
      
      context = described_class.build(debug: true) do
        # Proxy single objects
        proxy :company, company, only: [:id, :name], with_methods: [:market_segment]
        
        # Conditional proxying
        proxy_if(company.name.include?("Acme"), :primary_product, product)
        
        # Proxy collections
        proxy_all(products, as: :all_products, only: [:id, :name])
        
        # Set simple values
        set :analysis_depth, "comprehensive"
        set_if(products.length > 1, :has_multiple_products, true)
        
        # Validation
        requires :company, :analysis_depth
        validates :company, presence: [:name]
        validates :analysis_depth, type: String
      end
      
      expect(context.get(:company).name).to eq("Acme Corp")
      expect(context.get(:company).market_segment).to eq("Enterprise")
      expect(context.get(:primary_product).name).to eq("Widget")
      expect(context.get(:all_products)).to be_an(Array)
      expect(context.get(:analysis_depth)).to eq("comprehensive")
      expect(context.get(:has_multiple_products)).to be true
    end
  end
end