# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::SpanCollectors::ToolCollector do
  let(:tool) do
    double("Tool",
      class: double("ToolClass", name: "RAAF::WebSearchTool")
    ).tap do |tool|
      tool.instance_variable_set(:@method_name, :search)
      allow(tool).to receive(:respond_to?).with(:detect_agent_context).and_return(true)
      
      agent_context = double("Agent", class: double("AgentClass", name: "RAAF::Agent"))
      allow(tool).to receive(:detect_agent_context).and_return(agent_context)
    end
  end

  let(:collector) { described_class.new }

  describe "DSL declarations" do
    it "declares custom span attributes with lambdas" do
      custom_attrs = described_class.instance_variable_get(:@span_custom)
      expect(custom_attrs).to have_key(:name)
      expect(custom_attrs).to have_key(:method)
      expect(custom_attrs).to have_key(:agent_context)
    end

    it "declares result attributes" do
      result_attrs = described_class.instance_variable_get(:@result_custom)
      expect(result_attrs).to have_key(:execution_result)
    end
  end

  describe "#collect_attributes" do
    it "collects base attributes" do
      attributes = collector.collect_attributes(tool)

      expect(attributes).to include("component.type")
      expect(attributes).to include("component.name")
      expect(attributes["component.name"]).to eq("RAAF::WebSearchTool")
    end

    it "collects tool name from class" do
      attributes = collector.collect_attributes(tool)
      name_key = attributes.keys.find { |k| k.end_with?(".name") && !k.start_with?("component.") }
      expect(attributes[name_key]).to eq("RAAF::WebSearchTool")
    end

    it "collects method name from instance variable" do
      attributes = collector.collect_attributes(tool)
      method_key = attributes.keys.find { |k| k.end_with?(".method") }
      expect(attributes[method_key]).to eq("search")
    end

    it "handles missing method name gracefully" do
      tool.instance_variable_set(:@method_name, nil)
      
      attributes = collector.collect_attributes(tool)
      method_key = attributes.keys.find { |k| k.end_with?(".method") }
      expect(attributes[method_key]).to eq("unknown")
    end

    it "collects agent context when available" do
      attributes = collector.collect_attributes(tool)
      agent_context_key = attributes.keys.find { |k| k.end_with?(".agent_context") }
      expect(attributes[agent_context_key]).to eq("RAAF::Agent")
    end

    it "handles missing agent context detection gracefully" do
      allow(tool).to receive(:respond_to?).with(:detect_agent_context).and_return(false)
      
      attributes = collector.collect_attributes(tool)
      agent_context_key = attributes.keys.find { |k| k.end_with?(".agent_context") }
      expect(attributes[agent_context_key]).to be_nil
    end

    it "handles nil agent context gracefully" do
      allow(tool).to receive(:detect_agent_context).and_return(nil)
      
      attributes = collector.collect_attributes(tool)
      agent_context_key = attributes.keys.find { |k| k.end_with?(".agent_context") }
      expect(attributes[agent_context_key]).to be_nil
    end

    it "handles agent context without class gracefully" do
      agent_context = double("Agent", class: nil)
      allow(tool).to receive(:detect_agent_context).and_return(agent_context)
      
      attributes = collector.collect_attributes(tool)
      agent_context_key = attributes.keys.find { |k| k.end_with?(".agent_context") }
      expect(attributes[agent_context_key]).to be_nil
    end
  end

  describe "#collect_result" do
    let(:result) { "Tool execution completed successfully with data: #{[*1..50].join(', ')}" }

    it "collects base result attributes" do
      attributes = collector.collect_result(tool, result)

      expect(attributes).to include("result.type")
      expect(attributes).to include("result.success")
      expect(attributes["result.type"]).to eq("String")
      expect(attributes["result.success"]).to be true
    end

    it "truncates long execution results to 101 characters" do
      long_result = "x" * 200

      attributes = collector.collect_result(tool, long_result)
      expect(attributes).to include("result.execution_result")
      expect(attributes["result.execution_result"]).to eq("x" * 101)
      expect(attributes["result.execution_result"].length).to eq(101)
    end

    it "handles short execution results" do
      short_result = "success"
      
      attributes = collector.collect_result(tool, short_result)
      expect(attributes).to include("result.execution_result")
      expect(attributes["result.execution_result"]).to eq("success")
    end

    it "handles nil result" do
      attributes = collector.collect_result(tool, nil)

      expect(attributes["result.type"]).to eq("NilClass")
      expect(attributes["result.success"]).to be false
      expect(attributes["result.execution_result"]).to eq("")
    end

    it "handles complex result objects" do
      complex_result = { status: "success", data: [1, 2, 3] }
      
      attributes = collector.collect_result(tool, complex_result)
      expect(attributes["result.execution_result"]).to match(/\{.*status.*success.*\}/)
      expect(attributes["result.execution_result"].length).to be <= 101
    end
  end

  describe "component prefix" do
    it "generates correct prefix for tool collector" do
      prefix = collector.send(:component_prefix)
      expect(prefix).to match(/tool$/)
    end
  end
end
