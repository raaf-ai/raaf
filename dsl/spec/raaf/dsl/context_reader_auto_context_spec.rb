# frozen_string_literal: true

require 'spec_helper'
require 'raaf/dsl/agent'

RSpec.describe "Context Reader with Auto-Context Integration" do
  # Test agent with context readers
  class ContextReaderTestAgent < RAAF::DSL::Agent
    agent_name "ContextReaderTestAgent"
    static_instructions "Test agent for context reader integration"
    
    # Define context readers with various options
    context_reader :product, required: true
    context_reader :company, required: true
    context_reader :mode, default: "standard"
    context_reader :limit, default: 10
    context_reader :filters, default: {}
    context_reader :optional_param
    
    # Method to expose context values for testing
    def get_all_values
      {
        product: product,
        company: company,
        mode: mode,
        limit: limit,
        filters: filters,
        optional: optional_param
      }
    end
  end
  
  describe "basic context reader functionality" do
    it "creates accessor methods that work with auto-context" do
      agent = ContextReaderTestAgent.new(
        product: "Widget Pro",
        company: "Acme Corp"
      )
      
      values = agent.get_all_values
      expect(values[:product]).to eq("Widget Pro")
      expect(values[:company]).to eq("Acme Corp")
    end
    
    it "applies default values when parameters not provided" do
      agent = ContextReaderTestAgent.new(
        product: "Widget",
        company: "Acme"
      )
      
      values = agent.get_all_values
      expect(values[:mode]).to eq("standard")
      expect(values[:limit]).to eq(10)
      expect(values[:filters]).to eq({})
    end
    
    it "overrides defaults when values provided" do
      agent = ContextReaderTestAgent.new(
        product: "Widget",
        company: "Acme",
        mode: "advanced",
        limit: 50,
        filters: { category: "premium" }
      )
      
      values = agent.get_all_values
      expect(values[:mode]).to eq("advanced")
      expect(values[:limit]).to eq(50)
      expect(values[:filters]).to eq({ category: "premium" })
    end
    
    it "returns nil for optional parameters not provided" do
      agent = ContextReaderTestAgent.new(
        product: "Widget",
        company: "Acme"
      )
      
      values = agent.get_all_values
      expect(values[:optional]).to be_nil
    end
    
    it "raises error when required parameter is missing" do
      expect {
        agent = ContextReaderTestAgent.new(company: "Acme")
        agent.get_all_values # This triggers the accessor which checks required
      }.to raise_error(ArgumentError, /product.*required/)
    end
  end
  
  describe "context reader with complex objects" do
    class ComplexContextAgent < RAAF::DSL::Agent
      agent_name "ComplexContextAgent"
      static_instructions "Test complex objects"
      
      context_reader :user, required: true
      context_reader :settings, default: { theme: "dark", notifications: true }
      context_reader :items, default: []
      
      def process
        {
          user_name: user[:name],
          theme: settings[:theme],
          item_count: items.length
        }
      end
    end
    
    it "handles complex objects through auto-context" do
      user_obj = { name: "Alice", id: 123, role: "admin" }
      items_list = ["item1", "item2", "item3"]
      
      agent = ComplexContextAgent.new(
        user: user_obj,
        items: items_list
      )
      
      result = agent.process
      expect(result[:user_name]).to eq("Alice")
      expect(result[:theme]).to eq("dark")  # From default
      expect(result[:item_count]).to eq(3)
    end
  end
  
  describe "context reader with validation context DSL" do
    class ValidatedContextAgent < RAAF::DSL::Agent
      agent_name "ValidatedContextAgent"
      static_instructions "Test validation"
      
      # Context DSL for validation
      context do
        requires :email, :user_id
        validate :priority, with: ->(v) { %w[low normal high urgent].include?(v) }
      end
      
      # Context readers
      context_reader :email, required: true
      context_reader :user_id, required: true
      context_reader :priority, default: "normal"
      context_reader :notes
      
      def process
        "Processing #{priority} priority request for #{email}"
      end
    end
    
    it "works with both context DSL validation and context_reader" do
      agent = ValidatedContextAgent.new(
        email: "test@example.com",
        user_id: 42,
        priority: "high"
      )
      
      result = agent.process
      expect(result).to eq("Processing high priority request for test@example.com")
    end
    
    it "applies context_reader defaults even with validation" do
      agent = ValidatedContextAgent.new(
        email: "test@example.com",
        user_id: 42
      )
      
      result = agent.process
      expect(result).to include("normal priority")
    end
  end
  
  describe "context reader with prepare methods" do
    class PrepareContextAgent < RAAF::DSL::Agent
      agent_name "PrepareContextAgent"
      static_instructions "Test prepare methods"
      
      context_reader :user, required: true
      context_reader :processed_data
      
      private
      
      # This should be called before adding to context
      def prepare_user_for_context(user)
        {
          id: user[:id],
          name: user[:name].upcase,
          email: user[:email].downcase
        }
      end
      
      def get_prepared_user
        user
      end
    end
    
    it "applies prepare methods before context_reader accesses values" do
      agent = PrepareContextAgent.new(
        user: { id: 1, name: "alice", email: "ALICE@EXAMPLE.COM" }
      )
      
      # Access through private method for testing
      prepared = agent.send(:get_prepared_user)
      expect(prepared[:name]).to eq("ALICE")
      expect(prepared[:email]).to eq("alice@example.com")
    end
  end
  
  describe "context reader with computed context" do
    class ComputedContextAgent < RAAF::DSL::Agent
      agent_name "ComputedContextAgent"
      static_instructions "Test computed context"
      
      context_reader :orders, required: true
      context_reader :statistics  # This will be computed
      context_reader :summary      # This will be computed
      
      private
      
      def build_statistics_context
        {
          total_count: orders.length,
          total_value: orders.sum { |o| o[:value] },
          average: orders.sum { |o| o[:value] } / orders.length.to_f
        }
      end
      
      def build_summary_context
        "Processed #{orders.length} orders"
      end
      
      def get_computed_values
        {
          stats: statistics,
          summary: summary
        }
      end
    end
    
    it "makes computed context available through context_reader" do
      orders = [
        { id: 1, value: 100 },
        { id: 2, value: 200 },
        { id: 3, value: 300 }
      ]
      
      agent = ComputedContextAgent.new(orders: orders)
      
      values = agent.send(:get_computed_values)
      expect(values[:stats][:total_count]).to eq(3)
      expect(values[:stats][:total_value]).to eq(600)
      expect(values[:stats][:average]).to eq(200.0)
      expect(values[:summary]).to eq("Processed 3 orders")
    end
  end
  
  describe "backward compatibility" do
    class BackwardCompatAgent < RAAF::DSL::Agent
      agent_name "BackwardCompatAgent"
      static_instructions "Test backward compatibility"
      
      # Mix of context_reader and manual accessors
      context_reader :new_param, default: "new_style"
      
      def old_style_param
        get(:old_param, "old_default")
      end
      
      def mixed_access
        {
          new: new_param,
          old: old_style_param,
          direct: get(:direct_param)
        }
      end
    end
    
    it "supports both context_reader and manual get() calls" do
      agent = BackwardCompatAgent.new(
        new_param: "custom_new",
        old_param: "custom_old",
        direct_param: "direct_value"
      )
      
      result = agent.mixed_access
      expect(result[:new]).to eq("custom_new")
      expect(result[:old]).to eq("custom_old")
      expect(result[:direct]).to eq("direct_value")
    end
    
    it "applies defaults correctly for both styles" do
      agent = BackwardCompatAgent.new(direct_param: "only_direct")
      
      result = agent.mixed_access
      expect(result[:new]).to eq("new_style")      # context_reader default
      expect(result[:old]).to eq("old_default")    # manual get() default
      expect(result[:direct]).to eq("only_direct")
    end
  end
  
  describe "error handling" do
    class ErrorHandlingAgent < RAAF::DSL::Agent
      agent_name "ErrorHandlingAgent"
      static_instructions "Test error handling"
      
      context_reader :critical, required: true
      context_reader :optional
      
      def process_critical
        critical
      end
      
      def process_optional
        optional || "default_value"
      end
    end
    
    it "raises clear error for missing required context_reader fields" do
      agent = ErrorHandlingAgent.new(optional: "something")
      
      expect {
        agent.process_critical
      }.to raise_error(ArgumentError, /critical.*required/)
    end
    
    it "handles nil gracefully for optional fields" do
      agent = ErrorHandlingAgent.new(critical: "present")
      
      result = agent.process_optional
      expect(result).to eq("default_value")
    end
  end
end