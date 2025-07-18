# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe RAAF::DSL::ToolDsl do
  let(:tool_class) do
    Class.new(RAAF::DSL::Tools::Base) do
      include RAAF::DSL::ToolDsl

      tool_name "test_tool"
      description "A test tool for configuration testing"
      version "1.0.0"
      category "testing"

      parameter :query, type: :string, required: true, description: "Search query"
      parameter :limit, type: :integer, default: 10, description: "Result limit"
      parameter :enabled, type: :boolean, default: true

      validates :query, presence: true, length: { minimum: 1 }
      validates :limit, numericality: { in: 1..100 }
    end
  end

  let(:tool_instance) { tool_class.new }

  describe "class methods" do
    describe "#tool_name" do
      it "sets and gets tool name" do
        expect(tool_class.tool_name).to eq("test_tool")
      end

      it "defaults to class name when not set" do
        unnamed_class = Class.new(RAAF::DSL::Tools::Base) do
          include RAAF::DSL::ToolDsl
        end
        # Should not raise error and provide reasonable default
        expect(unnamed_class.tool_name).to be_a(String)
      end
    end

    describe "#description" do
      it "sets and gets description" do
        expect(tool_class.description).to eq("A test tool for configuration testing")
      end

      it "returns nil when not set" do
        class_without_desc = Class.new(RAAF::DSL::Tools::Base) do
          include RAAF::DSL::ToolDsl
        end
        expect(class_without_desc.description).to be_nil
      end
    end

    describe "#version" do
      it "sets and gets version" do
        expect(tool_class.version).to eq("1.0.0")
      end

      it "defaults to 1.0.0 when not set" do
        class_without_version = Class.new(RAAF::DSL::Tools::Base) do
          include RAAF::DSL::ToolDsl
        end
        expect(class_without_version.version).to eq("1.0.0")
      end
    end

    describe "#category" do
      it "sets and gets category" do
        expect(tool_class.category).to eq("testing")
      end

      it "returns nil when not set" do
        class_without_category = Class.new(RAAF::DSL::Tools::Base) do
          include RAAF::DSL::ToolDsl
        end
        expect(class_without_category.category).to be_nil
      end
    end

    describe "#parameter" do
      it "defines basic parameters" do
        params = tool_class._parameters_config

        expect(params[:query]).to include(
          type: :string,
          required: true,
          description: "Search query"
        )

        expect(params[:limit]).to include(
          type: :integer,
          default: 10,
          description: "Result limit"
        )

        expect(params[:enabled]).to include(
          type: :boolean,
          default: true
        )
      end

      it "supports nested object parameters" do
        nested_class = Class.new(RAAF::DSL::Tools::Base) do
          include RAAF::DSL::ToolDsl

          parameter :filters, type: :object do
            field :date_range, type: :string, enum: %w[today week month]
            field :include_images, type: :boolean, default: false
          end
        end

        params = nested_class._parameters_config
        expect(params[:filters][:properties]).to include(
          date_range: { type: :string, required: false, default: nil, enum: %w[today week month] },
          include_images: { type: :boolean, required: false, default: false }
        )
      end
    end

    describe "#validates" do
      it "stores validation configurations" do
        validations = tool_class._validations_config

        expect(validations).to include(
          { param: :query, options: { presence: true, length: { minimum: 1 } } },
          { param: :limit, options: { numericality: { in: 1..100 } } }
        )
      end
    end

    describe "#tool_configuration" do
      it "returns complete tool configuration" do
        config = tool_class.tool_configuration

        expect(config).to include(
          name: "test_tool",
          description: "A test tool for configuration testing",
          version: "1.0.0",
          category: "testing",
          parameters: tool_class._parameters_config,
          validations: tool_class._validations_config
        )
      end

      it "omits nil values" do
        minimal_class = Class.new(RAAF::DSL::Tools::Base) do
          include RAAF::DSL::ToolDsl
          tool_name "minimal"
        end

        config = minimal_class.tool_configuration
        expect(config.keys).not_to include(:description, :category)
        expect(config[:name]).to eq("minimal")
      end
    end
  end

  describe "instance methods" do
    describe "#tool_definition" do
      it "returns OpenAI function format" do
        definition = tool_instance.tool_definition

        expect(definition).to include(
          type: "function",
          function: hash_including(
            name: "test_tool",
            description: "A test tool for configuration testing",
            parameters: hash_including(
              type: "object",
              properties: hash_including(
                query: { type: "string", description: "Search query" },
                limit: { type: "integer", description: "Result limit", default: 10 },
                enabled: { type: "boolean", default: true }
              ),
              required: ["query"]
            )
          )
        )
      end

      it "handles tools without required parameters" do
        optional_class = Class.new(RAAF::DSL::Tools::Base) do
          include RAAF::DSL::ToolDsl

          tool_name "optional_tool"
          parameter :optional_param, type: :string, default: "default_value"
        end

        instance = optional_class.new
        definition = instance.tool_definition

        expect(definition[:function][:parameters][:required]).to be_nil
      end

      it "handles nested object parameters in OpenAI format" do
        nested_class = Class.new(RAAF::DSL::Tools::Base) do
          include RAAF::DSL::ToolDsl

          tool_name "nested_tool"
          parameter :config, type: :object do
            field :timeout, type: :integer, default: 30
            field :retries, type: :integer, required: true
          end
        end

        instance = nested_class.new
        definition = instance.tool_definition

        config_param = definition[:function][:parameters][:properties][:config]
        expect(config_param).to include(
          type: "object",
          properties: {
            timeout: { type: "integer", default: 30 },
            retries: { type: "integer" }
          }
        )
      end
    end

    describe "#build_tool_definition" do
      it "delegates to tool_definition" do
        expect(tool_instance.build_tool_definition).to eq(tool_instance.tool_definition)
      end
    end

    describe "parameter type conversion" do
      let(:type_class) do
        Class.new(RAAF::DSL::Tools::Base) do
          include RAAF::DSL::ToolDsl

          tool_name "type_test"
          parameter :string_param, type: :string
          parameter :integer_param, type: :integer
          parameter :boolean_param, type: :boolean
          parameter :array_param, type: :array
          parameter :object_param, type: :object
          parameter :unknown_param, type: :unknown_type
        end
      end

      it "converts DSL types to OpenAI types correctly" do
        instance = type_class.new
        properties = instance.tool_definition[:function][:parameters][:properties]

        expect(properties[:string_param][:type]).to eq("string")
        expect(properties[:integer_param][:type]).to eq("integer")
        expect(properties[:boolean_param][:type]).to eq("boolean")
        expect(properties[:array_param][:type]).to eq("array")
        expect(properties[:object_param][:type]).to eq("object")
        expect(properties[:unknown_param][:type]).to eq("string") # defaults to string
      end
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new(RAAF::DSL::Tools::Base) do
        include RAAF::DSL::ToolDsl

        tool_name "parent_tool"
        description "Parent tool"
        parameter :parent_param, type: :string, required: true

        validates :parent_param, presence: true
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        tool_name "child_tool"
        parameter :child_param, type: :integer, default: 42
      end
    end

    it "inherits parent configuration" do
      child_config = child_class.tool_configuration

      expect(child_config[:name]).to eq("child_tool")
      expect(child_config[:description]).to eq("Parent tool")

      # Should have both parent and child parameters
      expect(child_config[:parameters]).to include(:parent_param, :child_param)

      # Should inherit validations
      expect(child_config[:validations]).to include(
        { param: :parent_param, options: { presence: true } }
      )
    end

    it "child can override parent configuration" do
      child_class.description "Child tool description"

      expect(child_class.description).to eq("Child tool description")
      expect(parent_class.description).to eq("Parent tool") # Parent unchanged
    end
  end

  describe "NestedParameterBuilder" do
    let(:builder) { RAAF::DSL::ToolDsl::NestedParameterBuilder.new }

    it "builds nested parameter structures" do
      builder.field :name, type: :string, required: true
      builder.field :age, type: :integer, default: 0
      builder.field :active, type: :boolean, default: true, description: "Is active"

      expect(builder.properties).to eq({
                                         name: { type: :string, required: true, default: nil },
                                         age: { type: :integer, required: false, default: 0 },
                                         active: { type: :boolean, required: false, default: true,
                                                   description: "Is active" }
                                       })
    end
  end

  describe "edge cases" do
    it "handles empty tool configuration" do
      empty_class = Class.new(RAAF::DSL::Tools::Base) do
        include RAAF::DSL::ToolDsl
      end

      instance = empty_class.new
      definition = instance.tool_definition

      expect(definition[:function][:name]).to be_a(String)
      expect(definition[:function][:description]).to eq("AI tool")
      expect(definition[:function][:parameters][:properties]).to be_empty
    end

    it "handles parameters with enum options" do
      enum_class = Class.new(RAAF::DSL::Tools::Base) do
        include RAAF::DSL::ToolDsl

        tool_name "enum_tool"
        parameter :mode, type: :string, enum: %w[fast accurate balanced]
      end

      instance = enum_class.new
      mode_param = instance.tool_definition[:function][:parameters][:properties][:mode]

      expect(mode_param).to include(enum: %w[fast accurate balanced])
    end
  end
end
