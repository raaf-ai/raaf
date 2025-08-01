# frozen_string_literal: true

module RAAF
  module DSL
    # ContextBuilder provides a fluent interface for building ContextVariables
    #
    # This class helps prevent common errors with the immutable ContextVariables pattern
    # by providing a chainable API that correctly captures the returned instances.
    #
    # @example Basic usage
    #   context = RAAF::DSL::ContextBuilder.new
    #     .with(:product, product)
    #     .with(:company, company)
    #     .with(:analysis_depth, "detailed")
    #     .build
    #
    # @example With validation
    #   context = RAAF::DSL::ContextBuilder.new(validate: true)
    #     .with(:product, product, type: Product)
    #     .with(:company, company, type: Company)
    #     .build
    #
    # @example From existing context
    #   builder = RAAF::DSL::ContextBuilder.from(existing_context)
    #     .with(:new_key, new_value)
    #     .build
    #
    class ContextBuilder
      # @return [RAAF::DSL::ContextVariables] The current context being built
      attr_reader :context

      # @return [Hash] Validation rules for context keys
      attr_reader :validations

      # @return [Boolean] Whether to enable debug mode
      attr_reader :debug_enabled

      # Initialize a new ContextBuilder
      #
      # @param initial_variables [Hash] Initial variables to start with
      # @param debug [Boolean] Enable debug mode for the context
      # @param validate [Boolean] Enable validation for the context
      #
      def initialize(initial_variables = {}, debug: false, validate: true)
        @context = ContextVariables.new(initial_variables, debug: debug, validate: validate)
        @validations = {}
        @debug_enabled = debug
        @validate_enabled = validate
      end

      # Create a ContextBuilder from an existing ContextVariables instance
      #
      # @param context [ContextVariables] Existing context to build from
      # @return [ContextBuilder] New builder with the existing context
      #
      def self.from(context)
        builder = new({}, debug: context.debug_enabled)
        builder.instance_variable_set(:@context, context)
        builder
      end

      # Add or update a context variable with optional validation
      #
      # @param key [Symbol, String] The variable key
      # @param value [Object] The variable value
      # @param type [Class] Optional type validation
      # @param required [Boolean] Whether this key is required
      # @param validate [Proc] Optional custom validation proc
      # @return [ContextBuilder] Self for method chaining
      #
      # @example Basic usage
      #   builder.with(:product, product)
      #
      # @example With type validation
      #   builder.with(:product, product, type: Product)
      #
      # @example With custom validation
      #   builder.with(:score, 85, validate: ->(v) { v.between?(0, 100) })
      #
      def with(key, value, type: nil, required: false, validate: nil)
        # Store validation rules if provided
        if type || required || validate
          @validations[key.to_sym] = {
            type: type,
            required: required,
            validate: validate
          }
        end

        # Validate the value if rules are defined
        if @validate_enabled && @validations[key.to_sym]
          validate_key!(key, value)
        end

        # Update context (capturing the new instance)
        @context = @context.set(key, value)
        
        debug_log("Added #{key}: #{value.inspect}") if @debug_enabled
        
        self
      end

      # Add multiple variables at once
      #
      # @param variables [Hash] Hash of key-value pairs to add
      # @return [ContextBuilder] Self for method chaining
      #
      # @example
      #   builder.with_all(
      #     product: product,
      #     company: company,
      #     analysis_depth: "detailed"
      #   )
      #
      def with_all(variables)
        variables.each do |key, value|
          with(key, value)
        end
        self
      end

      # Add a variable only if the condition is true
      #
      # @param condition [Boolean] Condition to check
      # @param key [Symbol, String] The variable key
      # @param value [Object, Proc] The variable value (or proc to compute it)
      # @return [ContextBuilder] Self for method chaining
      #
      # @example
      #   builder
      #     .with_if(user.premium?, :tier, "premium")
      #     .with_if(params[:debug], :debug_mode, true)
      #
      def with_if(condition, key, value)
        return self unless condition
        
        computed_value = value.is_a?(Proc) ? value.call : value
        with(key, computed_value)
      end

      # Add a variable only if it's not nil
      #
      # @param key [Symbol, String] The variable key
      # @param value [Object] The variable value
      # @return [ContextBuilder] Self for method chaining
      #
      # @example
      #   builder
      #     .with_present(:email, params[:email])
      #     .with_present(:name, user.name)
      #
      def with_present(key, value)
        with(key, value) unless value.nil?
        self
      end

      # Merge another context or hash
      #
      # @param other [ContextVariables, Hash] Context to merge
      # @return [ContextBuilder] Self for method chaining
      #
      def merge(other)
        other_hash = other.is_a?(ContextVariables) ? other.to_h : other
        @context = @context.update(other_hash)
        self
      end

      # Define required keys that must be present when building
      #
      # @param keys [Array<Symbol>] Required key names
      # @return [ContextBuilder] Self for method chaining
      #
      # @example
      #   builder
      #     .requires(:product, :company)
      #     .with(:product, product)
      #     .with(:company, company)
      #     .build # Will validate required keys are present
      #
      def requires(*keys)
        keys.each do |key|
          @validations[key.to_sym] ||= {}
          @validations[key.to_sym][:required] = true
        end
        self
      end

      # Build and return the final ContextVariables instance
      #
      # @param strict [Boolean] Whether to enforce all validations
      # @return [ContextVariables] The built context
      # @raise [ArgumentError] If required keys are missing or validation fails
      #
      def build(strict: true)
        if strict && @validate_enabled
          validate_all!
        end
        
        debug_log("Built context with #{@context.size} variables") if @debug_enabled
        
        @context
      end

      # Build or raise with detailed error information
      #
      # @return [ContextVariables] The built context
      # @raise [ArgumentError] With detailed validation errors
      #
      def build!
        build(strict: true)
      rescue ArgumentError => e
        raise ArgumentError, "ContextBuilder validation failed: #{e.message}\n" \
                           "Current keys: #{@context.keys.inspect}\n" \
                           "Required keys: #{required_keys.inspect}"
      end

      # Get a snapshot of the current state (for debugging)
      #
      # @return [Hash] Current builder state
      #
      def snapshot
        {
          context: @context.to_h,
          validations: @validations,
          required_keys: required_keys,
          debug_enabled: @debug_enabled
        }
      end

      private

      # Validate a single key-value pair
      def validate_key!(key, value)
        rules = @validations[key.to_sym]
        return unless rules

        # Type validation
        if rules[:type] && !value.nil? && !value.is_a?(rules[:type])
          raise ArgumentError, "Context key '#{key}' must be #{rules[:type]} but was #{value.class}"
        end

        # Custom validation
        if rules[:validate] && !rules[:validate].call(value)
          raise ArgumentError, "Context key '#{key}' failed custom validation"
        end
      end

      # Validate all required keys are present
      def validate_all!
        missing_keys = required_keys - @context.keys
        
        if missing_keys.any?
          raise ArgumentError, "Required context keys missing: #{missing_keys.join(', ')}"
        end

        # Run all validations
        @context.to_h.each do |key, value|
          validate_key!(key, value) if @validations[key]
        end
      end

      # Get list of required keys
      def required_keys
        @validations.select { |_, rules| rules[:required] }.keys
      end

      # Debug logging helper
      def debug_log(message)
        return unless @debug_enabled

        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.debug "[ContextBuilder] #{message}"
        else
          puts "[ContextBuilder] #{message}"
        end
      end
    end
  end
end