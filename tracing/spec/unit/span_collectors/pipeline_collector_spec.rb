# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::SpanCollectors::PipelineCollector do
  let(:flow_structure) { "Agent1 >> Agent2 | Agent3" }
  let(:agent_count) { 3 }
  let(:context_fields) { [:product, :company, :analysis_depth] }
  
  let(:pipeline) do
    pipeline_class = double("PipelineClass",
      name: "RAAF::MarketDiscoveryPipeline",
      context_fields: context_fields
    ).tap do |klass|
      # Set up class method expectations
      allow(klass).to receive(:respond_to?).and_return(false)
      allow(klass).to receive(:respond_to?).with(:context_fields).and_return(true)
      allow(klass).to receive(:respond_to?).with(:trace_component_type).and_return(false)
    end

    double("Pipeline",
      class: pipeline_class,
      pipeline_name: "MarketDiscovery"
    ).tap do |pipeline|
      flow = double("Flow")
      pipeline.instance_variable_set(:@flow, flow)

      # Set up instance method expectations
      allow(pipeline).to receive(:respond_to?).and_return(false)
      allow(pipeline).to receive(:respond_to?).with(:pipeline_name).and_return(true)
      allow(pipeline).to receive(:respond_to?).with(:flow_structure_description).and_return(true)
      allow(pipeline).to receive(:respond_to?).with(:count_agents_in_flow).and_return(true)
      allow(pipeline).to receive(:flow_structure_description).with(flow).and_return(flow_structure)
      allow(pipeline).to receive(:count_agents_in_flow).with(flow).and_return(agent_count)
    end
  end

  let(:collector) { described_class.new }

  describe "DSL declarations" do
    it "declares custom span attributes with lambdas" do
      custom_attrs = described_class.instance_variable_get(:@span_custom)
      expect(custom_attrs).to have_key(:name)
      expect(custom_attrs).to have_key(:flow_structure)
      expect(custom_attrs).to have_key(:agent_count)
      expect(custom_attrs).to have_key(:context_fields)
    end

    it "declares result attributes" do
      result_attrs = described_class.instance_variable_get(:@result_custom)
      expect(result_attrs).to have_key(:execution_status)
    end
  end

  describe "#collect_attributes" do
    it "collects base attributes" do
      attributes = collector.collect_attributes(pipeline)

      expect(attributes).to include("component.type")
      expect(attributes).to include("component.name")
      expect(attributes["component.name"]).to eq("RAAF::MarketDiscoveryPipeline")
    end

    it "collects pipeline name" do
      attributes = collector.collect_attributes(pipeline)
      name_key = attributes.keys.find { |k| k.end_with?(".name") && !k.start_with?("component.") }
      expect(attributes[name_key]).to eq("MarketDiscovery")
    end

    it "falls back to class name when pipeline_name not available" do
      allow(pipeline).to receive(:respond_to?).with(:pipeline_name).and_return(false)
      
      attributes = collector.collect_attributes(pipeline)
      name_key = attributes.keys.find { |k| k.end_with?(".name") && !k.start_with?("component.") }
      expect(attributes[name_key]).to eq("RAAF::MarketDiscoveryPipeline")
    end

    it "collects flow structure description" do
      attributes = collector.collect_attributes(pipeline)
      flow_structure_key = attributes.keys.find { |k| k.end_with?(".flow_structure") }
      expect(attributes[flow_structure_key]).to eq("Agent1 >> Agent2 | Agent3")
    end

    it "handles missing flow structure description gracefully" do
      allow(pipeline).to receive(:respond_to?).with(:flow_structure_description).and_return(false)
      
      attributes = collector.collect_attributes(pipeline)
      flow_structure_key = attributes.keys.find { |k| k.end_with?(".flow_structure") }
      expect(attributes[flow_structure_key]).to be_nil
    end

    it "handles missing flow gracefully" do
      pipeline.instance_variable_set(:@flow, nil)
      
      attributes = collector.collect_attributes(pipeline)
      flow_structure_key = attributes.keys.find { |k| k.end_with?(".flow_structure") }
      expect(attributes[flow_structure_key]).to be_nil
    end

    it "collects agent count from flow" do
      attributes = collector.collect_attributes(pipeline)
      agent_count_key = attributes.keys.find { |k| k.end_with?(".agent_count") }
      expect(attributes[agent_count_key]).to eq(3)
    end

    it "handles missing agent count method gracefully" do
      allow(pipeline).to receive(:respond_to?).with(:count_agents_in_flow).and_return(false)
      
      attributes = collector.collect_attributes(pipeline)
      agent_count_key = attributes.keys.find { |k| k.end_with?(".agent_count") }
      expect(attributes[agent_count_key]).to be_nil
    end

    it "collects context fields from class" do
      attributes = collector.collect_attributes(pipeline)
      context_fields_key = attributes.keys.find { |k| k.end_with?(".context_fields") }
      # Context fields are converted to strings by safe_value processing
      expect(attributes[context_fields_key]).to eq(["product", "company", "analysis_depth"])
    end

    it "handles missing context fields gracefully" do
      allow(pipeline.class).to receive(:respond_to?).with(:context_fields).and_return(false)
      
      attributes = collector.collect_attributes(pipeline)
      context_fields_key = attributes.keys.find { |k| k.end_with?(".context_fields") }
      expect(attributes[context_fields_key]).to eq([])
    end
  end

  describe "#collect_result" do
    it "collects base result attributes" do
      result = { success: true, markets: ["market1", "market2"] }
      attributes = collector.collect_result(pipeline, result)

      expect(attributes).to include("result.type")
      expect(attributes).to include("result.success")
      expect(attributes["result.type"]).to eq("Hash")
      expect(attributes["result.success"]).to be true
    end

    it "determines execution status as success for successful hash results" do
      result = { success: true, data: "completed" }
      attributes = collector.collect_result(pipeline, result)

      expect(attributes).to include("result.execution_status")
      expect(attributes["result.execution_status"]).to eq("success")
    end

    it "determines execution status as failure for failed hash results" do
      result = { success: false, error: "failed" }
      attributes = collector.collect_result(pipeline, result)

      expect(attributes["result.execution_status"]).to eq("failure")
    end

    it "determines execution status as failure for non-hash results" do
      result = "some string result"
      attributes = collector.collect_result(pipeline, result)

      expect(attributes["result.execution_status"]).to eq("failure")
    end

    it "determines execution status as failure for hash without success key" do
      result = { data: "completed" }
      attributes = collector.collect_result(pipeline, result)

      expect(attributes["result.execution_status"]).to eq("failure")
    end

    it "handles nil result" do
      attributes = collector.collect_result(pipeline, nil)

      expect(attributes["result.type"]).to eq("NilClass")
      expect(attributes["result.success"]).to be false
      expect(attributes["result.execution_status"]).to eq("failure")
    end
  end

  describe "component prefix" do
    it "generates correct prefix for pipeline collector" do
      prefix = collector.send(:component_prefix)
      expect(prefix).to match(/pipeline$/)
    end
  end
end
