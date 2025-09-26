# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::SpanCollectors::BaseCollector do
  describe "DSL methods" do
    describe ".span" do
      it "registers simple attributes" do
        test_class = Class.new(described_class) do
          span :name, :model
        end
        
        expect(test_class.instance_variable_get(:@span_attrs)).to eq([:name, :model])
      end
      
      it "registers custom attributes with lambdas" do
        test_class = Class.new(described_class) do
          span max_turns: -> { max_turns.to_s }
          span tools_count: -> { tools.length.to_s }
        end
        
        custom_attrs = test_class.instance_variable_get(:@span_custom)
        expect(custom_attrs).to have_key(:max_turns)
        expect(custom_attrs).to have_key(:tools_count)
        expect(custom_attrs[:max_turns]).to be_a(Proc)
        expect(custom_attrs[:tools_count]).to be_a(Proc)
      end
      
      it "combines simple and custom attributes" do
        test_class = Class.new(described_class) do
          span :name, :model
          span max_turns: -> { max_turns.to_s }
        end
        
        expect(test_class.instance_variable_get(:@span_attrs)).to eq([:name, :model])
        expect(test_class.instance_variable_get(:@span_custom)).to have_key(:max_turns)
      end
      
      it "accumulates multiple span declarations" do
        test_class = Class.new(described_class) do
          span :name
          span :model
          span max_turns: -> { max_turns.to_s }
          span tools_count: -> { tools.length.to_s }
        end
        
        expect(test_class.instance_variable_get(:@span_attrs)).to eq([:name, :model])
        custom_attrs = test_class.instance_variable_get(:@span_custom)
        expect(custom_attrs).to have_key(:max_turns)
        expect(custom_attrs).to have_key(:tools_count)
      end
    end
    
    describe ".result" do
      it "registers result custom attributes" do
        test_class = Class.new(described_class) do
          result execution_result: -> { _1.to_s[0..100] }
          result status: -> { _1.respond_to?(:status) ? _1.status : "unknown" }
        end
        
        result_custom = test_class.instance_variable_get(:@result_custom)
        expect(result_custom).to have_key(:execution_result)
        expect(result_custom).to have_key(:status)
        expect(result_custom[:execution_result]).to be_a(Proc)
        expect(result_custom[:status]).to be_a(Proc)
      end
      
      it "accumulates multiple result declarations" do
        test_class = Class.new(described_class) do
          result execution_result: -> { _1.to_s[0..100] }
        end
        
        test_class.class_eval do
          result status: -> { _1.respond_to?(:status) ? _1.status : "unknown" }
        end
        
        result_custom = test_class.instance_variable_get(:@result_custom)
        expect(result_custom).to have_key(:execution_result)
        expect(result_custom).to have_key(:status)
      end
    end
  end
  
  describe "#collect_attributes" do
    let(:component) do
      double("TestComponent", 
        class: double("ComponentClass", name: "TestAgent"),
        name: "MyAgent",
        model: "gpt-4o"
      )
    end
    
    it "returns base attributes" do
      collector = described_class.new
      attributes = collector.collect_attributes(component)
      
      expect(attributes).to include("component.type")
      expect(attributes).to include("component.name")
      expect(attributes["component.name"]).to eq("TestAgent")
    end
    
    it "includes custom attributes from DSL" do
      test_class = Class.new(described_class) do
        span :name, :model
      end
      
      collector = test_class.new
      attributes = collector.collect_attributes(component)
      
      # Base attributes
      expect(attributes).to include("component.type")
      expect(attributes).to include("component.name")
      
      # Custom attributes with component prefix (exclude base attributes)
      name_key = attributes.keys.find { |k| k.end_with?(".name") && !k.start_with?("component.") }
      model_key = attributes.keys.find { |k| k.end_with?(".model") }
      expect(name_key).not_to be_nil
      expect(model_key).not_to be_nil
      expect(attributes[name_key]).to eq("MyAgent")
      expect(attributes[model_key]).to eq("gpt-4o")
    end
    
    it "executes lambda-based custom attributes" do
      allow(component).to receive(:max_turns).and_return(5)
      allow(component).to receive(:tools).and_return(["tool1", "tool2"])
      
      test_class = Class.new(described_class) do
        span max_turns: ->(comp) { comp.max_turns.to_s }
        span tools_count: ->(comp) { comp.tools.length.to_s }
      end
      
      collector = test_class.new
      attributes = collector.collect_attributes(component)
      
      # Should have lambda-generated attributes
      max_turns_key = attributes.keys.find { |k| k.end_with?(".max_turns") }
      tools_count_key = attributes.keys.find { |k| k.end_with?(".tools_count") }
      
      expect(attributes[max_turns_key]).to eq("5")
      expect(attributes[tools_count_key]).to eq("2")
    end
  end
  
  describe "#collect_result" do
    let(:component) do
      double("TestComponent", 
        class: double("ComponentClass", name: "TestAgent")
      )
    end
    
    let(:result) do
      double("TestResult", class: double("ResultClass", name: "Hash"))
    end
    
    it "returns base result attributes" do
      collector = described_class.new
      attributes = collector.collect_result(component, result)
      
      expect(attributes).to include("result.type")
      expect(attributes).to include("result.success")
      expect(attributes["result.type"]).to eq("Hash")
      expect(attributes["result.success"]).to be true
    end
    
    it "handles nil result" do
      collector = described_class.new
      attributes = collector.collect_result(component, nil)
      
      expect(attributes["result.type"]).to eq("NilClass")
      expect(attributes["result.success"]).to be false
    end
    
    it "includes custom result attributes from DSL" do
      test_class = Class.new(described_class) do
        result execution_result: ->(result, component) { result.to_s[0..10] }
        result status: ->(result, component) { "success" }
      end
      
      allow(result).to receive(:to_s).and_return("test result data")
      
      collector = test_class.new
      attributes = collector.collect_result(component, result)
      
      expect(attributes).to include("result.execution_result")
      expect(attributes).to include("result.status")
      expect(attributes["result.execution_result"]).to eq("test result")
      expect(attributes["result.status"]).to eq("success")
    end
  end
  
  describe "#component_prefix" do
    it "generates prefix from collector class name" do
      # Test with the base collector
      collector = described_class.new
      expect(collector.send(:component_prefix)).to eq("raaf::tracing::spancollectors::base")
    end
    
    it "removes 'collector' suffix" do
      test_class = Class.new(described_class)
      stub_const("TestAgentCollector", test_class)
      
      collector = TestAgentCollector.new
      expect(collector.send(:component_prefix)).to eq("testagent")
    end
  end
  
  describe "#safe_value" do
    let(:collector) { described_class.new }
    
    it "passes through safe primitives" do
      expect(collector.send(:safe_value, "string")).to eq("string")
      expect(collector.send(:safe_value, 42)).to eq(42)
      expect(collector.send(:safe_value, 3.14)).to eq(3.14)
      expect(collector.send(:safe_value, true)).to be true
      expect(collector.send(:safe_value, false)).to be false
      expect(collector.send(:safe_value, nil)).to be nil
    end
    
    it "converts arrays recursively with size limit" do
      large_array = (1..15).to_a
      result = collector.send(:safe_value, large_array)
      
      expect(result).to be_an(Array)
      expect(result.length).to eq(10)  # Limited to first 10 elements
      expect(result).to eq((1..10).to_a)
    end
    
    it "converts hashes recursively" do
      hash = { name: "test", count: 42, nested: { value: "inner" } }
      result = collector.send(:safe_value, hash)
      
      expect(result).to eq({
        name: "test",
        count: 42,
        nested: { value: "inner" }
      })
    end
    
    it "converts complex objects to strings" do
      complex_object = double("ComplexObject")
      allow(complex_object).to receive(:to_s).and_return("complex_string")
      
      expect(collector.send(:safe_value, complex_object)).to eq("complex_string")
    end
  end
  
  describe "protected methods" do
    let(:component) do
      double("TestComponent", 
        class: double("ComponentClass", name: "TestAgent")
      )
    end
    
    let(:result) do
      double("TestResult", class: double("ResultClass", name: "Hash"))
    end
    
    describe "#base_attributes" do
      it "includes component type and name" do
        collector = described_class.new
        attrs = collector.send(:base_attributes, component)

        expect(attrs).to include("component.type")
        expect(attrs).to include("component.name")
        expect(attrs["component.name"]).to eq("TestAgent")
      end
    end
    
    describe "#base_result_attributes" do
      it "includes result type and success" do
        collector = described_class.new
        attrs = collector.send(:base_result_attributes, result)
        
        expect(attrs).to include("result.type")
        expect(attrs).to include("result.success")
        expect(attrs["result.type"]).to eq("Hash")
        expect(attrs["result.success"]).to be true
      end
      
      it "marks nil results as unsuccessful" do
        collector = described_class.new
        attrs = collector.send(:base_result_attributes, nil)
        
        expect(attrs["result.success"]).to be false
      end
    end
  end
end
