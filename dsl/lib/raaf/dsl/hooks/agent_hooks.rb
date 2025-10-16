# frozen_string_literal: true

# AgentHooks provides agent-specific hook configuration
#
# This module provides DSL methods for configuring callbacks that are
# specific to individual agent instances. The hooks are configuration-only
# and are passed to the RAAF SDK for execution. Multiple handlers
# can be registered for each event type and they are executed in registration order.
#
# All hooks receive parameters as Ruby keyword arguments, making for clean and idiomatic code.
# Standard parameters (context, agent, timestamp) are automatically injected into all hooks.
#
# @example Basic usage with keyword arguments
#   class MyAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::AgentDsl
#     include RAAF::DSL::Hooks::AgentHooks
#
#     # Use Ruby keyword argument syntax
#     on_start do |agent:, **|
#       puts "#{agent.name} is starting"
#     end
#
#     # Specify only the parameters you need, ** ignores the rest
#     on_end do |output:, agent:, **|
#       log_completion(output)
#     end
#
#     # Standard parameters are always available as keyword arguments
#     on_result_ready do |context:, agent:, timestamp:, result:, **|
#       # Direct access via keyword arguments
#       Rails.logger.info "Agent #{agent.name} completed at #{timestamp}"
#       ResultCache.store(result, context)
#     end
#
#     # Use ** to capture all keyword arguments as a hash
#     on_tokens_counted do |**data|
#       TokenTracker.record(data)  # data is a hash with all parameters
#     end
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
          before_execute
          after_execute
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
          # Fires after the DSL agent's context has been fully assembled from initialization
          # parameters. Receives the complete ContextVariables object for inspection.
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [context:, agent:, timestamp:, **] Block called after context is built with keyword arguments
          # @yieldparam context [RAAF::DSL::ContextVariables] The assembled context (hook-specific)
          # @yieldparam agent [RAAF::Agent] The agent instance (auto-injected)
          # @yieldparam timestamp [Time] Hook execution time (auto-injected)
          #
          # @example Access context after assembly with keyword arguments
          #   on_context_built do |context:, agent:, **|
          #     product_name = context[:product_name]
          #     Rails.logger.info "#{agent.name} context built with product: #{product_name}"
          #   end
          #
          # @example Selective parameter extraction
          #   on_context_built do |context:, **|
          #     # Only extract context, ignore agent and timestamp
          #     Rails.logger.debug "Context: #{context.inspect}"
          #   end
          #
          def on_context_built(method_name = nil, &block)
            register_agent_hook(:on_context_built, method_name, &block)
          end

          # Register an agent-specific callback for when schema validation fails
          #
          # Fires when schema validation or context validation detects issues. Useful for
          # logging validation errors, implementing custom retry logic, or triggering alerts.
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [error:, error_type:, field:, value:, expected_type:, context:, agent:, timestamp:, **] Block called when validation fails with keyword arguments
          # @yieldparam error [String] The validation error message (hook-specific)
          # @yieldparam error_type [String] Type of validation error (hook-specific)
          # @yieldparam field [Symbol, nil] The field that failed validation (hook-specific, optional)
          # @yieldparam value [Object, nil] The invalid value (hook-specific, optional)
          # @yieldparam expected_type [Symbol, nil] The expected type (hook-specific, optional)
          # @yieldparam context [RAAF::DSL::ContextVariables] The agent context (auto-injected)
          # @yieldparam agent [RAAF::Agent] The agent instance (auto-injected)
          # @yieldparam timestamp [Time] Hook execution time (auto-injected)
          #
          # @example Log validation errors with keyword arguments
          #   on_validation_failed do |error:, error_type:, field: nil, **|
          #     Rails.logger.error "Validation (#{error_type}) failed for #{field}: #{error}"
          #   end
          #
          def on_validation_failed(method_name = nil, &block)
            register_agent_hook(:on_validation_failed, method_name, &block)
          end

          # Register an agent-specific callback for after all result transformations complete
          #
          # Fires after DSL agent's result_transform block has processed the AI response.
          # Receives both raw and processed results for comparison or additional processing.
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [raw_result:, processed_result:, context:, agent:, timestamp:, **] Block called after transformations complete with keyword arguments
          # @yieldparam raw_result [Hash] The original AI response (hook-specific)
          # @yieldparam processed_result [Hash] The transformed result (hook-specific)
          # @yieldparam context [RAAF::DSL::ContextVariables] The agent context (auto-injected)
          # @yieldparam agent [RAAF::Agent] The agent instance (auto-injected)
          # @yieldparam timestamp [Time] Hook execution time (auto-injected)
          #
          # @example Store processed results with keyword arguments
          #   on_result_ready do |processed_result:, timestamp:, **|
          #     ResultCache.store(processed_result, timestamp)
          #   end
          #
          # @example Compare raw and processed results
          #   on_result_ready do |raw_result:, processed_result:, **|
          #     Rails.logger.debug "Raw: #{raw_result.keys}, Processed: #{processed_result.keys}"
          #   end
          #
          def on_result_ready(method_name = nil, &block)
            register_agent_hook(:on_result_ready, method_name, &block)
          end

          # DSL-LEVEL HOOKS (Tier 2: High-Value Development)

          # Register an agent-specific callback for after prompt generation
          #
          # Fires after system and user prompts have been generated from prompt classes
          # or inline instructions. Useful for logging, debugging, or modifying prompts
          # before they are sent to the LLM.
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [system_prompt:, user_prompt:, context:, agent:, timestamp:, **] Block called after prompts are generated with keyword arguments
          # @yieldparam system_prompt [String] The generated system prompt (hook-specific)
          # @yieldparam user_prompt [String] The generated user prompt (hook-specific)
          # @yieldparam context [RAAF::DSL::ContextVariables] The agent context (auto-injected)
          # @yieldparam agent [RAAF::Agent] The agent instance (auto-injected)
          # @yieldparam timestamp [Time] Hook execution time (auto-injected)
          #
          # @example Log generated prompts with keyword arguments
          #   on_prompt_generated do |system_prompt:, user_prompt:, **|
          #     Rails.logger.debug "System: #{system_prompt}\nUser: #{user_prompt}"
          #   end
          #
          # @example Log only user prompt
          #   on_prompt_generated do |user_prompt:, **|
          #     Rails.logger.debug "User query: #{user_prompt}"
          #   end
          #
          def on_prompt_generated(method_name = nil, &block)
            register_agent_hook(:on_prompt_generated, method_name, &block)
          end

          # Register an agent-specific callback for after token counting
          #
          # Fires after token usage has been calculated for an AI request. Provides
          # detailed token counts and estimated costs for monitoring and budgeting.
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          # @yield [input_tokens:, output_tokens:, total_tokens:, estimated_cost:, model:, context:, agent:, timestamp:, **] Block called after token counting with keyword arguments
          # @yieldparam input_tokens [Integer] Number of input tokens used (hook-specific)
          # @yieldparam output_tokens [Integer] Number of output tokens generated (hook-specific)
          # @yieldparam total_tokens [Integer] Total tokens used (hook-specific)
          # @yieldparam estimated_cost [Float] Estimated cost in USD (hook-specific)
          # @yieldparam model [String] Model name used (hook-specific)
          # @yieldparam context [RAAF::DSL::ContextVariables] The agent context (auto-injected)
          # @yieldparam agent [RAAF::Agent] The agent instance (auto-injected)
          # @yieldparam timestamp [Time] Hook execution time (auto-injected)
          #
          # @example Track token usage and costs with keyword arguments
          #   on_tokens_counted do |input_tokens:, output_tokens:, estimated_cost:, **|
          #     TokenUsageTracker.record(input_tokens, output_tokens, estimated_cost)
          #   end
          #
          # @example Selective parameter extraction
          #   on_tokens_counted do |total_tokens:, model:, **|
          #     Rails.logger.info "#{model} used #{total_tokens} tokens"
          #   end
          #
          # @example Capture all parameters as hash
          #   on_tokens_counted do |**data|
          #     TokenTracker.record(data)  # data contains all parameters
          #   end
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

          # WRAPPER-LEVEL HOOKS (Pipeline DSL)

          # Register an agent-specific callback for before wrapper execution
          #
          # This hook fires BEFORE a pipeline wrapper executes, providing a single
          # interception point that runs once per wrapper execution (before all chunks
          # for batched agents, before parallel execution, etc.).
          #
          # **When This Hook Fires:**
          # - BatchedAgent: Once BEFORE splitting into chunks (not per chunk)
          # - ChainedAgent: Before executing the agent chain
          # - ParallelAgents: Before executing parallel agents
          # - RemappedAgent: Before field remapping
          # - ConfiguredAgent: Before applying configuration
          # - IteratingAgent: Before iteration begins
          #
          # **Hook Parameters:**
          # @yieldparam context [RAAF::DSL::ContextVariables] Pipeline context (mutable - can be modified)
          # @yieldparam wrapper_type [Symbol] Type of wrapper (:batched, :chained, :parallel, :remapped, :configured, :iterating)
          # @yieldparam wrapper_config [Hash] Wrapper-specific configuration data
          # @yieldparam timestamp [Time] Hook execution timestamp
          #
          # **Common Use Cases:**
          # - Input validation and filtering before processing
          # - Deduplication (remove already-processed items)
          # - Logging wrapper execution start
          # - Context enrichment before execution
          # - Cache lookups to skip unnecessary work
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          #
          # @example Deduplication before batch processing
          #   class QuickFitAnalyzer < RAAF::DSL::Agent
          #     before_execute do |context:, wrapper_type:, **|
          #       # Only process companies that haven't been analyzed yet
          #       if wrapper_type == :batched && context[:company_list]
          #         context[:company_list] = context[:company_list].reject do |company|
          #           already_analyzed?(company[:coc_number])
          #         end
          #       end
          #     end
          #   end
          #
          # @example Wrapper-aware logging
          #   before_execute do |context:, wrapper_type:, wrapper_config:, **|
          #     case wrapper_type
          #     when :batched
          #       RAAF.logger.info "Processing #{context[:items].count} items in chunks of #{wrapper_config[:chunk_size]}"
          #     when :parallel
          #       RAAF.logger.info "Executing #{wrapper_config[:agent_count]} agents in parallel"
          #     end
          #   end
          #
          # @example Context validation and enrichment
          #   before_execute do |context:, **|
          #     # Validate required context
          #     raise "Missing product" unless context[:product]
          #
          #     # Enrich context before execution
          #     context[:analysis_timestamp] = Time.current
          #     context[:execution_id] = SecureRandom.uuid
          #   end
          #
          def before_execute(method_name = nil, &block)
            register_agent_hook(:before_execute, method_name, &block)
          end

          # Register an agent-specific callback for after wrapper execution
          #
          # This hook fires AFTER a pipeline wrapper completes execution, providing
          # a single interception point that runs once per wrapper execution (after
          # all chunks complete for batched agents, after parallel execution, etc.).
          #
          # **When This Hook Fires:**
          # - BatchedAgent: Once AFTER all chunks have been processed
          # - ChainedAgent: After the entire agent chain completes
          # - ParallelAgents: After all parallel agents complete
          # - RemappedAgent: After field remapping completes
          # - ConfiguredAgent: After configured execution completes
          # - IteratingAgent: After all iterations complete
          #
          # **Hook Parameters:**
          # @yieldparam context [RAAF::DSL::ContextVariables] Pipeline context (final state)
          # @yieldparam result [Object] Result from wrapper execution
          # @yieldparam wrapper_type [Symbol] Type of wrapper (:batched, :chained, :parallel, :remapped, :configured, :iterating)
          # @yieldparam wrapper_config [Hash] Wrapper-specific configuration data
          # @yieldparam duration_ms [Float] Execution duration in milliseconds
          # @yieldparam timestamp [Time] Hook execution timestamp
          #
          # **Common Use Cases:**
          # - Result validation and post-processing
          # - Metrics collection (timing, throughput, success rates)
          # - Logging wrapper execution completion
          # - Database persistence of results
          # - Cache updates with execution results
          # - Error recovery and cleanup
          #
          # @param method_name [Symbol, nil] Method name to call as callback
          # @param block [Proc, nil] Block to execute as callback
          #
          # @example Performance metrics collection
          #   class DataProcessor < RAAF::DSL::Agent
          #     after_execute do |context:, result:, duration_ms:, wrapper_type:, **|
          #       MetricsCollector.record(
          #         agent: "DataProcessor",
          #         wrapper_type: wrapper_type,
          #         items_processed: result[:processed_items]&.count || 0,
          #         duration_ms: duration_ms,
          #         success: result[:success]
          #       )
          #     end
          #   end
          #
          # @example Wrapper-aware logging with results
          #   after_execute do |result:, duration_ms:, wrapper_type:, wrapper_config:, **|
          #     case wrapper_type
          #     when :batched
          #       RAAF.logger.info "Processed #{result[:items].count} items in #{wrapper_config[:chunk_count]} chunks (#{duration_ms}ms)"
          #     when :parallel
          #       RAAF.logger.info "Completed #{wrapper_config[:agent_count]} parallel agents (#{duration_ms}ms)"
          #     end
          #   end
          #
          # @example Result persistence and cleanup
          #   after_execute do |context:, result:, duration_ms:, **|
          #     # Persist results to database
          #     PipelineResult.create!(
          #       context: context.to_h,
          #       result: result,
          #       duration_ms: duration_ms,
          #       executed_at: Time.current
          #     )
          #
          #     # Cleanup temporary resources
          #     context.delete(:temp_data)
          #   end
          #
          def after_execute(method_name = nil, &block)
            register_agent_hook(:after_execute, method_name, &block)
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
