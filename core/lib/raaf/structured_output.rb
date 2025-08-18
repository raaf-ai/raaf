# frozen_string_literal: true

require "json"
require_relative "errors"

module RAAF

  ##
  # Structured output validation and formatting
  #
  # The StructuredOutput module provides JSON Schema validation and formatting
  # capabilities for agent responses. It ensures that agent outputs conform
  # to specified schemas, enabling reliable structured data extraction.
  #
  # Features:
  # - JSON Schema validation
  # - Type checking and constraints
  # - Custom schema builders
  # - Response formatting
  # - Error handling
  #
  # @example Using object schema
  #   schema = StructuredOutput::ObjectSchema.build do
  #     string :name, required: true
  #     integer :age, minimum: 0, maximum: 120
  #     array :tags, items: { type: "string" }
  #   end
  #
  #   formatter = StructuredOutput::ResponseFormatter.new(schema)
  #   result = formatter.format_response({ name: "Alice", age: 30, tags: ["user"] })
  #
  # @example Direct schema validation
  #   schema = StructuredOutput::BaseSchema.new({
  #     type: "object",
  #     properties: {
  #       status: { type: "string", enum: ["success", "failure"] },
  #       message: { type: "string" }
  #     },
  #     required: ["status"]
  #   })
  #
  #   schema.validate({ status: "success", message: "Done" })
  #
  module StructuredOutput

    ##
    # Raised when data fails schema validation
    class ValidationError < Error; end

    ##
    # Raised when schema definition is invalid
    class SchemaError < Error; end

    ##
    # Base class for structured output schemas
    #
    # BaseSchema provides core JSON Schema validation functionality.
    # It supports all standard JSON Schema types and constraints.
    #
    # @example Direct schema usage
    #   schema = BaseSchema.new({
    #     type: "object",
    #     properties: {
    #       name: { type: "string" },
    #       age: { type: "integer", minimum: 0 }
    #     },
    #     required: ["name"]
    #   })
    #
    #   schema.validate({ name: "Alice", age: 30 })
    #
    class BaseSchema

      # @!attribute [r] schema
      #   @return [Hash] The JSON Schema definition
      # @!attribute [r] required_fields
      #   @return [Array<String>] Required field names
      attr_reader :schema, :required_fields

      ##
      # Initialize a new schema
      #
      # @param schema [Hash] JSON Schema definition
      # @raise [SchemaError] if schema is not a hash or invalid
      #
      def initialize(schema = {})
        raise SchemaError, "Schema must be a hash" unless schema.is_a?(Hash)

        @schema = schema
        @required_fields = schema[:required] || []
        validate_schema!
      end

      ##
      # Validates data against the schema
      #
      # @param data [Object] Data to validate
      # @return [Object] The validated data
      # @raise [ValidationError] if validation fails
      #
      # @example
      #   schema.validate({ name: "Bob" })  # => { name: "Bob" }
      #   schema.validate({ age: -5 })      # => ValidationError
      #
      def validate(data)
        validate_type(data, @schema, "root")
        data
      end

      ##
      # Converts schema to hash representation
      #
      # @return [Hash] The schema as a hash
      #
      def to_h
        @schema
      end

      ##
      # Converts schema to JSON string
      #
      # @param args [Array] Arguments passed to JSON.generate
      # @return [String] JSON representation of the schema
      #
      def to_json(*)
        JSON.generate(@schema, *)
      end

      private

      ##
      # Validates the schema definition itself
      #
      # @raise [SchemaError] if schema is missing required fields
      # @private
      #
      def validate_schema!
        return if @schema[:type]

        raise SchemaError, "Schema must have a type"
      end

      ##
      # Validates data against a specific type schema
      #
      # @param data [Object] Data to validate
      # @param schema [Hash] Schema to validate against
      # @param path [String] Current path in the data structure (for error messages)
      # @raise [ValidationError] if validation fails
      # @private
      #
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
            raise ValidationError, "Missing required field '#{field}' at #{path}" unless data.key?(field) || data.key?(field_key)
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
          raise ValidationError, "Additional property '#{key}' not allowed at #{path}" unless allowed_keys.include?(key.to_s)
        end
      end

      def validate_array(data, schema, path)
        raise ValidationError, "Expected array at #{path}, got #{data.class}" unless data.is_a?(Array)

        # Check array length constraints
        raise ValidationError, "Array at #{path} has fewer than #{schema[:minItems]} items" if schema[:minItems] && data.length < schema[:minItems]

        raise ValidationError, "Array at #{path} has more than #{schema[:maxItems]} items" if schema[:maxItems] && data.length > schema[:maxItems]

        # Validate array items
        return unless schema[:items]

        data.each_with_index do |item, index|
          validate_type(item, schema[:items], "#{path}[#{index}]")
        end
      end

      def validate_string(data, schema, path)
        raise ValidationError, "Expected string at #{path}, got #{data.class}" unless data.is_a?(String)

        # Check string length constraints
        raise ValidationError, "String at #{path} is shorter than #{schema[:minLength]} characters" if schema[:minLength] && data.length < schema[:minLength]

        raise ValidationError, "String at #{path} is longer than #{schema[:maxLength]} characters" if schema[:maxLength] && data.length > schema[:maxLength]

        # Check pattern
        if schema[:pattern]
          pattern = Regexp.new(schema[:pattern])
          raise ValidationError, "String at #{path} doesn't match pattern #{schema[:pattern]}" unless data.match?(pattern)
        end

        # Check enum values
        return unless schema[:enum] && !schema[:enum].include?(data)

        raise ValidationError, "String at #{path} is not one of #{schema[:enum].join(", ")}"
      end

      def validate_number(data, schema, path)
        raise ValidationError, "Expected number at #{path}, got #{data.class}" unless data.is_a?(Numeric)

        # For integer type, check if it's actually an integer
        raise ValidationError, "Expected integer at #{path}, got #{data.class}" if schema[:type] == "integer" && !data.is_a?(Integer)

        # Check numeric constraints
        raise ValidationError, "Number at #{path} is less than minimum #{schema[:minimum]}" if schema[:minimum] && data < schema[:minimum]

        raise ValidationError, "Number at #{path} is greater than maximum #{schema[:maximum]}" if schema[:maximum] && data > schema[:maximum]

        raise ValidationError, "Number at #{path} is not greater than #{schema[:exclusiveMinimum]}" if schema[:exclusiveMinimum] && data <= schema[:exclusiveMinimum]

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

    ##
    # Convenience class for creating object schemas
    #
    # ObjectSchema simplifies creating schemas for object validation with
    # properties, required fields, and additional property constraints.
    #
    # @example Direct initialization
    #   schema = ObjectSchema.new(
    #     properties: {
    #       name: { type: "string" },
    #       email: { type: "string", pattern: "^[^@]+@[^@]+$" }
    #     },
    #     required: [:name, :email],
    #     additional_properties: false
    #   )
    #
    # @example Using builder DSL
    #   schema = ObjectSchema.build do
    #     string :name, required: true
    #     string :email, pattern: "^[^@]+@[^@]+$", required: true
    #     integer :age, minimum: 0, maximum: 120
    #     no_additional_properties
    #   end
    #
    class ObjectSchema < BaseSchema

      ##
      # Initialize an object schema
      #
      # @param properties [Hash] Property definitions
      # @param required [Array<String, Symbol>] Required property names
      # @param additional_properties [Boolean] Whether to allow additional properties
      #
      def initialize(properties: {}, required: [], additional_properties: false)
        schema = {
          type: "object",
          properties: properties,
          required: required,
          additionalProperties: additional_properties
        }
        super(schema)
      end

      ##
      # Build an object schema using DSL
      #
      # @yield [ObjectSchemaBuilder] Builder instance for configuration
      # @return [ObjectSchema] The constructed schema
      #
      # @example
      #   schema = ObjectSchema.build do
      #     string :id, required: true
      #     object :metadata do
      #       string :version
      #       boolean :active, required: true
      #     end
      #   end
      #
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

    ##
    # Builder class for object schemas
    #
    # ObjectSchemaBuilder provides a DSL for defining object schemas
    # with a fluent, readable interface.
    #
    # @example Building a user schema
    #   builder = ObjectSchemaBuilder.new
    #   builder.string :username, required: true, min_length: 3
    #   builder.string :email, required: true, pattern: EMAIL_REGEX
    #   builder.integer :age, minimum: 13
    #   builder.array :tags, items: { type: "string" }
    #
    class ObjectSchemaBuilder

      # @!attribute [r] properties
      #   @return [Hash] Built property definitions
      # @!attribute [r] required_fields
      #   @return [Array] List of required field names
      # @!attribute [r] additional_properties
      #   @return [Boolean] Whether additional properties are allowed
      attr_reader :properties, :required_fields, :additional_properties

      ##
      # Initialize a new builder
      #
      def initialize
        @properties = {}
        @required_fields = []
        @additional_properties = false
      end

      ##
      # Define a string property
      #
      # @param name [Symbol, String] Property name
      # @param options [Hash] String constraints (min_length, max_length, pattern, enum)
      # @option options [Boolean] :required Whether this field is required
      # @option options [Integer] :min_length Minimum string length
      # @option options [Integer] :max_length Maximum string length
      # @option options [String] :pattern Regex pattern to match
      # @option options [Array<String>] :enum Allowed values
      # @return [void]
      #
      def string(name, **options)
        required = options.delete(:required)
        @properties[name] = { type: "string", **options }
        @required_fields << name if required
      end

      ##
      # Define an integer property
      #
      # @param name [Symbol, String] Property name
      # @param options [Hash] Integer constraints (minimum, maximum, exclusiveMinimum, exclusiveMaximum)
      # @option options [Boolean] :required Whether this field is required
      # @option options [Integer] :minimum Minimum value (inclusive)
      # @option options [Integer] :maximum Maximum value (inclusive)
      # @return [void]
      #
      def integer(name, **options)
        required = options.delete(:required)
        @properties[name] = { type: "integer", **options }
        @required_fields << name if required
      end

      ##
      # Define a number (float) property
      #
      # @param name [Symbol, String] Property name
      # @param options [Hash] Number constraints (same as integer)
      # @option options [Boolean] :required Whether this field is required
      # @return [void]
      #
      def number(name, **options)
        required = options.delete(:required)
        @properties[name] = { type: "number", **options }
        @required_fields << name if required
      end

      ##
      # Define a boolean property
      #
      # @param name [Symbol, String] Property name
      # @param options [Hash] Boolean options
      # @option options [Boolean] :required Whether this field is required
      # @return [void]
      #
      def boolean(name, **options)
        required = options.delete(:required)
        @properties[name] = { type: "boolean", **options }
        @required_fields << name if required
      end

      ##
      # Define an array property
      #
      # @param name [Symbol, String] Property name
      # @param items [Hash] Schema for array items
      # @param options [Hash] Array constraints (minItems, maxItems)
      # @option options [Boolean] :required Whether this field is required
      # @option options [Integer] :min_items Minimum number of items
      # @option options [Integer] :max_items Maximum number of items
      # @return [void]
      #
      def array(name, items:, **options)
        required = options.delete(:required)
        @properties[name] = { type: "array", items: items, **options }
        @required_fields << name if required
      end

      ##
      # Define a nested object property
      #
      # @param name [Symbol, String] Property name
      # @param properties [Hash] Nested object properties
      # @param options [Hash] Object options
      # @option options [Boolean] :required Whether this field is required
      # @option options [Array] :required_properties Required properties in the nested object
      # @return [void]
      #
      def object(name, properties:, required: nil, **options)
        # Check if this field itself is required
        field_required = options.delete(:required)

        # Build the object schema
        object_def = { type: "object", properties: properties }
        object_def[:required] = required if required
        object_def.merge!(options)

        @properties[name] = object_def

        # Add to parent's required fields if needed
        @required_fields << name if field_required
      end

      ##
      # Mark fields as required
      #
      # @param fields [Array<Symbol, String>] Field names to mark as required
      # @return [void]
      #
      # @example
      #   required :username, :email
      #
      def required(*fields)
        @required_fields.concat(fields)
      end

      ##
      # Disallow additional properties not defined in the schema
      #
      # @return [void]
      #
      def no_additional_properties
        @additional_properties = false
      end

    end

    ##
    # Array schema convenience class
    #
    # ArraySchema simplifies creating schemas for array validation with
    # item schemas and length constraints.
    #
    # @example String array with constraints
    #   schema = ArraySchema.new(
    #     items: { type: "string" },
    #     min_items: 1,
    #     max_items: 10
    #   )
    #
    # @example Array of objects
    #   schema = ArraySchema.new(
    #     items: {
    #       type: "object",
    #       properties: {
    #         id: { type: "integer" },
    #         name: { type: "string" }
    #       }
    #     }
    #   )
    #
    class ArraySchema < BaseSchema

      ##
      # Initialize an array schema
      #
      # @param items [Hash] Schema for array items
      # @param min_items [Integer, nil] Minimum number of items
      # @param max_items [Integer, nil] Maximum number of items
      #
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

    ##
    # String schema convenience class
    #
    # StringSchema simplifies creating schemas for string validation with
    # length constraints, patterns, and enumerated values.
    #
    # @example Email validation
    #   schema = StringSchema.new(
    #     pattern: "^[^@]+@[^@]+\\.[^@]+$",
    #     max_length: 255
    #   )
    #
    # @example Enum validation
    #   schema = StringSchema.new(
    #     enum: ["active", "inactive", "pending"]
    #   )
    #
    class StringSchema < BaseSchema

      ##
      # Initialize a string schema
      #
      # @param min_length [Integer, nil] Minimum string length
      # @param max_length [Integer, nil] Maximum string length
      # @param pattern [String, nil] Regex pattern to match
      # @param enum [Array<String>, nil] Allowed values
      #
      def initialize(min_length: nil, max_length: nil, pattern: nil, enum: nil)
        schema = { type: "string" }
        schema[:minLength] = min_length if min_length
        schema[:maxLength] = max_length if max_length
        schema[:pattern] = pattern if pattern
        schema[:enum] = enum if enum
        super(schema)
      end

    end

    ##
    # Response formatter that validates against schema
    #
    # ResponseFormatter validates data against a schema and returns
    # formatted results with validation status and error information.
    #
    # @example Basic usage
    #   formatter = ResponseFormatter.new({
    #     type: "object",
    #     properties: {
    #       status: { type: "string" },
    #       code: { type: "integer" }
    #     }
    #   })
    #
    #   result = formatter.format_response({ status: "ok", code: 200 })
    #   # => { data: {...}, schema: {...}, valid: true }
    #
    # @example With validation errors
    #   result = formatter.format_response({ status: "ok", code: "invalid" })
    #   # => { data: {...}, schema: {...}, valid: false, error: "Expected integer..." }
    #
    class ResponseFormatter

      ##
      # Initialize a formatter with a schema
      #
      # @param schema [BaseSchema, Hash] Schema to validate against
      #
      def initialize(schema)
        @schema = schema.is_a?(BaseSchema) ? schema : BaseSchema.new(schema)
      end

      ##
      # Formats and validates response data
      #
      # @param data [Object] Data to validate and format
      # @return [Hash] Formatted result with validation status
      #   - :data [Object] The input data (validated or original)
      #   - :schema [Hash] The schema used for validation
      #   - :valid [Boolean] Whether validation succeeded
      #   - :error [String, nil] Error message if validation failed
      #
      # @example Successful validation
      #   formatter.format_response({ name: "Alice" })
      #   # => { data: { name: "Alice" }, schema: {...}, valid: true }
      #
      # @example Failed validation
      #   formatter.format_response({ age: "not a number" })
      #   # => { data: {...}, schema: {...}, valid: false, error: "Expected integer..." }
      #
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

      ##
      # Validates and formats JSON string input
      #
      # @param json_string [String] JSON string to parse and validate
      # @return [Hash] Formatted result with validation status
      #   - :data [Object, String] Parsed data or original string if parsing failed
      #   - :schema [Hash] The schema used for validation
      #   - :valid [Boolean] Whether parsing and validation succeeded
      #   - :error [String, nil] Error message if parsing or validation failed
      #
      # @example Valid JSON
      #   formatter.validate_and_format('{"name": "Bob"}')
      #   # => { data: { "name" => "Bob" }, schema: {...}, valid: true }
      #
      # @example Invalid JSON
      #   formatter.validate_and_format('{invalid json}')
      #   # => { data: "{invalid json}", schema: {...}, valid: false, error: "Invalid JSON: ..." }
      #
      def validate_and_format(json_string)
        data = JSON.parse(json_string, symbolize_names: true)
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
