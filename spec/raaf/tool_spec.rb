# frozen_string_literal: true

require "spec_helper"
require "raaf/tool"

RSpec.describe RAAF::Tool do
  let(:test_tool_class) do
    Class.new(described_class) do
      def call(input:)
        "Processed: #{input}"
      end
    end
  end

  let(:tool_instance) { test_tool_class.new }

  describe "#call" do
    context "when not implemented" do
      let(:base_tool) { described_class.new }

      it "raises NotImplementedError" do
        expect { base_tool.call }.to raise_error(NotImplementedError, /must implement #call/)
      end
    end

    context "when implemented" do
      it "executes the tool logic" do
        result = tool_instance.call(input: "test")
        expect(result).to eq("Processed: test")
      end
    end
  end

  describe "#name" do
    context "with explicit name" do
      let(:named_tool_class) do
        Class.new(described_class) do
          configure name: "custom_tool"
        end
      end

      it "returns the configured name" do
        expect(named_tool_class.new.name).to eq("custom_tool")
      end
    end

    context "with automatic name generation" do
      let(:auto_named_class) do
        stub_const("TestAnalyzerTool", Class.new(described_class))
      end

      it "generates name from class name" do
        expect(auto_named_class.new.name).to eq("test_analyzer")
      end

      it "removes Tool suffix" do
        stub_const("DataProcessorTool", Class.new(described_class))
        expect(DataProcessorTool.new.name).to eq("data_processor")
      end

      it "handles namespaced classes" do
        stub_const("RAAF::Tools::WebSearchTool", Class.new(described_class))
        expect(RAAF::Tools::WebSearchTool.new.name).to eq("web_search")
      end
    end
  end

  describe "#description" do
    context "with explicit description" do
      let(:described_tool_class) do
        Class.new(described_class) do
          configure description: "Performs custom analysis"
        end
      end

      it "returns the configured description" do
        expect(described_tool_class.new.description).to eq("Performs custom analysis")
      end
    end

    context "with automatic description generation" do
      let(:auto_described_class) do
        stub_const("SentimentAnalyzerTool", Class.new(described_class))
      end

      it "generates description from class name" do
        expect(auto_described_class.new.description).to eq("Tool for sentiment analyzer operations")
      end
    end
  end

  describe "#parameters" do
    context "with method signature extraction" do
      let(:parameterized_tool) do
        Class.new(described_class) do
          def call(query:, max_results: 10, filter: nil)
            # Implementation
          end
        end
      end

      let(:parameters) { parameterized_tool.new.parameters }

      it "extracts required parameters" do
        expect(parameters[:properties]).to include(:query)
        expect(parameters[:required]).to include("query")
      end

      it "extracts optional parameters" do
        expect(parameters[:properties]).to include(:max_results, :filter)
        expect(parameters[:required]).not_to include("max_results", "filter")
      end

      it "includes parameter types" do
        expect(parameters[:properties][:query]).to include(type: "string")
      end

      it "includes default values in description" do
        expect(parameters[:properties][:max_results][:description]).to include("default: 10")
      end
    end

    context "with explicit parameter definition" do
      let(:explicit_params_tool) do
        Class.new(described_class) do
          parameters do
            property :text, type: "string", description: "Text to analyze"
            property :language, type: "string", enum: ["en", "es", "fr"]
            required :text
          end

          def call(text:, language: "en")
            # Implementation
          end
        end
      end

      let(:parameters) { explicit_params_tool.new.parameters }

      it "uses explicit parameter definitions" do
        expect(parameters[:properties][:text][:description]).to eq("Text to analyze")
      end

      it "supports enum values" do
        expect(parameters[:properties][:language][:enum]).to eq(["en", "es", "fr"])
      end
    end
  end

  describe "#enabled?" do
    context "by default" do
      it "returns true" do
        expect(tool_instance.enabled?).to be true
      end
    end

    context "when explicitly disabled" do
      let(:disabled_tool) do
        Class.new(described_class) do
          configure enabled: false
        end
      end

      it "returns false" do
        expect(disabled_tool.new.enabled?).to be false
      end
    end

    context "with conditional enabling" do
      let(:conditional_tool) do
        Class.new(described_class) do
          attr_accessor :api_key

          def enabled?
            !api_key.nil?
          end
        end
      end

      it "evaluates the condition" do
        tool = conditional_tool.new
        expect(tool.enabled?).to be false

        tool.api_key = "test_key"
        expect(tool.enabled?).to be true
      end
    end
  end

  describe "#to_function_tool" do
    let(:tool_with_implementation) do
      Class.new(described_class) do
        def call(message:)
          "Echo: #{message}"
        end
      end
    end

    it "returns a FunctionTool instance" do
      function_tool = tool_with_implementation.new.to_function_tool
      expect(function_tool).to be_a(RAAF::FunctionTool)
    end

    it "preserves tool name" do
      stub_const("EchoTool", tool_with_implementation)
      function_tool = EchoTool.new.to_function_tool
      expect(function_tool.name).to eq("echo")
    end

    it "preserves tool functionality" do
      function_tool = tool_with_implementation.new.to_function_tool
      result = function_tool.call(message: "Hello")
      expect(result).to eq("Echo: Hello")
    end
  end

  describe "#to_tool_definition" do
    let(:complete_tool) do
      Class.new(described_class) do
        configure name: "search", description: "Search for information"

        def call(query:, limit: 10)
          # Implementation
        end
      end
    end

    let(:definition) { complete_tool.new.to_tool_definition }

    it "generates OpenAI-compatible format" do
      expect(definition).to include(
        type: "function",
        function: hash_including(
          name: "search",
          description: "Search for information"
        )
      )
    end

    it "includes parameter schema" do
      expect(definition[:function][:parameters]).to include(
        type: "object",
        properties: hash_including(:query, :limit),
        required: ["query"]
      )
    end
  end

  describe ".inherited" do
    it "automatically registers the tool" do
      expect(RAAF::ToolRegistry).to receive(:register).with(anything, anything)
      
      Class.new(described_class) do
        # This should trigger auto-registration
      end
    end

    it "uses the generated name for registration" do
      expect(RAAF::ToolRegistry).to receive(:register).with("custom_analyzer", anything)
      
      stub_const("CustomAnalyzerTool", Class.new(described_class))
    end
  end

  describe "logging" do
    let(:logged_tool) do
      Class.new(described_class) do
        def call(input:)
          log_debug_tools("Processing input", input: input)
          "Result"
        end
      end
    end

    it "uses RAAF::Logger for debug output" do
      expect_any_instance_of(logged_tool).to receive(:log_debug_tools).with("Processing input", input: "test")
      logged_tool.new.call(input: "test")
    end
  end
end