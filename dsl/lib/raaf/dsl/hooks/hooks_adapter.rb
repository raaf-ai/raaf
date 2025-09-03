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
          execute_hooks(@dsl_hooks[:on_start], context, agent_for_hook)
        end

        # Called when this agent produces a final output
        # @param context [RunContext] The current run context
        # @param agent [Agent] This agent
        # @param output [Object] The final output produced
        def on_end(context, agent, output)
          # Use DSL agent if available, otherwise fall back to Core agent
          agent_for_hook = @dsl_agent || agent
          execute_hooks(@dsl_hooks[:on_end], context, agent_for_hook, output)
        end

        # Called when this agent is being handed off to
        # @param context [RunContext] The current run context
        # @param agent [Agent] This agent
        # @param source [Agent] The agent handing off to this agent
        def on_handoff(context, agent, source)
          # Use DSL agent if available, otherwise fall back to Core agent
          agent_for_hook = @dsl_agent || agent
          execute_hooks(@dsl_hooks[:on_handoff], context, agent_for_hook, source)
        end

        # Called before this agent invokes a tool
        # @param context [RunContext] The current run context
        # @param agent [Agent] This agent
        # @param tool [FunctionTool] The tool about to be invoked
        # @param arguments [Hash] The arguments to be passed to the tool
        def on_tool_start(context, agent, tool, arguments = {})
          # Use DSL agent if available, otherwise fall back to Core agent
          agent_for_hook = @dsl_agent || agent
          execute_hooks(@dsl_hooks[:on_tool_start], context, agent_for_hook, tool, arguments)
        end

        # Called after this agent invokes a tool
        # @param context [RunContext] The current run context
        # @param agent [Agent] This agent
        # @param tool [FunctionTool] The tool that was invoked
        # @param result [Object] The result returned by the tool
        def on_tool_end(context, agent, tool, result)
          # Use DSL agent if available, otherwise fall back to Core agent
          agent_for_hook = @dsl_agent || agent
          execute_hooks(@dsl_hooks[:on_tool_end], context, agent_for_hook, tool, result)
        end

        # Called when an error occurs in this agent
        # @param context [RunContext] The current run context
        # @param agent [Agent] This agent
        # @param error [Exception] The error that occurred
        def on_error(context, agent, error)
          # Use DSL agent if available, otherwise fall back to Core agent
          agent_for_hook = @dsl_agent || agent
          execute_hooks(@dsl_hooks[:on_error], context, agent_for_hook, error)
        end

        private

        # Execute all hooks for a given hook type
        # 
        # @param hooks [Array] Array of hooks to execute (methods or blocks)
        # @param args [Array] Arguments to pass to the hooks
        def execute_hooks(hooks, *args)
          return unless hooks&.any?

          hooks.each do |hook|
            begin
              case hook
              when Symbol
                # Method reference - call method on the current agent instance
                # Note: We need access to the DSL agent instance to call the method
                # This would need to be passed during adapter creation
                RAAF.logger.warn "Method hooks not yet implemented in adapter: #{hook}"
                
              when Proc
                # Block - call directly with arguments
                hook.call(*args)
                
              else
                RAAF.logger.warn "Unknown hook type: #{hook.class}"
              end
              
            rescue => e
              RAAF.logger.error "❌ Hook execution failed: #{e.message}"
              RAAF.logger.error "🔍 Hook: #{hook.inspect}"
              RAAF.logger.error "📄 Arguments: #{args.inspect}"
              # Continue with other hooks even if one fails
            end
          end
        end
      end
    end
  end
end