# frozen_string_literal: true

require "json"
require_relative "errors"
require_relative "step_errors"
require_relative "strict_schema"

module RAAF

  ##
  # Base class for agent output schemas
  #
  # Defines the interface that all agent output schema implementations must follow.
  # Output schemas validate and structure agent responses according to specified formats.
  #
  # @abstract Subclasses must implement all abstract methods
  #
  class AgentOutputSchemaBase

    ##
    # Whether the output type is plain text (versus a JSON object)
    #
    # @return [Boolean] true if output is plain text, false for structured data
    # @abstract Must be implemented by subclasses
    #
    def plain_text?
      raise NotImplementedError, "Subclasses must implement #plain_text?"
    end

    ##
    # The name of the output type
    #
    # @return [String] Human-readable name of the output type
    # @abstract Must be implemented by subclasses
    #
    def name
      raise NotImplementedError, "Subclasses must implement #name"
    end

    ##
    # Returns the JSON schema of the output
    #
    # @return [Hash] JSON schema definition for validation
    # @abstract Must be implemented by subclasses
    # @raise [NotImplementedError] if not implemented by subclass
    #
    def json_schema
      raise NotImplementedError, "Subclasses must implement #json_schema"
    end

    ##
    # Whether the JSON schema is in strict mode
    #
    # @return [Boolean] true if using strict JSON schema validation
    # @abstract Must be implemented by subclasses
    #
    def strict_json_schema?
      raise NotImplementedError, "Subclasses must implement #strict_json_schema?"
    end

    ##
    # Validate a response against the output type
    #
    # @param response [Object] Response to validate
    # @return [Object] Validated response
    # @abstract Must be implemented by subclasses
    # @raise [NotImplementedError] if not implemented by subclass
    #
    def validate_response(response)
      raise NotImplementedError, "Subclasses must implement #validate_response"
    end

    ##
    # Validate a JSON string against the output type
    #
    # @param json_str [String] JSON string to validate
    # @return [Object] Parsed and validated object
    # @abstract Must be implemented by subclasses
    # @raise [NotImplementedError] if not implemented by subclass
    #
    def validate_json(json_str)
      raise NotImplementedError, "Subclasses must implement #validate_json"
    end

  end

  ##
  # Agent output schema implementation
  #
  # Concrete implementation of agent output schema validation that supports
  # both plain text and structured JSON output validation. Automatically
  # generates JSON schemas from Ruby types and validates agent responses.
  #
  # @example Plain text output
  #   schema = AgentOutputSchema.new(String)
  #   schema.plain_text? # => true
  #   schema.validate_json("Hello world") # => "Hello world"
  #
  # @example Structured output with Hash
  #   schema = AgentOutputSchema.new(Hash)
  #   result = schema.validate_json('{"name": "John", "age": 30}')
  #   # => {"name" => "John", "age" => 30}
  #
  # @example Custom class output
  #   class Person
  #     def initialize(name:, age:)
  #       @name, @age = name, age
  #     end
  #   end
  #
  #   schema = AgentOutputSchema.new(Person)
  #   schema.strict_json_schema? # => true by default
  #   schema.json_schema # => Generated JSON schema for Person
  #
  # @example Disabling strict mode
  #   schema = AgentOutputSchema.new(CustomClass, strict_json_schema: false)
  #   # More lenient validation for complex types
  #
  class AgentOutputSchema < AgentOutputSchemaBase

    # Key used when wrapping non-Hash types in a JSON object
    WRAPPER_DICT_KEY = "response"

    # @return [Class, nil] The Ruby type that output should conform to
    attr_reader :output_type

    ##
    # Initialize agent output schema
    #
    # @param output_type [Class, nil] Ruby type for output validation (nil for plain text)
    # @param strict_json_schema [Boolean] Whether to use strict JSON schema validation
    #
    def initialize(output_type, strict_json_schema: true)
      super()
      @output_type = output_type
      @strict_json_schema = strict_json_schema
      @is_wrapped = false

      # Configure based on output type
      configure_schema
    end

    ##
    # Check if output type is plain text
    #
    # @return [Boolean] true for nil or String types
    #
    def plain_text?
      @output_type.nil? || @output_type == String
    end

    ##
    # Check if strict JSON schema validation is enabled
    #
    # @return [Boolean] true if using strict validation
    #
    def strict_json_schema?
      @strict_json_schema
    end

    ##
    # Get human-readable name of the output type
    #
    # @return [String] Name of the output type
    #
    def name
      if plain_text?
        "text"
      else
        type_to_string(@output_type)
      end
    end

    ##
    # Get JSON schema for validation
    #
    # @return [Hash] JSON schema definition
    # @raise [UserError] if output type is plain text
    #
    def json_schema
      return nil if plain_text?

      # Convert back to symbol keys for backwards compatibility with tests
      deep_symbolize_keys(@output_schema)
    end

    ##
    # Validate JSON string against the output type
    #
    # Parses JSON and validates it against the configured output type.
    # Handles both wrapped and unwrapped output formats.
    #
    # @param response [Object] Response to validate (could be string or already parsed)
    # @return [Object] Validated response data
    # @raise [ModelBehaviorError] if validation fails
    #
    def validate_response(response)
      if response.is_a?(String) && !plain_text?
        # For structured types, try to parse as JSON first, then validate type
        begin
          validate_json(response)
        rescue Errors::ModelBehaviorError => e
          # If JSON parsing fails and it's not obviously JSON, treat as direct validation
          raise e if response.strip.start_with?("{", "[")

          validate_against_type(response)
        end
      elsif response.is_a?(String)
        # For plain text, return as-is
        response
      else
        validate_against_type(response)
      end
    end

    ##
    # Validate JSON string against the output type
    #
    # Handles both wrapped and unwrapped output formats.
    #
    # @param json_str [String] JSON string to validate
    # @return [Object] Validated and parsed object
    # @raise [ModelBehaviorError] if JSON is invalid or doesn't match schema
    #
    def validate_json(json_str)
      return json_str if plain_text?

      begin
        parsed = JSON.parse(json_str, symbolize_names: true)

        if @is_wrapped
          raise Errors::ModelBehaviorError, "Expected a Hash, got #{parsed.class} for JSON: #{json_str}" unless parsed.is_a?(Hash)

          wrapper_key_sym = WRAPPER_DICT_KEY.to_sym
          raise Errors::ModelBehaviorError, "Could not find key '#{wrapper_key_sym}' in JSON: #{json_str}" unless parsed.key?(wrapper_key_sym)

          # Extract the wrapped value and validate it against the expected type
          wrapped_value = parsed[wrapper_key_sym]
          return validate_against_type(wrapped_value)
        end

        # For unwrapped types, validate the entire parsed value
        validate_against_type(parsed)
      rescue JSON::ParserError => e
        raise Errors::ModelBehaviorError, "Invalid JSON: #{e.message}"
      end
    end

    private

    def deep_symbolize_keys(obj)
      case obj
      when Hash
        obj.transform_keys(&:to_sym).transform_values { |v| deep_symbolize_keys(v) }
      when Array
        obj.map { |v| deep_symbolize_keys(v) }
      else
        obj
      end
    end

    def configure_schema
      if plain_text?
        @output_schema = { type: "string" }
        return
      end

      # Check if we need to wrap the output
      @is_wrapped = !subclass_of_hash_or_structured?(@output_type)

      @output_schema = if @is_wrapped
                         # Wrap in a dictionary
                         {
                           type: "object",
                           properties: {
                             WRAPPER_DICT_KEY => generate_schema_for_type(@output_type)
                           },
                           required: [WRAPPER_DICT_KEY],
                           additionalProperties: false
                         }
                       else
                         generate_schema_for_type(@output_type)
                       end

      # Apply strict schema if requested
      return unless @strict_json_schema

      begin
        @output_schema = StrictSchema.ensure_strict_json_schema(@output_schema)
      rescue StandardError
        raise Errors::UserError, "Strict JSON schema is enabled, but the output type is not valid. " \
                                 "Either make the output type strict, or pass strict_json_schema: false"
      end
    end

    def subclass_of_hash_or_structured?(type)
      return false unless type.is_a?(Class)

      # Check if it's Hash, Array, or a structured type
      begin
        is_hash_subclass = type <= Hash
      rescue StandardError
        is_hash_subclass = false
      end

      begin
        is_array_subclass = type <= Array
      rescue StandardError
        is_array_subclass = false
      end

      has_json_schema = !defined?(type.json_schema).nil? && type.respond_to?(:json_schema)
      has_schema = !defined?(type.schema).nil? && type.respond_to?(:schema)

      is_hash_subclass || is_array_subclass || has_json_schema || has_schema
    end

    def generate_schema_for_type(type)
      case type
      when Class
        if type == String
          { type: "string" }
        elsif type == Integer
          { type: "integer" }
        elsif type == Float
          { type: "number" }
        elsif [TrueClass, FalseClass].include?(type)
          { type: "boolean" }
        elsif type == Array
          { type: "array", items: {} }
        elsif type == Hash
          if @strict_json_schema
            { type: "object", properties: {}, additionalProperties: false }
          else
            { type: "object", additionalProperties: true }
          end
        elsif type.respond_to?(:json_schema)
          type.json_schema
        elsif type.respond_to?(:schema)
          type.schema
        else
          # For custom classes, attempt to infer from instance variables
          infer_schema_from_class(type)
        end
      else
        { type: "object", additionalProperties: @strict_json_schema ? false : true }
      end
    end

    def infer_schema_from_class(klass)
      # Basic inference - can be extended
      properties = {}

      # Try to get attributes from various sources
      if klass.respond_to?(:attributes)
        # ActiveRecord-style
        klass.attributes.each do |name, type|
          properties[name.to_s] = type_to_json_schema(type)
        end
      elsif klass.instance_methods.include?(:to_h)
        # Classes with to_h method
        begin
          instance = klass.new
          if instance.respond_to?(:to_h)
            instance.to_h.each do |key, value|
              properties[key.to_s] = type_to_json_schema(value.class)
            end
          end
        rescue StandardError
          # Can't instantiate, use basic object schema
        end
      end

      {
        type: "object",
        properties: properties.empty? ? {} : properties,
        additionalProperties: @strict_json_schema ? false : true
      }
    end

    def type_to_json_schema(type)
      case type
      when String.class, "String"
        { type: "string" }
      when Integer.class, "Integer", "Fixnum", "Bignum"
        { type: "integer" }
      when Float.class, "Float", Numeric.class, "Numeric"
        { type: "number" }
      when TrueClass.class, FalseClass.class, "Boolean", "TrueClass", "FalseClass"
        { type: "boolean" }
      when Array.class, "Array"
        { type: "array", items: {} }
      else
        # Default for Hash, unknown types, and else case
        { type: "object", additionalProperties: @strict_json_schema ? false : true }
      end
    end

    def validate_against_type(data)
      return data if @output_type.nil?

      case @output_type.name
      when "String"
        raise ArgumentError, "Expected String, got #{data.class}" unless data.is_a?(String)

        data
      when "Integer"
        raise ArgumentError, "Expected Integer, got #{data.class}" unless data.is_a?(Integer)

        data
      when "Float"
        raise ArgumentError, "Expected Float, got #{data.class}" unless data.is_a?(Float)

        data
      when "Hash"
        raise Errors::ModelBehaviorError, "Expected Hash, got #{data.class}" if @strict_json_schema && !data.is_a?(Hash)

        data
      when "Array"
        unless data.is_a?(Array)
          raise Errors::ModelBehaviorError, "Expected Array, got #{data.class}" if @strict_json_schema

          raise ArgumentError, "Expected Array, got #{data.class}"

        end
        data
      else
        # For custom types, attempt validation
        validate_custom_type(data)
      end
    end

    def type_to_string(type)
      return "nil" if type.nil?
      return type.name if type.respond_to?(:name)

      type.to_s
    end

    def validate_type_match(data, expected_type)
      return if data.is_a?(expected_type)

      raise ArgumentError, "Expected #{expected_type}, got #{data.class}"
    end

    def validate_custom_type(data)
      return data if data.is_a?(@output_type)

      if data.is_a?(Hash) && @output_type.respond_to?(:from_hash)
        @output_type.from_hash(data)
      elsif !@strict_json_schema
        # In non-strict mode, return data as-is if conversion fails
        data
      else
        raise ArgumentError, "Cannot convert #{data.class} to #{@output_type}"
      end
    end

  end

  ##
  # Type adapter for Ruby type validation
  #
  # Provides runtime type validation and JSON schema generation for Ruby types.
  # Used internally by output schemas to validate individual values against
  # expected types.
  #
  # @example Basic type validation
  #   adapter = TypeAdapter.new(String)
  #   adapter.validate("hello")  # => "hello"
  #   adapter.validate(123)      # => raises TypeError
  #
  # @example JSON schema generation
  #   adapter = TypeAdapter.new(Integer)
  #   adapter.json_schema # => { type: "integer" }
  #
  # @example Custom type with schema method
  #   class CustomType
  #     def self.json_schema
  #       { type: "object", properties: { value: { type: "string" } } }
  #     end
  #   end
  #
  #   adapter = TypeAdapter.new(CustomType)
  #   adapter.json_schema # => Uses CustomType.json_schema
  #
  class TypeAdapter

    # @return [Class, Module] The type this adapter validates against
    attr_reader :type

    ##
    # Initialize type adapter
    #
    # @param type [Class, Module] Ruby type to validate against
    #
    def initialize(type)
      @type = type
    end

    ##
    # Validate value against the configured type
    #
    # @param value [Object] Value to validate
    # @return [Object] The validated value
    # @raise [TypeError] if value doesn't match expected type
    #
    def validate(value)
      case @type
      when Class, Module
        raise ArgumentError, "Expected #{@type}, got #{value.class}" unless value.is_a?(@type)
        # For non-class types, just return the value
      end
      value
    end

    ##
    # Generate JSON schema for the configured type
    #
    # @return [Hash] JSON schema definition for the type
    #
    def json_schema
      if @type == String
        { type: "string" }
      elsif @type == Integer
        { type: "integer" }
      elsif @type == Float
        { type: "number" }
      elsif @type == TrueClass || @type == FalseClass
        { type: "boolean" }
      elsif @type == Array
        { type: "array", items: {} }
      elsif @type.respond_to?(:json_schema)
        @type.json_schema
      else
        { type: "object", additionalProperties: true }
      end
    end

  end

end
