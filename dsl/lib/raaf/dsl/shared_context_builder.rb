# frozen_string_literal: true

require_relative "core/context_variables"
require_relative "core/context_builder"

module RAAF
  module DSL
    # Shared context building logic for Agent and Service classes
    #
    # This module extracts common context management functionality to eliminate
    # duplication between Agent and Service classes while ensuring identical
    # behavior for context initialization, validation, and management.
    #
    # Features:
    # - Auto-context building from kwargs
    # - Context parameter processing
    # - Context validation with descriptive errors
    # - DSL rule application (defaults, requirements, validation)
    #
    module SharedContextBuilder
      include RAAF::Logging
      
      # Build context automatically from provided arguments
      #
      # This method handles the intelligent context building that looks at:
      # 1. Required fields from context DSL
      # 2. Exclusion/inclusion rules
      # 3. Custom preparation methods
      # 4. Default value application
      #
      # @param params [Hash] Keyword arguments provided to initialize
      # @param debug [Boolean, nil] Debug mode for context variables
      # @return [RAAF::DSL::ContextVariables] Built context object
      # @raise [ArgumentError] If required fields are missing
      def build_auto_context(params, debug = nil)
        require_relative "core/context_builder"
        
        # Detect duplicate context determination before building
        if self.class.respond_to?(:detect_duplicate_context_determination!)
          self.class.detect_duplicate_context_determination!
        end
        
        rules = self.class._agent_config[:context_rules] || {}
        builder = RAAF::DSL::ContextBuilder.new({}, debug: debug)
        
        # Validate required fields are provided
        if rules[:required]
          missing_required = rules[:required] - params.keys
          if missing_required.any?
            raise ArgumentError, "Missing required context fields: #{missing_required.inspect}"
          end
        end
        
        # Add provided parameters (with exclusion/inclusion rules)
        params.each do |key, value|
          # Apply exclusion rules
          next if rules[:exclude]&.include?(key)
          next if rules[:include]&.any? && !rules[:include].include?(key)
          
          # Check for custom preparation method
          if respond_to?("prepare_#{key}_for_context", true)
            value = send("prepare_#{key}_for_context", value)
          end
          
          builder.with(key, value)
        end
        
        # Add optional fields with defaults (new DSL)
        if rules[:optional]
          rules[:optional].each do |key, default_value|
            next if builder.context.key?(key) # Don't override provided values
            
            final_value = default_value.is_a?(Proc) ? default_value.call : default_value
            builder.with(key, final_value)
          end
        end
        
        # Apply legacy defaults for backward compatibility
        if rules[:defaults]
          rules[:defaults].each do |key, default_value|
            next if builder.context.key?(key) # Don't override provided values
            
            final_value = default_value.is_a?(Proc) ? default_value.call : default_value
            builder.with(key, final_value)
          end
        end
        
        # Apply computed fields if configured
        if rules[:computed]
          rules[:computed].each do |field_name, method_name|
            if respond_to?(method_name, true)
              computed_value = send(method_name)
              builder.with(field_name, computed_value)
            end
          end
        end
        
        RAAF::DSL::ContextVariables.new(builder.context.to_h, debug: debug)
      end
      
      # Build context from an explicit context parameter
      #
      # This method handles cases where context is provided explicitly as a
      # ContextVariables object or Hash, applying agent defaults while
      # preserving provided values.
      #
      # @param context_param [RAAF::DSL::ContextVariables, Hash] Context to process
      # @param debug [Boolean, nil] Debug mode for context variables
      # @return [RAAF::DSL::ContextVariables] Processed context object
      # @raise [ArgumentError] If context parameter is invalid type
      def build_context_from_param(context_param, debug = nil)
        # Detect duplicate context determination before building
        if self.class.respond_to?(:detect_duplicate_context_determination!)
          self.class.detect_duplicate_context_determination!
        end
        
        # Only accept ContextVariables instances
        base_context = case context_param
        when RAAF::DSL::ContextVariables
          context_param.to_h
        else
          raise ArgumentError, "context must be RAAF::DSL::ContextVariables instance. Use RAAF::DSL::ContextVariables.new(your_hash) instead of passing raw hash."
        end
        
        # Apply agent's context defaults if they don't exist in provided context
        if self.class._agent_config && self.class._agent_config[:context_rules]
          rules = self.class._agent_config[:context_rules]
          
          # Apply optional defaults (new DSL)
          if rules[:optional]
            rules[:optional].each do |key, default_value|
              base_context[key] ||= default_value.is_a?(Proc) ? default_value.call : default_value
            end
          end
          
          # Apply legacy defaults for backward compatibility
          if rules[:defaults]
            rules[:defaults].each do |key, default_value|
              base_context[key] ||= default_value.is_a?(Proc) ? default_value.call : value
            end
          end
        end
        
        RAAF::DSL::ContextVariables.new(base_context, debug: debug)
      end
      
      # Validate that all required context is present
      #
      # This method checks that all required context fields are available
      # and runs any validation rules defined in the context DSL.
      #
      # @param context [RAAF::DSL::ContextVariables] Context to validate
      # @raise [ArgumentError] If required fields are missing or validation fails
      def validate_context!(context = @context)
        return unless self.class._agent_config && self.class._agent_config[:context_rules]
        
        rules = self.class._agent_config[:context_rules]
        
        # Check required fields
        if rules[:required]
          missing_keys = rules[:required].reject { |key| context.has?(key) }
          if missing_keys.any?
            raise ArgumentError, "Required context keys missing: #{missing_keys.join(', ')}"
          end
        end

        # Run validation rules if configured
        if rules[:validations]
          rules[:validations].each do |key, validation_config|
            next unless context.has?(key)
            
            value = context.get(key)
            
            # Type validation
            if validation_config[:type]
              expected_type = validation_config[:type]
              unless value.is_a?(expected_type)
                raise ArgumentError, "Context key '#{key}' must be #{expected_type}, got #{value.class}"
              end
            end
            
            # Custom validation proc
            if validation_config[:proc]
              validation_proc = validation_config[:proc]
              unless validation_proc.call(value)
                raise ArgumentError, "Context key '#{key}' failed custom validation"
              end
            end
          end
        end
      end
      
      private
      
    end
  end
end