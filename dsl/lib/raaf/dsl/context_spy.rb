# frozen_string_literal: true

module RAAF
  module DSL
    # ContextSpy tracks variable access during dry-run validation
    class ContextSpy
      # Methods that should NOT be claimed via respond_to_missing?
      # These are Ruby core methods that if claimed can cause infinite recursion
      # during serialization, inspection, or type coercion
      EXCLUDED_METHODS = %i[
        as_json to_json to_hash to_a to_ary to_yaml
        marshal_dump marshal_load _dump _load
        to_io to_int to_proc to_regexp
        pretty_print pretty_print_cycle encode_with inspect
        duplicable? deep_dup deep_symbolize_keys deep_stringify_keys
      ].freeze

      attr_reader :missing_variables, :accessed_variables

      def initialize(real_context)
        @real_context = real_context.is_a?(Hash) ? real_context : real_context.to_h
        @missing_variables = []
        @accessed_variables = []
      end

      def has?(key)
        @accessed_variables << key unless @accessed_variables.include?(key)
        @real_context.key?(key.to_sym) || @real_context.key?(key.to_s)
      end

      def get(key)
        @accessed_variables << key unless @accessed_variables.include?(key)

        if @real_context.key?(key.to_sym)
          SafeDummy.new(key)
        elsif @real_context.key?(key.to_s)
          SafeDummy.new(key)
        else
          @missing_variables << key unless @missing_variables.include?(key)
          SafeDummy.new(key)
        end
      end

      def key?(key)
        has?(key)
      end

      # Support hash access pattern: context[:key]
      def [](key)
        get(key)
      end

      def keys
        @real_context.keys
      end

      def to_h
        @real_context
      end

      # Explicit serialization implementations to prevent recursion
      def as_json(options = nil)
        @real_context.as_json(options)
      end

      def to_json(options = nil)
        @real_context.to_json(options)
      end

      def to_hash
        nil  # Don't treat as implicitly hashable
      end

      def to_s
        "#<ContextSpy keys=#{@real_context.keys}>"
      end

      def inspect
        "#<ContextSpy keys=#{@real_context.keys} accessed=#{@accessed_variables} missing=#{@missing_variables}>"
      end

      def method_missing(method_name, *args, &block)
        # Don't handle excluded methods - delegate to super
        return super if EXCLUDED_METHODS.include?(method_name.to_sym)

        method_str = method_name.to_s

        # Handle both getter and setter patterns
        if method_str.end_with?('=')
          # Setter - just return the value
          args.first
        else
          # Getter - use get method
          get(method_name)
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        # Never claim to respond to serialization methods
        return false if EXCLUDED_METHODS.include?(method_name.to_sym)
        true  # Respond to everything else during dry run
      end
    end
    
    # SafeDummy returns itself for any method call to allow chaining
    class SafeDummy
      # Methods that should NOT be claimed via respond_to_missing?
      # These are Ruby core methods that if claimed can cause infinite recursion
      # during serialization, inspection, or type coercion
      EXCLUDED_METHODS = %i[
        as_json to_json to_hash to_h to_a to_ary to_yaml
        marshal_dump marshal_load _dump _load
        to_io to_int to_proc to_regexp
        pretty_print pretty_print_cycle encode_with
        duplicable? deep_dup deep_symbolize_keys deep_stringify_keys
      ].freeze

      def initialize(name = nil)
        @name = name
      end

      def method_missing(method_name, *args, &block)
        # Don't handle excluded methods - delegate to super
        return super if EXCLUDED_METHODS.include?(method_name.to_sym)
        self  # Always return self to allow chaining
      end

      def respond_to_missing?(method_name, include_private = false)
        # Never claim to respond to serialization methods
        return false if EXCLUDED_METHODS.include?(method_name.to_sym)
        true  # Respond to everything else during dry run
      end

      # Explicit serialization implementations to prevent recursion
      def as_json(options = nil)
        "DUMMY"
      end

      def to_json(options = nil)
        '"DUMMY"'
      end

      def to_hash
        nil  # Don't treat as hashable
      end

      def to_h
        {}  # Empty hash
      end

      def to_s
        "DUMMY"
      end

      def to_str
        "DUMMY"
      end
      
      def nil?
        false
      end
      
      def present?
        true
      end
      
      def blank?
        false
      end
      
      def empty?
        false
      end
      
      # Support array operations
      def each(&block)
        []
      end
      
      def map(&block)
        []
      end
      
      def length
        0
      end
      
      alias size length
      alias count length
    end
  end
end