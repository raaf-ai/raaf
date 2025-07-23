# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::FunctionTool do
  let(:simple_proc) { proc { |value:| value * 2 } }
  let(:test_agent) { RAAF::Agent.new(name: "TestAgent") }

  describe "#initialize" do
    context "with proc" do
      it "creates tool with default name and description" do
        tool = described_class.new(simple_proc)
        
        expect(tool.callable).to eq(simple_proc)
        expect(tool.name).to eq("anonymous_function")
        expect(tool.description).to eq("A function tool")
        expect(tool.parameters).to include(type: "object")
      end

      it "accepts custom metadata" do
        tool = described_class.new(
          simple_proc,
          name: "multiplier",
          description: "Multiplies input by 2",
          parameters: { custom: "params" }
        )

        expect(tool.name).to eq("multiplier")
        expect(tool.description).to eq("Multiplies input by 2")
        expect(tool.parameters).to eq({ custom: "params" })
      end
    end

    context "with method" do
      def sample_method(arg1:, arg2: "default")
        "#{arg1}-#{arg2}"
      end

      it "extracts name from method" do
        tool = described_class.new(method(:sample_method))
        expect(tool.name).to eq("sample_method")
      end

      it "preserves explicitly provided parameters over extraction" do
        custom_params = {
          type: "object",
          properties: {
            custom_arg: { type: "string" }
          }
        }

        tool = described_class.new(method(:sample_method), parameters: custom_params)
        expect(tool.parameters).to eq(custom_params)
      end
    end

    context "with lambda" do
      it "treats lambda as proc" do
        lambda_func = lambda { |x:| x + 1 }
        tool = described_class.new(lambda_func)
        
        expect(tool.callable).to eq(lambda_func)
        expect(tool.name).to eq("anonymous_function")
      end
    end

    context "with is_enabled option" do
      it "stores boolean is_enabled value" do
        tool = described_class.new(simple_proc, is_enabled: false)
        expect(tool.is_enabled).to eq(false)
      end

      it "stores proc is_enabled value" do
        enabler = proc { true }
        tool = described_class.new(simple_proc, is_enabled: enabler)
        expect(tool.is_enabled).to eq(enabler)
      end
    end
  end

  describe "#call" do
    context "with different callable types" do
      it "executes proc with keyword arguments" do
        proc_tool = proc { |a:, b: 10| a + b }
        tool = described_class.new(proc_tool)
        
        expect(tool.call(a: 5)).to eq(15)
        expect(tool.call(a: 5, b: 20)).to eq(25)
      end

      it "executes proc with positional arguments" do
        proc_tool = proc { |x, y| x * y }
        tool = described_class.new(proc_tool)
        
        expect(tool.call(x: 3, y: 4)).to eq(12)
      end

      it "executes proc with no arguments" do
        proc_tool = proc { "constant" }
        tool = described_class.new(proc_tool)
        
        expect(tool.call).to eq("constant")
        expect(tool.call(ignored: "value")).to eq("constant")
      end

      it "executes proc with keyrest parameters" do
        proc_tool = proc { |**kwargs| kwargs }
        tool = described_class.new(proc_tool)
        
        result = tool.call(foo: "bar", baz: 42)
        expect(result).to eq({ foo: "bar", baz: 42 })
      end

      it "executes proc with mixed parameter types" do
        proc_tool = proc { |required:, optional: "default", **rest| 
          { required: required, optional: optional, rest: rest }
        }
        tool = described_class.new(proc_tool)
        
        result = tool.call(required: "value", extra: "data")
        expect(result).to eq({
          required: "value",
          optional: "default",
          rest: { extra: "data" }
        })
      end
    end

    context "error handling" do
      it "raises ToolError for non-callable" do
        tool = described_class.new("not_callable")
        
        expect { tool.call }.to raise_error(RAAF::ToolError, /Callable must be a Method or Proc/)
      end

      it "wraps execution errors with tool name" do
        error_proc = proc { raise "Custom error" }
        tool = described_class.new(error_proc, name: "error_tool")
        
        expect { tool.call }.to raise_error(RAAF::ToolError, /Error executing tool 'error_tool': Custom error/)
      end

      it "preserves original error class information" do
        class CustomToolError < StandardError; end
        
        error_proc = proc { raise CustomToolError, "Specific error" }
        tool = described_class.new(error_proc)
        
        expect { tool.call }.to raise_error(RAAF::ToolError) do |error|
          expect(error.message).to include("Specific error")
        end
      end
    end
  end

  describe "#enabled?" do
    context "with boolean value" do
      it "returns true when enabled is true" do
        tool = described_class.new(simple_proc, is_enabled: true)
        expect(tool.enabled?).to be true
      end

      it "returns false when enabled is false" do
        tool = described_class.new(simple_proc, is_enabled: false)
        expect(tool.enabled?).to be false
      end

      it "returns true when enabled is nil (default)" do
        tool = described_class.new(simple_proc)
        expect(tool.enabled?).to be true
      end
    end

    context "with proc value" do
      it "calls proc with no arguments when arity is 0" do
        called = false
        enabler = proc { called = true; false }
        tool = described_class.new(simple_proc, is_enabled: enabler)
        
        result = tool.enabled?
        expect(called).to be true
        expect(result).to be false
      end

      it "calls proc with context when arity is not 0" do
        context = double("context")
        received_context = nil
        enabler = proc { |ctx| received_context = ctx; true }
        tool = described_class.new(simple_proc, is_enabled: enabler)
        
        result = tool.enabled?(context)
        expect(received_context).to eq(context)
        expect(result).to be true
      end

      it "returns false when proc raises error" do
        enabler = proc { raise "Enable check failed" }
        tool = described_class.new(simple_proc, is_enabled: enabler)
        
        expect(tool.enabled?).to be false
      end
    end

    context "with other truthy/falsy values" do
      it "returns true for truthy non-boolean values" do
        tool = described_class.new(simple_proc, is_enabled: "enabled")
        expect(tool.enabled?).to be true
      end

      it "returns false for falsy non-boolean values" do
        tool = described_class.new(simple_proc, is_enabled: nil)
        tool.is_enabled = false  # Explicitly set to false after init
        expect(tool.enabled?).to be false
      end
    end
  end

  describe "#callable?" do
    it "returns true for proc" do
      tool = described_class.new(simple_proc)
      expect(tool.callable?).to be true
    end

    it "returns true for method" do
      def test_method; end
      tool = described_class.new(method(:test_method))
      expect(tool.callable?).to be true
    end

    it "returns false for invalid callable" do
      tool = described_class.new("not_callable")
      expect(tool.callable?).to be false
    end
  end

  describe "#parameters?" do
    it "returns true when parameters have properties" do
      tool = described_class.new(proc { |x:| x })
      expect(tool.parameters?).to be true
    end

    it "returns false when parameters have no properties" do
      tool = described_class.new(proc { "no params" })
      expect(tool.parameters?).to be false
    end

    it "returns false when parameters is nil" do
      tool = described_class.new(simple_proc)
      tool.instance_variable_set(:@parameters, nil)
      expect(tool.parameters?).to be false
    end

    it "returns false when properties is empty" do
      tool = described_class.new(simple_proc)
      tool.instance_variable_set(:@parameters, { type: "object", properties: {} })
      expect(tool.parameters?).to be false
    end
  end

  describe "#required_parameters?" do
    it "returns true when tool has required parameters" do
      tool = described_class.new(proc { |required:| required })
      expect(tool.required_parameters?).to be true
    end

    it "returns false when tool has only optional parameters" do
      tool = described_class.new(proc { |optional: "default"| optional })
      expect(tool.required_parameters?).to be false
    end

    it "returns false when required array is empty" do
      tool = described_class.new(proc { "no params" })
      expect(tool.required_parameters?).to be false
    end

    it "returns false when parameters is nil" do
      tool = described_class.new(simple_proc)
      tool.instance_variable_set(:@parameters, nil)
      expect(tool.required_parameters?).to be false
    end
  end

  describe ".enabled_tools" do
    let(:enabled_tool) { described_class.new(simple_proc, name: "enabled") }
    let(:disabled_tool) { described_class.new(simple_proc, name: "disabled", is_enabled: false) }
    let(:conditional_tool) do
      described_class.new(simple_proc, name: "conditional", is_enabled: proc { |ctx| ctx == :allowed })
    end
    let(:hash_tool) { { type: "web_search", name: "search" } }

    it "filters out disabled tools" do
      tools = [enabled_tool, disabled_tool]
      result = described_class.enabled_tools(tools)
      
      expect(result).to eq([enabled_tool])
    end

    it "includes tools without enabled? method" do
      tools = [enabled_tool, hash_tool]
      result = described_class.enabled_tools(tools)
      
      expect(result).to eq([enabled_tool, hash_tool])
    end

    it "passes context to conditional tools" do
      tools = [conditional_tool]
      
      result_allowed = described_class.enabled_tools(tools, :allowed)
      expect(result_allowed).to eq([conditional_tool])
      
      result_denied = described_class.enabled_tools(tools, :denied)
      expect(result_denied).to be_empty
    end

    it "handles empty tools array" do
      result = described_class.enabled_tools([])
      expect(result).to be_empty
    end

    it "handles mixed tool types" do
      tools = [enabled_tool, disabled_tool, hash_tool, conditional_tool]
      result = described_class.enabled_tools(tools, :allowed)
      
      expect(result).to contain_exactly(enabled_tool, hash_tool, conditional_tool)
    end
  end

  describe "#to_h" do
    it "generates OpenAI-compatible function definition" do
      tool = described_class.new(
        proc { |query:| "search for #{query}" },
        name: "web_search",
        description: "Search the web"
      )

      result = tool.to_h
      
      expect(result).to eq({
        type: "function",
        name: "web_search",
        function: {
          name: "web_search",
          description: "Search the web",
          parameters: tool.parameters
        }
      })
    end

    it "includes extracted parameters in definition" do
      def complex_method(required:, optional: "default", **kwargs)
        { required: required, optional: optional, extra: kwargs }
      end

      tool = described_class.new(method(:complex_method))
      result = tool.to_h

      params = result[:function][:parameters]
      expect(params[:type]).to eq("object")
      expect(params[:properties]).to have_key(:required)
      expect(params[:properties]).to have_key(:optional)
      expect(params[:required]).to eq([:required])
    end
  end

  describe "parameter extraction" do
    it "handles required keyword arguments" do
      tool = described_class.new(proc { |a:, b:| a + b })
      params = tool.parameters
      
      expect(params[:properties]).to have_key(:a)
      expect(params[:properties]).to have_key(:b)
      expect(params[:required]).to contain_exactly(:a, :b)
    end

    it "handles optional keyword arguments" do
      tool = described_class.new(proc { |a: 1, b: 2| a + b })
      params = tool.parameters
      
      expect(params[:properties]).to have_key(:a)
      expect(params[:properties]).to have_key(:b)
      expect(params[:required]).to be_empty
    end

    it "handles mixed positional arguments" do
      def mixed_method(required, optional = nil)
        [required, optional]
      end

      tool = described_class.new(method(:mixed_method))
      params = tool.parameters
      
      expect(params[:properties]).to have_key(:required)
      expect(params[:properties]).to have_key(:optional)
      expect(params[:required]).to eq([:required])
    end

    it "ignores splat and block parameters" do
      def complex_params(normal, *splat, **kwargs, &block)
        { normal: normal, splat: splat, kwargs: kwargs, block: block }
      end

      tool = described_class.new(method(:complex_params))
      params = tool.parameters
      
      expect(params[:properties]).to have_key(:normal)
      expect(params[:properties]).not_to have_key(:splat)
      expect(params[:properties]).not_to have_key(:kwargs)
      expect(params[:properties]).not_to have_key(:block)
    end

    it "sets additionalProperties to false" do
      tool = described_class.new(simple_proc)
      expect(tool.parameters[:additionalProperties]).to be false
    end
  end

  describe "logging behavior" do
    it "logs debug information during initialization" do
      allow_any_instance_of(described_class).to receive(:log_debug_tools)
      
      tool = described_class.new(simple_proc, name: "test", parameters: { custom: true })
      
      expect(tool).to have_received(:log_debug_tools).at_least(:once)
    end

    it "logs when generating to_h output" do
      tool = described_class.new(simple_proc, name: "test")
      allow(tool).to receive(:log_debug_tools)
      
      tool.to_h
      
      expect(tool).to have_received(:log_debug_tools).with(
        "FunctionTool.to_h generated",
        hash_including(tool_name: "test")
      )
    end
  end

  describe "integration scenarios" do
    it "works with agent handoff tools" do
      handoff_proc = proc do |input: nil|
        {
          __raaf_handoff__: true,
          target_agent: "SupportAgent",
          handoff_data: { input: input }
        }
      end

      tool = described_class.new(
        handoff_proc,
        name: "transfer_to_support",
        description: "Transfer to support agent"
      )

      result = tool.call(input: "Help needed")
      expect(result[:__raaf_handoff__]).to be true
      expect(result[:target_agent]).to eq("SupportAgent")
    end

    it "handles tools with complex return types" do
      complex_tool = proc do |action:|
        case action
        when "array"
          [1, 2, 3]
        when "hash"
          { data: "complex", nested: { value: 42 } }
        when "nil"
          nil
        else
          "string"
        end
      end

      tool = described_class.new(complex_tool, name: "complex_returns")
      
      expect(tool.call(action: "array")).to eq([1, 2, 3])
      expect(tool.call(action: "hash")).to eq({ data: "complex", nested: { value: 42 } })
      expect(tool.call(action: "nil")).to be_nil
      expect(tool.call(action: "other")).to eq("string")
    end

    it "supports dynamic enabling based on agent state" do
      agent_context = double("context", user_role: "admin")
      
      admin_tool = described_class.new(
        proc { "admin action" },
        name: "admin_tool",
        is_enabled: proc { |ctx| ctx&.user_role == "admin" }
      )

      expect(admin_tool.enabled?(agent_context)).to be true
      
      user_context = double("context", user_role: "user")
      expect(admin_tool.enabled?(user_context)).to be false
    end
  end
end