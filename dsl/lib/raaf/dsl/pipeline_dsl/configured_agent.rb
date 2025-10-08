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
        def execute(context)
          timeout_value = @options[:timeout] || 30
          retry_count = @options[:retry] || 1
          
          Timeout.timeout(timeout_value) do
            attempts = 0
            begin
              attempts += 1
              
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
              result = agent.run
              
              # Merge results back into original context
              if @agent_class.respond_to?(:provided_fields)
                @agent_class.provided_fields.each do |field|
                  context[field] = result[field] if result.respond_to?(:[]) && result[field]
                end
              end
              
              context
            rescue => e
              if attempts < retry_count
                sleep_time = 2 ** (attempts - 1) # Exponential backoff
                RAAF.logger.warn "Retrying #{@agent_class.name} after #{sleep_time}s (attempt #{attempts}/#{retry_count})"
                sleep(sleep_time)
                retry
              else
                raise e
              end
            end
          end
        rescue Timeout::Error => e
          RAAF.logger.error "#{@agent_class.name} timed out after #{timeout_value} seconds"
          raise e
        end
      end
    end
  end
end