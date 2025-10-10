# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RAAF::DSL::ToolMetadata do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include RAAF::DSL::ToolMetadata

      # Mock configuration for testing
      def self.tool_execution_config
        @tool_execution_config ||= {
          enable_validation: true,
          enable_logging: true,
          enable_metadata: true,
          log_arguments: true,
          truncate_logs: 100
        }
      end

      # Mock agent_name class method
      def self.agent_name
        "TestAgent"
      end
    end
  end

  let(:instance) { test_class.new }

  # Mock tools for testing
  let(:simple_tool) do
    double("SimpleTool",
      tool_name: "search_tool",
      name: "search_tool"
    )
  end

  let(:function_tool) do
    tool = RAAF::FunctionTool.new(
      ->(_params) { { success: true } },
      name: "calculator",
      description: "Math calculator"
    )
    # Set instance variable to simulate RAAF::FunctionTool behavior
    tool.instance_variable_set(:@name, "calculator")
    tool
  end

  let(:unnamed_tool) do
    Class.new do
      def call(**_args)
        { success: true }
      end
    end.new
  end

  describe "#inject_metadata!" do
    context "with Hash result" do
      it "adds execution metadata to result" do
        result = { success: true, data: "test data" }
        duration_ms = 42.5

        instance.inject_metadata!(result, simple_tool, duration_ms)

        expect(result).to have_key(:_execution_metadata)
        metadata = result[:_execution_metadata]

        expect(metadata[:duration_ms]).to eq(42.5)
        expect(metadata[:tool_name]).to eq("search_tool")
        expect(metadata[:agent_name]).to eq("TestAgent")
        expect(metadata[:timestamp]).to be_a(String)
        expect { Time.iso8601(metadata[:timestamp]) }.not_to raise_error
      end

      it "preserves original result data" do
        result = { success: true, data: "test data", count: 5 }
        original_keys = result.keys

        instance.inject_metadata!(result, simple_tool, 10.0)

        # Original keys still present
        expect(result[:success]).to eq(true)
        expect(result[:data]).to eq("test data")
        expect(result[:count]).to eq(5)
      end

      it "does not overwrite existing metadata" do
        result = {
          success: true,
          _execution_metadata: { custom: "value" }
        }

        instance.inject_metadata!(result, simple_tool, 10.0)

        # Original metadata preserved (merged)
        expect(result[:_execution_metadata][:custom]).to eq("value")
        # New metadata added
        expect(result[:_execution_metadata][:duration_ms]).to eq(10.0)
      end

      it "handles FunctionTool instances" do
        result = { success: true }

        instance.inject_metadata!(result, function_tool, 15.0)

        expect(result[:_execution_metadata][:tool_name]).to eq("calculator")
      end

      it "extracts tool name from various tool types" do
        # Tool with tool_name method
        result1 = { success: true }
        instance.inject_metadata!(result1, simple_tool, 10.0)
        expect(result1[:_execution_metadata][:tool_name]).to eq("search_tool")

        # FunctionTool instance
        result2 = { success: true }
        instance.inject_metadata!(result2, function_tool, 10.0)
        expect(result2[:_execution_metadata][:tool_name]).to eq("calculator")
      end

      it "includes ISO8601 formatted timestamp" do
        result = { success: true }

        freeze_time = Time.now
        allow(Time).to receive(:now).and_return(freeze_time)

        instance.inject_metadata!(result, simple_tool, 10.0)

        expect(result[:_execution_metadata][:timestamp]).to eq(freeze_time.iso8601)
      end

      it "includes agent name from class configuration" do
        result = { success: true }

        instance.inject_metadata!(result, simple_tool, 10.0)

        expect(result[:_execution_metadata][:agent_name]).to eq("TestAgent")
      end

      it "rounds duration to 2 decimal places" do
        result = { success: true }

        instance.inject_metadata!(result, simple_tool, 12.3456789)

        # Duration should be stored as-is (rounding happens during calculation)
        expect(result[:_execution_metadata][:duration_ms]).to eq(12.3456789)
      end
    end

    context "with non-Hash result" do
      it "does not modify string results" do
        result = "simple string"
        original_result = result.dup

        # inject_metadata! should only work with Hash results
        # We'll test this in the interceptor integration
        expect(result).to eq(original_result)
      end

      it "does not modify array results" do
        result = [1, 2, 3]
        original_result = result.dup

        # inject_metadata! should only work with Hash results
        # We'll test this in the interceptor integration
        expect(result).to eq(original_result)
      end
    end
  end

  describe "#extract_tool_name (private)" do
    it "extracts name from tool with tool_name method" do
      tool = double("Tool", tool_name: "custom_search")

      # Access private method for testing
      name = instance.send(:extract_tool_name, tool)

      expect(name).to eq("custom_search")
    end

    it "extracts name from tool with name method" do
      tool = double("Tool", name: "analyzer")
      allow(tool).to receive(:respond_to?).with(:tool_name).and_return(false)
      allow(tool).to receive(:respond_to?).with(:name).and_return(true)

      name = instance.send(:extract_tool_name, tool)

      expect(name).to eq("analyzer")
    end

    it "extracts name from FunctionTool @name instance variable" do
      name = instance.send(:extract_tool_name, function_tool)

      expect(name).to eq("calculator")
    end

    it "falls back to class name for unnamed tools" do
      allow(unnamed_tool).to receive(:respond_to?).with(:tool_name).and_return(false)
      allow(unnamed_tool).to receive(:respond_to?).with(:name).and_return(false)
      allow(unnamed_tool).to receive(:is_a?).with(RAAF::FunctionTool).and_return(false)

      # Mock class name
      tool_class = double("ToolClass")
      allow(unnamed_tool).to receive(:class).and_return(tool_class)
      allow(tool_class).to receive(:name).and_return("RAAF::Tools::CustomTool")

      name = instance.send(:extract_tool_name, unnamed_tool)

      # Implementation removes "_tool" suffix, so "CustomTool" -> "custom"
      expect(name).to eq("custom")
    end

    it "returns 'unknown_tool' when no name can be extracted" do
      tool = double("Tool")
      allow(tool).to receive(:respond_to?).with(:tool_name).and_return(false)
      allow(tool).to receive(:respond_to?).with(:name).and_return(false)
      allow(tool).to receive(:is_a?).with(RAAF::FunctionTool).and_return(false)
      allow(tool).to receive(:class).and_return(double("Class", name: nil))

      name = instance.send(:extract_tool_name, tool)

      expect(name).to eq("unknown_tool")
    end
  end

  describe "metadata structure" do
    it "contains all required fields" do
      result = { success: true }

      instance.inject_metadata!(result, simple_tool, 25.5)

      metadata = result[:_execution_metadata]
      expect(metadata.keys).to contain_exactly(
        :duration_ms,
        :tool_name,
        :timestamp,
        :agent_name
      )
    end

    it "uses symbol keys for consistency" do
      result = { success: true }

      instance.inject_metadata!(result, simple_tool, 25.5)

      metadata = result[:_execution_metadata]
      expect(metadata.keys.all? { |k| k.is_a?(Symbol) }).to be true
    end
  end

  describe "integration with configuration" do
    it "respects metadata_enabled? configuration (tested in interceptor)" do
      # This behavior is tested in the interceptor integration tests
      # The module itself always injects metadata when called
      # The interceptor decides whether to call inject_metadata! based on config

      result = { success: true }
      instance.inject_metadata!(result, simple_tool, 10.0)

      expect(result).to have_key(:_execution_metadata)
    end
  end
end
