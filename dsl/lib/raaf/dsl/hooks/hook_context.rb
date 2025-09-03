# frozen_string_literal: true

require_relative '../context_access'

module RAAF
  module DSL
    module Hooks
      ##
      # HookContext provides ergonomic context variable access within agent hooks
      #
      # This module allows agents to explicitly activate proxy context access within hooks,
      # providing direct variable access through method_missing while maintaining clear
      # architectural boundaries between RAAF Core and DSL layers.
      #
      # @example Using hook context proxy
      #   class MyAgent < RAAF::DSL::Agent
      #     context do
      #       optional :store_to_database, default: false
      #       optional :campaign_id
      #     end
      #     
      #     on_end do |context, agent, result|
      #       agent.with_context_variables do
      #         next unless store_to_database && campaign_id
      #         
      #         # Direct variable access works here
      #         logger.info "Storing for campaign: #{campaign_id}"
      #       end
      #     end
      #   end
      #
      module HookContext
        
        # Execute a block with proxy context access
        #
        # This method creates a temporary proxy object that includes ContextAccess,
        # allowing direct access to context variables within the block scope.
        # The proxy provides method_missing access to DSL context variables.
        #
        # @param block [Proc] The block to execute with proxy context
        # @return [Object] The result of the block execution
        # @yield Block executed with proxy context access
        #
        # @example Basic usage
        #   agent.with_context_variables do
        #     next unless store_to_database
        #     logger.info "Value: #{some_variable}"
        #   end
        #
        # @example Accessing agent methods
        #   agent.with_context_variables do
        #     current_agent.some_agent_method
        #     agent_send(:private_method, args)
        #   end
        #
        def with_context_variables(&block)
          # Only works if we have DSL context
          return yield if block.arity > 0  # Block expects parameters
          return yield unless defined?(@context) && @context
          
          # Create proxy with ContextAccess for direct variable access
          proxy = HookContextProxy.new(self, @context)
          proxy.instance_eval(&block)
        end
        
        ##
        # Proxy class that provides method_missing access to context variables
        #
        # This class wraps the agent and its context, providing seamless access to
        # context variables through the ContextAccess module. It also provides
        # helper methods to access the original agent and common utilities.
        #
        class HookContextProxy
          include RAAF::DSL::ContextAccess
          
          # @return [Object] The original agent instance
          attr_reader :agent
          
          # @return [ContextVariables] The context variables
          attr_reader :context
          
          # Initialize the proxy with agent and context
          #
          # @param agent [RAAF::DSL::Agent] The DSL agent instance
          # @param context [ContextVariables, Hash] The context variables
          def initialize(agent, context)
            @agent = agent
            @context = ensure_context_variables(context)
          end
          
          # Provide access to the original agent
          #
          # @return [Object] The agent instance
          # @example
          #   current_agent.some_method
          def current_agent
            @agent
          end
          
          # Provide access to RAAF logger
          #
          # @return [Logger] RAAF logger instance
          # @example
          #   logger.info "Hook executed successfully"
          def logger
            RAAF.logger
          end
          
          # Allow safe access to agent instance variables
          #
          # This provides a controlled way to access agent instance variables
          # without exposing the full agent internals.
          #
          # @param name [Symbol, String] The instance variable name (with or without @)
          # @return [Object] The instance variable value
          # @example
          #   agent_instance_variable_get(:@some_var)
          #   agent_instance_variable_get("some_var")
          def agent_instance_variable_get(name)
            var_name = name.to_s.start_with?('@') ? name.to_s : "@#{name}"
            @agent.instance_variable_get(var_name)
          end
          
          # Allow controlled access to agent methods
          #
          # This provides a way to call agent methods from within the hook context,
          # including private methods when necessary.
          #
          # @param method [Symbol, String] The method name
          # @param args [Array] Method arguments
          # @param block [Proc] Block to pass to the method
          # @return [Object] The method result
          # @example
          #   agent_send(:private_helper_method, arg1, arg2)
          def agent_send(method, *args, &block)
            @agent.send(method, *args, &block)
          end
          
          # Provide helpful inspect output for debugging
          #
          # @return [String] Inspection string
          def inspect
            "#<#{self.class.name}:#{object_id} agent=#{@agent.class.name} context_keys=#{@context.keys.sort}>"
          end
          
          # Provide helpful to_s output
          #
          # @return [String] String representation
          def to_s
            "HookContextProxy(#{@agent.class.name})"
          end
        end
      end
    end
  end
end