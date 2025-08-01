# frozen_string_literal: true

module RAAF
  module DSL
    module Context
      # SmartBuilder provides a completely declarative approach to context building
      #
      # This class eliminates verbose context building patterns and makes it incredibly
      # simple to create rich contexts with automatic object proxying, validation,
      # and conditional logic.
      #
      # @example Simple declarative context
      #   context = RAAF::Context.smart_build do
      #     proxy :product, only: [:id, :name, :description]
      #     proxy :company, with_methods: [:market_segment]
      #     requires :product, :company
      #   end
      #
      # @example Advanced conditional context
      #   context = RAAF::Context.smart_build do
      #     proxy :user, except: [:password_digest, :api_key]
      #     proxy_if include_history?, :interaction_history
      #     proxy_all products, only: [:id, :name], as: :available_products
      #     
      #     validates :user, presence: [:email, :name]
      #     debug_mode Rails.env.development?
      #   end
      #
      class SmartBuilder
        def initialize(**options)
          @context_variables = ContextVariables.new({}, **options)
          @proxy_configs = {}
          @validation_rules = {}
          @required_keys = []
          @debug_enabled = options[:debug] || false
        end

        # Build context using declarative syntax
        def self.build(**options, &block)
          builder = new(**options)
          builder.instance_eval(&block) if block_given?
          builder.finalize
        end

        # Proxy a single object with configuration
        #
        # @param key [Symbol] Context key for the object
        # @param object [Object] Object to proxy (can be nil)
        # @param options [Hash] Proxy configuration options
        #
        # @example Basic proxy
        #   proxy :product, product_instance
        #
        # @example With access control
        #   proxy :user, user_instance, only: [:id, :name, :email]
        #   proxy :product, product_instance, except: [:internal_data]
        #
        # @example With methods
        #   proxy :product, product_instance, with_methods: [:calculated_price]
        #
        def proxy(key, object = nil, **options)
          # If object is nil, try to infer from current context
          if object.nil? && @current_object_context
            object = @current_object_context[key]
          end

          store_proxy_config(key, object, options)
          self
        end

        # Proxy multiple objects with shared configuration
        #
        # @param objects [Hash, Array] Objects to proxy
        # @param options [Hash] Shared proxy configuration
        #
        # @example Hash of objects
        #   proxy_all({ product: product, company: company }, only: [:id, :name])
        #
        # @example Array with custom naming
        #   proxy_all(products, as: :available_products, only: [:id, :name])
        #
        def proxy_all(objects, **options)
          as_key = options.delete(:as)
          
          case objects
          when Hash
            objects.each { |key, obj| proxy(key, obj, **options) }
          when Array
            if as_key
              proxy(as_key, objects, **options)
            else
              objects.each_with_index do |obj, index|
                proxy("item_#{index}".to_sym, obj, **options)
              end
            end
          else
            raise ArgumentError, "proxy_all expects Hash or Array, got #{objects.class}"
          end
          
          self
        end

        # Conditionally proxy an object
        #
        # @param condition [Boolean, Proc] Condition to evaluate
        # @param key [Symbol] Context key
        # @param object [Object] Object to proxy
        # @param options [Hash] Proxy configuration
        #
        # @example Simple condition
        #   proxy_if user.premium?, :premium_features, features
        #
        # @example Proc condition
        #   proxy_if -> { params[:include_history] }, :history, interaction_history  
        #
        def proxy_if(condition, key, object = nil, **options)
          should_include = condition.is_a?(Proc) ? condition.call : condition
          proxy(key, object, **options) if should_include
          self
        end

        # Set a simple value (not proxied)
        #
        # @param key [Symbol] Context key
        # @param value [Object] Value to set
        #
        def set(key, value)
          @context_variables = @context_variables.set(key, value)
          self
        end

        # Set multiple simple values
        #
        # @param values [Hash] Key-value pairs to set
        #
        def set_all(values)
          values.each { |key, value| set(key, value) }
          self
        end

        # Conditionally set a value
        #
        # @param condition [Boolean, Proc] Condition to evaluate
        # @param key [Symbol] Context key
        # @param value [Object] Value to set
        #
        def set_if(condition, key, value)
          should_include = condition.is_a?(Proc) ? condition.call : condition
          set(key, value) if should_include
          self
        end

        # Declare required context keys
        #
        # @param keys [Array<Symbol>] Required keys
        #
        def requires(*keys)
          @required_keys.concat(keys.map(&:to_sym))
          self
        end

        # Add validation rules for context keys
        #
        # @param key [Symbol] Context key to validate
        # @param rules [Hash] Validation rules
        #
        # @example
        #   validates :user, presence: [:email, :name], type: User
        #   validates :score, range: 0..100
        #
        def validates(key, **rules)
          @validation_rules[key.to_sym] = rules
          self
        end

        # Enable or disable debug mode
        #
        # @param enabled [Boolean] Whether to enable debug mode
        #
        def debug_mode(enabled = true)
          @debug_enabled = enabled
          self
        end

        # Merge another context or hash
        #
        # @param other [ContextVariables, Hash] Context to merge
        #
        def merge(other)
          other_hash = other.is_a?(ContextVariables) ? other.to_h : other
          @context_variables = @context_variables.update(other_hash)
          self
        end

        # Set the current object context for implicit proxy resolution
        #
        # @param context [Hash] Object context mapping
        #
        def with_object_context(context)
          @current_object_context = context
          yield(self) if block_given?
          @current_object_context = nil
          self
        end

        # Finalize and build the context
        #
        # @return [ContextVariables] The built context with all proxies applied
        #
        def finalize
          # Apply all proxy configurations
          apply_proxies

          # Validate the final context
          validate_context if @validation_rules.any? || @required_keys.any?

          # Log debug information if enabled
          log_debug_info if @debug_enabled

          @context_variables
        end

        # Get a snapshot of the current builder state (for debugging)
        #
        # @return [Hash] Builder state information
        #
        def snapshot
          {
            proxy_configs: @proxy_configs,
            validation_rules: @validation_rules,
            required_keys: @required_keys,
            context_size: @context_variables.size,
            debug_enabled: @debug_enabled
          }
        end

        private

        def store_proxy_config(key, object, options)
          @proxy_configs[key] = {
            object: object,
            options: options
          }
        end

        def apply_proxies
          require_relative '../core/object_proxy' unless defined?(RAAF::DSL::ObjectProxy)

          @proxy_configs.each do |key, config|
            object = config[:object]
            options = config[:options]

            if object.nil?
              @context_variables = @context_variables.set(key, nil)
            else
              # Create proxy with configuration
              proxy = ObjectProxy.new(object, **options)
              @context_variables = @context_variables.set(key, proxy)
            end
          end
        end

        def validate_context
          # Check required keys
          missing_keys = @required_keys.reject { |key| @context_variables.has?(key) }
          if missing_keys.any?
            raise ArgumentError, "Required context keys missing: #{missing_keys.join(', ')}"
          end

          # Apply validation rules
          @validation_rules.each do |key, rules|
            validate_key(key, @context_variables.get(key), rules)
          end
        end

        def validate_key(key, value, rules)
          # Presence validation
          if rules[:presence] && value.nil?
            raise ArgumentError, "Context key '#{key}' is required but missing"
          end

          # Type validation
          if rules[:type] && value && !value.is_a?(rules[:type])
            raise ArgumentError, "Context key '#{key}' must be #{rules[:type]} but was #{value.class}"
          end

          # Range validation
          if rules[:range] && value.respond_to?(:between?)
            unless value.between?(rules[:range].min, rules[:range].max)
              raise ArgumentError, "Context key '#{key}' must be between #{rules[:range].min} and #{rules[:range].max}"
            end
          end

          # Presence of attributes validation (for objects)
          if rules[:presence].is_a?(Array) && value.respond_to?(:[])
            missing_attrs = rules[:presence].reject do |attr|
              attr_value = value[attr] || (value.respond_to?(attr) ? value.send(attr) : nil)
              attr_value.present?
            end

            if missing_attrs.any?
              raise ArgumentError, "Context key '#{key}' missing required attributes: #{missing_attrs.join(', ')}"
            end
          end

          # Custom validation proc
          if rules[:validate] && !rules[:validate].call(value)
            raise ArgumentError, "Context key '#{key}' failed custom validation"
          end
        end

        def log_debug_info
          RAAF::Logging.debug "[SmartBuilder] Context built successfully", 
                             category: :context,
                             data: {
                               keys: @context_variables.keys,
                               proxied_objects: @proxy_configs.keys,
                               total_size: @context_variables.size,
                               validation_rules: @validation_rules.keys
                             }
        end
      end
    end

    # Convenience module for the main RAAF namespace
    module Context
      # Build a context using the smart declarative syntax
      #
      # @param options [Hash] Context options (debug, validate, etc.)
      # @param block [Proc] Block containing declarative context configuration
      # @return [ContextVariables] Built context
      #
      def self.smart_build(**options, &block)
        Context::SmartBuilder.build(**options, &block)
      end

      # Create a simple context builder (original ContextBuilder)
      #
      # @param initial_variables [Hash] Initial context variables
      # @param options [Hash] Builder options
      # @return [ContextBuilder] Traditional context builder
      #
      def self.build(initial_variables = {}, **options)
        ContextBuilder.new(initial_variables, **options)
      end
    end
  end
end