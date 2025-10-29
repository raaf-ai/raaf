# frozen_string_literal: true

module RAAF
  module DSL
    # Base error class for RAAF DSL-specific errors
    class Error < StandardError; end

    # Raised when parsing AI response data fails
    class ParseError < Error
      def initialize(message = "Failed to parse AI response")
        super(message)
      end
    end

    # Raised when data validation fails in declarative agents
    class ValidationError < Error
      attr_reader :field, :value, :expected_type

      def initialize(message, field: nil, value: nil, expected_type: nil)
        @field = field
        @value = value
        @expected_type = expected_type
        super(message)
      end
    end

    # Raised when schema validation fails
    class SchemaError < ValidationError
      def initialize(message = "Response does not match expected schema")
        super(message)
      end
    end

    # Raised when configuration validation fails
    # Used by continuation configuration and other configuration validators
    class InvalidConfigurationError < Error
      def initialize(message = "Configuration is invalid")
        super(message)
      end
    end

    # Base error class for continuation-related issues
    # Used for errors that occur during continuation execution
    class ContinuationError < Error
      def initialize(message = "Continuation operation failed")
        super(message)
      end
    end

    # Raised when tool resolution fails during agent configuration
    # Provides detailed, actionable error messages with visual indicators
    class ToolResolutionError < Error
      attr_reader :identifier, :searched_namespaces, :suggestions

      # Initialize a new ToolResolutionError with comprehensive details
      #
      # @param identifier [Symbol, String, Class] The tool identifier that couldn't be resolved
      # @param searched_namespaces [Array<String>] List of namespaces that were searched
      # @param suggestions [Array<String>] Helpful suggestions for fixing the issue
      def initialize(identifier, searched_namespaces, suggestions)
        @identifier = identifier
        @searched_namespaces = searched_namespaces || []
        @suggestions = suggestions || []

        super(build_error_message)
      end

      private

      def build_error_message
        # Convert identifier to appropriate format for display
        tool_name = identifier.to_s
        tool_class_name = tool_name.split('_').map(&:capitalize).join
        tool_class_name += "Tool" unless tool_class_name.end_with?("Tool")

        # Format suggestions or provide default message
        formatted_suggestions = if @suggestions.empty?
          ["(No suggestions available)"]
        else
          @suggestions
        end

        # Format namespace list
        namespace_list = @searched_namespaces.empty? ? "(none)" : @searched_namespaces.join(", ")

        # Build the comprehensive error message
        <<~ERROR
          ❌ Tool not found: #{@identifier}

          📂 Searched in:
            - Registry: RAAF::ToolRegistry
            - Namespaces: #{namespace_list}

          💡 Suggestions:
            #{formatted_suggestions.join("\n            ")}

          🔧 To fix:
            1. Ensure the tool class exists
            2. Register it: RAAF::ToolRegistry.register(:#{tool_name}, #{tool_class_name})
            3. Or use direct class reference: tool #{tool_class_name}
        ERROR
      end
    end
  end
end

# Make errors available at RAAF module level for backward compatibility
module RAAF
  ParseError = DSL::ParseError
  ValidationError = DSL::ValidationError
  SchemaError = DSL::SchemaError
  InvalidConfigurationError = DSL::InvalidConfigurationError
  ContinuationError = DSL::ContinuationError
  # Note: ToolResolutionError is DSL-specific, not exposed at RAAF level
end