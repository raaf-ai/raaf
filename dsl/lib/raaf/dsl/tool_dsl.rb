# frozen_string_literal: true

# DSL for defining AI tool configurations in a declarative way
#
# Provides a clean, readable interface for configuring tools with
# parameters, validation, and metadata. This DSL is configuration-only
# and does not handle tool execution - that is delegated to the OpenAI
# Agents framework.
#
# Usage:
#   class MyTool < RAAF::DSL::Tools::Base
#     include RAAF::DSL::ToolDsl
#
#     tool_name "my_tool"
#     description "A tool for doing something useful"
#     version "1.0.0"
#
#     parameter :query, type: :string, required: true, description: "Search query"
#     parameter :limit, type: :integer, default: 10, range: 1..100
#     parameter :options, type: :object do
#       field :include_images, type: :boolean, default: false
#       field :language, type: :string, enum: ["en", "es", "fr"]
#     end
#
#     validates :query, presence: true, length: { minimum: 1 }
#     validates :limit, numericality: { in: 1..100 }
#   end
#
# DSL for defining AI tool configurations in a declarative way
#
# Provides a clean, readable interface for configuring tools with
# parameters, validation, and metadata. This DSL is configuration-only
# and generates tool definitions that are passed to the RAAF
# framework for execution.
#
# @example Basic usage
#   class MyTool < RAAF::DSL::Tools::Base
#     include RAAF::DSL::ToolDsl
#
#     tool_name "my_tool"
#     description "A tool for doing something useful"
#     parameter :query, type: :string, required: true
#   end
#
# @example Complex parameters
#   class AdvancedTool < RAAF::DSL::Tools::Base
#     include RAAF::DSL::ToolDsl
#
#     tool_name "advanced_search"
#     description "Advanced search with filtering"
#
#     parameter :query, type: :string, required: true, description: "Search query"
#     parameter :limit, type: :integer, default: 10, description: "Maximum results"
#     parameter :filters, type: :object do
#       field :date_range, type: :string, enum: ["today", "week", "month"]
#       field :include_images, type: :boolean, default: false
#     end
#   end
#
module RAAF
  module DSL
    module ToolDsl
      extend ActiveSupport::Concern

      included do
        class_attribute :_tool_config, default: {}
        class_attribute :_parameters_config, default: {}
        class_attribute :_validations_config, default: []
      end

      class_methods do
        # Configure tool basic properties

        # Set or get the tool name
        #
        # @param name [String, nil] Tool name to set, or nil to get current name
        # @return [String] Current tool name
        #
        def tool_name(name = nil)
          if name
            _tool_config[:name] = name
          else
            _tool_config[:name] || self.name.demodulize.underscore
          end
        end

        # Set or get the tool description
        #
        # @param desc [String, nil] Description to set, or nil to get current description
        # @return [String, nil] Current description
        #
        def description(desc = nil)
          if desc
            _tool_config[:description] = desc
          else
            _tool_config[:description]
          end
        end

        # Set or get the tool version
        #
        # @param ver [String, nil] Version to set, or nil to get current version
        # @return [String] Current version (defaults to "1.0.0")
        #
        def version(ver = nil)
          if ver
            _tool_config[:version] = ver
          else
            _tool_config[:version] || "1.0.0"
          end
        end

        # Set or get the tool category
        #
        # @param cat [String, nil] Category to set, or nil to get current category
        # @return [String, nil] Current category
        #
        def category(cat = nil)
          if cat
            _tool_config[:category] = cat
          else
            _tool_config[:category]
          end
        end

        # Define a parameter for the tool
        #
        # @param name [Symbol] Parameter name
        # @param type [Symbol] Parameter type (:string, :integer, :boolean, :object, :array)
        # @param required [Boolean] Whether parameter is required
        # @param default [Object] Default value if not provided
        # @param description [String] Parameter description
        # @param options [Hash] Additional parameter options (enum, range, etc.)
        # @param block [Proc] Block for defining nested object structure
        #
        def parameter(name, type:, required: false, default: nil, description: nil, **options, &block)
          param_config = {
            type: type,
            required: required,
            default: default,
            description: description,
            **options
          }

          # Handle nested object parameters
          if type == :object && block_given?
            nested_builder = NestedParameterBuilder.new
            nested_builder.instance_eval(&block)
            param_config[:properties] = nested_builder.properties
          end

          _parameters_config[name] = param_config
        end

        # Add validation for a parameter
        #
        # @param param_name [Symbol] Parameter to validate
        # @param validation_options [Hash] Validation options
        #
        def validates(param_name, **validation_options)
          _validations_config << { param: param_name, options: validation_options }
        end

        # Get the complete tool configuration
        #
        # @return [Hash] Tool configuration for RAAF framework
        #
        def tool_configuration
          {
            name: tool_name,
            description: description,
            version: version,
            category: category,
            parameters: _parameters_config,
            validations: _validations_config
          }.compact
        end
      end

      # Instance methods for tool configuration access

      # Get the tool name from class configuration
      #
      # @return [String] The tool name
      #
      def tool_name
        self.class.tool_name
      end

      # Get the tool description from class configuration
      #
      # @return [String, nil] The tool description
      #
      def description
        self.class.description
      end

      # Get the tool version from class configuration
      #
      # @return [String, nil] The tool version
      #
      def version
        self.class.version
      end

      # Get the tool category from class configuration
      #
      # @return [String, nil] The tool category
      #
      def category
        self.class.category
      end

      # Get tool definition in OpenAI function format
      #
      # @return [Hash] OpenAI function tool definition
      #
      def tool_definition
        {
          type: "function",
          function: {
            name: self.class.tool_name,
            description: self.class.description || "AI tool",
            parameters: build_openai_parameters_schema
          }
        }
      end

      # Build tool configuration for RAAF framework
      #
      # @return [Hash] Complete tool configuration
      #
      def build_tool_definition
        tool_definition
      end

      private

      # Build OpenAI-compatible parameters schema
      #
      # @return [Hash] Parameters schema in OpenAI format
      #
      def build_openai_parameters_schema
        schema = {
          type: "object",
          properties: {},
          required: []
        }

        self.class._parameters_config.each do |name, config|
          schema[:properties][name] = build_parameter_schema(config)
          schema[:required] << name if config[:required]
        end

        schema[:required] = schema[:required].empty? ? nil : schema[:required]
        schema.compact
      end

      # Build schema for a single parameter
      #
      # @param config [Hash] Parameter configuration
      # @return [Hash] Parameter schema
      #
      def build_parameter_schema(config)
        schema = { type: openai_type(config[:type]) }
        schema[:description] = config[:description] if config[:description]
        schema[:enum] = config[:enum] if config[:enum]
        schema[:default] = config[:default] if config.key?(:default)

        # Handle array items
        schema[:items] = { type: openai_type(config[:items_type]) } if config[:type] == :array && config[:items_type]

        # Handle nested object properties
        if config[:type] == :object && config[:properties]
          schema[:properties] = {}
          config[:properties].each do |prop_name, prop_config|
            schema[:properties][prop_name] = build_parameter_schema(prop_config)
          end
        end

        schema
      end

      # Convert DSL types to OpenAI types
      #
      # @param dsl_type [Symbol] DSL parameter type
      # @return [String] OpenAI parameter type
      #
      def openai_type(dsl_type)
        case dsl_type
        when :integer then "integer"
        when :boolean then "boolean"
        when :array then "array"
        when :object then "object"
        else "string"
        end
      end

      # Helper class for building nested parameter structures
      class NestedParameterBuilder
        attr_reader :properties

        def initialize
          @properties = {}
        end

        # Define a field in a nested object
        #
        # @param name [Symbol] Field name
        # @param type [Symbol] Field type
        # @param required [Boolean] Whether field is required
        # @param default [Object] Default value
        # @param options [Hash] Additional field options
        #
        def field(name, type:, required: false, default: nil, **options)
          @properties[name] = {
            type: type,
            required: required,
            default: default,
            **options
          }
        end
      end
    end
  end
end
