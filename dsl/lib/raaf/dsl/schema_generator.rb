# frozen_string_literal: true

module RAAF
  module DSL
    # Schema generator for Active Record models
    #
    # Automatically generates JSON schema definitions from Active Record model
    # introspection, including database columns, associations, and validations.
    #
    # @example Generate schema for a model
    #   schema = RAAF::DSL::SchemaGenerator.generate_for_model(Market)
    #   # => { type: :object, properties: {...}, required: [...] }
    class SchemaGenerator
      # Generate a complete JSON schema for an Active Record model
      #
      # @param model_class [Class] The Active Record model class
      # @return [Hash] JSON schema definition
      #
      # @example
      #   schema = SchemaGenerator.generate_for_model(Market)
      #   puts schema[:properties][:market_name]
      #   # => { type: :string, maxLength: 255 }
      def self.generate_for_model(model_class)
        properties = generate_properties(model_class)
        required_fields = generate_required_fields(model_class)

        # For OpenAI structured outputs, we always set additionalProperties: false
        # JSON/JSONB fields are now excluded from required array to avoid validation issues
        schema = {
          type: :object,
          properties: properties,
          required: required_fields,
          additionalProperties: false
        }

        # Convert symbols to strings for JSON compatibility
        convert_symbols_to_strings(schema)
      end

      private

      # Generate properties hash from model columns and associations
      #
      # @param model_class [Class] The Active Record model class
      # @return [Hash] Properties hash for JSON schema
      def self.generate_properties(model_class)
        properties = {}

        # Core attributes from database columns
        model_class.columns.each do |column|
          properties[column.name.to_sym] = map_column_to_schema(column)
        end

        # Association fields
        model_class.reflect_on_all_associations.each do |assoc|
          properties[assoc.name.to_sym] = map_association_to_schema(assoc)
        end

        # JSON column introspection could be added here in the future
        # detect_json_structures(model_class).each do |field, structure|
        #   properties[field] = structure
        # end

        properties
      end

      # Map a database column to JSON schema type definition
      #
      # @param column [ActiveRecord::ConnectionAdapters::Column] Database column
      # @return [Hash] JSON schema type definition
      def self.map_column_to_schema(column)
        base_schema = case column.type
                      when :string
                        schema = { type: :string }
                        schema[:maxLength] = column.limit if column.limit
                        schema
                      when :text
                        { type: :string }
                      when :integer
                        { type: :integer }
                      when :decimal, :float
                        { type: :number }
                      when :boolean
                        { type: :boolean }
                      when :datetime, :timestamp, :date, :time
                        { type: :string }  # OpenAI Structured Outputs don't support format keyword
                      when :json, :jsonb
                        # For JSON/JSONB columns, don't set additionalProperties: false
                        # since we don't know the internal structure
                        { type: :object }
                      else
                        { type: :string } # Fallback for unknown types
                      end

        base_schema
      end

      # Map an Active Record association to JSON schema type definition
      #
      # @param association [ActiveRecord::Reflection::AssociationReflection] Model association
      # @return [Hash] JSON schema type definition
      def self.map_association_to_schema(association)
        case association.macro
        when :belongs_to, :has_one
          { type: :object, description: "#{association.macro} association" }
        when :has_many, :has_and_belongs_to_many
          {
            type: :array,
            items: { type: :object },  # Required by OpenAI for all arrays
            description: "#{association.macro} association"
          }
        else
          { type: :object, description: "#{association.macro} association" }
        end
      end

      # Generate list of required fields from validations and database constraints
      #
      # For OpenAI structured outputs, ALL properties must be in the required array
      # to ensure strict schema validation works correctly.
      # EXCEPTION: JSON/JSONB columns without defined structure cannot be required
      # when additionalProperties is false
      #
      # @param model_class [Class] The Active Record model class
      # @return [Array<String>] List of ALL field names except JSON/JSONB (for OpenAI compatibility)
      def self.generate_required_fields(model_class)
        # For OpenAI structured outputs, we need ALL properties in the required array
        # This is different from traditional JSON schema where only truly required fields are listed
        # BUT we must exclude JSON/JSONB columns that don't have defined properties
        all_properties = []

        # All database columns EXCEPT json/jsonb
        model_class.columns.each do |column|
          # Skip JSON/JSONB columns since they're objects without defined properties
          # and OpenAI doesn't allow required fields that aren't in properties
          next if [:json, :jsonb].include?(column.type)
          all_properties << column.name
        end

        # All associations
        model_class.reflect_on_all_associations.each do |assoc|
          all_properties << assoc.name.to_s
        end

        # Return all properties as strings (OpenAI expects strings, not symbols)
        all_properties.uniq
      end

      # Get model file path for a given model class
      #
      # @param model_class [Class] The Active Record model class
      # @return [String] File path to the model file
      def self.model_class_file(model_class)
        # Convert class name to file path
        # E.g., "Market" -> "app/models/market.rb"
        # E.g., "Ai::Market::Analysis" -> "app/models/ai/market/analysis.rb"
        file_name = model_class.name.underscore
        if defined?(Rails) && Rails.root
          Rails.root.join("app", "models", "#{file_name}.rb").to_s
        else
          "app/models/#{file_name}.rb"
        end
      end

      # Detect JSON column structures (placeholder for future enhancement)
      #
      # This could analyze existing records to infer JSON structure
      # and generate more detailed schemas for JSON/JSONB columns.
      #
      # @param model_class [Class] The Active Record model class
      # @return [Hash] JSON field structures
      def self.detect_json_structures(model_class)
        # Future enhancement: analyze JSON columns to infer structure
        # For now, return empty hash
        {}
      end

      # Convert all symbols to strings recursively for JSON compatibility
      #
      # @param obj [Object] The object to convert
      # @return [Object] The object with symbols converted to strings
      def self.convert_symbols_to_strings(obj)
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
    end
  end
end