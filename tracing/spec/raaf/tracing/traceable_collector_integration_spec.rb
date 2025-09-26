# frozen_string_literal: true

require "spec_helper"
require "securerandom"

RSpec.describe RAAF::Tracing::Traceable, "collector integration" do
  # Mock collector classes that will be implemented
  let(:mock_base_collector_class) do
    Class.new do
      def self.collector_for(component)
        case component.class.name
        when "TestAgent"
          AgentCollector.new
        when "TestDSLAgent"
          DSLAgentCollector.new
        when "TestTool"
          ToolCollector.new
        when "TestPipeline"
          PipelineCollector.new
        when "TestJob"
          JobCollector.new
        else
          BaseCollector.new
        end
      end
      
      class BaseCollector
        def collect_attributes(component)
          {
            "component.type" => component.class.trace_component_type.to_s,
            "component.class" => component.class.name
          }
        end
        
        def collect_result(component, result)
          {
            "result.type" => result.class.name,
            "result.success" => !result.nil?
          }
        end
      end
      
      class AgentCollector < BaseCollector
        def collect_attributes(component)
          base_attrs = super(component)
          base_attrs.merge(
            "agent.name" => component.respond_to?(:name) ? component.name : "unknown",
            "agent.model" => component.respond_to?(:model) ? component.model : "gpt-4o",
            "agent.max_turns" => component.respond_to?(:max_turns) ? component.max_turns.to_s : "5"
          )
        end
      end
      
      class DSLAgentCollector < BaseCollector
        def collect_attributes(component)
          base_attrs = super(component)
          base_attrs.merge(
            "dsl_agent.name" => component.respond_to?(:agent_name) ? component.agent_name : "unknown",
            "dsl_agent.context_size" => component.respond_to?(:context) && component.context ? component.context.size.to_s : "0"
          )
        end
      end
      
      class ToolCollector < BaseCollector
        def collect_attributes(component)
          base_attrs = super(component)
          base_attrs.merge(
            "tool.name" => component.class.name,
            "tool.method" => component.respond_to?(:method_name) ? component.method_name.to_s : "unknown"
          )
        end
      end
      
      class PipelineCollector < BaseCollector
        def collect_attributes(component)
          base_attrs = super(component)
          base_attrs.merge(
            "pipeline.name" => component.respond_to?(:pipeline_name) ? component.pipeline_name : component.class.name,
            "pipeline.agent_count" => component.respond_to?(:agent_count) ? component.agent_count.to_s : "0"
          )
        end
      end
      
      class JobCollector < BaseCollector
        def collect_attributes(component)
          base_attrs = super(component)
          base_attrs.merge(
            "job.queue" => component.respond_to?(:queue_name) ? component.queue_name : "default",
            "job.arguments" => component.respond_to?(:arguments) ? component.arguments.inspect[0..100] : "N/A"
          )
        end
      end
    end
  end
  
  # Create test classes that include the Traceable module
  let(:test_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent
      
      attr_reader :name, :model, :max_turns, :current_span
      
      def initialize(name: "TestAgent", model: "gpt-4o", max_turns: 5)
        @name = name
        @model = model
        @max_turns = max_turns
      end
      
      def self.name
        "TestAgent"
      end
    end
  end
  
  let(:test_dsl_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent
      
      attr_reader :agent_name, :context, :current_span
      
      def initialize(agent_name: "TestDSLAgent", context: {test: "data"})
        @agent_name = agent_name
        @context = context
      end
      
      def self.name
        "TestDSLAgent"
      end
    end
  end
  
  let(:test_tool_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :tool
      
      attr_reader :method_name, :current_span
      
      def initialize(method_name: "execute")
        @method_name = method_name
      end
      
      def self.name
        "TestTool"
      end
    end
  end
  
  let(:test_pipeline_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :pipeline
      
      attr_reader :pipeline_name, :agent_count, :current_span
      
      def initialize(pipeline_name: "TestPipeline", agent_count: 3)
        @pipeline_name = pipeline_name
        @agent_count = agent_count
      end
      
      def self.name
        "TestPipeline"
      end
    end
  end
  
  let(:test_job_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :job
      
      attr_reader :queue_name, :arguments, :current_span
      
      def initialize(queue_name: "default", arguments: ["arg1", "arg2"])
        @queue_name = queue_name
        @arguments = arguments
      end
      
      def self.name
        "TestJob"
      end
    end
  end
  
  let(:agent) { test_agent_class.new }
  let(:dsl_agent) { test_dsl_agent_class.new }
  let(:tool) { test_tool_class.new }
  let(:pipeline) { test_pipeline_class.new }
  let(:job) { test_job_class.new }
  
  before do
    # Mock the span collectors module to use our test implementation
    stub_const("RAAF::Tracing::SpanCollectors", mock_base_collector_class)
  end

  describe "collector delegation in collect_span_attributes" do
    it "delegates to collector for agent components" do
      attributes = agent.collect_span_attributes
      
      # Should include base collector attributes
      expect(attributes["component.type"]).to eq("agent")
      expect(attributes["component.class"]).to eq("TestAgent")
      
      # Should include agent-specific attributes from AgentCollector
      expect(attributes["agent.name"]).to eq("TestAgent")
      expect(attributes["agent.model"]).to eq("gpt-4o")
      expect(attributes["agent.max_turns"]).to eq("5")
    end
    
    it "delegates to collector for DSL agent components" do
      attributes = dsl_agent.collect_span_attributes
      
      # Should include base collector attributes
      expect(attributes["component.type"]).to eq("agent")
      expect(attributes["component.class"]).to eq("TestDSLAgent")
      
      # Should include DSL agent-specific attributes from DSLAgentCollector
      expect(attributes["dsl_agent.name"]).to eq("TestDSLAgent")
      expect(attributes["dsl_agent.context_size"]).to eq("1")
    end
    
    it "delegates to collector for tool components" do
      attributes = tool.collect_span_attributes
      
      # Should include base collector attributes
      expect(attributes["component.type"]).to eq("tool")
      expect(attributes["component.class"]).to eq("TestTool")
      
      # Should include tool-specific attributes from ToolCollector
      expect(attributes["tool.name"]).to eq("TestTool")
      expect(attributes["tool.method"]).to eq("execute")
    end
    
    it "delegates to collector for pipeline components" do
      attributes = pipeline.collect_span_attributes
      
      # Should include base collector attributes
      expect(attributes["component.type"]).to eq("pipeline")
      expect(attributes["component.class"]).to eq("TestPipeline")
      
      # Should include pipeline-specific attributes from PipelineCollector
      expect(attributes["pipeline.name"]).to eq("TestPipeline")
      expect(attributes["pipeline.agent_count"]).to eq("3")
    end
    
    it "delegates to collector for job components" do
      attributes = job.collect_span_attributes
      
      # Should include base collector attributes
      expect(attributes["component.type"]).to eq("job")
      expect(attributes["component.class"]).to eq("TestJob")
      
      # Should include job-specific attributes from JobCollector
      expect(attributes["job.queue"]).to eq("default")
      expect(attributes["job.arguments"]).to eq('["arg1", "arg2"]')
    end
    
    it "uses correct collector based on component class name" do
      # Mock the collector discovery to verify correct collector is selected
      expect(RAAF::Tracing::SpanCollectors).to receive(:collector_for).with(agent).and_call_original
      
      agent.collect_span_attributes
    end
  end
  
  describe "collector delegation in collect_result_attributes" do
    it "delegates result collection to appropriate collector" do
      result = "test result"
      attributes = agent.collect_result_attributes(result)
      
      # Should include base result attributes
      expect(attributes["result.type"]).to eq("String")
      expect(attributes["result.success"]).to be(true)
    end
    
    it "handles nil results correctly" do
      attributes = agent.collect_result_attributes(nil)
      
      expect(attributes["result.type"]).to eq("NilClass")
      expect(attributes["result.success"]).to be(false)
    end
    
    it "uses the same collector discovery mechanism for both span and result attributes" do
      # Mock collector discovery to count calls
      allow(RAAF::Tracing::SpanCollectors).to receive(:collector_for).with(agent).and_call_original

      # Both calls should use the same collector discovery mechanism
      agent.collect_span_attributes
      agent.collect_result_attributes("test")

      expect(RAAF::Tracing::SpanCollectors).to have_received(:collector_for).with(agent).twice
    end
  end
  
  describe "backward compatibility" do
    it "maintains existing behavior when collectors not available" do
      # Temporarily remove the collector module to test fallback
      hide_const("RAAF::Tracing::SpanCollectors")
      
      # Should fall back to the original implementation
      attributes = agent.collect_span_attributes
      
      expect(attributes["component.type"]).to eq("agent")
      expect(attributes["component.name"]).to eq("TestAgent")
    end
    
    it "gracefully handles collector errors" do
      # Mock collector to raise an error
      allow(RAAF::Tracing::SpanCollectors).to receive(:collector_for).and_raise(StandardError, "Collector error")
      
      # Should fall back to original implementation without raising
      expect { 
        attributes = agent.collect_span_attributes
        expect(attributes["component.type"]).to eq("agent")
      }.not_to raise_error
    end
  end
end
