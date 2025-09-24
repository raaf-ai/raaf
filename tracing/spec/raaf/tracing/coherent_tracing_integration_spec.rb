# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF Coherent Tracing Integration" do
  # Test classes that demonstrate proper coherent tracing usage
  let(:test_pipeline_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :pipeline

      attr_reader :name, :current_span, :agents

      def initialize(name: "TestPipeline", agents: [])
        @name = name
        @agents = agents
      end

      def self.name
        "TestPipeline"
      end

      def execute
        with_tracing(:execute) do
          agents.each(&:run)
          "Pipeline completed"
        end
      end

      def collect_span_attributes
        super.merge({
          "pipeline.agents_count" => agents.size,
          "pipeline.name" => name
        })
      end
    end
  end

  let(:test_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent

      attr_reader :name, :current_span, :parent_component

      def initialize(name: "TestAgent", parent_component: nil)
        @name = name
        @parent_component = parent_component
      end

      def self.name
        "TestAgent"
      end

      def run
        with_tracing(:run) do
          "Agent #{name} completed"
        end
      end

      def collect_span_attributes
        super.merge({
          "agent.name" => name,
          "agent.model" => "test-model"
        })
      end
    end
  end

  let(:test_tool_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :tool

      attr_reader :name, :current_span, :parent_component

      def initialize(name: "TestTool", parent_component: nil)
        @name = name
        @parent_component = parent_component
      end

      def self.name
        "TestTool"
      end

      def execute(args = {})
        with_tracing(:execute) do
          "Tool #{name} executed with #{args}"
        end
      end

      def collect_span_attributes
        super.merge({
          "tool.name" => name,
          "tool.type" => "test_tool"
        })
      end
    end
  end

  describe "Coherent Span Hierarchy" do
    it "maintains proper parent-child relationships in complex workflows" do
      # Set up mock tracer to capture spans
      captured_spans = []
      mock_tracer = double("tracer")
      allow(mock_tracer).to receive(:processors).and_return([])

      mock_processor = double("processor")
      allow(mock_processor).to receive(:on_span_end) do |span|
        captured_spans << {
          span_id: span.span_id,
          parent_id: span.parent_id,
          trace_id: span.trace_id,
          name: span.name,
          kind: span.kind,
          attributes: span.attributes
        }
      end

      allow(mock_tracer).to receive(:processors).and_return([mock_processor])

      # Create agents with parent component reference
      agent1 = test_agent_class.new(name: "Agent1")
      agent2 = test_agent_class.new(name: "Agent2")
      tool1 = test_tool_class.new(name: "Calculator")

      pipeline = test_pipeline_class.new(name: "MainPipeline", agents: [agent1, agent2])

      # Set up parent-child relationships
      agent1.instance_variable_set(:@parent_component, pipeline)
      agent2.instance_variable_set(:@parent_component, pipeline)
      tool1.instance_variable_set(:@parent_component, agent1)

      # Mock the tracer method on all components
      [pipeline, agent1, agent2, tool1].each do |component|
        allow(component).to receive(:tracer).and_return(mock_tracer)
      end

      # Execute the workflow
      pipeline.with_tracing(:execute) do
        pipeline_span = pipeline.current_span

        agent1.with_tracing(:run) do
          agent1_span = agent1.current_span

          tool1.with_tracing(:execute) do
            tool1_span = tool1.current_span

            # Verify hierarchy during execution
            expect(agent1_span[:parent_id]).to eq(pipeline_span[:span_id])
            expect(tool1_span[:parent_id]).to eq(agent1_span[:span_id])
            expect(agent1_span[:trace_id]).to eq(pipeline_span[:trace_id])
            expect(tool1_span[:trace_id]).to eq(pipeline_span[:trace_id])
          end
        end

        agent2.with_tracing(:run) do
          agent2_span = agent2.current_span

          # Verify second agent is also a child of pipeline
          expect(agent2_span[:parent_id]).to eq(pipeline_span[:span_id])
          expect(agent2_span[:trace_id]).to eq(pipeline_span[:trace_id])
        end
      end

      # Verify captured spans structure
      expect(captured_spans).not_to be_empty

      # Find spans by name patterns
      pipeline_span = captured_spans.find { |s| s[:name].include?("pipeline") }
      agent1_span = captured_spans.find { |s| s[:name].include?("Agent1") }
      agent2_span = captured_spans.find { |s| s[:name].include?("Agent2") }
      tool_span = captured_spans.find { |s| s[:name].include?("tool") }

      expect(pipeline_span).to be_present
      expect(agent1_span).to be_present
      expect(agent2_span).to be_present
      expect(tool_span).to be_present

      # Verify hierarchy
      expect(pipeline_span[:parent_id]).to be_nil # Root span
      expect(agent1_span[:parent_id]).to eq(pipeline_span[:span_id])
      expect(agent2_span[:parent_id]).to eq(pipeline_span[:span_id])
      expect(tool_span[:parent_id]).to eq(agent1_span[:span_id])

      # Verify all spans share the same trace ID
      trace_id = pipeline_span[:trace_id]
      expect(agent1_span[:trace_id]).to eq(trace_id)
      expect(agent2_span[:trace_id]).to eq(trace_id)
      expect(tool_span[:trace_id]).to eq(trace_id)
    end

    it "correctly handles nested span creation and cleanup" do
      pipeline = test_pipeline_class.new
      agent = test_agent_class.new(parent_component: pipeline)

      outer_span = nil
      inner_span = nil
      final_span = nil

      pipeline.with_tracing(:execute) do
        outer_span = pipeline.current_span

        agent.with_tracing(:run) do
          inner_span = agent.current_span

          # Verify nesting
          expect(inner_span[:parent_id]).to eq(outer_span[:span_id])
          expect(agent.current_span).to eq(inner_span)
        end

        # Verify cleanup - agent should no longer have current span
        expect(agent.current_span).to be_nil
        expect(pipeline.current_span).to eq(outer_span)
      end

      # Verify all spans are cleaned up
      expect(pipeline.current_span).to be_nil
      expect(agent.current_span).to be_nil
    end
  end

  describe "Span Attribute Validation" do
    it "includes component-specific attributes in spans" do
      captured_attributes = {}
      mock_tracer = double("tracer")

      mock_processor = double("processor")
      allow(mock_processor).to receive(:on_span_end) do |span|
        captured_attributes[span.kind] = span.attributes
      end

      allow(mock_tracer).to receive(:processors).and_return([mock_processor])

      pipeline = test_pipeline_class.new(name: "TestPipeline")
      agent = test_agent_class.new(name: "TestAgent", parent_component: pipeline)
      tool = test_tool_class.new(name: "TestTool", parent_component: agent)

      [pipeline, agent, tool].each do |component|
        allow(component).to receive(:tracer).and_return(mock_tracer)
      end

      # Execute nested workflow
      pipeline.with_tracing(:execute) do
        agent.with_tracing(:run) do
          tool.with_tracing(:execute) do
            # Just execute to generate spans
          end
        end
      end

      # Verify pipeline attributes
      pipeline_attrs = captured_attributes[:pipeline]
      expect(pipeline_attrs["component.type"]).to eq("pipeline")
      expect(pipeline_attrs["component.name"]).to eq("TestPipeline")
      expect(pipeline_attrs["pipeline.name"]).to eq("TestPipeline")
      expect(pipeline_attrs["pipeline.agents_count"]).to eq(0)

      # Verify agent attributes
      agent_attrs = captured_attributes[:agent]
      expect(agent_attrs["component.type"]).to eq("agent")
      expect(agent_attrs["component.name"]).to eq("TestAgent")
      expect(agent_attrs["agent.name"]).to eq("TestAgent")
      expect(agent_attrs["agent.model"]).to eq("test-model")

      # Verify tool attributes
      tool_attrs = captured_attributes[:tool]
      expect(tool_attrs["component.type"]).to eq("tool")
      expect(tool_attrs["component.name"]).to eq("TestTool")
      expect(tool_attrs["tool.name"]).to eq("TestTool")
      expect(tool_attrs["tool.type"]).to eq("test_tool")
    end

    it "includes timing and success metrics" do
      captured_span = nil
      mock_tracer = double("tracer")

      mock_processor = double("processor")
      allow(mock_processor).to receive(:on_span_end) do |span|
        captured_span = span
      end

      allow(mock_tracer).to receive(:processors).and_return([mock_processor])

      agent = test_agent_class.new
      allow(agent).to receive(:tracer).and_return(mock_tracer)

      # Execute with a small delay to measure timing
      agent.with_tracing(:run) do
        sleep(0.01) # 10ms delay
        "success"
      end

      expect(captured_span.attributes["duration_ms"]).to be > 10
      expect(captured_span.attributes["success"]).to be(true)
      expect(captured_span.status).to eq(:ok)
    end

    it "captures error information in spans" do
      captured_span = nil
      mock_tracer = double("tracer")

      mock_processor = double("processor")
      allow(mock_processor).to receive(:on_span_end) do |span|
        captured_span = span
      end

      allow(mock_tracer).to receive(:processors).and_return([mock_processor])

      agent = test_agent_class.new
      allow(agent).to receive(:tracer).and_return(mock_tracer)

      # Execute with error
      expect {
        agent.with_tracing(:run) do
          raise StandardError, "Test error"
        end
      }.to raise_error(StandardError, "Test error")

      expect(captured_span.attributes["success"]).to be(false)
      expect(captured_span.attributes["error.type"]).to eq("StandardError")
      expect(captured_span.attributes["error.message"]).to eq("Test error")
      expect(captured_span.attributes["error.backtrace"]).to be_a(String)
      expect(captured_span.status).to eq(:error)
    end
  end

  describe "Span Name Generation" do
    it "generates consistent span names following RAAF conventions" do
      captured_spans = []
      mock_tracer = double("tracer")

      mock_processor = double("processor")
      allow(mock_processor).to receive(:on_span_end) do |span|
        captured_spans << { name: span.name, kind: span.kind }
      end

      allow(mock_tracer).to receive(:processors).and_return([mock_processor])

      pipeline = test_pipeline_class.new
      agent = test_agent_class.new(parent_component: pipeline)
      tool = test_tool_class.new(parent_component: agent)

      [pipeline, agent, tool].each do |component|
        allow(component).to receive(:tracer).and_return(mock_tracer)
      end

      # Execute workflow with different methods
      pipeline.with_tracing(:execute) do
        agent.with_tracing(:run) do
          tool.with_tracing(:execute) do
            # Generate spans
          end
        end
      end

      # Verify span names follow RAAF convention
      span_names = captured_spans.map { |s| s[:name] }

      expect(span_names).to include("run.workflow.pipeline.TestPipeline.execute")
      expect(span_names).to include("run.workflow.agent.TestAgent")
      expect(span_names).to include("run.workflow.tool.TestTool.execute")
    end
  end

  describe "Duplicate Span Prevention" do
    it "prevents duplicate spans when reusing compatible contexts" do
      captured_spans = []
      mock_tracer = double("tracer")

      mock_processor = double("processor")
      allow(mock_processor).to receive(:on_span_end) do |span|
        captured_spans << span.span_id
      end

      allow(mock_tracer).to receive(:processors).and_return([mock_processor])

      agent = test_agent_class.new
      allow(agent).to receive(:tracer).and_return(mock_tracer)

      # Execute nested run methods that should reuse spans
      agent.with_tracing(:run) do
        first_span_id = agent.current_span[:span_id]

        # Nested run should reuse the same span
        agent.with_tracing(:run) do
          second_span_id = agent.current_span[:span_id]
          expect(first_span_id).to eq(second_span_id)
        end
      end

      # Should only have one span captured
      expect(captured_spans.uniq.size).to eq(1)
    end
  end

  describe "Thread Safety" do
    it "maintains separate trace contexts across threads" do
      captured_spans = []
      captured_spans_mutex = Mutex.new

      mock_tracer = double("tracer")
      mock_processor = double("processor")

      allow(mock_processor).to receive(:on_span_end) do |span|
        captured_spans_mutex.synchronize do
          captured_spans << {
            span_id: span.span_id,
            trace_id: span.trace_id,
            thread_id: Thread.current.object_id,
            name: span.name
          }
        end
      end

      allow(mock_tracer).to receive(:processors).and_return([mock_processor])

      # Create agents for each thread
      agent1 = test_agent_class.new(name: "Agent1")
      agent2 = test_agent_class.new(name: "Agent2")

      [agent1, agent2].each do |agent|
        allow(agent).to receive(:tracer).and_return(mock_tracer)
      end

      threads = []

      # Start concurrent tracing in different threads
      threads << Thread.new do
        agent1.with_tracing(:run) do
          sleep(0.02) # Small delay to ensure overlap
        end
      end

      threads << Thread.new do
        agent2.with_tracing(:run) do
          sleep(0.02) # Small delay to ensure overlap
        end
      end

      threads.each(&:join)

      # Verify we have spans from both threads
      expect(captured_spans.size).to eq(2)

      thread_ids = captured_spans.map { |s| s[:thread_id] }.uniq
      expect(thread_ids.size).to eq(2)

      # Verify spans have different trace IDs (separate traces)
      trace_ids = captured_spans.map { |s| s[:trace_id] }.uniq
      expect(trace_ids.size).to eq(2)
    end
  end
end