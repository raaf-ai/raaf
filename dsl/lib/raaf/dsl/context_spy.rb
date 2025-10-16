# frozen_string_literal: true

module RAAF
  module DSL
    # ContextSpy tracks variable access during dry-run validation
    class ContextSpy
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
      
      def method_missing(method_name, *args, &block)
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
        true  # Respond to everything during dry run
      end
    end
    
    # SafeDummy returns itself for any method call to allow chaining
    class SafeDummy
      def initialize(name = nil)
        @name = name
      end
      
      def method_missing(method_name, *args, &block)
        self  # Always return self to allow chaining
      end
      
      def respond_to_missing?(method_name, include_private = false)
        true
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