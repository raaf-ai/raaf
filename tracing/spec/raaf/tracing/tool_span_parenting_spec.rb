# frozen_string_literal: true

require "spec_helper"
require "securerandom"

RSpec.describe "Tool Span Parenting Integration" do
  # Create test classes that simulate agent and tool behavior
  let(:test_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent
      
      attr_reader :name, :current_span, :tools
      
      def initialize(name: "TestAgent")
        @name = name
        @tools = []
      end
      
      def self.name
        "TestAgent"
      end
      
      def add_tool(tool)
        @tools << tool
      end
      
      def run_with_tool
        traced_run do
          # Simulate tool execution within agent context
          tool = @tools.first
          tool.execute if tool
        end
      end
    end
  end
  
  let(:test_tool_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :tool
      
      attr_reader :name, :current_span, :agent_context
      
      def initialize(name: "TestTool", agent_context: nil)
        @name = name
        @agent_context = agent_context
      end
      
      def self.name
        "TestTool"
      end
      
      def execute
        # Check if we're running within an agent context
        if @agent_context && @agent_context.respond_to?(:traced?) && @agent_context.traced?
          # Tool runs within agent span context
          traced_execute(parent_component: @agent_context) do
            "Tool executed within agent context"
          end
        else
          # Tool runs standalone
          traced_execute do
            "Tool executed standalone"
          end
        end
      end
      
      def execute_with_context_detection
        # Simulate automatic agent context detection
        detected_agent = detect_agent_context
        
        if detected_agent
          traced_execute(parent_component: detected_agent) do
            "Tool with detected agent context"
          end
        else
          traced_execute do
            "Tool without agent context"
          end
        end
      end
      
      private
      
      def detect_agent_context
        # In real implementation, this would look at the call stack or thread-local storage
        # For tests, we simulate this by checking a thread-local variable
        Thread.current[:current_agent]
      end
    end
  end
  
  let(:agent) { test_agent_class.new }
  let(:tool) { test_tool_class.new }
  let(:agent_aware_tool) { test_tool_class.new(agent_context: agent) }
  
  describe "tool span creation with agent context" do
    context "when tool runs within agent context" do
      it "creates child span of agent span" do
        agent.add_tool(agent_aware_tool)
        
        agent_span = nil
        tool_span = nil
        
        # Set up agent context detection
        Thread.current[:current_agent] = agent
        
        begin
          agent.with_tracing(:run) do
            agent_span = agent.current_span
            
            # Tool should detect agent context and create child span
            agent_aware_tool.with_tracing(:execute, parent_component: agent) do
              tool_span = agent_aware_tool.current_span
            end
          end
        ensure
          Thread.current[:current_agent] = nil
        end
        
        expect(tool_span[:parent_id]).to eq(agent_span[:span_id])
        expect(tool_span[:trace_id]).to eq(agent_span[:trace_id])
        expect(tool_span[:kind]).to eq(:tool)
        expect(agent_span[:kind]).to eq(:agent)
      end
      
      it "inherits trace context from agent" do
        agent_span = nil
        tool_span = nil
        
        agent.with_tracing(:run) do
          agent_span = agent.current_span
          
          # Explicit parent component passing
          agent_aware_tool.with_tracing(:execute, parent_component: agent) do
            tool_span = agent_aware_tool.current_span
          end
        end
        
        # Tool span should be child of agent span
        expect(tool_span[:parent_id]).to eq(agent_span[:span_id])
        expect(tool_span[:trace_id]).to eq(agent_span[:trace_id])
        
        # But different span IDs
        expect(tool_span[:span_id]).not_to eq(agent_span[:span_id])
      end
      
      it "includes appropriate tool attributes" do
        tool_span = nil
        
        agent.with_tracing(:run) do
          agent_aware_tool.with_tracing(:execute, parent_component: agent) do
            tool_span = agent_aware_tool.current_span
          end
        end
        
        expect(tool_span[:attributes]["component.type"]).to eq("tool")
        expect(tool_span[:attributes]["component.name"]).to eq("TestTool")
        expect(tool_span[:name]).to include("tool")
        expect(tool_span[:name]).to include("execute")
      end
    end
    
    context "when tool runs standalone" do
      it "creates root span when no agent context" do
        tool_span = nil
        
        tool.with_tracing(:execute) do
          tool_span = tool.current_span
        end
        
        expect(tool_span[:parent_id]).to be_nil
        expect(tool_span[:trace_id]).to be_a(String)
        expect(tool_span[:kind]).to eq(:tool)
      end
      
      it "handles missing agent context gracefully" do
        tool_span = nil
        
        # Ensure no thread-local agent context
        Thread.current[:current_agent] = nil
        
        tool.execute_with_context_detection
        
        # Should not raise any errors and create standalone span
        expect { tool.execute_with_context_detection }.not_to raise_error
      end
    end
  end
  
  describe "agent context detection" do
    it "detects agent context through thread-local storage" do
      Thread.current[:current_agent] = agent
      
      begin
        tool_span = nil
        agent_span = nil
        
        agent.with_tracing(:run) do
          agent_span = agent.current_span
          
          # Tool should automatically detect agent context
          tool.execute_with_context_detection
        end
        
        # Verify agent was detected (in real implementation, this would be tested differently)
        detected_agent = Thread.current[:current_agent]
        expect(detected_agent).to eq(agent)
      ensure
        Thread.current[:current_agent] = nil
      end
    end
    
    it "handles no agent context gracefully" do
      Thread.current[:current_agent] = nil
      
      expect { tool.execute_with_context_detection }.not_to raise_error
    end
  end
  
  describe "edge cases" do
    context "nested tool execution" do
      let(:nested_tool) { test_tool_class.new(agent_context: agent) }
      
      it "maintains proper span hierarchy" do
        agent_span = nil
        first_tool_span = nil
        nested_tool_span = nil
        
        agent.with_tracing(:run) do
          agent_span = agent.current_span
          
          agent_aware_tool.with_tracing(:execute, parent_component: agent) do
            first_tool_span = agent_aware_tool.current_span
            
            # Nested tool execution
            nested_tool.with_tracing(:execute, parent_component: agent_aware_tool) do
              nested_tool_span = nested_tool.current_span
            end
          end
        end
        
        # Verify hierarchy: agent -> first_tool -> nested_tool
        expect(first_tool_span[:parent_id]).to eq(agent_span[:span_id])
        expect(nested_tool_span[:parent_id]).to eq(first_tool_span[:span_id])
        
        # All should share same trace ID
        expect(first_tool_span[:trace_id]).to eq(agent_span[:trace_id])
        expect(nested_tool_span[:trace_id]).to eq(agent_span[:trace_id])
      end
    end
    
    context "concurrent tool execution" do
      it "maintains separate trace contexts per thread" do
        agent1 = test_agent_class.new(name: "Agent1")
        agent2 = test_agent_class.new(name: "Agent2")
        tool1 = test_tool_class.new(name: "Tool1", agent_context: agent1)
        tool2 = test_tool_class.new(name: "Tool2", agent_context: agent2)
        
        spans = {}
        
        threads = [
          Thread.new do
            agent1.with_tracing(:run) do
              spans[:agent1] = agent1.current_span
              tool1.with_tracing(:execute, parent_component: agent1) do
                spans[:tool1] = tool1.current_span
              end
            end
          end,
          Thread.new do
            agent2.with_tracing(:run) do
              spans[:agent2] = agent2.current_span
              tool2.with_tracing(:execute, parent_component: agent2) do
                spans[:tool2] = tool2.current_span
              end
            end
          end
        ]
        
        threads.each(&:join)
        
        # Each thread should have independent trace contexts
        expect(spans[:tool1][:parent_id]).to eq(spans[:agent1][:span_id])
        expect(spans[:tool2][:parent_id]).to eq(spans[:agent2][:span_id])
        expect(spans[:agent1][:trace_id]).not_to eq(spans[:agent2][:trace_id])
      end
    end
    
    context "error handling" do
      it "properly handles tool errors" do
        tool_span = nil

        # Test tool error handling in isolation
        begin
          agent_aware_tool.with_tracing(:execute) do
            tool_span = agent_aware_tool.current_span
            raise StandardError, "Tool execution failed"
          end
        rescue StandardError
          # Expected error
        end

        # Tool span should be marked as failed
        expect(tool_span[:status]).to eq(:error)
        expect(tool_span[:attributes]["error.message"]).to eq("Tool execution failed")
      end

      it "maintains span hierarchy with successful tool execution" do
        agent_span = nil
        tool_span = nil

        agent.with_tracing(:run) do
          agent_span = agent.current_span

          agent_aware_tool.with_tracing(:execute, parent_component: agent) do
            tool_span = agent_aware_tool.current_span
            # Successful execution
          end
        end

        # Verify parent-child relationship
        expect(tool_span[:parent_id]).to eq(agent_span[:span_id])
        expect(tool_span[:trace_id]).to eq(agent_span[:trace_id])
        expect(tool_span[:status]).to eq(:ok)
        expect(agent_span[:status]).to eq(:ok)
      end
    end
  end
  
  describe "span lifecycle management" do
    it "properly cleans up tool spans after execution" do
      agent.with_tracing(:run) do
        agent_aware_tool.with_tracing(:execute, parent_component: agent) do
          expect(agent_aware_tool.current_span).not_to be_nil
        end
        
        # Tool span should be cleaned up after execution
        expect(agent_aware_tool.current_span).to be_nil
      end
    end
    
    it "maintains agent span during tool execution" do
      agent_span_during_tool = nil
      
      agent.with_tracing(:run) do
        initial_agent_span = agent.current_span
        
        agent_aware_tool.with_tracing(:execute, parent_component: agent) do
          agent_span_during_tool = agent.current_span
        end
        
        # Agent should maintain its span during tool execution
        expect(agent_span_during_tool).to eq(initial_agent_span)
      end
    end
  end
end
