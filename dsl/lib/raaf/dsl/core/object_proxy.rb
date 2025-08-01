# frozen_string_literal: true

require "delegate"

module RAAF
  module DSL
    # ObjectProxy provides a lazy-loading proxy for any Ruby object in context
    #
    # This proxy allows objects to be stored in context without immediate serialization,
    # providing lazy access to attributes and methods while maintaining the benefits
    # of the immutable context pattern.
    #
    # @example Basic usage with ActiveRecord
    #   product = Product.find(1)
    #   proxy = ObjectProxy.new(product)
    #   proxy.name # => Lazy loads product.name
    #
    # @example With configuration
    #   proxy = ObjectProxy.new(user,
    #     only: [:id, :name, :email],
    #     except: [:password_digest],
    #     methods: [:full_name, :avatar_url]
    #   )
    #
    class ObjectProxy < SimpleDelegator
      # @return [Object] The original wrapped object
      attr_reader :__target__

      # @return [Hash] Configuration options for the proxy
      attr_reader :__options__

      # @return [Hash] Cached values for accessed attributes
      attr_reader :__cache__

      # @return [Set] Track accessed attributes for debugging
      attr_reader :__accessed__

      # Initialize a new ObjectProxy
      #
      # @param target [Object] The object to proxy
      # @param options [Hash] Configuration options
      # @option options [Array<Symbol>] :only Whitelist of attributes/methods to expose
      # @option options [Array<Symbol>] :except Blacklist of attributes/methods to hide
      # @option options [Array<Symbol>] :methods Additional methods to include
      # @option options [Integer] :depth Maximum depth for nested serialization (default: 2)
      # @option options [Boolean] :cache Whether to cache accessed values (default: true)
      #
      def initialize(target, **options)
        @__target__ = target
        @__options__ = options
        @__cache__ = {} if options.fetch(:cache, true)
        @__accessed__ = Set.new
        super(target)
      end

      # Override method_missing to add access control and caching
      def method_missing(method_name, *args, &block)
        # Check if method is allowed
        if !method_allowed?(method_name)
          raise NoMethodError, "Method '#{method_name}' is not allowed on proxied object"
        end

        # Track access
        @__accessed__ << method_name

        # Check cache first if enabled
        if @__cache__ && args.empty? && !block
          return @__cache__[method_name] if @__cache__.key?(method_name)
        end

        # Call the method on the target
        result = @__target__.send(method_name, *args, &block)

        # Cache the result if caching is enabled and it's a simple call
        if @__cache__ && args.empty? && !block && cacheable_result?(result)
          @__cache__[method_name] = result
        end

        # Wrap nested objects if configured
        if should_wrap_result?(result)
          wrap_result(result, method_name)
        else
          result
        end
      rescue NoMethodError => e
        # Re-raise with more context
        raise NoMethodError, "#{e.message} on #{@__target__.class.name} proxy"
      end

      # Check if proxy responds to a method
      def respond_to_missing?(method_name, include_private = false)
        method_allowed?(method_name) && @__target__.respond_to?(method_name, include_private)
      end

      # Serialize the proxy for use in prompts or storage
      #
      # @param options [Hash] Serialization options
      # @return [Hash] Serialized representation
      #
      def to_serialized_hash(options = {})
        serializer_options = @__options__.merge(options)
        ObjectSerializer.serialize(@__target__, serializer_options)
      end

      # String representation for debugging
      def inspect
        "#<RAAF::DSL::ObjectProxy:#{object_id} @target=#{@__target__.class.name}:#{@__target__.object_id} @accessed=#{@__accessed__.to_a}>"
      end

      # Convert to string (for prompt interpolation)
      def to_s
        if @__target__.respond_to?(:to_s) && @__target__.method(:to_s).owner != BasicObject
          @__target__.to_s
        else
          inspect
        end
      end

      # Get the class of the proxied object
      def class
        @__target__.class
      end

      # Check if this is a proxy
      def proxy?
        true
      end

      # Access the raw target object (escape hatch)
      def __getobj__
        @__target__
      end

      private

      # Check if a method is allowed based on configuration
      def method_allowed?(method_name)
        method_str = method_name.to_s
        method_sym = method_name.to_sym

        # Never allow private methods starting with _
        return false if method_str.start_with?('_')

        # Check whitelist (only)
        if @__options__[:only]
          return @__options__[:only].include?(method_sym)
        end

        # Check blacklist (except)
        if @__options__[:except]
          return !@__options__[:except].include?(method_sym)
        end

        # Check if it's in additional methods
        if @__options__[:methods]
          return true if @__options__[:methods].include?(method_sym)
        end

        # Default: allow public methods
        @__target__.respond_to?(method_name)
      end

      # Check if a result should be cached
      def cacheable_result?(result)
        # Cache primitive types and frozen objects
        case result
        when NilClass, TrueClass, FalseClass, Numeric, String, Symbol
          true
        when Array, Hash
          # Only cache if reasonably small
          result.size < 100
        else
          result.frozen?
        end
      end

      # Check if result should be wrapped in a proxy
      def should_wrap_result?(result)
        return false unless @__options__[:depth].to_i > 1

        case result
        when NilClass, TrueClass, FalseClass, Numeric, String, Symbol, Date, Time
          false
        when Array, Hash
          false # Handle collections separately if needed
        else
          # Wrap complex objects
          result.respond_to?(:attributes) || result.instance_variables.any?
        end
      end

      # Wrap a result in a nested proxy
      def wrap_result(result, method_name)
        depth = @__options__[:depth].to_i - 1
        return result if depth <= 0

        nested_options = @__options__.merge(
          depth: depth,
          parent_method: method_name
        )

        self.class.new(result, **nested_options)
      end
    end

    # Convenience method to create a proxy
    #
    # @param target [Object] The object to proxy
    # @param options [Hash] Proxy options
    # @return [ObjectProxy] The proxied object
    #
    def self.proxy_object(target, **options)
      ObjectProxy.new(target, **options)
    end
  end
end