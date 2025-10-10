# frozen_string_literal: true

require_relative "../../../../../core/lib/raaf/lifecycle"

##
# HooksAdapter - Bridges DSL hooks configuration to Core hooks execution
#
# This adapter transforms DSL-configured hooks into Core-compatible hook objects
# that can be executed by the RAAF Core execution engine. It maintains the 
# separation between configuration (DSL) and execution (Core) while providing
# a seamless bridge between the two systems.
#
# @example Usage with DSL Agent
#   class MyAgent < RAAF::DSL::Agent
#     on_end do |context, agent, result|
#       puts "Agent completed: #{result[:success]}"
#     end
#   end
#
#   # DSL Agent creates hooks adapter automatically:
#   hooks_config = agent_class.combined_hooks_config
#   adapter = RAAF::DSL::Hooks::HooksAdapter.new(hooks_config)
#   core_agent = RAAF::Agent.new(name: "Test", hooks: adapter)
#
module RAAF
  module DSL
    module Hooks
      ##
      # Core hooks adapter that wraps DSL hook configurations
      # 
      # Inherits from RAAF::AgentHooks to integrate with the Core lifecycle system.
      # Transforms DSL method references and blocks into executable hooks.
      class HooksAdapter < RAAF::AgentHooks
        
        def initialize(dsl_hooks_config, dsl_agent = nil)
          @dsl_hooks = dsl_hooks_config || {}
          @dsl_agent = dsl_agent  # Store DSL agent reference for proxy context access
        end

        # Called before this agent is invoked
        # @param context [RunContext] The current run context
        # @param agent [Agent] This agent
        def on_start(context, agent)
          # Use DSL agent if available, otherwise fall back to Core agent
          agent_for_hook = @dsl_agent || agent
          comprehensive_data = build_comprehensive_data(context, agent_for_hook)
          execute_hooks(@dsl_hooks[:on_start], comprehensive_data)
        end

        # Called when this agent produces a final output
        # @param context [RunContext] The current run context
        # @param agent [Agent] This agent
        # @param output [Object] The final output produced
        # @return [Object, nil] Modified output from hook, or nil if hook doesn't return anything
        def on_end(context, agent, output)
          # Use DSL agent if available, otherwise fall back to Core agent
          agent_for_hook = @dsl_agent || agent
          comprehensive_data = build_comprehensive_data(context, agent_for_hook, output: output)
          execute_hooks(@dsl_hooks[:on_end], comprehensive_data)
        end

        # Called when this agent is being handed off to
        # @param context [RunContext] The current run context
        # @param agent [Agent] This agent
        # @param source [Agent] The agent handing off to this agent
        def on_handoff(context, agent, source)
          # Use DSL agent if available, otherwise fall back to Core agent
          agent_for_hook = @dsl_agent || agent
          comprehensive_data = build_comprehensive_data(context, agent_for_hook, source: source)
          execute_hooks(@dsl_hooks[:on_handoff], comprehensive_data)
        end

        # Called before this agent invokes a tool
        # @param context [RunContext] The current run context
        # @param agent [Agent] This agent
        # @param tool [FunctionTool] The tool about to be invoked
        # @param arguments [Hash] The arguments to be passed to the tool
        def on_tool_start(context, agent, tool, arguments = {})
          # Use DSL agent if available, otherwise fall back to Core agent
          agent_for_hook = @dsl_agent || agent
          comprehensive_data = build_comprehensive_data(context, agent_for_hook, tool: tool, arguments: arguments)
          execute_hooks(@dsl_hooks[:on_tool_start], comprehensive_data)
        end

        # Called after this agent invokes a tool
        # @param context [RunContext] The current run context
        # @param agent [Agent] This agent
        # @param tool [FunctionTool] The tool that was invoked
        # @param result [Object] The result returned by the tool
        def on_tool_end(context, agent, tool, result)
          # Use DSL agent if available, otherwise fall back to Core agent
          agent_for_hook = @dsl_agent || agent
          comprehensive_data = build_comprehensive_data(context, agent_for_hook, tool: tool, result: result)
          execute_hooks(@dsl_hooks[:on_tool_end], comprehensive_data)
        end

        # Called when an error occurs in this agent
        # @param context [RunContext] The current run context
        # @param agent [Agent] This agent
        # @param error [Exception] The error that occurred
        def on_error(context, agent, error)
          # Use DSL agent if available, otherwise fall back to Core agent
          agent_for_hook = @dsl_agent || agent
          comprehensive_data = build_comprehensive_data(context, agent_for_hook, error: error)
          execute_hooks(@dsl_hooks[:on_error], comprehensive_data)
        end

        private

        # Build comprehensive data hash with standard parameters and hook-specific data
        #
        # @param context [RunContext] The current run context
        # @param agent [Agent] The agent instance
        # @param hook_specific_data [Hash] Additional hook-specific data
        # @return [ActiveSupport::HashWithIndifferentAccess] Comprehensive data hash
        def build_comprehensive_data(context, agent, **hook_specific_data)
          # Build comprehensive data with standard parameters
          comprehensive_data = {
            context: context,
            agent: agent,
            timestamp: Time.now,
            **hook_specific_data
          }

          # Ensure HashWithIndifferentAccess for flexible key access
          ActiveSupport::HashWithIndifferentAccess.new(comprehensive_data)
        end

        # Execute all hooks for a given hook type and return the last hook's result
        #
        # @param hooks [Array] Array of hooks to execute (methods or blocks)
        # @param data [Hash] Comprehensive data hash to pass to hooks
        # @return [Object, nil] The return value from the last hook, or nil if no hooks or all failed
        def execute_hooks(hooks, data)
          return nil unless hooks&.any?

          last_result = nil

          hooks.each do |hook|
            begin
              case hook
              when Symbol
                # Method reference - call method on the current agent instance
                # Note: We need access to the DSL agent instance to call the method
                # This would need to be passed during adapter creation
                RAAF.logger.warn "Method hooks not yet implemented in adapter: #{hook}"

              when Proc
                # Block - call directly with comprehensive data hash
                last_result = hook.call(data)

              else
                RAAF.logger.warn "Unknown hook type: #{hook.class}"
              end

            rescue => e
              RAAF.logger.error "❌ Hook execution failed: #{e.message}"
              RAAF.logger.error "🔍 Hook: #{hook.inspect}"
              RAAF.logger.error "📄 Data: #{data.except(:context, :agent).inspect}"
              # Continue with other hooks even if one fails
            end
          end

          last_result
        end
      end
    end
  end
end