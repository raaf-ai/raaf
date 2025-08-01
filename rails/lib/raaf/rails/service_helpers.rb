# frozen_string_literal: true

require 'active_support/concern'

module RAAF
  module Rails
    # ServiceHelpers provides seamless integration between Rails services and RAAF agents
    #
    # This module eliminates boilerplate for running RAAF agents from Rails services
    # and provides automatic context building, error handling, and result transformation.
    #
    # @example Basic usage in a Rails service
    #   class MarketAnalysisService < ApplicationService
    #     include RAAF::Rails::ServiceHelpers
    #     
    #     def call
    #       result = run_agent(MarketAnalysisAgent, with: {
    #         product: @product,
    #         company: @company
    #       })
    #       
    #       if result[:success]
    #         success_result(markets: result[:data])
    #       else
    #         error_result(result[:error])
    #       end
    #     end
    #   end
    #
    # @example Advanced usage with smart context
    #   class ProspectDiscoveryService < ApplicationService
    #     include RAAF::Rails::ServiceHelpers
    #     
    #     def call
    #       context = smart_context do
    #         proxy :product, @product, only: [:id, :name, :features]
    #         proxy :company, @company, except: [:sensitive_data]
    #         proxy_if @include_history, :interaction_history, @prospect.interactions
    #         
    #         requires :product, :company
    #         validates :product, presence: [:name, :description]
    #       end
    #       
    #       run_agent(ProspectDiscoveryAgent, context: context)
    #     end
    #   end
    #
    module ServiceHelpers
      extend ActiveSupport::Concern

      # Run a RAAF agent with automatic context handling
      #
      # @param agent_class [Class] The RAAF agent class to run
      # @param with [Hash] Simple key-value pairs for context (auto-proxied)
      # @param context [ContextVariables] Pre-built context (takes precedence over :with)
      # @param options [Hash] Additional options for agent execution
      # @return [Hash] Standardized result hash with :success, :data/:error keys
      #
      # @example Simple usage
      #   result = run_agent(MarketAnalysis, with: { product: product, company: company })
      #
      # @example With pre-built context
      #   context = smart_context { proxy :product, product, only: [:name] }
      #   result = run_agent(MarketAnalysis, context: context)
      #
      # @example With options
      #   result = run_agent(MarketAnalysis, with: context_data, timeout: 30)
      #
      def run_agent(agent_class, with: nil, context: nil, **options)
        start_time = Time.current

        begin
          # Build context if not provided
          final_context = context || build_auto_context(with || {})
          
          # Validate agent class
          validate_agent_class!(agent_class)
          
          # Create and run agent
          agent = agent_class.new(context: final_context)
          result = agent.call
          
          # Log execution metrics
          log_agent_execution(agent_class, start_time, result, options)
          
          # Normalize result format
          normalize_agent_result(result)
          
        rescue => e
          handle_agent_error(agent_class, e, start_time, options)
        end
      end

      # Create a smart context using declarative syntax
      #
      # @param options [Hash] Context options (debug, validate, etc.)
      # @param block [Proc] Block with declarative context configuration
      # @return [ContextVariables] Built context ready for agent usage
      #
      # @example
      #   context = smart_context do
      #     proxy :user, current_user, only: [:id, :name]
      #     proxy :product, product, with_methods: [:price_tier]
      #     requires :user, :product
      #   end
      #
      def smart_context(**options, &block)
        require_relative '../../dsl/lib/raaf/dsl/context/smart_builder'
        RAAF::DSL::Context.smart_build(**options, &block)
      end

      # Run multiple agents in sequence with context propagation
      #
      # @param pipeline [Array<Hash>] Array of agent configurations
      # @param initial_context [Hash, ContextVariables] Starting context
      # @return [Hash] Combined results from all agents
      #
      # @example
      #   result = run_agent_pipeline([
      #     { agent: MarketAnalysis, merge_result_as: :markets },
      #     { agent: CompanySearch, needs: [:markets], merge_result_as: :companies },
      #     { agent: ProspectScoring, needs: [:markets, :companies] }
      #   ], initial_context: { product: product })
      #
      def run_agent_pipeline(pipeline, initial_context: {})
        context = initial_context.is_a?(Hash) ? build_auto_context(initial_context) : initial_context
        results = {}

        pipeline.each_with_index do |step_config, index|
          agent_class = step_config[:agent]
          needs = step_config[:needs] || []
          merge_as = step_config[:merge_result_as]
          
          # Add needed results to context
          needs.each do |key|
            if results[key]
              context = context.set(key, results[key])
            end
          end
          
          # Run agent
          step_result = run_agent(agent_class, context: context)
          
          # Store result
          step_key = merge_as || "step_#{index}".to_sym
          results[step_key] = step_result[:data] if step_result[:success]
          
          # Break pipeline on failure
          unless step_result[:success]
            return {
              success: false,
              error: "Pipeline failed at step #{index + 1} (#{agent_class.name}): #{step_result[:error]}",
              partial_results: results
            }
          end
        end

        {
          success: true,
          results: results,
          final_context: context.to_h
        }
      end

      # Batch run multiple agents in parallel
      #
      # @param agents [Hash] Hash of agent_name => { agent: Class, with: Hash } configurations
      # @param shared_context [Hash] Context shared across all agents
      # @return [Hash] Results from all agents
      #
      # @example
      #   results = run_agents_parallel({
      #     market_analysis: { agent: MarketAnalysis, with: { depth: 'detailed' } },
      #     competitor_analysis: { agent: CompetitorAnalysis, with: { focus: 'pricing' } }
      #   }, shared_context: { product: product, company: company })
      #
      def run_agents_parallel(agents, shared_context: {})
        base_context = build_auto_context(shared_context)
        
        # Create threads for parallel execution
        threads = agents.map do |agent_name, config|
          Thread.new do
            agent_context = config[:with] ? base_context.update(config[:with]) : base_context
            result = run_agent(config[:agent], context: agent_context)
            [agent_name, result]
          end
        end
        
        # Wait for all threads and collect results
        results = {}
        errors = {}
        
        threads.each do |thread|
          agent_name, result = thread.value
          if result[:success]
            results[agent_name] = result[:data]
          else
            errors[agent_name] = result[:error]
          end
        end
        
        if errors.any?
          {
            success: false,
            errors: errors,
            partial_results: results
          }
        else
          {
            success: true,
            results: results
          }
        end
      end

      # Create a simple context with automatic ActiveRecord proxying
      #
      # @param context_hash [Hash] Simple key-value context
      # @return [ContextVariables] Context with auto-proxied ActiveRecord objects
      #
      def build_auto_context(context_hash)
        builder = smart_context do
          context_hash.each do |key, value|
            if active_record_object?(value)
              proxy(key, value, except: sensitive_activerecord_fields)
            elsif value.is_a?(Array) && value.all? { |v| active_record_object?(v) }
              proxy(key, value, except: sensitive_activerecord_fields)
            else
              set(key, value)
            end
          end
        end
        
        builder
      end

      # Check if an agent executed successfully
      #
      # @param result [Hash] Agent execution result
      # @return [Boolean] True if agent succeeded
      #
      def agent_success?(result)
        result.is_a?(Hash) && result[:success] == true
      end

      # Extract data from agent result
      #
      # @param result [Hash] Agent execution result
      # @return [Object] The data portion of the result, or nil if failed
      #
      def extract_agent_data(result)
        agent_success?(result) ? result[:data] : nil
      end

      # Extract error from agent result
      #
      # @param result [Hash] Agent execution result
      # @return [String, nil] The error message, or nil if succeeded
      #
      def extract_agent_error(result)
        agent_success?(result) ? nil : result[:error]
      end

      private

      def validate_agent_class!(agent_class)
        unless agent_class.is_a?(Class)
          raise ArgumentError, "Agent must be a class, got #{agent_class.class}"
        end

        # Check if it's a RAAF agent (duck typing)
        unless agent_class.instance_methods.include?(:call)
          raise ArgumentError, "Agent class must implement #call method"
        end
      end

      def normalize_agent_result(result)
        case result
        when Hash
          if result.key?(:success)
            # Already normalized
            result
          elsif result.key?('success')
            # String keys, normalize to symbols
            {
              success: result['success'],
              data: result['data'],
              error: result['error']
            }
          else
            # Assume success if no explicit success key
            { success: true, data: result }
          end
        else
          # Non-hash result, wrap it
          { success: true, data: result }
        end
      end

      def handle_agent_error(agent_class, error, start_time, options)
        duration = Time.current - start_time
        
        RAAF::Logging.error "❌ [ServiceHelpers] Agent #{agent_class.name} failed after #{duration.round(2)}s: #{error.message}",
                           category: :agents,
                           data: {
                             agent_class: agent_class.name,
                             duration_ms: (duration * 1000).round(2),
                             error_class: error.class.name,
                             options: options
                           }

        {
          success: false,
          error: "Agent execution failed: #{error.message}",
          error_type: categorize_error(error),
          duration_ms: (duration * 1000).round(2)
        }
      end

      def log_agent_execution(agent_class, start_time, result, options)
        duration = Time.current - start_time
        success = normalize_agent_result(result)[:success]
        
        log_level = success ? :info : :warn
        status = success ? "completed" : "failed"
        
        RAAF::Logging.send(log_level, "🤖 [ServiceHelpers] Agent #{agent_class.name} #{status} in #{duration.round(2)}s",
                          category: :agents,
                          data: {
                            agent_class: agent_class.name,
                            duration_ms: (duration * 1000).round(2),
                            success: success,
                            options: options
                          })
      end

      def categorize_error(error)
        case error
        when ArgumentError
          if error.message.include?("context")
            :validation_error
          else
            :argument_error
          end
        when JSON::ParserError
          :json_error
        when Net::Error, Timeout::Error
          :network_error
        when StandardError
          if error.message.include?("rate limit")
            :rate_limit
          else
            :unexpected_error
          end
        else
          :unknown_error
        end
      end

      def active_record_object?(obj)
        defined?(ActiveRecord::Base) && obj.is_a?(ActiveRecord::Base)
      end

      def sensitive_activerecord_fields
        [
          :password_digest, :password, :password_confirmation,
          :api_key, :api_secret, :access_token, :refresh_token,
          :secret_key, :private_key, :encrypted_password,
          :reset_password_token, :confirmation_token,
          :unlock_token, :authentication_token
        ]
      end
    end

    # Convenience methods for the main RAAF namespace
    module Agent
      # Quick agent execution for simple cases
      #
      # @param agent_class [Class] Agent class to run
      # @param context [Hash] Context for the agent
      # @return [Hash] Agent execution result
      #
      def self.run(agent_class, **context)
        dummy_service = Class.new { include RAAF::Rails::ServiceHelpers }.new
        dummy_service.run_agent(agent_class, with: context)
      end
    end
  end
end