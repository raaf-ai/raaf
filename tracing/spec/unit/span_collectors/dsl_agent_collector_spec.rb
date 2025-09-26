# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::SpanCollectors::DSL::AgentCollector do
  let(:dsl_agent) do
    agent_class = double("DSLAgentClass",
      name: "RAAF::DSL::Agent",
      _context_config: {
        model: "gpt-4o-mini",
        max_turns: 3,
        temperature: 0.7
      }
    ).tap do |klass|
      # Set up class method expectations
      allow(klass).to receive(:respond_to?).and_return(false)
      allow(klass).to receive(:respond_to?).with(:_context_config).and_return(true)
      allow(klass).to receive(:respond_to?).with(:trace_component_type).and_return(false)
    end

    double("DSLAgent",
      class: agent_class,
      agent_name: "DSLTestAgent",
      tools: ["search", "calculate"],
      handoffs: ["writer_agent"]
    ).tap do |agent|
      agent.instance_variable_set(:@context, { query: "test", depth: "deep" })
      # Set up instance method expectations
      allow(agent).to receive(:respond_to?).and_return(false)
      allow(agent).to receive(:respond_to?).with(:agent_name).and_return(true)
      allow(agent).to receive(:respond_to?).with(:tools).and_return(true)
      allow(agent).to receive(:respond_to?).with(:handoffs).and_return(true)
      allow(agent).to receive(:respond_to?).with(:has_smart_features?).and_return(true)
      allow(agent).to receive(:has_smart_features?).and_return(true)
    end
  end

  let(:collector) { described_class.new }

  describe "DSL declarations" do
    it "declares custom span attributes with lambdas" do
      custom_attrs = described_class.instance_variable_get(:@span_custom)
      expect(custom_attrs).to have_key(:name)
      expect(custom_attrs).to have_key(:model)
      expect(custom_attrs).to have_key(:max_turns)
      expect(custom_attrs).to have_key(:temperature)
      expect(custom_attrs).to have_key(:context_size)
      expect(custom_attrs).to have_key(:has_tools)
      expect(custom_attrs).to have_key(:execution_mode)
      expect(custom_attrs).to have_key(:tools_count)
      expect(custom_attrs).to have_key(:handoffs_count)
    end
  end

  describe "#collect_attributes" do
    it "collects base attributes" do
      attributes = collector.collect_attributes(dsl_agent)

      expect(attributes).to include("component.type")
      expect(attributes).to include("component.name")
      expect(attributes["component.name"]).to eq("RAAF::DSL::Agent")
    end

    it "collects DSL agent name" do
      attributes = collector.collect_attributes(dsl_agent)
      name_key = attributes.keys.find { |k| k.end_with?(".name") && !k.start_with?("component.") }
      expect(attributes[name_key]).to eq("DSLTestAgent")
    end

    it "falls back to class name when agent_name not available" do
      allow(dsl_agent).to receive(:respond_to?).with(:agent_name).and_return(false)
      
      attributes = collector.collect_attributes(dsl_agent)
      name_key = attributes.keys.find { |k| k.end_with?(".name") && !k.start_with?("component.") }
      expect(attributes[name_key]).to eq("RAAF::DSL::Agent")
    end

    it "collects model from context config" do
      attributes = collector.collect_attributes(dsl_agent)
      model_key = attributes.keys.find { |k| k.end_with?(".model") }
      expect(attributes[model_key]).to eq("gpt-4o-mini")
    end

    it "falls back to default model when context config not available" do
      allow(dsl_agent.class).to receive(:respond_to?).with(:_context_config).and_return(false)
      
      attributes = collector.collect_attributes(dsl_agent)
      model_key = attributes.keys.find { |k| k.end_with?(".model") }
      expect(attributes[model_key]).to eq("gpt-4o")
    end

    it "collects max_turns from context config" do
      attributes = collector.collect_attributes(dsl_agent)
      max_turns_key = attributes.keys.find { |k| k.end_with?(".max_turns") }
      expect(attributes[max_turns_key]).to eq("3")
    end

    it "falls back to default max_turns when context config not available" do
      allow(dsl_agent.class).to receive(:respond_to?).with(:_context_config).and_return(false)
      
      attributes = collector.collect_attributes(dsl_agent)
      max_turns_key = attributes.keys.find { |k| k.end_with?(".max_turns") }
      expect(attributes[max_turns_key]).to eq("5")
    end

    it "collects temperature from context config" do
      attributes = collector.collect_attributes(dsl_agent)
      temperature_key = attributes.keys.find { |k| k.end_with?(".temperature") }
      expect(attributes[temperature_key]).to eq(0.7)
    end

    it "handles missing temperature gracefully" do
      allow(dsl_agent.class).to receive(:respond_to?).with(:_context_config).and_return(false)
      
      attributes = collector.collect_attributes(dsl_agent)
      temperature_key = attributes.keys.find { |k| k.end_with?(".temperature") }
      expect(attributes[temperature_key]).to be_nil
    end

    it "collects context size" do
      attributes = collector.collect_attributes(dsl_agent)
      context_size_key = attributes.keys.find { |k| k.end_with?(".context_size") }
      expect(attributes[context_size_key]).to eq(2)  # query and depth
    end

    it "handles missing context gracefully" do
      dsl_agent.instance_variable_set(:@context, nil)
      
      attributes = collector.collect_attributes(dsl_agent)
      context_size_key = attributes.keys.find { |k| k.end_with?(".context_size") }
      expect(attributes[context_size_key]).to eq(0)
    end

    it "determines has_tools based on context" do
      attributes = collector.collect_attributes(dsl_agent)
      has_tools_key = attributes.keys.find { |k| k.end_with?(".has_tools") }
      expect(attributes[has_tools_key]).to be true
    end

    it "handles empty context for has_tools" do
      dsl_agent.instance_variable_set(:@context, {})
      
      attributes = collector.collect_attributes(dsl_agent)
      has_tools_key = attributes.keys.find { |k| k.end_with?(".has_tools") }
      expect(attributes[has_tools_key]).to be false
    end

    it "determines execution mode based on smart features" do
      attributes = collector.collect_attributes(dsl_agent)
      execution_mode_key = attributes.keys.find { |k| k.end_with?(".execution_mode") }
      expect(attributes[execution_mode_key]).to eq("smart")
    end

    it "falls back to direct execution mode" do
      allow(dsl_agent).to receive(:respond_to?).with(:has_smart_features?).and_return(false)
      
      attributes = collector.collect_attributes(dsl_agent)
      execution_mode_key = attributes.keys.find { |k| k.end_with?(".execution_mode") }
      expect(attributes[execution_mode_key]).to eq("direct")
    end

    it "collects tools count when available" do
      attributes = collector.collect_attributes(dsl_agent)
      tools_count_key = attributes.keys.find { |k| k.end_with?(".tools_count") }
      expect(attributes[tools_count_key]).to eq("2")
    end

    it "handles missing tools gracefully" do
      allow(dsl_agent).to receive(:respond_to?).with(:tools).and_return(false)
      
      attributes = collector.collect_attributes(dsl_agent)
      tools_count_key = attributes.keys.find { |k| k.end_with?(".tools_count") }
      expect(attributes[tools_count_key]).to eq("0")
    end

    it "collects handoffs count when available" do
      attributes = collector.collect_attributes(dsl_agent)
      handoffs_count_key = attributes.keys.find { |k| k.end_with?(".handoffs_count") }
      expect(attributes[handoffs_count_key]).to eq("1")
    end

    it "handles missing handoffs gracefully" do
      allow(dsl_agent).to receive(:respond_to?).with(:handoffs).and_return(false)
      
      attributes = collector.collect_attributes(dsl_agent)
      handoffs_count_key = attributes.keys.find { |k| k.end_with?(".handoffs_count") }
      expect(attributes[handoffs_count_key]).to eq("0")
    end
  end

  describe "#collect_result" do
    let(:result) { { success: true, data: "processed" } }

    it "collects base result attributes" do
      attributes = collector.collect_result(dsl_agent, result)

      expect(attributes).to include("result.type")
      expect(attributes).to include("result.success")
      expect(attributes["result.type"]).to eq("Hash")
      expect(attributes["result.success"]).to be true
    end

    it "handles nil result" do
      attributes = collector.collect_result(dsl_agent, nil)

      expect(attributes["result.type"]).to eq("NilClass")
      expect(attributes["result.success"]).to be false
    end
  end

  describe "component prefix" do
    it "generates correct prefix for DSL agent collector" do
      prefix = collector.send(:component_prefix)
      expect(prefix).to match(/agent$/)
    end
  end
end
