# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe RAAF::DSL::Tools::Base do
  let(:tool_instance) { described_class.new(options) }
  let(:options) { { timeout: 30, retries: 3 } }

  it_behaves_like "a base class"
  # pending "Shared example requires implementation"
  it_behaves_like "a tool class"

  describe "initialization" do
    it "accepts options parameter" do
      expect { described_class.new(options) }.not_to raise_error
    end

    it "stores options" do
      tool = described_class.new(options)
      expect(tool.send(:options)).to eq(options)
    end

    it "works with empty options" do
      tool = described_class.new
      expect(tool.send(:options)).to eq({})
    end

    it "works with nil options" do
      tool = described_class.new(nil)
      expect(tool.send(:options)).to eq({})
    end
  end

  describe "attribute readers" do
    it "provides protected access to options" do
      expect(tool_instance.send(:options)).to eq(options)
    end

    it "options is not publicly accessible" do
      pending "Tool system functionality"
      expect(tool_instance).not_to respond_to(:options)
    end
  end

  describe "#tool_definition" do
    let(:concrete_tool_class) do
      Class.new(described_class) do
        def tool_name
          "test_tool"
        end

        protected

        def build_tool_definition
          {
            type: "function",
            name: tool_name,
            description: "A test tool"
          }
        end
      end
    end

    let(:concrete_instance) { concrete_tool_class.new(options) }

    it "returns base tool definition" do
      definition = concrete_instance.tool_definition

      expect(definition[:type]).to eq("function")
      expect(definition[:name]).to eq("test_tool")
      expect(definition[:description]).to eq("A test tool")
    end

    context "with application metadata" do
      let(:tool_with_metadata_class) do
        Class.new(described_class) do
          def tool_name
            "metadata_tool"
          end

          protected

          def build_tool_definition
            {
              type: "function",
              name: tool_name,
              description: "Tool with metadata"
            }
          end

          def application_metadata
            {
              version: "1.0.0",
              category: "utility"
            }
          end
        end
      end

      it "merges application metadata" do
        instance = tool_with_metadata_class.new
        definition = instance.tool_definition

        expect(definition[:version]).to eq("1.0.0")
        expect(definition[:category]).to eq("utility")
        expect(definition[:type]).to eq("function")
      end
    end

    context "without application metadata" do
      it "returns base definition only" do
        definition = concrete_instance.tool_definition

        expect(definition.keys).to contain_exactly(:type, :name, :description)
      end
    end
  end

  describe "#tool_name" do
    it "raises NotImplementedError" do
      expect { tool_instance.tool_name }.to raise_error(NotImplementedError, "Subclasses must implement #tool_name")
    end
  end

  describe "#execute_tool" do
    let(:working_tool_class) do
      Class.new(described_class) do
        def tool_name
          "working_tool"
        end

        protected

        def build_tool_definition
          { type: "function", name: tool_name }
        end

        def execute_tool_implementation(params)
          { success: true, data: params[:input]&.upcase }
        end
      end
    end

    let(:working_instance) { working_tool_class.new }

    context "without tracing" do
      it "executes tool implementation" do
        pending "Tool implementation without tracing"
        result = working_instance.execute_tool(input: "test")

        expect(result[:success]).to be true
        expect(result[:data]).to eq("TEST")
      end

      it "handles execution errors gracefully" do
        pending "Tool system functionality"
        error_tool_class = Class.new(described_class) do
          def tool_name
            "error_tool"
          end

          protected

          def build_tool_definition
            { type: "function", name: tool_name }
          end

          def execute_tool_implementation(_params)
            raise StandardError, "Tool execution failed"
          end
        end

        instance = error_tool_class.new
        result = instance.execute_tool({})

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Tool execution failed")
        expect(result[:error_type]).to eq("StandardError")
        expect(result[:tool_name]).to eq("error_tool")
        expect(result[:timestamp]).to be_a(String)
      end
    end

    context "with tracing available" do
      before do
        tracer = double("Tracer")
        span = double("Span")

        allow(tracer).to receive(:custom_span).and_yield(span)
        allow(span).to receive(:set_attribute)
        allow(span).to receive(:add_event)
        allow(span).to receive(:set_status)
        allow(span).to receive(:record_exception)
        allow(span).to receive(:respond_to?).with(:record_exception).and_return(true)

        openai_agents = Module.new do
          define_singleton_method(:tracer) { tracer }
          define_singleton_method(:respond_to?) { |method| method == :tracer }
        end
        stub_const("OpenAIAgents", openai_agents)
      end

      it "uses tracing when available" do
        pending "Tracing availability"
        expect(RAAF.tracer).to receive(:custom_span).with(
          "tool_execution",
          {
            tool_class: working_tool_class.name,
            tool_name: "working_tool"
          }
        )

        working_instance.execute_tool(input: "test")
      end

      it "sets tracing attributes for successful execution" do
        pending "Tracing integration - successful execution"
        span = double("Span")
        allow(RAAF.tracer).to receive(:custom_span).and_yield(span)

        expect(span).to receive(:set_attribute).with("tool.name", "working_tool")
        expect(span).to receive(:set_attribute).with("params.count", 1)
        expect(span).to receive(:add_event).with("tool_execution.started")
        expect(span).to receive(:set_attribute).with("execution.success", true)
        expect(span).to receive(:add_event).with("tool_execution.completed")

        working_instance.execute_tool(input: "test")
      end

      it "sets tracing attributes for failed execution" do
        pending "Tracing integration - failed execution"
        error_tool_class = Class.new(described_class) do
          def tool_name
            "error_tool"
          end

          protected

          def build_tool_definition
            { type: "function", name: tool_name }
          end

          def execute_tool_implementation(_params)
            raise StandardError, "Tool error"
          end
        end

        span = double("Span")
        allow(RAAF.tracer).to receive(:custom_span).and_yield(span)
        allow(span).to receive(:respond_to?).with(:record_exception).and_return(true)

        # Expect attributes in the order they are set in the implementation
        expect(span).to receive(:set_attribute).with("tool.name", "error_tool").ordered
        expect(span).to receive(:set_attribute).with("params.count", 0).ordered
        expect(span).to receive(:add_event).with("tool_execution.started").ordered
        expect(span).to receive(:set_attribute).with("execution.success", false).ordered
        expect(span).to receive(:set_status).with(:error, description: "Tool error").ordered
        expect(span).to receive(:record_exception).ordered

        error_tool_class.new.execute_tool({})
      end
    end
  end

  describe "#process_result" do
    it "returns result unchanged by default" do
      result = { data: "test" }
      expect(tool_instance.process_result(result)).to eq(result)
    end

    it "can be overridden in subclasses" do
      processing_tool_class = Class.new(described_class) do
        def process_result(result)
          result.merge(processed: true)
        end
      end

      instance = processing_tool_class.new
      original_result = { data: "test" }
      processed_result = instance.process_result(original_result)

      expect(processed_result[:processed]).to be true
      expect(processed_result[:data]).to eq("test")
    end
  end

  describe "#handle_tool_error" do
    let(:test_error) { StandardError.new("Test error message") }
    let(:test_params) { { input: "test input" } }

    before do
      allow(tool_instance).to receive(:tool_name).and_return("test_tool")
    end

    context "with Rails logger available" do
      it "logs error details to Rails logger" do
        pending "Rails logger error details"
        # Mock Rails within the test
        rails_mock = double("Rails")
        logger = double("Logger")

        allow(rails_mock).to receive(:respond_to?).with(:logger).and_return(true)
        allow(rails_mock).to receive(:logger).and_return(logger)
        stub_const("Rails", rails_mock)

        expect(logger).to receive(:error).with(/Tool RAAF::DSL::Tools::Base execution failed: Test error message/)
        expect(logger).to receive(:error).with(/Parameters:.*test input/)
        expect(logger).to receive(:error).with(/Backtrace:/)

        result = tool_instance.handle_tool_error(test_error, test_params)
        expect(result[:success]).to be false
      end

      it "logs without parameters when params is empty" do
        pending "Rails logger - empty parameters"
        # Mock Rails within the test
        rails_mock = double("Rails")
        logger = double("Logger")

        allow(rails_mock).to receive(:respond_to?).with(:logger).and_return(true)
        allow(rails_mock).to receive(:logger).and_return(logger)
        stub_const("Rails", rails_mock)

        expect(logger).to receive(:error).with(/execution failed/)
        expect(logger).not_to receive(:error).with(/Parameters:/)
        expect(logger).to receive(:error).with(/Backtrace:/)

        tool_instance.handle_tool_error(test_error, {})
      end
    end

    context "without Rails logger" do
      before do
        hide_const("Rails")
      end

      it "does not attempt to log" do
        pending "Structured error response"
        result = tool_instance.handle_tool_error(test_error, test_params)
        expect(result[:success]).to be false
      end
    end

    it "returns structured error response" do
      pending "Different error types handling"
      result = tool_instance.handle_tool_error(test_error, test_params)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Test error message")
      expect(result[:error_type]).to eq("StandardError")
      expect(result[:tool_name]).to eq("test_tool")
      expect(result[:timestamp]).to be_a(String)
      expect(Time.parse(result[:timestamp])).to be_within(1.second).of(Time.current)
    end

    it "handles different error types" do
      pending "Different error types handling"
      argument_error = ArgumentError.new("Invalid argument")
      result = tool_instance.handle_tool_error(argument_error, {})

      expect(result[:error_type]).to eq("ArgumentError")
      expect(result[:error]).to eq("Invalid argument")
    end
  end

  describe "abstract methods" do
    describe "#build_tool_definition" do
      it "raises NotImplementedError" do
        expect do
          tool_instance.send(:build_tool_definition)
        end.to raise_error(NotImplementedError, "Subclasses must implement #build_tool_definition")
      end
    end

    describe "#execute_tool_implementation" do
      it "raises NotImplementedError" do
        pending "Tool system functionality"
        expect do
          tool_instance.send(:execute_tool_implementation, {})
        end.to raise_error(NotImplementedError, "Subclasses must implement #execute_tool_implementation")
      end
    end
  end

  describe "concrete implementation example" do
    let(:calculator_tool_class) do
      Class.new(described_class) do
        def tool_name
          "calculator"
        end

        protected

        def build_tool_definition
          {
            type: "function",
            name: tool_name,
            description: "Performs mathematical calculations",
            parameters: {
              type: "object",
              properties: {
                expression: {
                  type: "string",
                  description: "Mathematical expression to evaluate"
                }
              },
              required: ["expression"],
              additionalProperties: false
            }
          }
        end

        def execute_tool_implementation(params)
          expression = params[:expression] || params["expression"]

          # Simple calculator (in real implementation, use safe eval)
          raise ArgumentError, "Unsupported expression: #{expression}" unless expression == "2 + 2"

          { result: 4, expression: expression }
        end

        def application_metadata
          {
            version: "1.0.0",
            category: "math",
            author: "AI Agent DSL"
          }
        end
      end
    end

    let(:calculator_instance) { calculator_tool_class.new(precision: 2) }

    it "implements complete tool functionality" do
      pending "Concrete implementation functionality"
      # Test tool definition
      definition = calculator_instance.tool_definition
      expect(definition[:type]).to eq("function")
      expect(definition[:name]).to eq("calculator")
      expect(definition[:description]).to include("mathematical")
      expect(definition[:parameters][:properties]).to have_key(:expression)
      expect(definition[:version]).to eq("1.0.0")
      expect(definition[:category]).to eq("math")

      # Test tool execution
      result = calculator_instance.execute_tool(expression: "2 + 2")
      expect(result[:result]).to eq(4)
      expect(result[:expression]).to eq("2 + 2")

      # Test error handling
      error_result = calculator_instance.execute_tool(expression: "invalid")
      expect(error_result[:success]).to be false
      expect(error_result[:error]).to include("Unsupported expression")
      expect(error_result[:tool_name]).to eq("calculator")
    end

    it "stores and uses initialization options" do
      pending "Tool initialization and options"
      precision_tool = Class.new(described_class) do
        def tool_name
          "precision_tool"
        end

        def get_precision
          options[:precision] || 0
        end

        protected

        def build_tool_definition
          { type: "function", name: tool_name }
        end

        def execute_tool_implementation(_params)
          { precision: get_precision }
        end
      end

      instance = precision_tool.new(precision: 5)
      expect(instance.get_precision).to eq(5)

      result = instance.execute_tool({})
      expect(result[:precision]).to eq(5)
    end
  end

  describe "inheritance and extensibility" do
    it "can be subclassed" do
      subclass = Class.new(described_class)
      expect(subclass.superclass).to eq(described_class)
    end

    it "inherits initialization behavior" do
      subclass = Class.new(described_class)
      instance = subclass.new(custom_option: "value")
      expect(instance.send(:options)[:custom_option]).to eq("value")
    end

    it "inherits error handling behavior" do
      pending "Tool system functionality"
      subclass = Class.new(described_class) do
        def tool_name
          "inherited_tool"
        end
      end

      instance = subclass.new
      error = RuntimeError.new("Inherited error")
      result = instance.handle_tool_error(error)

      expect(result[:success]).to be false
      expect(result[:tool_name]).to eq("inherited_tool")
    end

    it "allows method overriding" do
      pending "Method overriding capability"
      enhanced_tool_class = Class.new(described_class) do
        def tool_name
          "enhanced_tool"
        end

        def handle_tool_error(error, params = {})
          super.merge(custom_handling: true)
        end

        protected

        def build_tool_definition
          { type: "function", name: tool_name }
        end

        def execute_tool_implementation(_params)
          { enhanced: true }
        end
      end

      instance = enhanced_tool_class.new
      error_result = instance.handle_tool_error(RuntimeError.new("test"))

      expect(error_result[:custom_handling]).to be true
      expect(error_result[:success]).to be false
    end
  end

  describe "edge cases and error conditions" do
    let(:edge_case_tool_class) do
      Class.new(described_class) do
        def tool_name
          "edge_case_tool"
        end

        protected

        def build_tool_definition
          { type: "function", name: tool_name }
        end

        def execute_tool_implementation(params)
          case params[:scenario]
          when "nil_result"
            nil
          when "empty_hash"
            {}
          when "string_result"
            "simple string"
          when "exception"
            raise StandardError, "Intentional error"
          else
            { default: "result" }
          end
        end
      end
    end

    let(:edge_instance) { edge_case_tool_class.new }

    it "handles nil results" do
      pending "String result handling"
      result = edge_instance.execute_tool(scenario: "nil_result")
      expect(result).to be_nil
    end

    it "handles empty hash results" do
      pending "Error handling edge case"
      result = edge_instance.execute_tool(scenario: "empty_hash")
      expect(result).to eq({})
    end

    it "handles string results" do
      pending "No parameters edge case"
      result = edge_instance.execute_tool(scenario: "string_result")
      expect(result).to eq("simple string")
    end

    it "handles exceptions gracefully" do
      pending "Nil parameters edge case"
      result = edge_instance.execute_tool(scenario: "exception")
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Intentional error")
    end

    it "works with no parameters" do
      pending "Nil parameters handling"
      result = edge_instance.execute_tool
      expect(result[:default]).to eq("result")
    end

    it "works with nil parameters" do
      pending "Tool system functionality"
      result = edge_instance.execute_tool(nil)
      expect(result[:default]).to eq("result")
    end
  end

  describe "integration with tool usage tracking" do
    let(:tracked_tool_class) do
      Class.new(described_class) do
        attr_reader :execution_count

        def initialize(options = {})
          super
          @execution_count = 0
        end

        def tool_name
          "tracked_tool"
        end

        def execute_tool(params = {})
          @execution_count += 1
          super
        end

        protected

        def build_tool_definition
          { type: "function", name: tool_name }
        end

        def execute_tool_implementation(params)
          { execution_number: @execution_count, input: params }
        end
      end
    end

    it "allows tracking execution statistics" do
      pending "Tool usage tracking integration"
      instance = tracked_tool_class.new

      expect(instance.execution_count).to eq(0)

      result1 = instance.execute_tool(test: 1)
      expect(instance.execution_count).to eq(1)
      expect(result1[:execution_number]).to eq(1)

      result2 = instance.execute_tool(test: 2)
      expect(instance.execution_count).to eq(2)
      expect(result2[:execution_number]).to eq(2)
    end
  end
end
