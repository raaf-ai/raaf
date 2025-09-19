# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Tools::Tool do
  # Create a concrete test tool class for testing
  let(:test_tool_class) do
    Class.new(described_class) do
      def self.name
        "TestTool"
      end

      def call(query:, limit: 10, format: "json")
        {
          query: query,
          limit: limit,
          format: format,
          results: ["result1", "result2"]
        }
      end
    end
  end

  describe "class methods" do
    describe "ConventionOverConfiguration integration" do
      it "generates tool name from class name" do
        expect(test_tool_class.tool_name).to be_a(String)
        expect(test_tool_class.tool_name).not_to be_empty
      end

      it "generates tool description automatically" do
        expect(test_tool_class.tool_description).to be_a(String)
        expect(test_tool_class.tool_description).not_to be_empty
      end

      it "generates parameter schema from call method signature" do
        schema = test_tool_class.parameter_schema
        expect(schema).to be_a(Hash)
        expect(schema[:type]).to eq("object")
        expect(schema[:properties]).to be_a(Hash)
      end

      it "includes required parameters in schema" do
        schema = test_tool_class.parameter_schema
        expect(schema[:required]).to include("query")
      end

      it "includes optional parameters with defaults" do
        schema = test_tool_class.parameter_schema
        expect(schema[:properties]).to have_key("limit")
        expect(schema[:properties]).to have_key("format")
      end
    end

    describe "class configuration" do
      it "can be configured with custom name and description" do
        configured_class = Class.new(described_class) do
          configure name: "custom_tool", description: "Custom description"

          def call(param:)
            { result: param }
          end
        end

        expect(configured_class.tool_name).to eq("custom_tool")
        expect(configured_class.tool_description).to eq("Custom description")
      end

      it "uses enabled status from configuration" do
        disabled_class = Class.new(described_class) do
          configure enabled: false

          def call
            { result: "test" }
          end
        end

        expect(disabled_class.tool_enabled).to eq(false)
      end
    end
  end

  describe "instance methods" do
    let(:tool_instance) { test_tool_class.new }

    describe "#initialize" do
      it "accepts options hash" do
        options = { name: "custom", description: "test" }
        tool = test_tool_class.new(options)
        expect(tool.options).to eq(options)
      end

      it "works with empty options" do
        expect { test_tool_class.new }.not_to raise_error
        expect { test_tool_class.new({}) }.not_to raise_error
      end
    end

    describe "#call" do
      it "raises NotImplementedError in base class" do
        base_tool = described_class.new({})
        expect { base_tool.call }.to raise_error(NotImplementedError)
      end

      it "executes with correct parameters in subclass" do
        result = tool_instance.call(query: "test query", limit: 5)
        expect(result[:query]).to eq("test query")
        expect(result[:limit]).to eq(5)
        expect(result[:results]).to eq(["result1", "result2"])
      end

      it "uses default parameter values" do
        result = tool_instance.call(query: "test")
        expect(result[:limit]).to eq(10)
        expect(result[:format]).to eq("json")
      end
    end

    describe "#enabled?" do
      it "returns true by default" do
        expect(tool_instance.enabled?).to eq(true)
      end

      it "can be disabled via options" do
        disabled_tool = test_tool_class.new(enabled: false)
        expect(disabled_tool.enabled?).to eq(false)
      end

      it "can be enabled explicitly via options" do
        enabled_tool = test_tool_class.new(enabled: true)
        expect(enabled_tool.enabled?).to eq(true)
      end
    end

    describe "#name" do
      it "returns tool name from class" do
        expect(tool_instance.name).to eq(test_tool_class.tool_name)
      end

      it "can be overridden via options" do
        custom_tool = test_tool_class.new(name: "custom_name")
        expect(custom_tool.name).to eq("custom_name")
      end
    end

    describe "#description" do
      it "returns tool description from class" do
        expect(tool_instance.description).to eq(test_tool_class.tool_description)
      end

      it "can be overridden via options" do
        custom_tool = test_tool_class.new(description: "custom description")
        expect(custom_tool.description).to eq("custom description")
      end
    end

    describe "#to_tool_definition" do
      it "returns complete tool definition" do
        definition = tool_instance.to_tool_definition

        expect(definition[:type]).to eq("function")
        expect(definition[:function]).to be_a(Hash)
        expect(definition[:function][:name]).to be_present
        expect(definition[:function][:description]).to be_present
        expect(definition[:function][:parameters]).to be_a(Hash)
      end

      it "includes parameter schema" do
        definition = tool_instance.to_tool_definition
        parameters = definition[:function][:parameters]

        expect(parameters[:type]).to eq("object")
        expect(parameters[:properties]).to include("query", "limit", "format")
        expect(parameters[:required]).to include("query")
      end
    end

    describe "#process_result" do
      it "returns result unchanged by default" do
        result = { test: "data" }
        expect(tool_instance.process_result(result)).to eq(result)
      end
    end

    describe "#tool_configuration" do
      it "returns complete configuration hash" do
        config = tool_instance.tool_configuration

        expect(config[:tool]).to eq(tool_instance.to_tool_definition)
        expect(config[:callable]).to eq(tool_instance)
        expect(config[:enabled]).to eq(tool_instance.enabled?)
        expect(config[:metadata]).to be_a(Hash)
        expect(config[:metadata][:class]).to eq(test_tool_class.name)
        expect(config[:metadata][:options]).to eq(tool_instance.options)
      end
    end
  end

  describe "inheritance" do
    let(:parent_tool_class) do
      Class.new(described_class) do
        def self.name
          "ParentTool"
        end

        def call(base_param:)
          { result: "parent", base_param: base_param }
        end
      end
    end

    let(:child_tool_class) do
      Class.new(parent_tool_class) do
        def self.name
          "ChildTool"
        end

        def call(base_param:, child_param: "default")
          result = super(base_param: base_param)
          result.merge(child_param: child_param, result: "child: #{result[:result]}")
        end
      end
    end

    it "generates different names for parent and child" do
      expect(parent_tool_class.tool_name).not_to eq(child_tool_class.tool_name)
    end

    it "generates parameter schema for child class" do
      schema = child_tool_class.parameter_schema
      expect(schema[:properties]).to include("base_param", "child_param")
      expect(schema[:required]).to include("base_param")
    end

    it "allows method override with super" do
      child_tool = child_tool_class.new
      result = child_tool.call(base_param: "test", child_param: "custom")

      expect(result[:result]).to eq("child: parent")
      expect(result[:base_param]).to eq("test")
      expect(result[:child_param]).to eq("custom")
    end
  end

  describe "parameter type inference" do
    let(:typed_tool_class) do
      Class.new(described_class) do
        def self.name
          "TypedTool"
        end

        def call(count:, email:, enabled:, tags:, config:)
          {
            count: count,
            email: email,
            enabled: enabled,
            tags: tags,
            config: config
          }
        end
      end
    end

    it "infers integer type for count parameters" do
      schema = typed_tool_class.parameter_schema
      expect(schema[:properties]["count"][:type]).to eq("integer")
    end

    it "infers string type for email parameters" do
      schema = typed_tool_class.parameter_schema
      expect(schema[:properties]["email"][:type]).to eq("string")
    end

    it "infers boolean type for enabled parameters" do
      schema = typed_tool_class.parameter_schema
      expect(schema[:properties]["enabled"][:type]).to eq("boolean")
    end

    it "infers array type for tags parameters" do
      schema = typed_tool_class.parameter_schema
      expect(schema[:properties]["tags"][:type]).to eq("array")
    end

    it "infers object type for config parameters" do
      schema = typed_tool_class.parameter_schema
      expect(schema[:properties]["config"][:type]).to eq("object")
    end
  end

  describe "edge cases" do
    it "handles tools without call method" do
      no_call_class = Class.new(described_class) do
        def self.name
          "NoCallTool"
        end
      end

      expect(no_call_class.parameter_schema).to be_a(Hash)
      expect(no_call_class.parameter_schema[:properties]).to eq({})
    end

    it "handles anonymous classes" do
      anonymous_class = Class.new(described_class) do
        def call
          { result: "anonymous" }
        end
      end

      expect(anonymous_class.tool_name).to eq("anonymous_tool")
      expect(anonymous_class.tool_description).to include("Anonymous tool")
    end

    it "handles tools with no parameters" do
      no_params_class = Class.new(described_class) do
        def self.name
          "NoParamsTool"
        end

        def call
          { result: "success" }
        end
      end

      schema = no_params_class.parameter_schema
      expect(schema[:properties]).to eq({})
      expect(schema[:required]).to eq([])
    end
  end
end