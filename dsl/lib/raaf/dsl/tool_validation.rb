# frozen_string_literal: true

module RAAF
  module DSL
    # Tool parameter validation module
    #
    # Provides parameter validation capabilities for tool execution in DSL agents.
    # This module is included in RAAF::DSL::Agent to provide automatic validation
    # of tool parameters before execution.
    #
    # @example Using validation in an agent
    #   class MyAgent < RAAF::DSL::Agent
    #     tool_execution do
    #       enable_validation true
    #     end
    #   end
    #
    module ToolValidation
      # Validate tool arguments against the tool's definition
      #
      # Checks that all required parameters are present and that parameter types
      # match the tool definition. Validation only occurs if the tool has a
      # tool_definition method.
      #
      # @param tool [Object] The tool being executed
      # @param arguments [Hash] Arguments passed to the tool
      # @raise [ArgumentError] If required parameters are missing or types are incorrect
      # @return [void]
      #
      def validate_tool_arguments(tool, arguments)
        # Skip validation if tool has no definition
        return unless tool.respond_to?(:tool_definition)

        definition = tool.tool_definition
        return unless definition && definition[:function]

        function_params = definition[:function][:parameters]
        return unless function_params

        required_params = function_params[:required] || []
        properties = function_params[:properties] || {}

        # Check required parameters
        validate_required_parameters(required_params, arguments)

        # Validate parameter types
        validate_parameter_types(arguments, properties)
      end

      private

      # Validate that all required parameters are present
      #
      # @param required_params [Array<String>] List of required parameter names
      # @param arguments [Hash] Arguments provided
      # @raise [ArgumentError] If a required parameter is missing
      # @return [void]
      #
      def validate_required_parameters(required_params, arguments)
        required_params.each do |param|
          # Check both symbol and string keys for flexibility
          unless arguments.key?(param.to_sym) || arguments.key?(param.to_s)
            raise ArgumentError, "Missing required parameter: #{param}"
          end
        end
      end

      # Validate parameter types against tool definition
      #
      # @param arguments [Hash] Arguments provided
      # @param properties [Hash] Parameter definitions from tool
      # @return [void]
      #
      def validate_parameter_types(arguments, properties)
        arguments.each do |key, value|
          # Find parameter definition (check both string and symbol keys)
          param_def = properties[key.to_s] || properties[key.to_sym]
          next unless param_def

          validate_parameter_type(key, value, param_def)
        end
      end

      # Validate a single parameter's type
      #
      # @param key [String, Symbol] Parameter name
      # @param value [Object] Parameter value
      # @param definition [Hash] Parameter definition
      # @raise [ArgumentError] If the parameter type is incorrect
      # @return [void]
      #
      def validate_parameter_type(key, value, definition)
        expected_type = definition[:type]

        case expected_type
        when "string"
          unless value.is_a?(String)
            raise ArgumentError, "Parameter #{key} must be a string"
          end
        when "integer"
          unless value.is_a?(Integer)
            raise ArgumentError, "Parameter #{key} must be an integer"
          end
        when "number"
          unless value.is_a?(Numeric)
            raise ArgumentError, "Parameter #{key} must be a number"
          end
        when "array"
          unless value.is_a?(Array)
            raise ArgumentError, "Parameter #{key} must be an array"
          end
        when "object"
          unless value.is_a?(Hash)
            raise ArgumentError, "Parameter #{key} must be an object (Hash)"
          end
        when "boolean"
          unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
            raise ArgumentError, "Parameter #{key} must be a boolean"
          end
        end
      end
    end
  end
end
