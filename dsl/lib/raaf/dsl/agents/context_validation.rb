# frozen_string_literal: true

module RAAF
  module DSL
    module Agents
      # ContextValidation provides a DSL for validating agent context
      #
      # This module focuses on the most valuable validations:
      # - Type checking to catch wrong data types
      # - Custom validation for business rules
      # 
      # It does NOT validate required fields (Ruby fails naturally with clear errors).
      #
      # @example Type validation
      #   class MyAgent < RAAF::DSL::Agents::Base
      #     include RAAF::DSL::Agents::ContextValidation
      #     
      #     validates_context :product, type: Product
      #     validates_context :score, type: Integer, validate: -> (v) { v.between?(0, 100) }
      #   end
      #
      # @example Multiple types and custom validation
      #   validates_context :identifier, type: [String, Integer]
      #   validates_context :email, validate: -> (v) { v =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i },
      #     message: "must be a valid email address"
      #
      module ContextValidation
        def self.included(base)
          base.extend(ClassMethods)
          base.prepend(InstanceMethods)
        end

        module ClassMethods
          # Define validation for a context key
          #
          # @param key [Symbol] The context key to validate
          # @param type [Class, Array<Class>] Expected type(s) - highly recommended
          # @param validate [Proc] Custom validation proc for business rules
          # @param message [String] Custom error message for validation failures
          #
          # @example Type validation (most common and valuable)
          #   validates_context :product, type: Product
          #   validates_context :company, type: Company
          #
          # @example Multiple types
          #   validates_context :identifier, type: [String, Integer]
          #
          # @example Custom business rule validation
          #   validates_context :score, type: Integer, validate: -> (v) { v.between?(0, 100) }
          #
          # @example With custom error message
          #   validates_context :email, 
          #     validate: -> (v) { v =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i },
          #     message: "must be a valid email address"
          #
          def validates_context(key, type: nil, validate: nil, message: nil)
            @context_validations ||= {}
            @context_validations[key.to_sym] = {
              type: type,
              validate: validate,
              message: message
            }.compact # Remove nil values
          end

          # Get all context validations
          #
          # @return [Hash] Validation rules
          #
          def context_validations
            @context_validations ||= {}
          end

          # Check if context validation is enabled
          #
          # @return [Boolean]
          #
          def validates_context?
            !context_validations.empty?
          end

          # Perform context validation
          #
          # Only validates type and custom business rules.
          # Does NOT validate required fields - let Ruby fail naturally.
          #
          # @param context [ContextVariables] Context to validate
          # @raise [ContextValidationError] If validation fails
          #
          def validate_context!(context)
            return unless validates_context?

            errors = []
            
            context_validations.each do |key, rules|
              value = context.get(key)
              
              # Skip validation if value is nil - let Ruby fail naturally
              next if value.nil?
              
              # Type validation - this catches real bugs
              if rules[:type]
                valid_type = Array(rules[:type]).any? { |t| value.is_a?(t) }
                unless valid_type
                  expected = Array(rules[:type]).map(&:name).join(" or ")
                  errors << "Context key '#{key}' must be #{expected} but was #{value.class.name}"
                end
              end
              
              # Custom validation for business rules
              if rules[:validate]
                begin
                  unless rules[:validate].call(value)
                    message = rules[:message] || "failed custom validation"
                    errors << "Context key '#{key}' #{message}"
                  end
                rescue => e
                  errors << "Context key '#{key}' validation error: #{e.message}"
                end
              end
            end
            
            if errors.any?
              raise ContextValidationError.new(errors, context)
            end
          end
        end

        module InstanceMethods
          # Override initialize to add validation
          def initialize(context: nil, **options)
            super(context: context, **options)
            
            # Only validate if there are meaningful validations (type or custom)
            if self.class.validates_context?
              begin
                self.class.validate_context!(@context)
              rescue ContextValidationError => e
                handle_validation_error(e)
                raise
              end
            end
          end

          private

          # Handle validation errors (can be overridden)
          def handle_validation_error(error)
            RAAF.logger.error "[#{self.class.name}] Context validation failed: #{error.errors.join('; ')}"
            RAAF.logger.debug "[#{self.class.name}] Available context keys: #{error.context.keys.inspect}"
          end
        end

        # Custom error class for context validation failures
        class ContextValidationError < StandardError
          attr_reader :errors, :context

          def initialize(errors, context)
            @errors = errors
            @context = context
            super(build_message)
          end

          private

          def build_message
            message = "Context validation failed with #{@errors.size} error(s):\n"
            message += @errors.map { |e| "  - #{e}" }.join("\n")
            message += "\n\nContext keys present: #{@context.keys.inspect}"
            message
          end
        end
      end

      # Convenience module for common validations
      module ContextValidators
        # Validate string is not blank
        NOT_BLANK = -> (v) { v.is_a?(String) && !v.strip.empty? }
        
        # Validate positive number
        POSITIVE = -> (v) { v.is_a?(Numeric) && v > 0 }
        
        # Validate non-negative number
        NON_NEGATIVE = -> (v) { v.is_a?(Numeric) && v >= 0 }
        
        # Validate percentage (0-100)
        PERCENTAGE = -> (v) { v.is_a?(Numeric) && v >= 0 && v <= 100 }
        
        # Validate email format
        EMAIL = -> (v) { v.is_a?(String) && v =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i }
        
        # Validate URL format
        URL = -> (v) { v.is_a?(String) && v =~ /\A#{URI::regexp(['http', 'https'])}\z/ }
        
        # Validate inclusion in list
        def self.included_in(list)
          -> (v) { list.include?(v) }
        end
        
        # Validate string length
        def self.length_between(min, max)
          -> (v) { v.is_a?(String) && v.length >= min && v.length <= max }
        end
        
        # Validate array size
        def self.array_size_between(min, max)
          -> (v) { v.is_a?(Array) && v.size >= min && v.size <= max }
        end
        
        # Validate numeric range
        def self.between(min, max)
          -> (v) { v.is_a?(Numeric) && v >= min && v <= max }
        end
      end
    end
  end
end