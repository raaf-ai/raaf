# frozen_string_literal: true

require_relative 'core/context_variables'

module RAAF
  module DSL
    # Error raised when attempting to access undeclared context variables in restricted mode
    class ContextAccessError < NameError; end
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
      # TODO: Add respond_to_missing? implementation for proper Ruby method resolution
      def method_missing(method_name, *args, &block)
        method_str = method_name.to_s

        # Handle assignment calls (variable = value)
        if method_str.end_with?('=') && args.size == 1 && !block_given?
          variable_name = method_str.chomp('=').to_sym
          
          # Try to set in primary context
          if respond_to?(:context, true) && context&.respond_to?(:set)
            # For pipelines with output variables, always allow setting
            if respond_to?(:context_config, true) && 
               context_config&.respond_to?(:output_variables) && 
               context_config.output_variables&.include?(variable_name)
              context.set(variable_name, args[0])
              return args[0]  # Return the assigned value like normal Ruby assignment
            end
            
            # For existing variables, update them
            if context.respond_to?(:has?) && context.has?(variable_name)
              context.set(variable_name, args[0])
              return args[0]  # Return the assigned value like normal Ruby assignment
            end
            
            # For new variables in unrestricted contexts, add them
            unless context_is_restricted?
              context.set(variable_name, args[0])
              return args[0]  # Return the assigned value like normal Ruby assignment
            end
          end
          
          # If we can't set it, provide helpful error (but avoid recursion)
          raise NameError, "undefined context variable `#{variable_name}' for assignment"
        end
        
        # Handle getter calls (variable)
        if args.empty? && !block_given?
          # Skip context variable handling for method calls (ending with ! or ?)
          # These should be handled by the class's actual methods, not context access
          if method_str.end_with?('!', '?')
            return super
          end

          # FIRST: Check restrictions if context is restricted
          # This prevents access to undeclared variables even if they exist in the underlying context
          if context_is_restricted?
            declared_vars = get_declared_context_variables
            all_declared = (declared_vars[:required] + declared_vars[:optional] + declared_vars[:output]).map(&:to_sym)

            unless all_declared.include?(method_name.to_sym)
              raise_context_restriction_error(method_name)
            end

            # Variable is declared - proceed with normal access
          end
          
          # Try multiple context sources in order of preference (only for declared variables or unrestricted contexts)
          
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
          
          # Final fallback: provide helpful error message
          if context_is_restricted?
            # This should not happen since we checked restrictions above, but safety net
            raise_context_restriction_error(method_name)
          else
            available_keys = get_available_context_keys
            raise NameError, "undefined variable `#{method_name}' - not found in context. Available: #{available_keys.inspect}"
          end
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
      # when a variable is not found. This version avoids method_missing recursion.
      #
      # @return [Array<Symbol>] Array of available context variable names
      def get_available_context_keys
        keys = []
        
        # Safely collect from primary context using instance variable
        if instance_variable_defined?(:@context)
          ctx = @context
          if ctx&.respond_to?(:keys)
            keys.concat(ctx.keys)
          elsif ctx&.respond_to?(:to_h)
            keys.concat(ctx.to_h.keys)
          elsif ctx.is_a?(Hash)
            keys.concat(ctx.keys)
          end
        end
        
        # Collect from context variables
        if instance_variable_defined?(:@context_variables) 
          vars = @context_variables
          if vars&.respond_to?(:keys)
            keys.concat(vars.keys)
          elsif vars&.respond_to?(:to_h)
            keys.concat(vars.to_h.keys)
          end
        end
        
        # Collect relevant instance variables (excluding internal ones)
        instance_variables.each do |ivar|
          var_name = ivar.to_s.sub('@', '')
          next if var_name.start_with?('_') || %w[context context_variables].include?(var_name)

          # Skip instance variables that have corresponding instance methods
          # These are not context variables, they're regular attributes
          next if self.class.method_defined?(var_name.to_sym) ||
                  self.class.private_method_defined?(var_name.to_sym)

          keys << var_name.to_sym
        end
        
        # Convert all keys to symbols for consistent comparison
        keys.map(&:to_sym).uniq.sort
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

      # Check if context is in restricted mode (has declared context DSL)
      #
      # Context is restricted when the class uses context DSL with required or optional declarations.
      # In restricted mode, only declared variables should be accessible.
      #
      # @return [Boolean] true if context access should be restricted to declared variables
      def context_is_restricted?
        return false unless respond_to?(:class)
        
        # Check if class has context configuration with restrictions
        if self.class.respond_to?(:_context_config) && self.class._context_config
          context_rules = self.class._context_config[:context_rules]
          return false unless context_rules
          
          # Context is restricted if it has explicit required or optional declarations
          has_required = context_rules[:required] && !context_rules[:required].empty?
          has_optional = context_rules[:optional] && !context_rules[:optional].empty?
          
          has_required || has_optional
        else
          false
        end
      end

      # Get declared context variables from the context DSL
      #
      # Returns all variables that have been explicitly declared in the context DSL,
      # both required and optional ones.
      #
      # @return [Hash] Hash with :required and :optional arrays
      def get_declared_context_variables
        return { required: [], optional: [] } unless respond_to?(:class)
        
        if self.class.respond_to?(:_context_config) && self.class._context_config
          context_rules = self.class._context_config[:context_rules]
          return { required: [], optional: [] } unless context_rules
          
          required = context_rules[:required] || []
          optional = (context_rules[:optional] || {}).keys
          output = context_rules[:output] || []
          
          { required: required, optional: optional, output: output }
        else
          { required: [], optional: [] }
        end
      end

      # Raise a context restriction error with helpful information
      #
      # Creates a detailed error message that explains:
      # 1. What variable was attempted to be accessed
      # 2. What variables are actually declared
      # 3. How to fix the issue by updating the context DSL
      #
      # @param variable_name [Symbol] The variable that was attempted to be accessed
      # @raise [ContextAccessError] Always raises with detailed error message
      def raise_context_restriction_error(variable_name)
        declared_vars = get_declared_context_variables
        agent_name = respond_to?(:class) && self.class.respond_to?(:agent_name) ? self.class.agent_name : self.class.name
        
        error_message = build_context_restriction_error_message(variable_name, declared_vars, agent_name)
        
        raise ContextAccessError, error_message
      end

      # Build a comprehensive error message for context restriction violations
      #
      # @param variable_name [Symbol] The variable that was attempted to be accessed
      # @param declared_vars [Hash] Hash with declared variables (:required, :optional, :output)
      # @param agent_name [String] Name of the agent class for context
      # @return [String] Formatted error message
      def build_context_restriction_error_message(variable_name, declared_vars, agent_name)
        lines = []
        lines << "❌ Context Access Error: Attempted to access undeclared context variable '#{variable_name}'"
        lines << ""
        lines << "🔒 #{agent_name} uses restricted context mode with the following declared variables:"
        
        if declared_vars[:required].any?
          lines << "   Required: #{declared_vars[:required].join(', ')}"
        else
          lines << "   Required: (none)"
        end
        
        if declared_vars[:optional].any?
          lines << "   Optional: #{declared_vars[:optional].join(', ')}"
        else
          lines << "   Optional: (none)"
        end
        
        if declared_vars[:output].any?
          lines << "   Output: #{declared_vars[:output].join(', ')}"
        end
        
        lines << ""
        lines << "💡 To access '#{variable_name}', you must declare it in the context DSL block:"
        lines << "   context do"
        
        if should_be_required?(variable_name)
          current_required = declared_vars[:required] + [variable_name]
          lines << "     required #{current_required.map(&:inspect).join(', ')}"
        else
          lines << "     # Add to required if this variable must always be provided:"
          lines << "     # required #{(declared_vars[:required] + [variable_name]).map(&:inspect).join(', ')}"
          lines << "     # OR add to optional with a default value:"
          lines << "     # optional #{variable_name}: nil  # or some default value"
        end
        
        lines << "     # ... rest of configuration"
        lines << "   end"
        lines << ""
        
        available_in_actual_context = get_available_context_keys
        variable_name_sym = variable_name.to_sym
        
        if available_in_actual_context.map(&:to_sym).include?(variable_name_sym)
          lines << "ℹ️  Note: '#{variable_name}' IS present in the actual context but not declared in the DSL."
        else
          lines << "ℹ️  Note: '#{variable_name}' is neither declared in the DSL nor present in the actual context."
        end
        
        if available_in_actual_context.any?
          lines << "   Available in actual context: #{available_in_actual_context.inspect}"
        end
        
        lines.join("\n")
      end

      # Heuristic to determine if a variable should be required vs optional
      #
      # @param variable_name [Symbol] The variable name to analyze
      # @return [Boolean] true if the variable seems like it should be required
      def should_be_required?(variable_name)
        # Common patterns that suggest a variable should be required
        required_patterns = %w[
          id user_id company_id product_id customer_id
          user company product customer
          data input query
          prospect stakeholder
        ]
        
        variable_str = variable_name.to_s
        required_patterns.any? { |pattern| variable_str.include?(pattern) }
      end
      
    end
  end
end