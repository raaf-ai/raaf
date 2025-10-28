# frozen_string_literal: true

require 'timeout'
require_relative 'wrapper_dsl'

module RAAF
  module DSL
    module PipelineDSL
      # Wrapper for agents with inline configuration
      class ConfiguredAgent
        include WrapperDSL

        attr_reader :agent_class, :options

        def initialize(agent_class, options)
          @agent_class = agent_class
          @options = options
        end

        # Create a new wrapper with merged options (required by WrapperDSL)
        def create_wrapper(**new_options)
          ConfiguredAgent.new(@agent_class, @options.merge(new_options))
        end
        
        # Delegate metadata methods
        def required_fields
          @agent_class.respond_to?(:required_fields) ? @agent_class.required_fields : []
        end
        
        def provided_fields
          @agent_class.respond_to?(:provided_fields) ? @agent_class.provided_fields : []
        end
        
        def requirements_met?(context)
          @agent_class.respond_to?(:requirements_met?) ? @agent_class.requirements_met?(context) : true
        end
        
        # Execute with configuration
        #
        # This method delegates to the agent's built-in retry and timeout mechanisms
        # instead of implementing its own. This ensures:
        # - Retry configurations (retry_on) from ApplicationAgent are respected
        # - Timeout errors are properly retried with exponential backoff
        # - Circuit breaker and other smart features work correctly
        # - Consistent behavior across all execution paths
        def execute(context)
          # Wrap execution with before_execute/after_execute hooks
          agent_name = @agent_class.respond_to?(:agent_name) ? @agent_class.agent_name : @agent_class.name

          execute_with_hooks(context, :configured, agent_name: agent_name, options: @options) do
            # Ensure context is ContextVariables if it's a plain Hash
            unless context.respond_to?(:set)
              context = RAAF::DSL::ContextVariables.new(context)
            end

            # Merge non-control options into context for agent to use
            enhanced_context = context.dup
            @options.each do |key, value|
              unless [:timeout, :retry].include?(key)
                enhanced_context[key] = value
              end
            end

            # Execute agent - convert context to keyword arguments to trigger context DSL processing
            context_hash = enhanced_context.is_a?(RAAF::DSL::ContextVariables) ? enhanced_context.to_h : enhanced_context
            agent = @agent_class.new(**context_hash)

            # Delegate to agent.run which handles:
            # - Retry logic (via execute_with_retry)
            # - Timeout logic (via execution_timeout config)
            # - Circuit breaker
            # - All smart features from ApplicationAgent
            result = agent.run

            # Merge results back into original context
            if @agent_class.respond_to?(:provided_fields)
              @agent_class.provided_fields.each do |field|
                context[field] = result[field] if result.respond_to?(:[]) && result[field]
              end
            end

            context
          end
        end
      end
    end
  end
end