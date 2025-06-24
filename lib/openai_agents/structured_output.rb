# frozen_string_literal: true

require "json"
require_relative "errors"

module OpenAIAgents
  module StructuredOutput
    class ValidationError < Error; end
    class SchemaError < Error; end

    # Base class for structured output schemas
    class BaseSchema
      attr_reader :schema, :required_fields

      def initialize(schema = {})
        raise SchemaError, "Schema must be a hash" unless schema.is_a?(Hash)

        @schema = schema
        @required_fields = schema[:required] || []
        validate_schema!
      end

      def validate(data)
        validate_type(data, @schema, "root")
        data
      end

      def to_h
        @schema
      end

      def to_json(*)
        JSON.generate(@schema, *)
      end

      private

      def validate_schema!
        return if @schema[:type]

        raise SchemaError, "Schema must have a type"
      end

      def validate_type(data, schema, path)
        type = schema[:type]

        case type
        when "object"
          validate_object(data, schema, path)
        when "array"
          validate_array(data, schema, path)
        when "string"
          validate_string(data, schema, path)
        when "number", "integer"
          validate_number(data, schema, path)
        when "boolean"
          validate_boolean(data, schema, path)
        when "null"
          validate_null(data, schema, path)
        else
          raise ValidationError, "Unknown type '#{type}' at #{path}"
        end
      end

      def validate_object(data, schema, path)
        raise ValidationError, "Expected object at #{path}, got #{data.class}" unless data.is_a?(Hash)

        # Check required fields
        required_fields = schema[:required]
        if required_fields.is_a?(Array)
          required_fields.each do |field|
            field_key = field.to_s
            unless data.key?(field) || data.key?(field_key)
              raise ValidationError, "Missing required field '#{field}' at #{path}"
            end
          end
        end

        # Validate properties
        properties = schema[:properties]
        if properties.is_a?(Hash)
          properties.each do |key, prop_schema|
            key_str = key.to_s
            if data.key?(key) || data.key?(key_str)
              value = data[key] || data[key_str]
              validate_type(value, prop_schema, "#{path}.#{key}")
            end
          end
        end

        # Check for additional properties
        return unless schema[:additionalProperties] == false

        allowed_keys = (schema[:properties]&.keys || []).map(&:to_s)
        data.each_key do |key|
          unless allowed_keys.include?(key.to_s)
            raise ValidationError, "Additional property '#{key}' not allowed at #{path}"
          end
        end
      end

      def validate_array(data, schema, path)
        raise ValidationError, "Expected array at #{path}, got #{data.class}" unless data.is_a?(Array)

        # Check array length constraints
        if schema[:minItems] && data.length < schema[:minItems]
          raise ValidationError, "Array at #{path} has fewer than #{schema[:minItems]} items"
        end

        if schema[:maxItems] && data.length > schema[:maxItems]
          raise ValidationError, "Array at #{path} has more than #{schema[:maxItems]} items"
        end

        # Validate array items
        return unless schema[:items]

        data.each_with_index do |item, index|
          validate_type(item, schema[:items], "#{path}[#{index}]")
        end
      end

      def validate_string(data, schema, path)
        raise ValidationError, "Expected string at #{path}, got #{data.class}" unless data.is_a?(String)

        # Check string length constraints
        if schema[:minLength] && data.length < schema[:minLength]
          raise ValidationError, "String at #{path} is shorter than #{schema[:minLength]} characters"
        end

        if schema[:maxLength] && data.length > schema[:maxLength]
          raise ValidationError, "String at #{path} is longer than #{schema[:maxLength]} characters"
        end

        # Check pattern
        if schema[:pattern]
          pattern = Regexp.new(schema[:pattern])
          unless data.match?(pattern)
            raise ValidationError, "String at #{path} doesn't match pattern #{schema[:pattern]}"
          end
        end

        # Check enum values
        return unless schema[:enum] && !schema[:enum].include?(data)

        raise ValidationError, "String at #{path} is not one of #{schema[:enum].join(", ")}"
      end

      def validate_number(data, schema, path)
        raise ValidationError, "Expected number at #{path}, got #{data.class}" unless data.is_a?(Numeric)

        # For integer type, check if it's actually an integer
        if schema[:type] == "integer" && !data.is_a?(Integer)
          raise ValidationError, "Expected integer at #{path}, got #{data.class}"
        end

        # Check numeric constraints
        if schema[:minimum] && data < schema[:minimum]
          raise ValidationError, "Number at #{path} is less than minimum #{schema[:minimum]}"
        end

        if schema[:maximum] && data > schema[:maximum]
          raise ValidationError, "Number at #{path} is greater than maximum #{schema[:maximum]}"
        end

        if schema[:exclusiveMinimum] && data <= schema[:exclusiveMinimum]
          raise ValidationError, "Number at #{path} is not greater than #{schema[:exclusiveMinimum]}"
        end

        return unless schema[:exclusiveMaximum] && data >= schema[:exclusiveMaximum]

        raise ValidationError, "Number at #{path} is not less than #{schema[:exclusiveMaximum]}"
      end

      def validate_boolean(data, _schema, path)
        return if data.is_a?(TrueClass) || data.is_a?(FalseClass)

        raise ValidationError, "Expected boolean at #{path}, got #{data.class}"
      end

      def validate_null(data, _schema, path)
        return if data.nil?

        raise ValidationError, "Expected null at #{path}, got #{data.class}"
      end
    end

    # Convenience class for creating object schemas
    class ObjectSchema < BaseSchema
      def initialize(properties: {}, required: [], additional_properties: true)
        schema = {
          type: "object",
          properties: properties,
          required: required,
          additionalProperties: additional_properties
        }
        super(schema)
      end

      def self.build(&)
        builder = ObjectSchemaBuilder.new
        builder.instance_eval(&)
        new(
          properties: builder.properties,
          required: builder.required_fields,
          additional_properties: builder.additional_properties
        )
      end
    end

    # Builder class for object schemas
    class ObjectSchemaBuilder
      attr_reader :properties, :required_fields, :additional_properties

      def initialize
        @properties = {}
        @required_fields = []
        @additional_properties = true
      end

      def string(name, **options)
        @properties[name] = { type: "string", **options }
        @required_fields << name if options[:required]
      end

      def integer(name, **options)
        @properties[name] = { type: "integer", **options }
        @required_fields << name if options[:required]
      end

      def number(name, **options)
        @properties[name] = { type: "number", **options }
        @required_fields << name if options[:required]
      end

      def boolean(name, **options)
        @properties[name] = { type: "boolean", **options }
        @required_fields << name if options[:required]
      end

      def array(name, items:, **options)
        @properties[name] = { type: "array", items: items, **options }
        @required_fields << name if options[:required]
      end

      def object(name, properties:, **options)
        @properties[name] = { type: "object", properties: properties, **options }
        @required_fields << name if options[:required]
      end

      def required(*fields)
        @required_fields.concat(fields)
      end

      def no_additional_properties
        @additional_properties = false
      end
    end

    # Array schema convenience class
    class ArraySchema < BaseSchema
      def initialize(items:, min_items: nil, max_items: nil)
        schema = {
          type: "array",
          items: items
        }
        schema[:minItems] = min_items if min_items
        schema[:maxItems] = max_items if max_items
        super(schema)
      end
    end

    # String schema convenience class
    class StringSchema < BaseSchema
      def initialize(min_length: nil, max_length: nil, pattern: nil, enum: nil)
        schema = { type: "string" }
        schema[:minLength] = min_length if min_length
        schema[:maxLength] = max_length if max_length
        schema[:pattern] = pattern if pattern
        schema[:enum] = enum if enum
        super(schema)
      end
    end

    # Response formatter that validates against schema
    class ResponseFormatter
      def initialize(schema)
        @schema = schema.is_a?(BaseSchema) ? schema : BaseSchema.new(schema)
      end

      def format_response(data)
        validated_data = @schema.validate(data)

        {
          data: validated_data,
          schema: @schema.to_h,
          valid: true
        }
      rescue ValidationError => e
        {
          data: data,
          schema: @schema.to_h,
          valid: false,
          error: e.message
        }
      end

      def validate_and_format(json_string)
        data = JSON.parse(json_string)
        format_response(data)
      rescue JSON::ParserError => e
        {
          data: json_string,
          schema: @schema.to_h,
          valid: false,
          error: "Invalid JSON: #{e.message}"
        }
      end
    end
  end
end
