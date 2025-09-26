# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::SpanCollectors do
  describe ".collector_for" do
    let(:dsl_agent_class) { double("DSLAgentClass", name: "RAAF::DSL::Agent") }
    let(:dsl_agent) { double("DSLAgent", class: dsl_agent_class) }
    
    let(:core_agent_class) { double("CoreAgentClass", name: "RAAF::Agent") }
    let(:core_agent) { double("CoreAgent", class: core_agent_class) }
    
    let(:tool_class) { double("ToolClass", name: "MyCustomTool") }
    let(:tool_component) { double("Tool", class: tool_class) }
    
    let(:pipeline_class) { double("PipelineClass", name: "DataProcessingPipeline") }
    let(:pipeline_component) { double("Pipeline", class: pipeline_class) }
    
    let(:job_class) { double("JobClass", name: "ProcessingJob") }
    let(:job_component) { double("Job", class: job_class) }
    
    let(:unknown_class) { double("UnknownClass", name: "SomeRandomClass") }
    let(:unknown_component) { double("Unknown", class: unknown_class) }
    
    before do
      # Ensure clean state for each test
      # Remove any existing constants to avoid conflicts
      begin
        RAAF::Tracing::SpanCollectors.send(:remove_const, :DSL) if defined?(RAAF::Tracing::SpanCollectors::DSL)
      rescue NameError
        # Constant doesn't exist, that's fine
      end
      
      # Create the DSL module and AgentCollector class for testing
      unless defined?(RAAF::Tracing::SpanCollectors::DSL)
        RAAF::Tracing::SpanCollectors.const_set(:DSL, Module.new)
      end
      
      unless defined?(RAAF::Tracing::SpanCollectors::DSL::AgentCollector)
        test_dsl_collector = Class.new(RAAF::Tracing::SpanCollectors::BaseCollector)
        RAAF::Tracing::SpanCollectors::DSL.const_set(:AgentCollector, test_dsl_collector)
      end
      
      unless defined?(RAAF::Tracing::SpanCollectors::AgentCollector)
        test_agent_collector = Class.new(RAAF::Tracing::SpanCollectors::BaseCollector)
        RAAF::Tracing::SpanCollectors.const_set(:AgentCollector, test_agent_collector)
      end
      
      unless defined?(RAAF::Tracing::SpanCollectors::ToolCollector)
        test_tool_collector = Class.new(RAAF::Tracing::SpanCollectors::BaseCollector)
        RAAF::Tracing::SpanCollectors.const_set(:ToolCollector, test_tool_collector)
      end
      
      unless defined?(RAAF::Tracing::SpanCollectors::PipelineCollector)
        test_pipeline_collector = Class.new(RAAF::Tracing::SpanCollectors::BaseCollector)
        RAAF::Tracing::SpanCollectors.const_set(:PipelineCollector, test_pipeline_collector)
      end
      
      unless defined?(RAAF::Tracing::SpanCollectors::JobCollector)
        test_job_collector = Class.new(RAAF::Tracing::SpanCollectors::BaseCollector)
        RAAF::Tracing::SpanCollectors.const_set(:JobCollector, test_job_collector)
      end
    end
    
    it "returns DSL::AgentCollector for RAAF::DSL::Agent" do
      collector = described_class.collector_for(dsl_agent)
      expect(collector).to be_a(RAAF::Tracing::SpanCollectors::DSL::AgentCollector)
    end
    
    it "returns AgentCollector for RAAF::Agent" do
      collector = described_class.collector_for(core_agent)
      expect(collector).to be_a(RAAF::Tracing::SpanCollectors::AgentCollector)
    end
    
    it "returns ToolCollector for classes ending with 'Tool'" do
      collector = described_class.collector_for(tool_component)
      expect(collector).to be_a(RAAF::Tracing::SpanCollectors::ToolCollector)
    end
    
    it "returns PipelineCollector for classes ending with 'Pipeline'" do
      collector = described_class.collector_for(pipeline_component)
      expect(collector).to be_a(RAAF::Tracing::SpanCollectors::PipelineCollector)
    end
    
    it "returns JobCollector for classes ending with 'Job'" do
      collector = described_class.collector_for(job_component)
      expect(collector).to be_a(RAAF::Tracing::SpanCollectors::JobCollector)
    end
    
    it "returns BaseCollector as ultimate fallback" do
      collector = described_class.collector_for(unknown_component)
      expect(collector).to be_a(RAAF::Tracing::SpanCollectors::BaseCollector)
      expect(collector.class).to eq(RAAF::Tracing::SpanCollectors::BaseCollector)
    end
    
    context "with specific collector classes" do
      let(:custom_class) { double("CustomClass", name: "MyAgentCollector") }
      let(:custom_component) { double("Custom", class: custom_class) }
      
      before do
        # Create a test collector class that would match naming convention
        unless defined?(RAAF::Tracing::SpanCollectors::MyAgentCollectorCollector)
          test_custom_collector = Class.new(RAAF::Tracing::SpanCollectors::BaseCollector)
          RAAF::Tracing::SpanCollectors.const_set(:MyAgentCollectorCollector, test_custom_collector)
        end
      end
      
      it "uses naming convention for exact matches" do
        # For MyAgentCollector component, it should look for MyAgentCollectorCollector
        collector = described_class.collector_for(custom_component)
        expect(collector).to be_a(RAAF::Tracing::SpanCollectors::MyAgentCollectorCollector)
      end
    end
    
    context "with nested class names" do
      let(:nested_class) { double("NestedClass", name: "MyModule::CustomAgent") }
      let(:nested_component) { double("Nested", class: nested_class) }
      
      before do
        unless defined?(RAAF::Tracing::SpanCollectors::CustomAgentCollector)
          test_nested_collector = Class.new(RAAF::Tracing::SpanCollectors::BaseCollector)
          RAAF::Tracing::SpanCollectors.const_set(:CustomAgentCollector, test_nested_collector)
        end
      end
      
      it "handles nested class names by using the last part" do
        collector = described_class.collector_for(nested_component)
        expect(collector).to be_a(RAAF::Tracing::SpanCollectors::CustomAgentCollector)
      end
    end
  end
end
