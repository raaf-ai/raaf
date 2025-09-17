# frozen_string_literal: true

module RAAF
  module DSL
    module Schema
      # Automatically generates JSON schemas from Active Record model introspection
      #
      # This class analyzes Active Record models to extract column definitions,
      # associations, and validations to automatically generate comprehensive
      # JSON schemas for AI agent use. This eliminates the need to manually
      # duplicate field definitions between database models and AI agent schemas.
      #
      # @example Basic usage
      #   schema = RAAF::DSL::Schema::SchemaGenerator.generate_for_model(Market)
      #   # => { type: :object, properties: { ... }, required: [...] }
      #
      # @example Generated schema structure
      #   {
      #     type: :object,
      #     properties: {
      #       id: { type: :integer },
      #       name: { type: :string, maxLength: 255 },
      #       description: { type: :string },
      #       created_at: { type: :string, format: :datetime },
      #       metadata: { type: :object },
      #       products: { type: :array, items: { type: :object } },
      #       company: { type: :object }
      #     },
      #     required: [:name, :description]
      #   }
      #
      class SchemaGenerator
        # ActiveModel validation classes that indicate required fields
        PRESENCE_VALIDATOR_CLASSES = [
          "ActiveModel::Validations::PresenceValidator",
          "ActiveRecord::Validations::PresenceValidator"
        ].freeze

        # Database column types that should be excluded from required fields
        EXCLUDED_REQUIRED_COLUMNS = %w[id created_at updated_at].freeze

        class << self
          # Generates a complete JSON schema from an Active Record model class
          #
          # @param model_class [Class] The Active Record model class to analyze
          # @return [Hash] JSON schema hash with type, properties, and required fields
          # @raise [ArgumentError] If model_class is nil or invalid
          #
          def generate_for_model(model_class)
            raise ArgumentError, "Model class cannot be nil" if model_class.nil?

            {
              type: :object,
              properties: generate_properties(model_class),
              required: generate_required_fields(model_class)
            }
          end

          # Maps an Active Record column to a JSON schema property definition
          #
          # @param column [ActiveRecord::ConnectionAdapters::Column] Database column
          # @return [Hash] JSON schema property definition
          #
          def map_column_to_schema(column)
            base_type = map_column_type(column.type)

            # Add length constraints for string types
            if base_type[:type] == :string && column.limit
              base_type[:maxLength] = column.limit
            end

            base_type
          end

          # Maps an Active Record association to a JSON schema property definition
          #
          # @param association [ActiveRecord::Reflection] Association reflection object
          # @return [Hash] JSON schema property definition
          #
          def map_association_to_schema(association)
            case association.macro
            when :has_many, :has_and_belongs_to_many
              { type: :array, items: { type: :object } }
            when :belongs_to, :has_one
              { type: :object }
            else
              { type: :object }
            end
          end

          # Extracts required field names from model validations and database constraints
          #
          # @param model_class [Class] The Active Record model class
          # @return [Array<Symbol>] List of required field names
          #
          def generate_required_fields(model_class)
            required = []

            # Extract from presence validations
            required.concat(extract_required_from_validations(model_class))

            # Extract from NOT NULL database constraints
            required.concat(extract_required_from_constraints(model_class))

            # Remove duplicates and return as symbols
            required.uniq.map(&:to_sym)
          end

          private

          # Generates all schema properties from model columns and associations
          #
          # @param model_class [Class] The Active Record model class
          # @return [Hash] Hash of property name to schema definition
          #
          def generate_properties(model_class)
            properties = {}

            # Add database column properties
            if model_class.respond_to?(:columns)
              model_class.columns.each do |column|
                next unless column.name

                properties[column.name.to_sym] = map_column_to_schema(column)
              end
            end

            # Add association properties
            if model_class.respond_to?(:reflect_on_all_associations)
              model_class.reflect_on_all_associations.each do |association|
                next unless association.name

                properties[association.name.to_sym] = map_association_to_schema(association)
              end
            end

            properties
          end

          # Maps database column types to JSON schema types
          #
          # @param column_type [Symbol] Active Record column type
          # @return [Hash] Base JSON schema type definition
          #
          def map_column_type(column_type)
            case column_type&.to_sym
            when :string
              { type: :string }
            when :text
              { type: :string }
            when :integer, :bigint
              { type: :integer }
            when :decimal, :float, :numeric
              { type: :number }
            when :boolean
              { type: :boolean }
            when :datetime, :timestamp, :time
              { type: :string, format: :datetime }
            when :date
              { type: :string, format: :date }
            when :json, :jsonb
              { type: :object }
            else
              # Default fallback for unknown types
              { type: :string }
            end
          end

          # Extracts required fields from Active Model validations
          #
          # @param model_class [Class] The Active Record model class
          # @return [Array<Symbol>] Required field names from validations
          #
          def extract_required_from_validations(model_class)
            required = []

            return required unless model_class.respond_to?(:validators)

            model_class.validators.each do |validator|
              # Check if this is a presence validator
              if presence_validator?(validator)
                required.concat(validator.attributes)
              end
            end

            required
          end

          # Extracts required fields from database NOT NULL constraints
          #
          # @param model_class [Class] The Active Record model class
          # @return [Array<Symbol>] Required field names from constraints
          #
          def extract_required_from_constraints(model_class)
            required = []

            return required unless model_class.respond_to?(:columns)

            model_class.columns.each do |column|
              # Skip if column allows NULL or is in excluded list
              next if column.null
              next if EXCLUDED_REQUIRED_COLUMNS.include?(column.name)

              required << column.name.to_sym
            end

            required
          end

          # Checks if a validator is a presence validator
          #
          # @param validator [ActiveModel::Validator] Validator instance
          # @return [Boolean] True if validator requires presence
          #
          def presence_validator?(validator)
            # Use duck typing to check for presence validator
            return false unless validator.respond_to?(:is_a?)

            # Check against known presence validator classes
            validator.is_a?(ActiveModel::Validations::PresenceValidator)
          rescue StandardError
            # Fallback: check class name as string
            PRESENCE_VALIDATOR_CLASSES.include?(validator.class.name)
          end
        end
      end
    end
  end
end