# frozen_string_literal: true

require "spec_helper"
require "raaf/tracing/tool_integration"

RSpec.describe "End-to-End Tool Tracing Integration", :integration do
  # Mock classes to simulate the actual RAAF ecosystem
  let(:agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent
      
      attr_reader :name, :current_span, :tools
      
      def initialize(name: "ProductionAgent")
        @name = name
        @tools = []
      end
      
      def self.name
        "ProductionAgent"
      end
      
      def add_tool(tool)
        @tools << tool
      end
      
      def run_with_tools(input)
        traced_run do
          results = []
          
          # Set agent context for all tools
          RAAF::Tracing::ToolIntegration.with_agent_context(self) do
            @tools.each do |tool|
              if tool.respond_to?(:with_tool_tracing)
                result = tool.with_tool_tracing(:execute) do
                  tool.process(input)
                end
                results << result
              else
                results << tool.process(input)
              end
            end
          end
          
          results
        end
      end
    end
  end
  
  let(:modern_tool_class) do
    Class.new do
      include RAAF::Tracing::ToolIntegration
      
      attr_reader :name
      
      def initialize(name: "ModernTool")
        @name = name
      end
      
      def self.name
        "ModernTool"
      end
      
      def process(input)
        # Tool automatically detects agent context and creates child spans
        "Processed: #{input}"
      end
    end
  end
  
  let(:legacy_tool_class) do
    Class.new do
      attr_reader :name
      
      def initialize(name: "LegacyTool")
        @name = name
      end
      
      def self.name
        "LegacyTool"
      end
      
      def process(input)
        # Legacy tool without tracing integration
        "Legacy processed: #{input}"
      end
    end
  end
  
  let(:runner_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :runner
      
      attr_reader :agent
      
      def initialize(agent:)
        @agent = agent
      end
      
      def self.name
        "ProductionRunner"
      end
      
      def run(input)
        traced_run do
          @agent.run_with_tools(input)
        end
      end
    end
  end
  
  let(:agent) { agent_class.new }
  let(:modern_tool) { modern_tool_class.new }
  let(:legacy_tool) { legacy_tool_class.new }
  let(:runner) { runner_class.new(agent: agent) }
  
  # Mock tracer to capture spans
  let(:captured_spans) { [] }
  let(:mock_processor) do
    double("processor").tap do |processor|
      allow(processor).to receive(:on_span_end) do |span|
        captured_spans << span.to_h
      end
    end
  end

  let(:mock_tracer) do
    double("tracer").tap do |tracer|
      allow(tracer).to receive(:processors).and_return([mock_processor])
      allow(tracer).to receive(:process_span) do |span|
        captured_spans << span
      end
    end
  end
  
  before do
    # Set up mock tracer for all components
    allow(runner).to receive(:tracer).and_return(mock_tracer)
    allow(agent).to receive(:tracer).and_return(mock_tracer)
    allow(modern_tool).to receive(:tracer).and_return(mock_tracer)
    
    # Clear any existing agent context
    Thread.current[:current_agent] = nil
  end
  
  describe "complete agent-tool execution flow" do
    it "creates proper span hierarchy for modern tools" do
      agent.add_tool(modern_tool)
      
      result = runner.run("test input")
      
      expect(result).to eq(["Processed: test input"])
      
      # Verify span hierarchy was created
      expect(captured_spans.length).to be >= 3
      
      # Find spans by type
      runner_spans = captured_spans.select { |span| span[:kind] == :runner }
      agent_spans = captured_spans.select { |span| span[:kind] == :agent }
      tool_spans = captured_spans.select { |span| span[:kind] == :tool }
      
      expect(runner_spans.length).to eq(1)
      expect(agent_spans.length).to eq(1)
      expect(tool_spans.length).to eq(1)
      
      runner_span = runner_spans.first
      agent_span = agent_spans.first
      tool_span = tool_spans.first
      
      # Verify parent-child relationships
      expect(agent_span[:parent_id]).to eq(runner_span[:span_id])
      expect(tool_span[:parent_id]).to eq(agent_span[:span_id])
      
      # Verify all spans share the same trace ID
      expect(agent_span[:trace_id]).to eq(runner_span[:trace_id])
      expect(tool_span[:trace_id]).to eq(runner_span[:trace_id])
    end
    
    it "handles mixed modern and legacy tools" do
      agent.add_tool(modern_tool)
      agent.add_tool(legacy_tool)
      
      result = runner.run("test input")
      
      expect(result).to eq(["Processed: test input", "Legacy processed: test input"])
      
      # Modern tool should create trace, legacy tool should not
      tool_spans = captured_spans.select { |span| span[:kind] == :tool }
      expect(tool_spans.length).to eq(1) # Only modern tool creates span
      
      tool_span = tool_spans.first
      expect(tool_span[:attributes]["tool.name"]).to eq("ModernTool")
    end
    
    it "includes proper metadata in tool spans" do
      agent.add_tool(modern_tool)
      
      runner.run("test input")
      
      tool_spans = captured_spans.select { |span| span[:kind] == :tool }
      tool_span = tool_spans.first
      
      # Check tool-specific metadata
      expect(tool_span[:attributes]["tool.name"]).to eq("ModernTool")
      expect(tool_span[:attributes]["tool.agent_context"]).to eq("ProductionAgent")
      expect(tool_span[:attributes]["component.type"]).to eq("tool")
      expect(tool_span[:attributes]["component.name"]).to eq("ModernTool")
    end
  end
  
  describe "agent context detection scenarios" do
    it "works when tools are called directly within agent context" do
      agent_span_id = nil
      tool_span_data = nil

      agent.with_tracing(:run) do
        agent_span_id = agent.current_span[:span_id]

        RAAF::Tracing::ToolIntegration.with_agent_context(agent) do
          modern_tool.with_tool_tracing(:direct_call) do
            tool_span_data = modern_tool.current_span
          end
        end
      end

      expect(tool_span_data).not_to be_nil
      expect(tool_span_data[:kind]).to eq(:tool)
      expect(tool_span_data[:parent_id]).to eq(agent_span_id)
    end
    
    it "creates root spans when no agent context" do
      span_data = nil
      
      modern_tool.with_tool_tracing(:standalone) do
        span_data = modern_tool.current_span
      end
      
      expect(span_data).not_to be_nil
      expect(span_data[:kind]).to eq(:tool)
      expect(span_data[:parent_id]).to be_nil # Root span
    end
  end
  
  describe "error scenarios" do
    let(:failing_tool_class) do
      Class.new do
        include RAAF::Tracing::ToolIntegration
        
        attr_reader :name
        
        def initialize(name: "FailingTool")
          @name = name
        end
        
        def self.name
          "FailingTool"
        end
        
        def process(input)
          raise StandardError, "Tool processing failed"
        end
      end
    end
    
    let(:failing_tool) { failing_tool_class.new }
    
    it "properly handles tool failures while maintaining span hierarchy" do
      agent.add_tool(failing_tool)
      
      expect {
        agent.with_tracing(:run) do
          RAAF::Tracing::ToolIntegration.with_agent_context(agent) do
            failing_tool.with_tool_tracing(:execute) do
              failing_tool.process("test input")
            end
          end
        end
      }.to raise_error(StandardError, "Tool processing failed")
      
      # Find the tool span
      tool_spans = captured_spans.select { |span| span[:kind] == :tool }
      
      expect(tool_spans.length).to eq(1)
      tool_span = tool_spans.first
      
      # Tool span should be marked as failed
      expect(tool_span[:status]).to eq(:error)
      expect(tool_span[:attributes]["error.message"]).to eq("Tool processing failed")
      
      # Should still maintain proper parent relationship
      agent_spans = captured_spans.select { |span| span[:kind] == :agent }
      if agent_spans.any?
        agent_span = agent_spans.first
        expect(tool_span[:parent_id]).to eq(agent_span[:span_id])
      end
    end
  end
  
  describe "performance and concurrency" do
    it "maintains separate contexts in concurrent execution" do
      agents = [agent_class.new(name: "Agent1"), agent_class.new(name: "Agent2")]
      tools = [modern_tool_class.new(name: "Tool1"), modern_tool_class.new(name: "Tool2")]
      
      # Set up tracers for new components
      agents.each { |a| allow(a).to receive(:tracer).and_return(mock_tracer) }
      tools.each { |t| allow(t).to receive(:tracer).and_return(mock_tracer) }
      
      agents.each_with_index { |agent, i| agent.add_tool(tools[i]) }
      
      threads = agents.map.with_index do |agent, i|
        Thread.new do
          agent.run_with_tools("input #{i}")
        end
      end
      
      results = threads.map(&:value)
      
      expect(results).to eq([["Processed: input 0"], ["Processed: input 1"]])
      
      # Each thread should have created independent trace contexts
      trace_ids = captured_spans.map { |span| span[:trace_id] }.uniq
      expect(trace_ids.length).to be >= 2 # At least 2 separate traces
    end
  end
end
