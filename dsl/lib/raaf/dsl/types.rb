# frozen_string_literal: true

module RAAF
  module DSL
    # Semantic type system for RAAF DSL schema builder
    #
    # Provides predefined semantic types with built-in validations and formats
    # for common data types like email, URL, percentage, currency, etc.
    #
    # @example Using semantic types
    #   RAAF::DSL::Types.define(:email)
    #   # => { type: :string, format: :email, pattern: /regex/ }
    #
    #   RAAF::DSL::Types.define(:score, minimum: 50)
    #   # => { type: :integer, minimum: 50, maximum: 100 }
    class Types
      # Pre-defined semantic types with validation patterns
      SEMANTIC_TYPES = {
        email: {
          type: :string,
          format: :email,
          pattern: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
        },
        url: {
          type: :string,
          format: :uri
        },
        percentage: {
          type: :number,
          minimum: 0,
          maximum: 100
        },
        currency: {
          type: :number,
          minimum: 0,
          multipleOf: 0.01
        },
        phone: {
          type: :string,
          pattern: /\A\+?[1-9]\d{1,14}\z/
        },
        positive_integer: {
          type: :integer,
          minimum: 1
        },
        score: {
          type: :integer,
          minimum: 0,
          maximum: 100
        },
        naics_code: {
          type: :string,
          pattern: /\A\d{2,6}\z/
        }
      }.freeze

      # Define a type with semantic validation rules
      #
      # @param type_name [Symbol] The semantic type name or base type
      # @param options [Hash] Additional type options that override defaults
      # @return [Hash] JSON schema type definition
      #
      # @example Semantic type with defaults
      #   Types.define(:email)
      #   # => { type: :string, format: :email, pattern: /regex/ }
      #
      # @example Semantic type with overrides
      #   Types.define(:email, required: true, maxLength: 255)
      #   # => { type: :string, format: :email, pattern: /regex/, required: true, maxLength: 255 }
      #
      # @example Custom type
      #   Types.define(:custom, type: :string, minLength: 5)
      #   # => { type: :string, minLength: 5 }
      #
      # @example Unknown type (graceful fallback)
      #   Types.define(:unknown_type)
      #   # => {}
      def self.define(type_name, **options)
        if SEMANTIC_TYPES.key?(type_name)
          SEMANTIC_TYPES[type_name].merge(options)
        else
          options
        end
      end

      # Get the base type for a semantic type
      #
      # @param type_name [Symbol] The semantic type name
      # @return [Symbol, nil] The base JSON schema type
      #
      # @example
      #   Types.base_type(:email)  # => :string
      #   Types.base_type(:score)  # => :integer
      #   Types.base_type(:unknown) # => nil
      def self.base_type(type_name)
        SEMANTIC_TYPES.dig(type_name, :type)
      end

      # Check if a type is a semantic type
      #
      # @param type_name [Symbol] The type name to check
      # @return [Boolean] true if it's a predefined semantic type
      #
      # @example
      #   Types.semantic?(email)   # => true
      #   Types.semantic?(:string) # => false
      def self.semantic?(type_name)
        SEMANTIC_TYPES.key?(type_name)
      end

      # Get all available semantic type names
      #
      # @return [Array<Symbol>] List of all semantic type names
      #
      # @example
      #   Types.available_types
      #   # => [:email, :url, :percentage, :currency, :phone, :positive_integer, :score, :naics_code]
      def self.available_types
        SEMANTIC_TYPES.keys
      end

      # Validate a value against a type definition
      #
      # @param value [Object] The value to validate
      # @param type_definition [Hash] The type definition from define()
      # @return [Boolean] true if value matches type constraints
      #
      # @example
      #   email_type = Types.define(:email)
      #   Types.valid?("test@example.com", email_type)  # => true
      #   Types.valid?("invalid-email", email_type)     # => false
      def self.valid?(value, type_definition)
        return true if type_definition.empty?

        # Check type constraints
        case type_definition[:type]
        when :string
          return false unless value.is_a?(String)

          # Check format constraints
          if type_definition[:format]
            case type_definition[:format]
            when :email
              # Use the pattern if available, otherwise basic email check
              if type_definition[:pattern]
                return false unless value.match?(type_definition[:pattern])
              else
                return false unless value.include?('@') && value.include?('.')
              end
            when :uri, :url
              # Basic URL validation - must start with http/https/ftp
              return false unless value.match?(/\A(https?|ftp):\/\/\S+\z/)
            end
          end

          # Check pattern if present (and not already checked by format)
          if type_definition[:pattern] && !type_definition[:format]
            return false unless value.match?(type_definition[:pattern])
          end

          # Check length constraints
          if type_definition[:maxLength]
            return false if value.length > type_definition[:maxLength]
          end

          if type_definition[:minLength]
            return false if value.length < type_definition[:minLength]
          end

        when :integer
          return false unless value.is_a?(Integer)

          # Check numeric constraints
          if type_definition[:minimum]
            return false if value < type_definition[:minimum]
          end

          if type_definition[:maximum]
            return false if value > type_definition[:maximum]
          end

        when :number
          return false unless value.is_a?(Numeric)

          # Check numeric constraints
          if type_definition[:minimum]
            return false if value < type_definition[:minimum]
          end

          if type_definition[:maximum]
            return false if value > type_definition[:maximum]
          end

          # Check multipleOf constraint
          if type_definition[:multipleOf]
            return false unless (value % type_definition[:multipleOf]).zero?
          end

        when :boolean
          return false unless [true, false].include?(value)

        when :array
          return false unless value.is_a?(Array)

        when :object
          return false unless value.is_a?(Hash)
        end

        true
      end
    end
  end
end