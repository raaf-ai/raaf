# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::SpanCollectors::ToolCollector do
  let(:tool) do
    double("Tool",
      class: double("ToolClass", name: "RAAF::WebSearchTool")
    ).tap do |tool|
      tool.instance_variable_set(:@method_name, :search)
      # Allow respond_to? to work for any method, returning false by default
      allow(tool).to receive(:respond_to?).and_return(false)
      # But specifically allow detect_agent_context
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

  describe "execution metrics (span attributes)" do
    context "with execution duration available" do
      before do
        allow(tool).to receive(:respond_to?).with(:execution_duration_ms).and_return(true)
        allow(tool).to receive(:execution_duration_ms).and_return(1250)
      end

      it "collects execution duration in milliseconds" do
        attributes = collector.collect_attributes(tool)
        duration_key = attributes.keys.find { |k| k.end_with?(".duration.ms") && k.start_with?("tool.") }
        expect(attributes[duration_key]).to eq("1250")
      end
    end

    context "without execution duration" do
      it "handles missing execution duration gracefully" do
        attributes = collector.collect_attributes(tool)
        duration_key = attributes.keys.find { |k| k.end_with?(".duration.ms") && k.start_with?("tool.") }
        expect(attributes[duration_key]).to eq("N/A")
      end
    end

    context "with retry metrics available" do
      before do
        allow(tool).to receive(:respond_to?).with(:retry_count).and_return(true)
        allow(tool).to receive(:retry_count).and_return(3)
        allow(tool).to receive(:respond_to?).with(:total_backoff_ms).and_return(true)
        allow(tool).to receive(:total_backoff_ms).and_return(5000)
      end

      it "collects retry count" do
        attributes = collector.collect_attributes(tool)
        retry_count_key = attributes.keys.find { |k| k.end_with?(".retry.count") }
        expect(attributes[retry_count_key]).to eq("3")
      end

      it "collects total backoff duration" do
        attributes = collector.collect_attributes(tool)
        backoff_key = attributes.keys.find { |k| k.end_with?(".retry.total_backoff_ms") }
        expect(attributes[backoff_key]).to eq("5000")
      end
    end

    context "without retry metrics" do
      it "defaults retry count to 0" do
        attributes = collector.collect_attributes(tool)
        retry_count_key = attributes.keys.find { |k| k.end_with?(".retry.count") }
        expect(attributes[retry_count_key]).to eq("0")
      end

      it "defaults total backoff to 0" do
        attributes = collector.collect_attributes(tool)
        backoff_key = attributes.keys.find { |k| k.end_with?(".retry.total_backoff_ms") }
        expect(attributes[backoff_key]).to eq("0")
      end
    end
  end

  describe "result execution metrics" do
    context "with successful execution" do
      it "marks status as success for normal results" do
        result = "successful execution"
        attributes = collector.collect_result(tool, result)
        expect(attributes["result.status"]).to eq("success")
      end

      it "collects result size in bytes" do
        result = "x" * 100
        attributes = collector.collect_result(tool, result)
        expect(attributes["result.size.bytes"]).to eq("100")
      end
    end

    context "with failed execution (Exception)" do
      let(:error) { RuntimeError.new("Tool failed") }

      it "marks status as error for exceptions" do
        attributes = collector.collect_result(tool, error)
        expect(attributes["result.status"]).to eq("error")
      end

      it "captures error type" do
        attributes = collector.collect_result(tool, error)
        expect(attributes["result.error.type"]).to eq("RuntimeError")
      end

      it "captures error message" do
        attributes = collector.collect_result(tool, error)
        expect(attributes["result.error.message"]).to eq("Tool failed")
      end

      it "includes ERROR prefix in execution result" do
        attributes = collector.collect_result(tool, error)
        expect(attributes["result.execution_result"]).to start_with("ERROR:")
        expect(attributes["result.execution_result"]).to include("Tool failed")
      end
    end

    context "with error response object" do
      let(:error_response) do
        double("ErrorResponse",
          failure?: true,
          error: double("Error", class: double("ErrorClass", name: "NetworkError"), message: "Connection timeout")
        )
      end

      it "marks status as error for error response objects" do
        attributes = collector.collect_result(tool, error_response)
        expect(attributes["result.status"]).to eq("error")
      end

      it "extracts error type from error response" do
        attributes = collector.collect_result(tool, error_response)
        expect(attributes["result.error.type"]).to eq("NetworkError")
      end

      it "extracts error message from error response" do
        attributes = collector.collect_result(tool, error_response)
        expect(attributes["result.error.message"]).to eq("Connection timeout")
      end
    end

    context "with result duration tracking" do
      before do
        allow(tool).to receive(:respond_to?).with(:execution_duration_ms).and_return(true)
        allow(tool).to receive(:execution_duration_ms).and_return(523)
      end

      it "includes result duration in result attributes" do
        result = "successful"
        attributes = collector.collect_result(tool, result)
        expect(attributes["result.duration.ms"]).to eq("523")
      end
    end

    context "with tool_result field (full result data)" do
      let(:complex_result) do
        {
          status: "success",
          data: [1, 2, 3],
          metadata: { timestamp: "2024-01-01" }
        }
      end

      it "includes full result object in tool_result field" do
        attributes = collector.collect_result(tool, complex_result)
        # BaseCollector converts symbol keys to string keys for JSONB storage
        expect(attributes["result.tool_result"]).to eq({
          "status" => "success",
          "data" => [1, 2, 3],
          "metadata" => { "timestamp" => "2024-01-01" }
        })
      end

      it "converts exception to hash in tool_result" do
        error = RuntimeError.new("Test error")
        attributes = collector.collect_result(tool, error)
        # BaseCollector converts symbol keys to string keys for JSONB storage
        expect(attributes["result.tool_result"]).to eq({
          "error" => "Test error",
          "class" => "RuntimeError"
        })
      end
    end
  end

  describe "component prefix" do
    it "generates correct prefix for tool collector" do
      prefix = collector.send(:component_prefix)
      expect(prefix).to match(/tool$/)
    end
  end
end
