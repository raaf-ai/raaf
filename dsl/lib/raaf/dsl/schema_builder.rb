# frozen_string_literal: true

module RAAF
  module DSL
    # Fluent interface for building JSON schemas with semantic types
    #
    # Provides a concise, chainable API for defining schemas with automatic
    # model introspection, semantic type support, and composition patterns.
    #
    # @example Basic usage
    #   builder = SchemaBuilder.new
    #     .field(:name, :string)
    #     .field(:email, :email)
    #     .required(:name, :email)
    #   schema = builder.to_schema
    #
    # @example Model-based usage
    #   builder = SchemaBuilder.new(model: Market)
    #     .override(:overall_score, type: :score)
    #     .field(:insights, :text)
    #   schema = builder.to_schema
    class SchemaBuilder
      # Initialize schema builder
      #
      # @param model [Class, nil] Optional Active Record model class for auto-generation
      #
      # @example Without model
      #   builder = SchemaBuilder.new
      #
      # @example With model (auto-generates schema from Market model)
      #   builder = SchemaBuilder.new(model: Market)
      def initialize(model: nil, &block)
        @model = model
        @properties = {}
        @required = []
        @validation_config = { mode: :strict, repair_attempts: 0, allow_extra: false }

        # Auto-generate from model if provided
        if @model
          auto_schema = RAAF::DSL::SchemaCache.get_schema(@model)
          @properties.merge!(auto_schema[:properties]) if auto_schema[:properties]
          @required.concat(auto_schema[:required]) if auto_schema[:required]
        end

        # Execute block for DSL usage (supports both old and new patterns)
        instance_eval(&block) if block_given?
      end

      # Add a field to the schema
      #
      # @param name [Symbol] Field name
      # @param type [Symbol] Field type (semantic or basic JSON schema type)
      # @param options [Hash] Additional field options
      # @return [SchemaBuilder] self for method chaining
      #
      # @example Basic field
      #   builder.field(:name, :string)
      #
      # @example Semantic type
      #   builder.field(:email, :email)
      #
      # @example With options
      #   builder.field(:score, :integer, minimum: 0, maximum: 100)
      def field(name, positional_type = nil, type: nil, required: false, description: nil, **options, &block)
        # Support both old and new calling styles:
        # New: field(:name, :string, minimum: 0)
        # Old: field(:name, type: :string, required: true, description: "Name")
        actual_type = positional_type || type || :string

        # Handle semantic types first
        type_definition = RAAF::DSL::Types.define(actual_type, **options)

        # For non-semantic types, ensure we have the basic type definition
        if type_definition.empty?
          type_definition = { type: actual_type.to_s }
        end

        # Add description if provided
        type_definition[:description] = description if description

        # Add fault-tolerance options from old SchemaBuilder
        type_definition[:default] = options[:default] if options.key?(:default)
        type_definition[:flexible] = options[:flexible] if options[:flexible]
        type_definition[:passthrough] = options[:passthrough] if options[:passthrough]
        type_definition[:enum] = options[:enum] if options[:enum]
        type_definition[:fallback] = options[:fallback] if options[:fallback]

        # Handle union types for flexible schema support
        if actual_type == :union && options[:schemas]
          type_definition = { oneOf: options[:schemas] }
        end

        # Handle type-specific options from old SchemaBuilder
        case actual_type.to_s
        when "integer", "number"
          type_definition[:type] = actual_type.to_s
          type_definition[:minimum] = options[:min] if options[:min]
          type_definition[:maximum] = options[:max] if options[:max]
          if options[:range]
            type_definition[:minimum] = options[:range].min
            type_definition[:maximum] = options[:range].max
          end
        when "string"
          type_definition[:type] = "string"
          type_definition[:minLength] = options[:min_length] if options[:min_length]
          type_definition[:maxLength] = options[:max_length] if options[:max_length]
        when "array"
          # Ensure array type is preserved
          type_definition[:type] = "array"

          # Handle model-based array items (e.g., field :markets, :array, model: Market)
          if options[:model]
            resolved_model = resolve_model_constant(options[:model])
            model_schema = RAAF::DSL::SchemaCache.get_schema(resolved_model)
            type_definition[:items] = model_schema
          else
            type_definition[:items] = { type: (options[:items_type] || :string).to_s }
          end

          type_definition[:minItems] = options[:min_items] if options[:min_items]
          type_definition[:maxItems] = options[:max_items] if options[:max_items]

          # Handle nested schema for array items (when using blocks)
          if block_given?
            nested_builder = self.class.new(&block)
            nested_result = nested_builder.build
            if nested_result.is_a?(Hash) && nested_result[:schema]
              type_definition[:items] = nested_result[:schema]
            else
              type_definition[:items] = nested_result
            end
          end
        when "object"
          type_definition[:type] = "object"
          # Handle nested object schema
          if block_given?
            nested_builder = self.class.new(&block)
            nested_result = nested_builder.build
            if nested_result.is_a?(Hash) && nested_result[:schema]
              type_definition.merge!(nested_result[:schema])
            else
              type_definition.merge!(nested_result)
            end
          end
        end

        # Set the property definition AFTER type-specific processing
        @properties[name] = type_definition

        # Handle required flag from old interface
        @required << name.to_sym if required

        self
      end

      # Mark fields as required
      #
      # @param fields [Array<Symbol>] Field names to mark as required
      # @return [SchemaBuilder] self for method chaining
      #
      # @example
      #   builder.required(:name, :email)
      def required(*fields)
        @required.concat(fields)
        self
      end

      # Add an array field with typed items
      #
      # @param name [Symbol] Field name
      # @param item_type [Symbol] Type for array items
      # @param options [Hash] Additional options for items
      # @return [SchemaBuilder] self for method chaining
      #
      # @example String array
      #   builder.array_of(:tags, :string)
      #
      # @example Semantic type array
      #   builder.array_of(:emails, :email)
      #
      # @example With constraints
      #   builder.array_of(:scores, :integer, minimum: 0, maximum: 100)
      def array_of(name, item_type, **options)
        @properties[name] = {
          type: :array,
          items: RAAF::DSL::Types.define(item_type, **options)
        }
        self
      end

      # Add a nested object field
      #
      # @param name [Symbol] Field name
      # @param block [Proc] Block to define nested schema
      # @return [SchemaBuilder] self for method chaining
      #
      # @example
      #   builder.nested(:address) do
      #     field :street, :string
      #     field :city, :string
      #     required :street, :city
      #   end
      def nested(name, &block)
        nested_builder = self.class.new
        nested_builder.instance_eval(&block)
        @properties[name] = nested_builder.to_schema
        self
      end

      # Override properties of existing fields (useful with model introspection)
      #
      # @param name [Symbol] Field name to override
      # @param options [Hash] Properties to merge/override
      # @return [SchemaBuilder] self for method chaining
      #
      # @example Override existing field type
      #   builder.override(:overall_score, type: :score)
      #
      # @example Add additional constraints
      #   builder.override(:name, required: true, description: "Full name")
      def override(name, **options)
        if @properties[name]
          # Handle type changes with semantic types
          if options[:type] && RAAF::DSL::Types.semantic?(options[:type])
            semantic_definition = RAAF::DSL::Types.define(options[:type])
            # Remove the :type key since we're merging the full semantic definition
            options_without_type = options.except(:type)
            @properties[name] = @properties[name].merge(semantic_definition).merge(options_without_type)
          else
            @properties[name] = @properties[name].merge(options)
          end
        end
        self
      end

      # Generate the final JSON schema
      #
      # @return [Hash] Complete JSON schema definition
      #
      # @example
      #   schema = builder.to_schema
      #   puts schema[:type]        # => :object
      #   puts schema[:properties]  # => {...}
      #   puts schema[:required]    # => [...]
      def to_schema
        schema = {
          type: "object",
          properties: @properties,
          required: @required.uniq.map(&:to_s),
          additionalProperties: false
        }

        # Convert all symbols to strings for JSON compatibility
        schema = convert_symbols_to_strings(schema)

        # Clean non-JSON Schema properties for OpenAI compatibility
        clean_non_json_schema_properties(schema)
      end

      # Get current properties (useful for debugging)
      #
      # @return [Hash] Current properties hash
      def properties
        @properties.dup
      end

      # Get current required fields (useful for debugging)
      #
      # @return [Array<Symbol>] Current required fields
      def required_fields
        @required.dup
      end

      # Check if a field exists
      #
      # @param name [Symbol] Field name to check
      # @return [Boolean] true if field exists
      def field_exists?(name)
        @properties.key?(name)
      end

      # Remove a field from the schema
      #
      # @param name [Symbol] Field name to remove
      # @return [SchemaBuilder] self for method chaining
      #
      # @example
      #   builder.remove_field(:unwanted_field)
      def remove_field(name)
        @properties.delete(name)
        @required.delete(name)
        self
      end

      # Create a copy of the builder
      #
      # @return [SchemaBuilder] New builder instance with same state
      def dup
        new_builder = self.class.new
        new_builder.instance_variable_set(:@properties, @properties.deep_dup)
        new_builder.instance_variable_set(:@required, @required.dup)
        new_builder
      end

      # Merge another schema builder into this one
      #
      # @param other [SchemaBuilder] Another schema builder
      # @return [SchemaBuilder] self for method chaining
      #
      # @example
      #   base_builder = SchemaBuilder.new.field(:id, :integer)
      #   extended_builder = SchemaBuilder.new.field(:name, :string)
      #   final_builder = base_builder.merge(extended_builder)
      def merge(other)
        @properties.merge!(other.properties)
        @required.concat(other.required_fields)
        @required.uniq!
        self
      end

      # Backward compatibility method for old DSL interface
      #
      # @return [Hash] Schema definition with configuration
      #
      # @example
      #   builder = SchemaBuilder.new
      #   builder.field(:name, :string, required: true)
      #   result = builder.build
      #   puts result[:schema]    # => { type: :object, properties: {...}, required: [...] }
      #   puts result[:config]    # => { mode: :tolerant, ... }
      def build
        {
          schema: to_schema,
          config: @validation_config
        }
      end

      private

      # Resolve model constant with proper namespace handling
      #
      # When an agent uses `model: Market`, the constant might resolve to the wrong
      # namespace (e.g., Ai::Agents::Market module instead of the Market ActiveRecord model).
      # This method tries to find the correct ActiveRecord model class.
      #
      # @param model_constant [Class, Module] The model constant as resolved in the current context
      # @return [Class] The correct ActiveRecord model class
      def resolve_model_constant(model_constant)
        model_name = model_constant.name

        # If it's already an ActiveRecord model, use it directly
        begin
          if model_constant.respond_to?(:columns) && model_constant < ActiveRecord::Base
            return model_constant
          end
        rescue StandardError
          # If we can't check inheritance, continue with resolution
        end

        # Extract the base model name (e.g., "Ai::Agents::Market" -> "Market")
        base_name = model_name.split('::').last

        # Try to find the model in common Rails model locations
        candidates = [
          "::#{base_name}",  # Top-level constant (e.g., ::Market)
          base_name          # Relative constant (e.g., Market)
        ]

        candidates.each do |candidate_name|
          begin
            candidate = Object.const_get(candidate_name)
            begin
              if candidate.respond_to?(:columns) && candidate < ActiveRecord::Base
                return candidate
              end
            rescue StandardError
              # If we can't check inheritance, try the next candidate
              next
            end
          rescue NameError, TypeError
            # Continue trying other candidates
            next
          end
        end

        # If we can't find a proper ActiveRecord model, raise an error
        raise ArgumentError, "Could not resolve model '#{model_name}' to an ActiveRecord model class. " \
                           "Available candidates tried: #{candidates.join(', ')}"
      end

      # Convert all symbols to strings recursively for JSON compatibility
      #
      # @param obj [Object] The object to convert
      # @return [Object] The object with symbols converted to strings
      def convert_symbols_to_strings(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(key, value), hash|
            string_key = key.is_a?(Symbol) ? key.to_s : key
            hash[string_key] = convert_symbols_to_strings(value)
          end
        when Array
          obj.map { |item| convert_symbols_to_strings(item) }
        when Symbol
          obj.to_s
        else
          obj
        end
      end

      # Remove non-JSON Schema properties that OpenAI doesn't support
      #
      # @param obj [Object] The object to clean
      # @return [Object] The object with non-JSON Schema properties removed
      def clean_non_json_schema_properties(obj)
        # List of properties that are not part of JSON Schema spec
        # These might be used internally by RAAF but should not be sent to OpenAI
        non_json_schema_keys = %w[model flexible passthrough fallback]

        case obj
        when Hash
          cleaned = {}
          obj.each do |key, value|
            # Skip non-JSON Schema properties
            next if non_json_schema_keys.include?(key.to_s)

            cleaned[key] = clean_non_json_schema_properties(value)
          end
          cleaned
        when Array
          obj.map { |item| clean_non_json_schema_properties(item) }
        else
          obj
        end
      end
    end
  end
end