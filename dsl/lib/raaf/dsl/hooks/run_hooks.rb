# frozen_string_literal: true

# RunHooks provides global hook configuration for AI agents
#
# This module provides a configuration-only interface for defining global
# hooks that will be passed to the RAAF SDK for execution.
# The DSL collects hook definitions but does not execute them - all
# execution is delegated to the RAAF framework.
#
# @example Basic usage
#   RAAF::DSL::Hooks::RunHooks.on_agent_start do |agent|
#     puts "Agent #{agent.name} is starting"
#   end
#
#   RAAF::DSL::Hooks::RunHooks.on_agent_start :log_agent_start
#
# @example Multiple handlers in order
#   RAAF::DSL::Hooks::RunHooks.on_agent_start :first_handler
#   RAAF::DSL::Hooks::RunHooks.on_agent_start :second_handler
#   RAAF::DSL::Hooks::RunHooks.on_agent_start { |agent| puts "Third handler" }
#
module RAAF
  module DSL
    module Hooks
      module RunHooks
        # Event types supported by the global hooks system
        HOOK_TYPES = %i[
          on_agent_start
          on_agent_end
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

        # Thread-safe storage for global hooks
        @hooks = {}
        @mutex = Mutex.new

        class << self
          # Register a global callback for when any agent starts
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [agent] Block called when agent starts
          # @yieldparam agent [RAAF::Agent] The agent that is starting
          #
          def on_agent_start(method_name = nil, &block)
            register_hook(:on_agent_start, method_name, &block)
          end

          # Register a global callback for when any agent completes
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [agent, result] Block called when agent completes
          # @yieldparam agent [RAAF::Agent] The agent that completed
          # @yieldparam result [Hash] The agent execution result
          #
          def on_agent_end(method_name = nil, &block)
            register_hook(:on_agent_end, method_name, &block)
          end

          # Register a global callback for when control transfers between agents
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [from_agent, to_agent] Block called during handoff
          # @yieldparam from_agent [RAAF::Agent] The agent transferring control
          # @yieldparam to_agent [RAAF::Agent] The agent receiving control
          #
          def on_handoff(method_name = nil, &block)
            register_hook(:on_handoff, method_name, &block)
          end

          # Register a global callback for before any tool execution
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [agent, tool_name, params] Block called before tool execution
          # @yieldparam agent [RAAF::Agent] The agent executing the tool
          # @yieldparam tool_name [String] The name of the tool being executed
          # @yieldparam params [Hash] The parameters being passed to the tool
          #
          def on_tool_start(method_name = nil, &block)
            register_hook(:on_tool_start, method_name, &block)
          end

          # Register a global callback for after any tool execution
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
            register_hook(:on_tool_end, method_name, &block)
          end

          # Register a global callback for when errors occur
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [agent, error] Block called when error occurs
          # @yieldparam agent [RAAF::Agent] The agent where the error occurred
          # @yieldparam error [Exception] The error that occurred
          #
          def on_error(method_name = nil, &block)
            register_hook(:on_error, method_name, &block)
          end

          # DSL-LEVEL HOOKS (Tier 1: Essential)

          # Register a callback for after context assembly
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called after context is built
          # @yieldparam data [Hash] Context data with :context key
          #
          def on_context_built(method_name = nil, &block)
            register_hook(:on_context_built, method_name, &block)
          end

          # Register a callback for when schema validation fails
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called when validation fails
          # @yieldparam data [Hash] Validation error data
          #
          def on_validation_failed(method_name = nil, &block)
            register_hook(:on_validation_failed, method_name, &block)
          end

          # Register a callback for after all result transformations complete
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called after transformations complete
          # @yieldparam data [Hash] Result data with :result and :timestamp keys
          #
          def on_result_ready(method_name = nil, &block)
            register_hook(:on_result_ready, method_name, &block)
          end

          # DSL-LEVEL HOOKS (Tier 2: High-Value Development)

          # Register a callback for after prompt generation
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called after prompts are generated
          # @yieldparam data [Hash] Prompt data with :system_prompt, :user_prompt, :context keys
          #
          def on_prompt_generated(method_name = nil, &block)
            register_hook(:on_prompt_generated, method_name, &block)
          end

          # Register a callback for after token counting
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called after token counting
          # @yieldparam data [Hash] Token usage data with costs
          #
          def on_tokens_counted(method_name = nil, &block)
            register_hook(:on_tokens_counted, method_name, &block)
          end

          # Register a callback for when circuit breaker opens
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called when circuit breaker opens
          # @yieldparam data [Hash] Circuit breaker state data
          #
          def on_circuit_breaker_open(method_name = nil, &block)
            register_hook(:on_circuit_breaker_open, method_name, &block)
          end

          # Register a callback for when circuit breaker closes
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called when circuit breaker closes
          # @yieldparam data [Hash] Circuit breaker state data
          #
          def on_circuit_breaker_closed(method_name = nil, &block)
            register_hook(:on_circuit_breaker_closed, method_name, &block)
          end

          # DSL-LEVEL HOOKS (Tier 3: Specialized Operations)

          # Register a callback for before each retry attempt
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called before retry
          # @yieldparam data [Hash] Retry context data
          #
          def on_retry_attempt(method_name = nil, &block)
            register_hook(:on_retry_attempt, method_name, &block)
          end

          # Register a callback for when execution exceeds threshold
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called when execution is slow
          # @yieldparam data [Hash] Execution timing data
          #
          def on_execution_slow(method_name = nil, &block)
            register_hook(:on_execution_slow, method_name, &block)
          end

          # Register a callback for after pipeline stages complete
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [data] Block called after pipeline stage
          # @yieldparam data [Hash] Pipeline stage data
          #
          def on_pipeline_stage_complete(method_name = nil, &block)
            register_hook(:on_pipeline_stage_complete, method_name, &block)
          end

          # Get hook configuration for RAAF SDK
          #
          # This method returns the configured hooks in a format that can be
          # consumed by the RAAF framework for execution.
          #
          # @return [Hash] Hook configuration for RAAF SDK
          #
          def hooks_config
            config = {}
            @mutex.synchronize do
              HOOK_TYPES.each do |hook_type|
                config[hook_type] = @hooks[hook_type].dup if @hooks[hook_type]&.any?
              end
            end
            config
          end

          # Clear all registered hooks (primarily for testing)
          #
          def clear_hooks!
            @mutex.synchronize do
              @hooks.clear
            end
          end

          # Get all registered hooks for a given type (primarily for testing)
          #
          # @param hook_type [Symbol] The type of hook to get
          # @return [Array] Array of registered hooks
          #
          def get_hooks(hook_type)
            @mutex.synchronize do
              @hooks[hook_type] ||= []
              @hooks[hook_type].dup
            end
          end

          private

          # Register a hook with thread safety
          #
          # @param hook_type [Symbol] The type of hook to register
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          #
          def register_hook(hook_type, method_name = nil, &block)
            unless HOOK_TYPES.include?(hook_type)
              raise ArgumentError, "Invalid hook type: #{hook_type}. Must be one of: #{HOOK_TYPES.join(', ')}"
            end

            raise ArgumentError, "Either method_name or block must be provided" if method_name.nil? && block.nil?

            raise ArgumentError, "Cannot provide both method_name and block" if method_name && block

            hook = method_name || block

            @mutex.synchronize do
              @hooks[hook_type] ||= []
              @hooks[hook_type] << hook
            end
          end
        end
      end
    end
  end
end
