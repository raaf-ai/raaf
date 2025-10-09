# frozen_string_literal: true

# AgentHooks provides agent-specific hook configuration
#
# This module provides DSL methods for configuring callbacks that are
# specific to individual agent instances. The hooks are configuration-only
# and are passed to the RAAF SDK for execution. Multiple handlers
# can be registered for each event type and they are executed in registration order.
#
# @example Basic usage
#   class MyAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::AgentDsl
#     include RAAF::DSL::Hooks::AgentHooks
#
#     on_start do |agent|
#       puts "#{agent.name} is starting"
#     end
#
#     on_start :log_start
#
#     on_end :cleanup_resources
#     on_end { |agent, result| log_completion(result) }
#   end
#
module RAAF
  module DSL
    module Hooks
      module AgentHooks
        extend ActiveSupport::Concern

        # Event types supported by the agent hooks system
        HOOK_TYPES = %i[
          on_start
          on_end
          on_handoff
          on_tool_start
          on_tool_end
          on_error
          on_context_built
          on_validation_failed
          on_result_ready
          on_prompt_generated
          on_tokens_counted
          on_circuit_breaker_open
          on_circuit_breaker_closed
          on_retry_attempt
          on_execution_slow
          on_pipeline_stage_complete
        ].freeze

        included do
          # Class-level hook storage
          class_attribute :_agent_hooks, default: {}

          # Initialize hooks for each hook type
          HOOK_TYPES.each do |hook_type|
            _agent_hooks[hook_type] = []
          end
        end

        class_methods do
          # Register an agent-specific callback for when this agent starts
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [agent] Block called when agent starts
          # @yieldparam agent [RAAF::Agent] The agent that is starting
          #
          def on_start(method_name = nil, &block)
            register_agent_hook(:on_start, method_name, &block)
          end

          # Register an agent-specific callback for when this agent completes
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [agent, result] Block called when agent completes
          # @yieldparam agent [RAAF::Agent] The agent that completed
          # @yieldparam result [Hash] The agent execution result
          #
          def on_end(method_name = nil, &block)
            register_agent_hook(:on_end, method_name, &block)
          end

          # Register an agent-specific callback for when this agent receives handoff
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [from_agent, to_agent] Block called during handoff
          # @yieldparam from_agent [RAAF::Agent] The agent transferring control
          # @yieldparam to_agent [RAAF::Agent] The agent receiving control (this agent)
          #
          def on_handoff(method_name = nil, &block)
            register_agent_hook(:on_handoff, method_name, &block)
          end

          # Register an agent-specific callback for before this agent uses a tool
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [agent, tool_name, params] Block called before tool execution
          # @yieldparam agent [RAAF::Agent] The agent executing the tool
          # @yieldparam tool_name [String] The name of the tool being executed
          # @yieldparam params [Hash] The parameters being passed to the tool
          #
          def on_tool_start(method_name = nil, &block)
            register_agent_hook(:on_tool_start, method_name, &block)
          end

          # Register an agent-specific callback for after this agent uses a tool
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [agent, tool_name, params, result] Block called after tool execution
          # @yieldparam agent [RAAF::Agent] The agent that executed the tool
          # @yieldparam tool_name [String] The name of the tool that was executed
          # @yieldparam params [Hash] The parameters that were passed to the tool
          # @yieldparam result [Object] The result returned by the tool
          #
          def on_tool_end(method_name = nil, &block)
            register_agent_hook(:on_tool_end, method_name, &block)
          end

          # Register an agent-specific callback for when an error occurs in this agent
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [agent, error] Block called when error occurs
          # @yieldparam agent [RAAF::Agent] The agent where the error occurred
          # @yieldparam error [Exception] The error that occurred
          #
          def on_error(method_name = nil, &block)
            register_agent_hook(:on_error, method_name, &block)
          end

          # DSL-LEVEL HOOKS (Tier 1: Essential)

          # Register an agent-specific callback for after context assembly
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called after context is built
          # @yieldparam data [Hash] Context data with :context key
          #
          def on_context_built(method_name = nil, &block)
            register_agent_hook(:on_context_built, method_name, &block)
          end

          # Register an agent-specific callback for when schema validation fails
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called when validation fails
          # @yieldparam data [Hash] Validation error data
          #
          def on_validation_failed(method_name = nil, &block)
            register_agent_hook(:on_validation_failed, method_name, &block)
          end

          # Register an agent-specific callback for after all result transformations complete
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called after transformations complete
          # @yieldparam data [Hash] Result data with :result and :timestamp keys
          #
          def on_result_ready(method_name = nil, &block)
            register_agent_hook(:on_result_ready, method_name, &block)
          end

          # DSL-LEVEL HOOKS (Tier 2: High-Value Development)

          # Register an agent-specific callback for after prompt generation
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called after prompts are generated
          # @yieldparam data [Hash] Prompt data with :system_prompt, :user_prompt, :context keys
          #
          def on_prompt_generated(method_name = nil, &block)
            register_agent_hook(:on_prompt_generated, method_name, &block)
          end

          # Register an agent-specific callback for after token counting
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called after token counting
          # @yieldparam data [Hash] Token usage data with costs
          #
          def on_tokens_counted(method_name = nil, &block)
            register_agent_hook(:on_tokens_counted, method_name, &block)
          end

          # Register an agent-specific callback for when circuit breaker opens
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called when circuit breaker opens
          # @yieldparam data [Hash] Circuit breaker state data
          #
          def on_circuit_breaker_open(method_name = nil, &block)
            register_agent_hook(:on_circuit_breaker_open, method_name, &block)
          end

          # Register an agent-specific callback for when circuit breaker closes
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called when circuit breaker closes
          # @yieldparam data [Hash] Circuit breaker state data
          #
          def on_circuit_breaker_closed(method_name = nil, &block)
            register_agent_hook(:on_circuit_breaker_closed, method_name, &block)
          end

          # DSL-LEVEL HOOKS (Tier 3: Specialized Operations)

          # Register an agent-specific callback for before each retry attempt
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called before retry
          # @yieldparam data [Hash] Retry context data
          #
          def on_retry_attempt(method_name = nil, &block)
            register_agent_hook(:on_retry_attempt, method_name, &block)
          end

          # Register an agent-specific callback for when execution exceeds threshold
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called when execution is slow
          # @yieldparam data [Hash] Execution timing data
          #
          def on_execution_slow(method_name = nil, &block)
            register_agent_hook(:on_execution_slow, method_name, &block)
          end

          # Register an agent-specific callback for after pipeline stages complete
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called after pipeline stage
          # @yieldparam data [Hash] Pipeline stage data
          #
          def on_pipeline_stage_complete(method_name = nil, &block)
            register_agent_hook(:on_pipeline_stage_complete, method_name, &block)
          end

          # Get hook configuration for RAAF SDK
          #
          # This method returns the configured hooks in a format that can be
          # consumed by the RAAF framework for execution.
          #
          # @return [Hash] Hook configuration for RAAF SDK
          #
          def agent_hooks_config
            config = {}
            HOOK_TYPES.each do |hook_type|
              config[hook_type] = _agent_hooks[hook_type].dup if _agent_hooks[hook_type]&.any?
            end
            config
          end

          # Get all registered hooks for a given type (primarily for testing)
          #
          # @param hook_type [Symbol] The type of hook to get
          # @return [Array] Array of registered hooks
          #
          def get_agent_hooks(hook_type)
            _agent_hooks[hook_type] || []
          end

          # Clear all registered hooks (primarily for testing)
          #
          def clear_agent_hooks!
            HOOK_TYPES.each do |hook_type|
              _agent_hooks[hook_type] = []
            end
          end

          private

          # Register a hook for this agent class
          #
          # @param hook_type [Symbol] The type of hook to register
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          #
          def register_agent_hook(hook_type, method_name = nil, &block)
            unless HOOK_TYPES.include?(hook_type)
              raise ArgumentError, "Invalid hook type: #{hook_type}. Must be one of: #{HOOK_TYPES.join(', ')}"
            end

            raise ArgumentError, "Either method_name or block must be provided" if method_name.nil? && block.nil?

            raise ArgumentError, "Cannot provide both method_name and block" if method_name && block

            hook = method_name || block

            _agent_hooks[hook_type] ||= []
            _agent_hooks[hook_type] << hook
          end
        end

        # Instance methods for hook configuration

        # Get the combined hook configuration for this agent instance
        #
        # This combines both global hooks and agent-specific hooks into a single
        # configuration that can be passed to the RAAF SDK.
        #
        # @return [Hash] Combined hook configuration for RAAF SDK
        #
        def combined_hooks_config
          global_config = RAAF::DSL::Hooks::RunHooks.hooks_config
          agent_config = self.class.agent_hooks_config

          # Merge global and agent-specific hooks
          combined = {}
          (global_config.keys + agent_config.keys).uniq.each do |hook_type|
            combined[hook_type] = []
            combined[hook_type].concat(global_config[hook_type]) if global_config[hook_type]
            combined[hook_type].concat(agent_config[hook_type]) if agent_config[hook_type]
          end

          combined.empty? ? nil : combined
        end
      end
    end
  end
end
