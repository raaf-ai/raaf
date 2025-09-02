# frozen_string_literal: true

require_relative "config/config"

module RAAF
  module DSL
    # Error raised when duplicate context determination methods are detected
    class DuplicateContextError < StandardError; end
    
    # ContextConfig class for the context DSL
    class ContextConfig
      def initialize
        @rules = {}
      end
      
      # New DSL methods
      def required(*fields)
        @rules[:required] ||= []
        @rules[:required].concat(fields.map(&:to_sym))
      end
      
      def optional(**fields_with_defaults)
        @rules[:optional] ||= {}
        fields_with_defaults.each do |field, default_value|
          @rules[:optional][field.to_sym] = default_value
        end
      end
      
      def output(*fields)
        @rules[:output] ||= []
        @rules[:output].concat(fields.map(&:to_sym))
      end
      
      def computed(field_name, method_name = nil)
        @rules[:computed] ||= {}
        method_name ||= "compute_#{field_name}".to_sym
        @rules[:computed][field_name.to_sym] = method_name.to_sym
      end
      
      # Keep existing methods for backward compatibility and other functionality
      def exclude(*keys)
        @rules[:exclude] ||= []
        @rules[:exclude].concat(keys)
      end
      
      def include(*keys)
        @rules[:include] ||= []
        @rules[:include].concat(keys)
      end
      
      def validate(key, type: nil, with: nil)
        @rules[:validations] ||= {}
        @rules[:validations][key] = { type: type, proc: with }
      end
      
      def to_h
        @rules
      end
    end
    
    # Shared context configuration module for Agent and Service classes
    #
    # This module provides unified context DSL functionality that can be shared
    # between RAAF::DSL::Agent and RAAF::DSL::Service classes, ensuring consistent
    # context management behavior across both AI agents and direct service classes.
    #
    # Features:
    # - Thread-safe configuration storage
    # - Context DSL with defaults, requirements, and validation
    # - Auto-context behavior configuration
    # - Field introspection for pipeline integration
    #
    # @example Usage in Agent class
    #   class MyAgent < RAAF::DSL::Agent
    #     include RAAF::DSL::ContextConfiguration
    #     
    #     context do
    #       default :timeout, 30
    #       requires :product, :company
    #     end
    #   end
    #
    # @example Usage in Service class
    #   class MyService < RAAF::DSL::Service
    #     include RAAF::DSL::ContextConfiguration
    #     
    #     context do
    #       default :max_results, 10
    #     end
    #   end
    #
    module ContextConfiguration
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Class-specific configuration storage for thread safety
        #
        # Each class gets its own thread-local configuration storage to prevent
        # cross-contamination between different agent/service classes in
        # multi-threaded environments.
        #
        # @return [Hash] Thread-local configuration hash for this class
        def _context_config
          Thread.current["raaf_dsl_config_#{object_id}"] ||= {}
        end

        def _context_config=(value)
          Thread.current["raaf_dsl_config_#{object_id}"] = value
        end

        # Control auto-context behavior (default: true)
        #
        # Auto-context automatically loads context variables from the calling
        # environment, method arguments, and explicitly passed context objects.
        #
        # @param enabled [Boolean] Whether to enable auto-context loading
        def auto_context(enabled = true)
          _context_config[:auto_context] = enabled
        end

        # Check if auto-context is enabled (default: true)
        #
        # @return [Boolean] True if auto-context is enabled
        def auto_context?
          _context_config[:auto_context] != false
        end

        # Configuration for context building rules
        #
        # Provides a DSL for defining context requirements, defaults, and validation
        # rules. Can be used with a block (DSL syntax) or with a hash (direct syntax).
        #
        # @example DSL syntax
        #   context do
        #     default :timeout, 30
        #     requires :product, :company
        #     optional :analysis_depth, "standard"
        #   end
        #
        # @example Hash syntax
        #   context(defaults: { timeout: 30 }, requirements: [:product])
        #
        # @param options [Hash] Direct context configuration (when not using block)
        # @param block [Proc] DSL block for context configuration
        def context(options = {}, &block)
          if block_given?
            config = ContextConfig.new
            config.instance_eval(&block)
            _context_config[:context_rules] = config.to_h
          else
            _context_config[:context_rules] = options
          end
        end

        # Extract required fields from context configuration
        #
        # Used by pipeline DSL for field validation and introspection.
        # Returns only explicitly required fields - fields with defaults are optional.
        #
        # @return [Array<Symbol>] Array of required field names
        def required_fields
          return [] unless _context_config[:context_rules]

          context_rules = _context_config[:context_rules]
          # Check both :required (new format) and :requirements (legacy format)
          requirements = context_rules[:required] || context_rules[:requirements] || []
          # Check both :optional (new format) and :defaults (legacy format)
          defaults = context_rules[:optional] || context_rules[:defaults] || {}

          # Return only explicitly required fields (optional fields with defaults are handled separately)
          requirements.uniq
        end

        # Extract externally required fields (required fields WITHOUT defaults)
        #
        # This is used by pipeline validation to check what MUST be provided
        # externally vs what can be satisfied by internal defaults.
        #
        # @return [Array<Symbol>] Array of externally required field names
        def externally_required_fields
          return [] unless _context_config[:context_rules]

          context_rules = _context_config[:context_rules]
          # Check both :required (new format) and :requirements (legacy format)
          requirements = context_rules[:required] || context_rules[:requirements] || []
          # Check both :optional (new format) and :defaults (legacy format)
          defaults = context_rules[:optional] || context_rules[:defaults] || {}

          # Return only required fields that don't have defaults
          (requirements - defaults.keys).uniq
        end

        # Auto-discover provided fields from service result
        #
        # Automatically discovers what fields this service provides by analyzing
        # the result structure, eliminating manual declaration mismatches.
        #
        # @return [Array<Symbol>] Array of provided field names
        def provided_fields
          # Check context configuration for output fields (DSL declaration)
          if _context_config[:context_rules] && _context_config[:context_rules][:output]
            return _context_config[:context_rules][:output]
          end
          
          # Check if service has been instantiated and run to analyze result
          if respond_to?(:last_result_fields) && last_result_fields
            return last_result_fields
          end
          
          # Fallback to manual declaration if available (backward compatibility)
          if respond_to?(:declared_provided_fields)
            return declared_provided_fields
          end
          
          # Default empty array for services that haven't been analyzed
          []
        end

        # Check if requirements are met by given context
        #
        # Validates that all required fields are present in the context or have
        # default values defined in the configuration.
        #
        # @param context [Hash, Object] Context to validate
        # @return [Boolean] True if all requirements are met
        def requirements_met?(context)
          required = required_fields
          return true if required.empty?

          # Get agent defaults if available
          defaults = {}
          if _context_config[:context_rules]
            # Check both :optional (new format) and :defaults (legacy format)
            defaults = _context_config[:context_rules][:optional] || _context_config[:context_rules][:defaults] || {}
          end

          # Check if context has all required fields (or they have defaults)
          if context.is_a?(Hash)
            # Ensure context has indifferent access for key checking
            context_with_indifferent_access = context.is_a?(ActiveSupport::HashWithIndifferentAccess) ? 
                                               context : 
                                               context.with_indifferent_access
            required.all? { |field| context_with_indifferent_access.key?(field) || defaults.key?(field) }
          elsif context.respond_to?(:keys) && context.respond_to?(:key?)
            # Handle objects that support both keys and key? (like ContextVariables)
            required.all? { |field| context.key?(field) || defaults.key?(field) }
          elsif context.respond_to?(:keys)
            # Fallback for objects that only support keys (convert to symbols for comparison)
            context_keys = context.keys.map(&:to_sym)
            required.all? { |field| context_keys.include?(field.to_sym) || defaults.key?(field) }
          else
            # For other context objects
            required.all? do |field|
              context.respond_to?(field) ||
                (context.respond_to?(:[]) && !context[field].nil?) ||
                defaults.key?(field)
            end
          end
        end

        # Ensure each subclass gets its own configuration
        #
        # Called automatically when a class inherits from a class that includes
        # this module. Ensures that subclasses don't share configuration state.
        def inherited(subclass)
          super
          subclass._context_config = {}
        end
        
        # Detect duplicate context determination (both DSL declaration and build_*_context methods)
        #
        # This validation ensures that context fields are not determined in multiple ways,
        # preventing confusion about the source of truth for context values.
        #
        # @raise [DuplicateContextError] If any field has both DSL declaration and build method
        def detect_duplicate_context_determination!
          return unless _context_config[:context_rules]
          
          context_rules = _context_config[:context_rules]
          duplicates = []
          
          # Collect all declared fields (required and optional)
          declared_fields = []
          declared_fields.concat(context_rules[:required] || [])
          declared_fields.concat((context_rules[:optional] || {}).keys)
          
          # Check for build_*_context methods for declared fields
          declared_fields.each do |field|
            build_method = "build_#{field}_context"
            if instance_methods.include?(build_method.to_sym) || 
               private_instance_methods.include?(build_method.to_sym)
              
              determination_methods = []
              
              # Check if it's required
              if (context_rules[:required] || []).include?(field)
                determination_methods << "Declared as 'required' in context DSL"
              end
              
              # Check if it's optional with default
              if (context_rules[:optional] || {}).key?(field)
                default_value = context_rules[:optional][field]
                determination_methods << "Declared as 'optional' with default: #{default_value.inspect}"
              end
              
              determination_methods << "Has method '#{build_method}'"
              
              duplicates << {
                field: field,
                methods: determination_methods
              }
            end
          end
          
          # Also check for computed fields that might conflict
          if context_rules[:computed]
            context_rules[:computed].each do |field, method_name|
              if declared_fields.include?(field)
                duplicates << {
                  field: field,
                  methods: [
                    declared_fields.include?(field) ? "Declared in context DSL" : nil,
                    "Has computed method '#{method_name}'"
                  ].compact
                }
              end
            end
          end
          
          if duplicates.any?
            raise_duplicate_context_error(duplicates)
          end
        end
        
        private
        
        # Raise a detailed error about duplicate context determination
        #
        # @param duplicates [Array<Hash>] Array of duplicate field information
        # @raise [DuplicateContextError] Always raises with detailed error message
        def raise_duplicate_context_error(duplicates)
          agent_name = respond_to?(:name) ? name : self.to_s
          
          lines = []
          lines << "RAAF::DSL::DuplicateContextError: Duplicate context determination detected in #{agent_name}!"
          lines << ""
          
          duplicates.each do |duplicate|
            lines << "Field '#{duplicate[:field]}' has multiple determination methods:"
            duplicate[:methods].each do |method|
              lines << "  - #{method}"
            end
            lines << ""
          end
          
          lines << "To fix this issue, choose ONE method for each field:"
          lines << "  Option 1: Remove the field from context DSL and use build_*_context method"
          lines << "  Option 2: Remove the build_*_context method and use context DSL declaration"
          lines << ""
          lines << "Context DSL is preferred for:"
          lines << "  - Fields that must be provided externally (use 'required')"
          lines << "  - Fields with simple default values (use 'optional')"
          lines << ""
          lines << "build_*_context methods are preferred for:"
          lines << "  - Fields that require complex computation"
          lines << "  - Fields that depend on other context values"
          lines << "  - Fields that need conditional logic"
          
          raise DuplicateContextError, lines.join("\n")
        end
      end
    end
  end
end