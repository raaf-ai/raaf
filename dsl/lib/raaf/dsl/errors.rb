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
  end
end

# Make errors available at RAAF module level for backward compatibility
module RAAF
  ParseError = DSL::ParseError
  ValidationError = DSL::ValidationError
  SchemaError = DSL::SchemaError
end