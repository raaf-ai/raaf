# frozen_string_literal: true

require_relative 'core/context_variables'

module RAAF
  module DSL
    # Shared context access module for consistent variable resolution
    # 
    # This module provides unified context variable access for both Agent and Prompt classes,
    # ensuring consistent behavior when accessing context variables, default values, and
    # error handling across the RAAF DSL framework.
    #
    # @example Usage in Agent class
    #   class MyAgent < RAAF::DSL::Agent
    #     include RAAF::DSL::ContextAccess
    #     # Now has unified context access
    #   end
    #
    # @example Usage in Prompt class  
    #   class MyPrompt < RAAF::DSL::Prompts::Base
    #     include RAAF::DSL::ContextAccess
    #     # Now has unified context access
    #   end
    #
    module ContextAccess
      
      def self.included(base)
        base.class_eval do
          # Ensure context is always a ContextVariables object for consistency and safety
          # This prevents recursion issues when objects that include ContextAccess are stored in context
          #
          # @param context [ContextVariables, Hash, nil] The context to convert
          # @param debug [Boolean] Whether to enable debug mode
          # @return [ContextVariables] A ContextVariables object
          def ensure_context_variables(context = nil, debug: false)
            case context
            when RAAF::DSL::ContextVariables
              context
            when Hash
              RAAF::DSL::ContextVariables.new(context, debug: debug)
            when nil
              RAAF::DSL::ContextVariables.new({}, debug: debug)
            else
              # Try to convert to hash first
              if context.respond_to?(:to_h)
                RAAF::DSL::ContextVariables.new(context.to_h, debug: debug)
              else
                raise ArgumentError, "Context must be Hash or ContextVariables, got #{context.class}"
              end
            end
          end
          
        end
      end
      
      # Universal context variable access via method_missing
      # 
      # Provides consistent context resolution across Agent and Prompt classes:
      # 1. Handles variable assignment (variable = value) 
      # 2. Handles variable access (variable)
      # 3. Falls back through multiple context sources
      # 4. Provides helpful error messages with available context keys
      #
      # @param method_name [Symbol] The variable name being accessed
      # @param args [Array] Method arguments (empty for variable access, single value for assignment)
      # @param block [Proc] Block argument (should be nil for variable access)
      # @return [Object] The context variable value
      # @raise [NameError] If variable doesn't exist in any context source
      def method_missing(method_name, *args, &block)
        method_str = method_name.to_s
        
        # Handle assignment calls (variable = value)
        if method_str.end_with?('=') && args.size == 1 && !block_given?
          variable_name = method_str.chomp('=').to_sym
          
          # Try to set in primary context
          if respond_to?(:context, true) && context&.respond_to?(:has?) && context.has?(variable_name)
            return context.set(variable_name, args[0]) if context.respond_to?(:set)
          end
          
          # Handle context DSL output variables (agent-specific)
          if respond_to?(:context_config, true) && context_config&.respond_to?(:output_variables) && 
             context_config.output_variables&.include?(variable_name)
            return context.set(variable_name, args[0]) if context.respond_to?(:set)
          end
          
          # Provide helpful error for unknown assignment
          available_keys = get_available_context_keys
          raise NameError, "undefined context variable `#{variable_name}' for assignment. Available: #{available_keys.inspect}"
        end
        
        # Handle getter calls (variable)
        if args.empty? && !block_given?
          # Try multiple context sources in order of preference
          
          # 1. Primary context (agent-style with defaults)
          if (method_defined_in_class?(:context) || instance_variable_defined?(:@context)) && 
             (context_obj = get_context_object) && 
             context_obj.respond_to?(:has?) && context_obj.has?(method_name)
            return context_obj.get(method_name) if context_obj.respond_to?(:get)
          end
          
          # 2. Context variables (prompt-style from agents)
          if instance_variable_defined?(:@context_variables) && @context_variables&.respond_to?(:has?) && @context_variables.has?(method_name)
            return @context_variables.get(method_name)
          end
          
          # 3. Direct context hash (prompt-style from initialization)
          if instance_variable_defined?(:@context) && @context.is_a?(Hash) && @context.key?(method_name)
            return @context[method_name]
          end
          
          # 4. Instance variable fallback (for compatibility)
          ivar_name = "@#{method_name}"
          if instance_variable_defined?(ivar_name)
            return instance_variable_get(ivar_name)
          end
          
          # Provide helpful error message with available context
          available_keys = get_available_context_keys
          raise NameError, "undefined variable `#{method_name}' - not found in context. Available: #{available_keys.inspect}"
        end
        
        # For all other method calls, delegate to super
        super
      end
      
      # Respond to missing for Ruby introspection
      # 
      # Indicates whether this object responds to a given variable name by checking
      # all available context sources.
      #
      # @param method_name [Symbol] The method name to check
      # @param include_private [Boolean] Whether to include private methods
      # @return [Boolean] true if the variable exists in any context source
      def respond_to_missing?(method_name, include_private = false)
        return true if variable_exists_in_context?(method_name)
        return true if method_name.to_s.end_with?('=') && variable_exists_in_context?(method_name.to_s.chomp('=').to_sym)
        
        super
      end
      
      private
      
      # Check if a variable exists in any context source
      # 
      # @param method_name [Symbol] The variable name to check
      # @return [Boolean] true if variable exists in any context
      def variable_exists_in_context?(method_name)
        # Check primary context (agent/service-style) - use direct instance variable check to avoid recursion
        return true if instance_variable_defined?(:@context) && @context&.respond_to?(:has?) && @context.has?(method_name)
        
        # Check context variables (prompt-style from agents)  
        return true if instance_variable_defined?(:@context_variables) && @context_variables&.respond_to?(:has?) && @context_variables.has?(method_name)
        
        # Check direct context hash (prompt-style from initialization)
        return true if instance_variable_defined?(:@context) && @context.is_a?(Hash) && @context.key?(method_name)
        
        # Check instance variables - but only with valid instance variable names
        # Ruby instance variables cannot contain special characters like ?, !, etc.
        ivar_name = "@#{method_name}"
        if valid_instance_variable_name?(ivar_name)
          return true if instance_variable_defined?(ivar_name)
        end
        
        false
      end
      
      # Get all available context keys for error messages
      # 
      # Collects keys from all context sources to provide helpful error messages
      # when a variable is not found.
      #
      # @return [Array<Symbol>] Array of available context variable names
      def get_available_context_keys
        keys = []
        
        # Collect from primary context (agent-style)
        if respond_to?(:context, true) && context&.respond_to?(:keys)
          keys.concat(context.keys)
        elsif respond_to?(:context, true) && context&.respond_to?(:to_h)
          keys.concat(context.to_h.keys)
        end
        
        # Collect from context variables (prompt-style from agents)
        if instance_variable_defined?(:@context_variables) && @context_variables&.respond_to?(:keys)
          keys.concat(@context_variables.keys)
        elsif instance_variable_defined?(:@context_variables) && @context_variables&.respond_to?(:to_h)
          keys.concat(@context_variables.to_h.keys)
        end
        
        # Collect from direct context hash (prompt-style from initialization)  
        if instance_variable_defined?(:@context) && @context.is_a?(Hash)
          keys.concat(@context.keys)
        end
        
        # Collect relevant instance variables (excluding internal ones)
        instance_variables.each do |ivar|
          var_name = ivar.to_s.sub('@', '')
          next if var_name.start_with?('_') || %w[context context_variables].include?(var_name)
          keys << var_name.to_sym
        end
        
        keys.uniq.sort
      end
      
      # Get context keys specifically (for backward compatibility)
      # 
      # This method maintains compatibility with existing error messages that
      # call `context_keys.inspect` in the current agent implementation.
      #
      # @return [Array<Symbol>] Array of context variable names
      def context_keys
        get_available_context_keys
      end
      
      # Check if a method is defined in the class hierarchy (without triggering method_missing)
      # 
      # @param method_name [Symbol] The method name to check
      # @return [Boolean] true if the method is defined in the class hierarchy
      def method_defined_in_class?(method_name)
        self.class.method_defined?(method_name) || 
        self.class.private_method_defined?(method_name)
      end
      
      # Safely get the context object without triggering method_missing
      # 
      # @return [Object, nil] The context object or nil if not available
      def get_context_object
        if method_defined_in_class?(:context)
          # Use the context method if it's defined
          context
        elsif instance_variable_defined?(:@context)
          # Fall back to instance variable
          @context
        else
          nil
        end
      rescue => e
        # If calling context method fails, fall back to instance variable
        instance_variable_defined?(:@context) ? @context : nil
      end

      # Check if a string would be a valid Ruby instance variable name
      # Ruby instance variables must start with @ and contain only alphanumeric characters and underscores
      # They cannot contain special characters like ?, !, etc.
      #
      # @param name [String] The instance variable name to check (should include @)
      # @return [Boolean] true if it's a valid instance variable name
      def valid_instance_variable_name?(name)
        return false unless name.is_a?(String)
        return false unless name.start_with?('@')
        
        # Check that the rest contains only alphanumeric characters and underscores
        var_part = name[1..-1]
        return false if var_part.empty?
        
        # Ruby instance variables can contain letters, numbers, and underscores
        # but cannot start with a number and cannot contain special chars like ?, !, etc.
        /\A[a-zA-Z_][a-zA-Z0-9_]*\z/.match?(var_part)
      end
      
    end
  end
end