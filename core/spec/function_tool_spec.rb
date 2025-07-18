# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::FunctionTool do
  describe "#initialize" do
    it "creates a tool with a proc" do
      tool_proc = proc { |value| value * 2 }
      tool = described_class.new(tool_proc)

      expect(tool.callable).to eq(tool_proc)
      expect(tool.name).to eq("anonymous_function")
      expect(tool.description).to eq("A function tool")
      expect(tool.parameters).to be_a(Hash)
    end

    it "creates a tool with a method" do
      def test_method(value)
        value * 2
      end

      tool = described_class.new(method(:test_method))

      expect(tool.callable).to be_a(Method)
      expect(tool.name).to eq("test_method")
      expect(tool.description).to eq("A function tool")
    end

    it "accepts custom name and description" do
      tool_proc = proc { |value| value * 2 }
      tool = described_class.new(
        tool_proc,
        name: "double",
        description: "Doubles a number"
      )

      expect(tool.name).to eq("double")
      expect(tool.description).to eq("Doubles a number")
    end

    it "accepts custom parameters" do
      tool_proc = proc { |value| value * 2 }
      custom_params = {
        type: "object",
        properties: {
          value: { type: "number", description: "Number to double" }
        },
        required: ["value"]
      }

      tool = described_class.new(tool_proc, parameters: custom_params)

      expect(tool.parameters).to eq(custom_params)
    end
  end

  describe "#call" do
    it "executes a proc with keyword arguments" do
      tool_proc = proc { |first_value:, second_value: 1| (first_value * 2) + second_value }
      tool = described_class.new(tool_proc)

      result = tool.call(first_value: 5, second_value: 3)
      expect(result).to eq(13)
    end

    it "executes a method with keyword arguments" do
      def multiply_add(first_value:, second_value: 1)
        (first_value * 2) + second_value
      end

      tool = described_class.new(method(:multiply_add))

      result = tool.call(first_value: 5, second_value: 3)
      expect(result).to eq(13)
    end

    it "handles proc with no arguments" do
      tool_proc = proc { "Hello World" }
      tool = described_class.new(tool_proc)

      result = tool.call
      expect(result).to eq("Hello World")
    end

    it "handles method with no arguments" do
      def no_args_method
        "Hello World"
      end

      tool = described_class.new(method(:no_args_method))

      result = tool.call
      expect(result).to eq("Hello World")
    end

    it "raises ToolError for invalid callable" do
      tool = described_class.new("not_callable")

      expect { tool.call }.to raise_error(RAAF::ToolError, /Callable must be a Method or Proc/)
    end

    it "wraps execution errors in ToolError" do
      tool_proc = proc { raise StandardError, "Something went wrong" }
      tool = described_class.new(tool_proc, name: "failing_tool")

      expect do
        tool.call
      end.to raise_error(RAAF::ToolError, /Error executing tool 'failing_tool': Something went wrong/)
    end

    context "with different argument types" do
      it "handles required arguments" do
        def required_args(name:, age:)
          "#{name} is #{age} years old"
        end

        tool = described_class.new(method(:required_args))

        result = tool.call(name: "Alice", age: 30)
        expect(result).to eq("Alice is 30 years old")
      end

      it "handles optional arguments" do
        def optional_args(name:, greeting: "Hello")
          "#{greeting}, #{name}!"
        end

        tool = described_class.new(method(:optional_args))

        result = tool.call(name: "Bob")
        expect(result).to eq("Hello, Bob!")

        result = tool.call(name: "Bob", greeting: "Hi")
        expect(result).to eq("Hi, Bob!")
      end

      it "handles keyword arguments" do
        def keyword_args(name:, age: 25)
          "#{name} is #{age} years old"
        end

        tool = described_class.new(method(:keyword_args))

        result = tool.call(name: "Charlie")
        expect(result).to eq("Charlie is 25 years old")

        result = tool.call(name: "Charlie", age: 35)
        expect(result).to eq("Charlie is 35 years old")
      end
    end
  end

  describe "#to_h" do
    it "returns hash representation for OpenAI function calling format" do
      tool_proc = proc { |value| value * 2 }
      tool = described_class.new(
        tool_proc,
        name: "double",
        description: "Doubles a number"
      )

      hash = tool.to_h

      expect(hash).to eq({
                           type: "function",
                           name: "double",
                           function: {
                             name: "double",
                             description: "Doubles a number",
                             parameters: tool.parameters
                           }
                         })
    end

    it "includes extracted parameters" do
      def test_method(required_param, optional_param = nil)
        "#{required_param} #{optional_param}"
      end

      tool = described_class.new(method(:test_method))
      hash = tool.to_h

      expect(hash[:function][:parameters]).to be_a(Hash)
      expect(hash[:function][:parameters][:type]).to eq("object")
      expect(hash[:function][:parameters][:properties]).to be_a(Hash)
    end
  end

  describe "parameter extraction" do
    describe "#extract_name" do
      it "extracts name from method" do
        def named_method(value)
          value
        end

        tool = described_class.new(method(:named_method))
        expect(tool.name).to eq("named_method")
      end

      it "handles anonymous procs" do
        tool_proc = proc { |value| value }
        tool = described_class.new(tool_proc)

        expect(tool.name).to eq("anonymous_function")
      end

      it "extracts name from callable with name method" do
        callable = double("callable")
        allow(callable).to receive(:name).and_return("custom_name")
        allow(callable).to receive(:is_a?).with(Method).and_return(false)
        allow(callable).to receive(:respond_to?).with(:name).and_return(true)
        allow(callable).to receive(:respond_to?).with(:parameters).and_return(false)

        tool = described_class.new(callable)
        expect(tool.name).to eq("custom_name")
      end
    end

    describe "#extract_parameters" do
      it "extracts required parameters" do
        def required_params(name, age)
          "#{name} #{age}"
        end

        tool = described_class.new(method(:required_params))
        params = tool.parameters

        expect(params[:properties][:name]).to be_a(Hash)
        expect(params[:properties][:age]).to be_a(Hash)
        expect(params[:required]).to include(:name, :age)
      end

      it "extracts optional parameters" do
        def optional_params(name, greeting = "Hello")
          "#{greeting} #{name}"
        end

        tool = described_class.new(method(:optional_params))
        params = tool.parameters

        expect(params[:properties][:name]).to be_a(Hash)
        expect(params[:properties][:greeting]).to be_a(Hash)
        expect(params[:required]).to include(:name)
        expect(params[:required]).not_to include(:greeting)
      end

      it "extracts keyword parameters" do
        def keyword_params(name:, age: 25)
          "#{name} #{age}"
        end

        tool = described_class.new(method(:keyword_params))
        params = tool.parameters

        expect(params[:properties]).to have_key(:name)
        expect(params[:properties]).to have_key(:age)
      end

      it "returns empty parameters for non-parametrized callables" do
        callable = double("callable")
        allow(callable).to receive(:respond_to?).with(:parameters).and_return(false)
        allow(callable).to receive(:respond_to?).with(:name).and_return(false)
        allow(callable).to receive(:is_a?).with(Method).and_return(false)

        tool = described_class.new(callable)
        params = tool.parameters

        expect(params[:properties]).to be_empty
        expect(params[:required]).to be_empty
      end

      it "sets proper schema structure" do
        def test_method(value)
          value
        end

        tool = described_class.new(method(:test_method))
        params = tool.parameters

        expect(params[:type]).to eq("object")
        expect(params[:properties]).to be_a(Hash)
        expect(params[:required]).to be_an(Array)
      end
    end
  end

  describe "edge cases" do
    it "handles proc with splat arguments" do
      tool_proc = proc { |*args| args.sum }
      tool = described_class.new(tool_proc)

      # Should not raise error during initialization
      expect(tool.parameters).to be_a(Hash)
    end

    it "handles method with block argument" do
      def method_with_block(value, &block)
        block ? block.call(value) : value
      end

      tool = described_class.new(method(:method_with_block))

      # Should not raise error during initialization
      expect(tool.parameters).to be_a(Hash)
    end

    it "handles complex parameter combinations" do
      def complex_method(req, opt = nil, *splat, key:, opt_key: "default", **kwargs)
        { req: req, opt: opt, splat: splat, key: key, opt_key: opt_key, kwargs: kwargs }
      end

      tool = described_class.new(method(:complex_method))

      # Should not raise error during initialization
      expect(tool.parameters).to be_a(Hash)
      expect(tool.parameters[:type]).to eq("object")
    end
  end

  describe "integration with Agent" do
    it "works correctly when added to an agent" do
      agent = RAAF::Agent.new(name: "TestAgent")
      tool_proc = proc { |value:| value * 2 }
      tool = described_class.new(tool_proc, name: "double")

      agent.add_tool(tool)

      result = agent.execute_tool("double", value: 5)
      expect(result).to eq(10)
    end

    it "maintains tool identity when added to agent" do
      agent = RAAF::Agent.new(name: "TestAgent")
      tool = described_class.new(proc { |value| value }, name: "identity")

      agent.add_tool(tool)

      expect(agent.tools.first).to eq(tool)
      expect(agent.tools.first.name).to eq("identity")
    end
  end
end
