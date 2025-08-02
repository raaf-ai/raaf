# frozen_string_literal: true

module RAAF
  module DSL
    module Agents
      # ContextValidation provides a DSL for validating agent context
      #
      # This module adds context validation capabilities to agents, allowing
      # them to declare required keys, types, and custom validations.
      #
      # @example Basic validation
      #   class MyAgent < RAAF::DSL::Agents::Base
      #     include RAAF::DSL::Agents::ContextValidation
      #     
      #     validates_context :product, required: true, type: Product
      #     validates_context :score, type: Integer, validate: -> (v) { v.between?(0, 100) }
      #   end
      #
      # @example With error messages
      #   validates_context :email, 
      #     required: true,
      #     validate: -> (v) { v =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i },
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
          # @param required [Boolean] Whether the key is required
          # @param type [Class, Array<Class>] Expected type(s)
          # @param validate [Proc] Custom validation proc
          # @param message [String] Custom error message
          # @param allow_nil [Boolean] Whether nil values are allowed
          #
          # @example Type validation
          #   validates_context :product, type: Product
          #
          # @example Multiple types
          #   validates_context :identifier, type: [String, Integer]
          #
          # @example Custom validation
          #   validates_context :age, validate: -> (v) { v >= 18 }
          #
          # @example With custom message
          #   validates_context :score,
          #     validate: -> (v) { v.between?(0, 100) },
          #     message: "must be between 0 and 100"
          #
          def validates_context(key, options = {})
            @context_validations ||= {}
            @context_validations[key.to_sym] = {
              required: options[:required] || false,
              type: options[:type],
              validate: options[:validate],
              message: options[:message],
              allow_nil: options.fetch(:allow_nil, true)
            }
          end

          # Define multiple required context keys at once
          #
          # @param keys [Array<Symbol>] Required key names
          #
          # @example
          #   requires_context :product, :company, :user
          #
          def requires_context(*keys)
            keys.each do |key|
              validates_context key, required: true
            end
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
          # @param context [ContextVariables] Context to validate
          # @raise [ContextValidationError] If validation fails
          #
          def validate_context!(context)
            return unless validates_context?

            errors = []
            
            context_validations.each do |key, rules|
              value = context.get(key)
              
              # Check required
              if rules[:required] && value.nil?
                errors << "Context key '#{key}' is required but was not provided"
                next
              end
              
              # Skip other validations if nil and allowed
              next if value.nil? && rules[:allow_nil]
              
              # Type validation
              if rules[:type] && value
                valid_type = Array(rules[:type]).any? { |t| value.is_a?(t) }
                unless valid_type
                  expected = Array(rules[:type]).map(&:name).join(" or ")
                  errors << "Context key '#{key}' must be #{expected} but was #{value.class.name}"
                end
              end
              
              # Custom validation
              if rules[:validate] && value
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
            
            # Validate context if validations are defined
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
            RAAF::Logging.error "[#{self.class.name}] Context validation failed:", errors: error.errors.join("; "), context_keys: error.context.keys.inspect
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