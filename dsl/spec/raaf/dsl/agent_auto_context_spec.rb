# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/agent"
require "raaf/dsl/core/context_variables"
require "raaf/dsl/core/context_builder"

RSpec.describe "RAAF::DSL::Agent Auto-Context" do
  # Test agent without any configuration (default auto-context)
  class SimpleTestAgent < RAAF::DSL::Agent
    agent_name "SimpleTestAgent"
    static_instructions "Test agent"
  end
  
  # Test agent with auto-context explicitly enabled
  class ExplicitAutoContextAgent < RAAF::DSL::Agent
    agent_name "ExplicitAutoContextAgent"
    auto_context true
    static_instructions "Test agent"
  end
  
  # Test agent with auto-context disabled
  class ManualContextAgent < RAAF::DSL::Agent
    agent_name "ManualContextAgent"
    auto_context false
    static_instructions "Test agent"
  end
  
  # Test agent with context DSL configuration
  class ConfiguredContextAgent < RAAF::DSL::Agent
    agent_name "ConfiguredContextAgent"
    static_instructions "Test agent"
    
    context do
      exclude :cache, :logger
      requires :user, :data
    end
  end
  
  # Test agent with custom preparation methods
  class CustomPrepAgent < RAAF::DSL::Agent
    agent_name "CustomPrepAgent"
    static_instructions "Test agent"
    
    private
    
    def prepare_user_for_context(user)
      { id: user[:id], name: user[:name] }
    end
  end
  
  # Test agent with computed context values
  class ComputedContextAgent < RAAF::DSL::Agent
    agent_name "ComputedContextAgent"
    static_instructions "Test agent"
    
    private
    
    def build_metadata_context
      { generated_at: "2025-01-01", version: "1.0" }
    end
    
    def build_classification_context
      { type: "automated", confidence: 95 }
    end
  end
  
  # Test backward compatibility
  class BackwardCompatibleAgent < RAAF::DSL::Agent
    agent_name "BackwardCompatibleAgent"
    static_instructions "Test agent"
    
    def initialize(data:)
      context = RAAF::DSL::ContextVariables.new(processed_data: process_data(data))
      super(context: context)
    end
    
    private
    
    def process_data(data)
      data.upcase
    end
  end

  describe "default behavior" do
    it "enables auto-context by default" do
      expect(SimpleTestAgent.auto_context?).to be true
    end
    
    it "automatically builds context from parameters" do
      agent = SimpleTestAgent.new(
        user: "john",
        query: "test query",
        max_results: 10
      )
      
      expect(agent.get(:user)).to eq("john")
      expect(agent.get(:query)).to eq("test query")
      expect(agent.get(:max_results)).to eq(10)
    end
    
    it "works without defining initialize method" do
      agent = SimpleTestAgent.new(data: { key: "value" })
      expect(agent.get(:data)).to eq({ key: "value" })
    end
  end

  describe "clean context API" do
    let(:agent) { SimpleTestAgent.new(initial: "value") }
    
    it "provides get method" do
      expect(agent.get(:initial)).to eq("value")
      expect(agent.get(:missing, "default")).to eq("default")
    end
    
    it "provides set method" do
      result = agent.set(:new_key, "new_value")
      expect(result).to eq("new_value")
      expect(agent.get(:new_key)).to eq("new_value")
    end
    
    it "provides update method" do
      result = agent.update(
        status: "complete",
        count: 42
      )
      expect(result).to eq(agent)
      expect(agent.get(:status)).to eq("complete")
      expect(agent.get(:count)).to eq(42)
    end
    
    it "provides has? method" do
      expect(agent.has?(:initial)).to be true
      expect(agent.has?(:missing)).to be false
    end
    
    it "provides context_keys method" do
      expect(agent.context_keys).to include(:initial)
    end
  end

  describe "auto_context DSL" do
    it "can be explicitly enabled" do
      expect(ExplicitAutoContextAgent.auto_context?).to be true
    end
    
    it "can be disabled" do
      expect(ManualContextAgent.auto_context?).to be false
    end
    
    it "returns empty context when disabled" do
      agent = ManualContextAgent.new(user: "john", data: "test")
      expect(agent.context_keys).to be_empty
    end
  end

  describe "context DSL configuration" do
    it "excludes specified keys" do
      agent = ConfiguredContextAgent.new(
        user: "john",
        data: "test",
        cache: "should_be_excluded",
        logger: "also_excluded"
      )
      
      expect(agent.has?(:user)).to be true
      expect(agent.has?(:data)).to be true
      expect(agent.has?(:cache)).to be false
      expect(agent.has?(:logger)).to be false
    end
  end

  describe "custom preparation methods" do
    it "applies prepare_*_for_context methods" do
      user_data = { id: 123, name: "John", email: "john@example.com" }
      agent = CustomPrepAgent.new(user: user_data)
      
      # Should only have id and name due to preparation method
      context_user = agent.get(:user)
      expect(context_user).to eq({ id: 123, name: "John" })
      expect(context_user).not_to have_key(:email)
    end
  end

  describe "computed context values" do
    it "automatically adds build_*_context method results" do
      agent = ComputedContextAgent.new(base_data: "test")
      
      expect(agent.get(:base_data)).to eq("test")
      expect(agent.get(:metadata)).to eq({ generated_at: "2025-01-01", version: "1.0" })
      expect(agent.get(:classification)).to eq({ type: "automated", confidence: 95 })
    end
  end

  describe "backward compatibility" do
    it "works with existing agents that pass context explicitly" do
      agent = BackwardCompatibleAgent.new(data: "test")
      
      # Should use the explicitly provided context
      expect(agent.get(:processed_data)).to eq("TEST")
      # Should not have the original data parameter
      expect(agent.has?(:data)).to be false
    end
    
    it "bypasses auto-context when context: is provided" do
      manual_context = RAAF::DSL::ContextVariables.new(manual: "context")
      agent = SimpleTestAgent.new(
        context: manual_context,
        ignored_param: "should_not_be_in_context"
      )
      
      expect(agent.get(:manual)).to eq("context")
      expect(agent.has?(:ignored_param)).to be false
    end
  end

  describe "integration with existing features" do
    it "works with context_reader DSL" do
      class ReaderAgent < RAAF::DSL::Agent
        context_reader :product, :company
        static_instructions "Test"
      end
      
      agent = ReaderAgent.new(product: "Widget", company: "Acme")
      # context_reader methods should work
      expect(agent.send(:product)).to eq("Widget")
      expect(agent.send(:company)).to eq("Acme")
    end
    
    it "maintains immutability of context" do
      agent = SimpleTestAgent.new(value: "original")
      original_context = agent.context
      
      agent.set(:value, "modified")
      
      # Context should be a new instance
      expect(agent.context).not_to equal(original_context)
      expect(agent.get(:value)).to eq("modified")
    end
  end

  describe "edge cases" do
    it "handles nil parameters" do
      agent = SimpleTestAgent.new(value: nil)
      expect(agent.has?(:value)).to be true
      expect(agent.get(:value)).to be_nil
    end
    
    it "handles empty initialization" do
      agent = SimpleTestAgent.new
      expect(agent.context_keys).to be_empty
    end
    
    it "handles complex nested structures" do
      complex_data = {
        nested: { deep: { value: "found" } },
        array: [1, 2, 3],
        mixed: [{ a: 1 }, { b: 2 }]
      }
      
      agent = SimpleTestAgent.new(data: complex_data)
      result = agent.get(:data)
      
      expect(result[:nested][:deep][:value]).to eq("found")
      expect(result[:array]).to eq([1, 2, 3])
      expect(result[:mixed]).to eq([{ a: 1 }, { b: 2 }])
    end
  end
  
  describe "context rules with include" do
    class IncludeOnlyAgent < RAAF::DSL::Agent
      context include: [:allowed_one, :allowed_two]
      static_instructions "Test"
    end
    
    it "only includes specified keys" do
      agent = IncludeOnlyAgent.new(
        allowed_one: "yes",
        allowed_two: "also_yes",
        not_allowed: "no"
      )
      
      expect(agent.has?(:allowed_one)).to be true
      expect(agent.has?(:allowed_two)).to be true
      expect(agent.has?(:not_allowed)).to be false
    end
  end
end