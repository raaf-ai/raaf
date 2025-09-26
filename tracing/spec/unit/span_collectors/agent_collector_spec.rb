# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::SpanCollectors::AgentCollector do
  let(:agent) do
    double("Agent",
      class: double("AgentClass", name: "RAAF::Agent"),
      name: "TestAgent",
      model: "gpt-4o",
      max_turns: 5,
      tools: ["tool1", "tool2"],
      handoffs: ["agent1", "agent2"]
    ).tap do |agent|
      # Set default respond_to? behavior for common methods
      allow(agent).to receive(:respond_to?).and_return(false)
      allow(agent).to receive(:respond_to?).with(:name).and_return(true)
      allow(agent).to receive(:respond_to?).with(:model).and_return(true)
      allow(agent).to receive(:respond_to?).with(:max_turns).and_return(true)
      allow(agent).to receive(:respond_to?).with(:tools).and_return(true)
      allow(agent).to receive(:respond_to?).with(:handoffs).and_return(true)
      allow(agent).to receive(:respond_to?).with(:trace_metadata).and_return(false)
    end
  end

  let(:collector) { described_class.new }

  describe "DSL declarations" do
    it "declares simple span attributes" do
      expect(described_class.instance_variable_get(:@span_attrs)).to include(:name, :model)
    end

    it "declares custom span attributes with lambdas" do
      custom_attrs = described_class.instance_variable_get(:@span_custom)
      expect(custom_attrs).to have_key(:max_turns)
      expect(custom_attrs).to have_key(:tools_count)
      expect(custom_attrs).to have_key(:handoffs_count)
      expect(custom_attrs).to have_key(:workflow_name)
      expect(custom_attrs).to have_key(:dsl_metadata)
    end
  end

  describe "#collect_attributes" do
    it "collects base attributes" do
      attributes = collector.collect_attributes(agent)

      expect(attributes).to include("component.type")
      expect(attributes).to include("component.name")
      expect(attributes["component.name"]).to eq("RAAF::Agent")
    end

    it "collects simple agent attributes" do
      attributes = collector.collect_attributes(agent)

      # Find keys with agent prefix
      name_key = attributes.keys.find { |k| k.end_with?(".name") && !k.start_with?("component.") }
      model_key = attributes.keys.find { |k| k.end_with?(".model") }

      expect(attributes[name_key]).to eq("TestAgent")
      expect(attributes[model_key]).to eq("gpt-4o")
    end

    it "collects max_turns with safe handling" do
      attributes = collector.collect_attributes(agent)
      max_turns_key = attributes.keys.find { |k| k.end_with?(".max_turns") }
      expect(attributes[max_turns_key]).to eq("5")
    end

    it "handles missing max_turns gracefully" do
      allow(agent).to receive(:respond_to?).with(:max_turns).and_return(false)
      attributes = collector.collect_attributes(agent)
      max_turns_key = attributes.keys.find { |k| k.end_with?(".max_turns") }
      expect(attributes[max_turns_key]).to eq("N/A")
    end

    it "collects tools count" do
      attributes = collector.collect_attributes(agent)
      tools_count_key = attributes.keys.find { |k| k.end_with?(".tools_count") }
      expect(attributes[tools_count_key]).to eq("2")
    end

    it "handles missing tools gracefully" do
      allow(agent).to receive(:respond_to?).with(:tools).and_return(false)
      attributes = collector.collect_attributes(agent)
      tools_count_key = attributes.keys.find { |k| k.end_with?(".tools_count") }
      expect(attributes[tools_count_key]).to eq("0")
    end

    it "collects handoffs count" do
      attributes = collector.collect_attributes(agent)
      handoffs_count_key = attributes.keys.find { |k| k.end_with?(".handoffs_count") }
      expect(attributes[handoffs_count_key]).to eq("2")
    end

    it "handles missing handoffs gracefully" do
      allow(agent).to receive(:respond_to?).with(:handoffs).and_return(false)
      attributes = collector.collect_attributes(agent)
      handoffs_count_key = attributes.keys.find { |k| k.end_with?(".handoffs_count") }
      expect(attributes[handoffs_count_key]).to eq("0")
    end

    it "collects workflow name from thread context" do
      job_span_class = double("JobClass", name: "TestJob")
      job_span = double("JobSpan", class: job_span_class)
      Thread.current[:raaf_job_span] = job_span

      attributes = collector.collect_attributes(agent)
      workflow_name_key = attributes.keys.find { |k| k.end_with?(".workflow_name") }
      expect(attributes[workflow_name_key]).to eq("TestJob")

      Thread.current[:raaf_job_span] = nil
    end

    it "handles missing workflow name gracefully" do
      Thread.current[:raaf_job_span] = nil

      attributes = collector.collect_attributes(agent)
      workflow_name_key = attributes.keys.find { |k| k.end_with?(".workflow_name") }
      expect(attributes[workflow_name_key]).to be_nil
    end

    it "collects DSL metadata when available" do
      trace_metadata = { version: "1.0", mode: "test" }
      allow(agent).to receive(:respond_to?).with(:trace_metadata).and_return(true)
      allow(agent).to receive(:trace_metadata).and_return(trace_metadata)

      attributes = collector.collect_attributes(agent)
      dsl_metadata_key = attributes.keys.find { |k| k.end_with?(".dsl_metadata") }
      expect(attributes[dsl_metadata_key]).to eq("version:1.0,mode:test")
    end

    it "handles missing DSL metadata gracefully" do
      allow(agent).to receive(:respond_to?).with(:trace_metadata).and_return(false)

      attributes = collector.collect_attributes(agent)
      dsl_metadata_key = attributes.keys.find { |k| k.end_with?(".dsl_metadata") }
      expect(attributes[dsl_metadata_key]).to be_nil
    end

    it "handles empty DSL metadata gracefully" do
      allow(agent).to receive(:respond_to?).with(:trace_metadata).and_return(true)
      allow(agent).to receive(:trace_metadata).and_return({})

      attributes = collector.collect_attributes(agent)
      dsl_metadata_key = attributes.keys.find { |k| k.end_with?(".dsl_metadata") }
      expect(attributes[dsl_metadata_key]).to be_nil
    end
  end

  describe "#collect_result" do
    let(:result) { { success: true, message: "Task completed" } }

    it "collects base result attributes" do
      attributes = collector.collect_result(agent, result)

      expect(attributes).to include("result.type")
      expect(attributes).to include("result.success")
      expect(attributes["result.type"]).to eq("Hash")
      expect(attributes["result.success"]).to be true
    end

    it "handles nil result" do
      attributes = collector.collect_result(agent, nil)

      expect(attributes["result.type"]).to eq("NilClass")
      expect(attributes["result.success"]).to be false
    end
  end

  describe "component prefix" do
    it "generates correct prefix for agent collector" do
      # This will be something like "raaf::tracing::spancollectors::agent"
      prefix = collector.send(:component_prefix)
      expect(prefix).to match(/agent$/)
    end
  end
end
