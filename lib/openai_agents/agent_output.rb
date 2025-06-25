# frozen_string_literal: true

require "json"
require_relative "errors"
require_relative "strict_schema"

module OpenAIAgents
  # Base class for agent output schemas
  class AgentOutputSchemaBase
    # Whether the output type is plain text (versus a JSON object)
    def plain_text?
      raise NotImplementedError, "Subclasses must implement #plain_text?"
    end

    # The name of the output type
    def name
      raise NotImplementedError, "Subclasses must implement #name"
    end

    # Returns the JSON schema of the output
    def json_schema
      raise NotImplementedError, "Subclasses must implement #json_schema"
    end

    # Whether the JSON schema is in strict mode
    def strict_json_schema?
      raise NotImplementedError, "Subclasses must implement #strict_json_schema?"
    end

    # Validate a JSON string against the output type
    def validate_json(json_str)
      raise NotImplementedError, "Subclasses must implement #validate_json"
    end
  end

  # Agent output schema implementation
  class AgentOutputSchema < AgentOutputSchemaBase
    WRAPPER_DICT_KEY = "response"

    attr_reader :output_type

    def initialize(output_type, strict_json_schema: true)
      @output_type = output_type
      @strict_json_schema = strict_json_schema
      @is_wrapped = false
      
      # Configure based on output type
      configure_schema
    end

    def plain_text?
      @output_type.nil? || @output_type == String
    end

    def strict_json_schema?
      @strict_json_schema
    end

    def name
      type_to_string(@output_type)
    end

    def json_schema
      raise UserError, "Output type is plain text, so no JSON schema is available" if plain_text?
      @output_schema
    end

    def validate_json(json_str)
      return json_str if plain_text?

      begin
        parsed = JSON.parse(json_str)
        validated = validate_against_type(parsed)
        
        if @is_wrapped
          unless validated.is_a?(Hash)
            raise ModelBehaviorError, "Expected a Hash, got #{validated.class} for JSON: #{json_str}"
          end

          unless validated.key?(WRAPPER_DICT_KEY)
            raise ModelBehaviorError, "Could not find key '#{WRAPPER_DICT_KEY}' in JSON: #{json_str}"
          end

          return validated[WRAPPER_DICT_KEY]
        end

        validated
      rescue JSON::ParserError => e
        raise ModelBehaviorError, "Invalid JSON: #{e.message}"
      end
    end

    private

    def configure_schema
      if plain_text?
        @output_schema = { type: "string" }
        return
      end

      # Check if we need to wrap the output
      @is_wrapped = !subclass_of_hash_or_structured?(@output_type)

      if @is_wrapped
        # Wrap in a dictionary
        @output_schema = {
          type: "object",
          properties: {
            WRAPPER_DICT_KEY => generate_schema_for_type(@output_type)
          },
          required: [WRAPPER_DICT_KEY],
          additionalProperties: false
        }
      else
        @output_schema = generate_schema_for_type(@output_type)
      end

      # Apply strict schema if requested
      if @strict_json_schema
        begin
          @output_schema = StrictSchema.ensure_strict_json_schema(@output_schema)
        rescue => e
          raise UserError, "Strict JSON schema is enabled, but the output type is not valid. " \
                          "Either make the output type strict, or pass strict_json_schema: false"
        end
      end
    end

    def subclass_of_hash_or_structured?(type)
      return false unless type.is_a?(Class)
      
      # Check if it's Hash or a structured type
      type <= Hash || 
        (defined?(type.json_schema) && type.respond_to?(:json_schema)) ||
        (defined?(type.schema) && type.respond_to?(:schema))
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
        elsif type == TrueClass || type == FalseClass
          { type: "boolean" }
        elsif type == Array
          { type: "array", items: {} }
        elsif type == Hash
          { type: "object", additionalProperties: true }
        elsif type.respond_to?(:json_schema)
          type.json_schema
        elsif type.respond_to?(:schema)
          type.schema
        else
          # For custom classes, attempt to infer from instance variables
          infer_schema_from_class(type)
        end
      else
        { type: "object", additionalProperties: true }
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
        rescue
          # Can't instantiate, use basic object schema
        end
      end

      {
        type: "object",
        properties: properties.empty? ? {} : properties,
        additionalProperties: true
      }
    end

    def type_to_json_schema(type)
      case type
      when String.class, "String"
        { type: "string" }
      when Integer.class, "Integer", Fixnum.class, "Fixnum", Bignum.class, "Bignum"
        { type: "integer" }
      when Float.class, "Float", Numeric.class, "Numeric"
        { type: "number" }
      when TrueClass.class, FalseClass.class, "Boolean", "TrueClass", "FalseClass"
        { type: "boolean" }
      when Array.class, "Array"
        { type: "array", items: {} }
      when Hash.class, "Hash"
        { type: "object", additionalProperties: true }
      else
        { type: "object", additionalProperties: true }
      end
    end

    def validate_against_type(data)
      return data if @output_type.nil?

      case @output_type.name
      when "String"
        data.to_s
      when "Integer"
        Integer(data)
      when "Float"
        Float(data)
      when "Hash"
        raise ModelBehaviorError, "Expected Hash, got #{data.class}" unless data.is_a?(Hash)
        data
      when "Array"
        raise ModelBehaviorError, "Expected Array, got #{data.class}" unless data.is_a?(Array)
        data
      else
        # For custom types, attempt validation
        validate_custom_type(data)
      end
    rescue ArgumentError => e
      raise ModelBehaviorError, "Type validation failed: #{e.message}"
    end

    def validate_custom_type(data)
      # If the type has a from_json method, use it
      if @output_type.respond_to?(:from_json)
        return @output_type.from_json(data)
      end

      # If the type has a new method and accepts a hash, try that
      if @output_type.respond_to?(:new) && data.is_a?(Hash)
        begin
          return @output_type.new(data)
        rescue
          # Fall through to next attempt
        end
      end

      # Otherwise, return the data as-is
      data
    end

    def type_to_string(type)
      return "nil" if type.nil?
      return type.name if type.respond_to?(:name)
      type.to_s
    end
  end

  # Type adapter for Ruby type validation
  class TypeAdapter
    attr_reader :type

    def initialize(type)
      @type = type
    end

    def validate(value)
      case @type
      when Class
        if value.is_a?(@type)
          value
        else
          raise TypeError, "Expected #{@type}, got #{value.class}"
        end
      when Module
        if value.is_a?(@type)
          value
        else
          raise TypeError, "Expected #{@type}, got #{value.class}"
        end
      else
        # For non-class types, just return the value
        value
      end
    end

    def json_schema
      case @type
      when String.class
        { type: "string" }
      when Integer.class
        { type: "integer" }
      when Float.class
        { type: "number" }
      when TrueClass.class, FalseClass.class
        { type: "boolean" }
      when Array.class
        { type: "array", items: {} }
      when Hash.class
        { type: "object", additionalProperties: true }
      else
        if @type.respond_to?(:json_schema)
          @type.json_schema
        else
          { type: "object", additionalProperties: true }
        end
      end
    end
  end
end