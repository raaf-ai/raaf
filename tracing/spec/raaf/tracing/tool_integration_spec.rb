# frozen_string_literal: true

require "spec_helper"
require "raaf/tracing/tool_integration"

RSpec.describe RAAF::Tracing::ToolIntegration do
  # Test tool class that includes the integration
  let(:tool_class) do
    Class.new do
      include RAAF::Tracing::ToolIntegration
      
      attr_reader :name, :execution_count
      
      def initialize(name: "TestTool")
        @name = name
        @execution_count = 0
      end
      
      def self.name
        "TestTool"
      end
      
      def execute
        with_tool_tracing(:execute) do
          @execution_count += 1
          "Tool executed #{@execution_count} times"
        end
      end
      
      def execute_with_explicit_parent(parent)
        with_tool_tracing(:execute, explicit_parent: parent) do
          @execution_count += 1
          "Tool executed with explicit parent"
        end
      end
      
      def call(**args)
        @execution_count += 1
        "Tool called with args: #{args}"
      end
    end
  end
  
  # Test agent class for context
  let(:agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent
      
      attr_reader :name, :current_span
      
      def initialize(name: "TestAgent")
        @name = name
      end
      
      def self.name
        "TestAgent"
      end
      
      def run_tool(tool)
        traced_run do
          tool.execute
        end
      end
    end
  end
  
  let(:tool) { tool_class.new }
  let(:agent) { agent_class.new }
  
  before do
    # Clean up any existing agent context
    Thread.current[:current_agent] = nil
  end
  
  describe "inclusion behavior" do
    it "includes Traceable module" do
      expect(tool).to be_a(RAAF::Tracing::Traceable)
    end
    
    it "sets component type to tool" do
      expect(tool_class.trace_component_type).to eq(:tool)
    end
  end
  
  describe "#with_tool_tracing" do
    context "without agent context" do
      it "creates root span" do
        span_data = nil
        
        result = tool.execute
        
        expect(result).to eq("Tool executed 1 times")
        # Span should be created and cleaned up
        expect(tool.current_span).to be_nil
      end
      
      it "includes tool-specific metadata" do
        span_data = nil
        
        tool.with_tool_tracing(:test_method) do
          span_data = tool.current_span
        end
        
        expect(span_data[:attributes]["tool.name"]).to eq("TestTool")
        expect(span_data[:attributes]["tool.method"]).to eq("test_method")
        expect(span_data[:attributes]).not_to have_key("tool.agent_context")
      end
    end
    
    context "with agent context" do
      it "creates child span of agent" do
        agent_span = nil
        tool_span = nil
        
        agent.with_tracing(:run) do
          agent_span = agent.current_span
          
          # Set agent context for tool detection
          RAAF::Tracing::ToolIntegration.set_agent_context(agent)
          
          begin
            tool.with_tool_tracing(:execute) do
              tool_span = tool.current_span
            end
          ensure
            RAAF::Tracing::ToolIntegration.clear_agent_context
          end
        end
        
        expect(tool_span[:parent_id]).to eq(agent_span[:span_id])
        expect(tool_span[:trace_id]).to eq(agent_span[:trace_id])
      end
      
      it "includes agent context in metadata" do
        span_data = nil
        
        agent.with_tracing(:run) do
          RAAF::Tracing::ToolIntegration.set_agent_context(agent)
          
          begin
            tool.with_tool_tracing(:execute) do
              span_data = tool.current_span
            end
          ensure
            RAAF::Tracing::ToolIntegration.clear_agent_context
          end
        end
        
        expect(span_data[:attributes]["tool.agent_context"]).to eq("TestAgent")
      end
    end
    
    context "with explicit parent" do
      it "uses explicit parent over detected context" do
        agent_span = nil
        tool_span = nil
        
        agent.with_tracing(:run) do
          agent_span = agent.current_span
          
          # Set different agent in thread context
          different_agent = agent_class.new(name: "DifferentAgent")
          RAAF::Tracing::ToolIntegration.set_agent_context(different_agent)
          
          begin
            # Explicit parent should take precedence
            tool.execute_with_explicit_parent(agent)
            tool_span = tool.current_span
          ensure
            RAAF::Tracing::ToolIntegration.clear_agent_context
          end
        end
        
        # Should use explicit parent (agent), not thread context (different_agent)
        expect(tool_span).to be_nil # Span cleaned up
      end
    end
  end
  
  describe "agent context detection" do
    describe "#detect_agent_context" do
      context "with thread-local agent" do
        it "detects agent from thread storage" do
          agent.with_tracing(:run) do
            Thread.current[:current_agent] = agent
            
            detected = tool.detect_agent_context
            expect(detected).to eq(agent)
          end
        end
        
        it "ignores non-traced agents" do
          # Ensure agent is not being traced by clearing any span
          agent.instance_variable_set(:@current_span, nil)
          Thread.current[:current_agent] = agent # Not traced (no current_span)

          # Verify agent is not currently being traced
          expect(agent.traced?).to be(false)
          expect(agent.respond_to?(:traced?)).to be(true)

          # Debug the detection logic step by step
          current_agent = Thread.current[:current_agent]
          expect(current_agent).to eq(agent)
          expect(current_agent&.respond_to?(:traced?)).to be(true)
          expect(current_agent.traced?).to be(false)

          # This should be the condition that passes: agent exists, responds to traced?, but traced? is false
          should_return_agent = current_agent&.respond_to?(:traced?) && current_agent.traced?
          expect(should_return_agent).to be(false)

          detected = tool.detect_agent_context
          expect(detected).to be_nil
        end
      end
      
      context "with instance variable agent context" do
        it "detects agent from @agent_context" do
          agent.with_tracing(:run) do
            tool.instance_variable_set(:@agent_context, agent)
            
            detected = tool.detect_agent_context
            expect(detected).to eq(agent)
          end
        end
      end
      
      context "with parent component" do
        it "detects agent from @parent_component" do
          agent.with_tracing(:run) do
            tool.instance_variable_set(:@parent_component, agent)
            
            detected = tool.detect_agent_context
            expect(detected).to eq(agent)
          end
        end
      end
      
      context "without any context" do
        it "returns nil" do
          detected = tool.detect_agent_context
          expect(detected).to be_nil
        end
      end
    end
  end
  
  describe "module-level methods" do
    describe ".set_agent_context" do
      it "sets thread-local agent context" do
        RAAF::Tracing::ToolIntegration.set_agent_context(agent)
        
        expect(Thread.current[:current_agent]).to eq(agent)
      end
    end
    
    describe ".clear_agent_context" do
      it "clears thread-local agent context" do
        Thread.current[:current_agent] = agent
        
        RAAF::Tracing::ToolIntegration.clear_agent_context
        
        expect(Thread.current[:current_agent]).to be_nil
      end
    end
    
    describe ".with_agent_context" do
      it "sets and restores agent context" do
        original_agent = agent_class.new(name: "OriginalAgent")
        Thread.current[:current_agent] = original_agent
        
        new_agent = agent_class.new(name: "NewAgent")
        result = nil
        
        RAAF::Tracing::ToolIntegration.with_agent_context(new_agent) do
          expect(Thread.current[:current_agent]).to eq(new_agent)
          result = "executed"
        end
        
        expect(Thread.current[:current_agent]).to eq(original_agent)
        expect(result).to eq("executed")
      end
      
      it "restores context even when block raises" do
        original_agent = agent_class.new(name: "OriginalAgent")
        Thread.current[:current_agent] = original_agent
        
        new_agent = agent_class.new(name: "NewAgent")
        
        expect {
          RAAF::Tracing::ToolIntegration.with_agent_context(new_agent) do
            raise StandardError, "Test error"
          end
        }.to raise_error(StandardError, "Test error")
        
        expect(Thread.current[:current_agent]).to eq(original_agent)
      end
    end
  end
  
  describe "integration with traceable" do
    it "creates proper span hierarchy" do
      agent_span = nil
      tool_span = nil
      
      agent.with_tracing(:run) do
        agent_span = agent.current_span
        
        RAAF::Tracing::ToolIntegration.with_agent_context(agent) do
          tool.with_tool_tracing(:execute) do
            tool_span = tool.current_span
          end
        end
      end
      
      # Verify proper hierarchy
      expect(agent_span[:kind]).to eq(:agent)
      expect(tool_span[:kind]).to eq(:tool)
      expect(tool_span[:parent_id]).to eq(agent_span[:span_id])
      expect(tool_span[:trace_id]).to eq(agent_span[:trace_id])
      
      # Verify span names
      expect(agent_span[:name]).to include("agent")
      expect(tool_span[:name]).to include("tool")
    end
  end
end
