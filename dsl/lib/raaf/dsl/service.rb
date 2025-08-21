# frozen_string_literal: true

require "raaf-core"
require "active_support/concern"
require "active_support/core_ext/object/blank"
require_relative "context_configuration"
require_relative "context_access"
require_relative "pipelineable"
require_relative "core/context_variables"
require_relative "shared_context_builder"

module RAAF
  module DSL
    # Base class for RAAF Service implementations
    #
    # RAAF::DSL::Service provides a base class for creating service objects that
    # can be used in RAAF pipeline DSL flows alongside Agent classes. Services are
    # designed for direct API calls, data processing, and other non-AI operations
    # that don't require LLM integration.
    #
    # Key differences from Agent:
    # - Uses `call` method instead of `run` for execution
    # - No LLM integration, prompts, or schema handling
    # - Focused on direct service operations and data processing
    # - Full context management and pipeline DSL integration
    #
    # Features shared with Agent:
    # - Context DSL with defaults and requirements
    # - Automatic context variable access
    # - Pipeline DSL operators (>>, |)
    # - Iterator support with each_over()
    # - Configuration methods (timeout, retry, limit)
    #
    # @example Basic service implementation
    #   class CompanySearchService < RAAF::DSL::Service
    #     context do
    #       default :max_results, 10
    #       default :timeout, 30
    #     end
    #
    #     def self.required_fields
    #       [:search_query]
    #     end
    #
    #     def self.provided_fields
    #       [:companies, :metadata]
    #     end
    #
    #     def call
    #       query = search_query
    #       companies = perform_search(query)
    #       
    #       {
    #         companies: companies,
    #         metadata: { count: companies.length }
    #       }
    #     end
    #   end
    #
    # @example Usage in pipeline with iteration
    #   class DataProcessingPipeline < RAAF::Pipeline
    #     flow DataLoader >>
    #          CompanySearchService.each_over(:queries).parallel >>
    #          ResultAggregator
    #   end
    #
    # @example Service with context validation
    #   class ValidatingService < RAAF::DSL::Service
    #     context do
    #       requires :product, :company
    #       default :analysis_depth, "standard"
    #     end
    #
    #     def call
    #       validate_inputs!
    #       process_data
    #     end
    #
    #     private
    #
    #     def validate_inputs!
    #       raise ArgumentError, "Product required" unless product.present?
    #     end
    #   end
    #
    class Service
      include RAAF::Logger
      include RAAF::DSL::ContextAccess
      include RAAF::DSL::ContextConfiguration
      include RAAF::DSL::Pipelineable
      include RAAF::DSL::SharedContextBuilder

      # Context accessor for compatibility with ContextAccess module
      attr_reader :context

      # Initialize service with context management (identical to Agent)
      #
      # Creates a new service instance with automatic context loading from the
      # provided arguments. Context variables become automatically accessible
      # as method calls on the service instance.
      #
      # @example Direct initialization
      #   service = MyService.new(product: product, company: company)
      #   service.product  # => product object
      #   service.company  # => company object
      #
      # @example With explicit context
      #   service = MyService.new(context: context_variables)
      #
      # @example Initialization from iterator (automatic)
      #   # In pipeline: MyService.each_over(:items)
      #   # Service receives: current_item, plus other context
      #
      # @param context [ContextVariables, Hash, nil] Explicit context (backward compatible)
      # @param processing_params [Hash] Processing configuration parameters
      # @param debug [Boolean, nil] Enable debug mode for context variables
      # @param kwargs [Hash] Context variables as keyword arguments
      def initialize(context: nil, processing_params: {}, debug: nil, **kwargs)
        @debug_enabled = debug || (defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.development?) || false
        @processing_params = processing_params
        
        # Use identical context building strategy as Agent
        if context
          @context = build_context_from_param(context, @debug_enabled)
        elsif self.class.auto_context?
          @context = build_auto_context(kwargs, @debug_enabled)
        else
          # Auto-context disabled, empty context
          @context = RAAF::DSL::ContextVariables.new({}, debug: @debug_enabled)
        end
        
        validate_context!
        after_initialize if respond_to?(:after_initialize, true)
      end

      # Abstract service execution method with result field capture
      #
      # This method must be implemented by all service subclasses. It should
      # contain the core logic for the service operation and return a hash
      # of results that can be used by subsequent pipeline steps.
      #
      # The service automatically captures the result fields for pipeline
      # integration, eliminating the need for manual field declarations.
      #
      # @example Implementation
      #   def call
      #     data = fetch_data
      #     processed = process_data(data)
      #     
      #     {
      #       result: processed,
      #       metadata: { processed_at: Time.current }
      #     }
      #   end
      #
      # @return [Hash] Hash of results for pipeline consumption
      # @raise [NotImplementedError] If not implemented by subclass
      def call
        raise NotImplementedError, "#{self.class.name} must implement #call method"
      end
      
      # Execute service and capture result fields for pipeline integration
      #
      # This is used by the pipeline DSL to both execute the service and
      # capture what fields it provides for the next pipeline step.
      #
      # @return [Hash] Service execution result
      def call_with_field_capture
        result = call
        
        # Capture result fields for pipeline integration
        if result.is_a?(Hash)
          @last_result_fields = result.keys.map(&:to_sym)
          self.class.instance_variable_set(:@last_result_fields, @last_result_fields)
        end
        
        result
      end
      
      # Get the fields from the last execution (for pipeline validation)
      #
      # @return [Array<Symbol>, nil] Array of field names or nil if not captured
      def last_result_fields
        @last_result_fields || self.class.instance_variable_get(:@last_result_fields)
      end

      # Access context variables directly
      #
      # Provides convenient access to context variables without needing to
      # go through the context object. Uses method_missing from ContextAccess.
      #
      # @example
      #   # Instead of: @context.get(:product)
      #   # Use: product
      #
      # @param key [Symbol] Context variable name
      # @return [Object] Context variable value
      def get(key)
        @context.get(key)
      end

      # Check if context has a specific key
      #
      # @param key [Symbol] Context variable name to check
      # @return [Boolean] True if context contains the key
      def has?(key)
        @context.has?(key)
      end

      # Get all context as a hash
      #
      # @return [Hash] All context variables as a hash
      def context_hash
        @context.to_h
      end

      # Service identification for debugging and logging
      #
      # @return [String] Human-readable service identifier
      def service_name
        self.class.name.demodulize
      end

      # String representation for debugging
      #
      # @return [String] Service representation with context info
      def to_s
        "#<#{self.class.name} context_keys=#{@context.keys.inspect}>"
      end

      private

      # Handle method calls for context access
      #
      # Delegates to the ContextAccess module which provides automatic
      # context variable access via method_missing.
      def method_missing(method_name, *args, &block)
        # ContextAccess handles context variable access
        super
      end

      def respond_to_missing?(method_name, include_private = false)
        # ContextAccess handles context variable detection
        super
      end
    end
  end
end