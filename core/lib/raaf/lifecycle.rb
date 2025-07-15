# frozen_string_literal: true

##
# OpenAI Agents Lifecycle Management
#
# This module provides comprehensive lifecycle hooks for monitoring and controlling
# agent execution, tool usage, handoffs, and error handling. The lifecycle system
# enables custom behavior injection at key execution points.
#
# == Hook Types
#
# * **RunHooks**: Global hooks that receive events for all agents
# * **AgentHooks**: Agent-specific hooks that only receive events for one agent  
# * **CompositeRunHooks**: Combines multiple hooks for complex scenarios
# * **AsyncHooks**: Async-compatible versions for async execution environments
#
# == Hook Events
#
# The lifecycle system provides hooks for:
# - Agent start/end events
# - Tool execution start/end
# - Agent handoffs between agents
# - Error handling and recovery
#
# @example Basic run-level hooks
#   class MyRunHooks < RubyAIAgentsFactory::RunHooks
#     def on_agent_start(context, agent)
#       puts "Agent #{agent.name} starting"
#     end
#
#     def on_tool_start(context, agent, tool, arguments)
#       puts "Tool #{tool.name} called with #{arguments}"
#     end
#   end
#
#   runner = RubyAIAgentsFactory::Runner.new(agent: agent)
#   config = RubyAIAgentsFactory::RunConfig.new(hooks: MyRunHooks.new)
#   runner.run(messages, config: config)
#
# @example Agent-specific hooks
#   class CustomerServiceHooks < RubyAIAgentsFactory::AgentHooks
#     def on_start(context, agent)
#       # Log customer service session start
#       context.metadata[:session_start] = Time.now
#     end
#
#     def on_end(context, agent, output)
#       # Calculate session duration
#       duration = Time.now - context.metadata[:session_start]
#       puts "Session completed in #{duration}s"
#     end
#   end
#
#   agent = RubyAIAgentsFactory::Agent.new(
#     name: "CustomerService",
#     hooks: CustomerServiceHooks.new
#   )
#
# @example Multiple hooks with composite
#   logging_hooks = LoggingHooks.new
#   metrics_hooks = MetricsHooks.new
#   audit_hooks = AuditHooks.new
#
#   composite = RubyAIAgentsFactory::CompositeRunHooks.new([logging_hooks, metrics_hooks])
#   composite.add_hook(audit_hooks)
#
#   config = RubyAIAgentsFactory::RunConfig.new(hooks: composite)
#
# @author OpenAI Agents Ruby Team
# @since 0.1.0
# @see RubyAIAgentsFactory::RunContext For context object passed to hooks
# @see RubyAIAgentsFactory::Agent For agent-level hook configuration
module RubyAIAgentsFactory
  ##
  # Base class for run-level lifecycle hooks
  #
  # Run-level hooks receive events for all agents during execution. These hooks
  # are useful for cross-cutting concerns like logging, monitoring, and metrics
  # collection that apply to the entire agent execution.
  #
  # Subclass this class and override the methods you need to implement custom
  # behavior. All methods have default empty implementations.
  #
  # @example Custom logging hooks
  #   class LoggingRunHooks < RubyAIAgentsFactory::RunHooks
  #     def on_agent_start(context, agent)
  #       Rails.logger.info("Agent #{agent.name} started", run_id: context.run_id)
  #     end
  #
  #     def on_tool_start(context, agent, tool, arguments)
  #       Rails.logger.info("Tool #{tool.name} invoked", 
  #                        agent: agent.name, arguments: arguments)
  #     end
  #
  #     def on_error(context, agent, error)
  #       Rails.logger.error("Agent error", 
  #                         agent: agent.name, error: error.message)
  #     end
  #   end
  #
  # @example Performance monitoring hooks
  #   class PerformanceHooks < RubyAIAgentsFactory::RunHooks
  #     def on_agent_start(context, agent)
  #       context.metadata[:start_time] = Time.now
  #     end
  #
  #     def on_agent_end(context, agent, output)
  #       duration = Time.now - context.metadata[:start_time]
  #       StatsD.histogram('agent.execution_time', duration, tags: ["agent:#{agent.name}"])
  #     end
  #   end
  class RunHooks
    ##
    # Called before an agent is invoked. Called each time the current agent changes.
    #
    # This hook is triggered when an agent is about to begin execution, either
    # as the initial agent or after a handoff from another agent.
    #
    # @param context [RunContext] The current run context with metadata and state
    # @param agent [Agent] The agent about to be invoked
    # @return [void]
    #
    # @example Log agent activation
    #   def on_agent_start(context, agent)
    #     puts "Starting agent #{agent.name} (run: #{context.run_id})"
    #   end
    def on_agent_start(context, agent)
      # Override in subclass
    end

    ##
    # Called when an agent produces a final output
    #
    # This hook is triggered when an agent completes its execution and produces
    # a final result. The output may be text, structured data, or a handoff.
    #
    # @param context [RunContext] The current run context
    # @param agent [Agent] The agent that produced the output
    # @param output [Object] The final output produced by the agent
    # @return [void]
    #
    # @example Track agent completion
    #   def on_agent_end(context, agent, output)
    #     context.metadata[:outputs] ||= []
    #     context.metadata[:outputs] << {agent: agent.name, output: output}
    #   end
    def on_agent_end(context, agent, output)
      # Override in subclass
    end

    ##
    # Called when a handoff occurs between agents
    #
    # This hook is triggered during agent-to-agent handoffs, allowing you to
    # track delegation patterns and implement custom handoff logic.
    #
    # @param context [RunContext] The current run context
    # @param from_agent [Agent] The agent performing the handoff
    # @param to_agent [Agent] The agent receiving the handoff
    # @return [void]
    #
    # @example Track handoff chain
    #   def on_handoff(context, from_agent, to_agent)
    #     context.metadata[:handoff_chain] ||= []
    #     context.metadata[:handoff_chain] << "#{from_agent.name} -> #{to_agent.name}"
    #   end
    def on_handoff(context, from_agent, to_agent)
      # Override in subclass
    end

    ##
    # Called before a tool is invoked
    #
    # This hook allows you to monitor tool usage, validate arguments, or implement
    # custom authorization logic before tool execution.
    #
    # @param context [RunContext] The current run context
    # @param agent [Agent] The agent invoking the tool
    # @param tool [FunctionTool] The tool about to be invoked
    # @param arguments [Hash] The arguments to be passed to the tool
    # @return [void]
    #
    # @example Validate tool permissions
    #   def on_tool_start(context, agent, tool, arguments)
    #     unless agent.can_use_tool?(tool.name)
    #       raise "Agent #{agent.name} not authorized for tool #{tool.name}"
    #     end
    #   end
    def on_tool_start(context, agent, tool, arguments = {})
      # Override in subclass
    end

    ##
    # Called after a tool is invoked
    #
    # This hook receives the tool execution result, allowing you to log outcomes,
    # validate results, or implement post-processing logic.
    #
    # @param context [RunContext] The current run context
    # @param agent [Agent] The agent that invoked the tool
    # @param tool [FunctionTool] The tool that was invoked
    # @param result [Object] The result returned by the tool
    # @return [void]
    #
    # @example Log tool results
    #   def on_tool_end(context, agent, tool, result)
    #     context.metadata[:tool_calls] ||= []
    #     context.metadata[:tool_calls] << {
    #       tool: tool.name,
    #       success: !result.is_a?(Exception),
    #       result_size: result.to_s.length
    #     }
    #   end
    def on_tool_end(context, agent, tool, result)
      # Override in subclass
    end

    ##
    # Called when an error occurs during agent execution
    #
    # This hook is triggered when exceptions occur during agent or tool execution,
    # allowing you to implement custom error handling, logging, or recovery logic.
    #
    # @param context [RunContext] The current run context
    # @param agent [Agent] The agent where the error occurred
    # @param error [Exception] The error that occurred
    # @return [void]
    #
    # @example Error recovery
    #   def on_error(context, agent, error)
    #     # Log error
    #     Rails.logger.error("Agent error", agent: agent.name, error: error.message)
    #     
    #     # Implement retry logic
    #     context.metadata[:error_count] ||= 0
    #     context.metadata[:error_count] += 1
    #     
    #     if context.metadata[:error_count] < 3
    #       context.metadata[:should_retry] = true
    #     end
    #   end
    def on_error(context, agent, error)
      # Override in subclass
    end
  end

  ##
  # Base class for agent-specific lifecycle hooks
  #
  # Agent-specific hooks receive events only for the agent they're attached to.
  # These hooks are useful for implementing agent-specific behavior, validation,
  # or monitoring without affecting other agents in the system.
  #
  # Set this on agent.hooks to receive events for that specific agent.
  #
  # @example Agent-specific logging
  #   class CustomerServiceHooks < RubyAIAgentsFactory::AgentHooks
  #     def on_start(context, agent)
  #       puts \"Customer service session started\"
  #       context.metadata[:session_id] = SecureRandom.uuid
  #     end
  #
  #     def on_end(context, agent, output)
  #       puts \"Session completed: #{context.metadata[:session_id]}\"
  #     end
  #   end
  #
  #   agent = RubyAIAgentsFactory::Agent.new(
  #     name: \"CustomerService\",
  #     hooks: CustomerServiceHooks.new
  #   )
  #
  # @example Agent-specific tool validation
  #   class SecureAgentHooks < RubyAIAgentsFactory::AgentHooks
  #     ALLOWED_TOOLS = %w[search_docs send_email].freeze
  #
  #     def on_tool_start(context, agent, tool, arguments)
  #       unless ALLOWED_TOOLS.include?(tool.name)
  #         raise \"Unauthorized tool: #{tool.name}\"
  #       end
  #     end
  #   end
  class AgentHooks
    # Called before this agent is invoked
    # @param context [RunContext] The current run context
    # @param agent [Agent] This agent
    def on_start(context, agent)
      # Override in subclass
    end

    # Called when this agent produces a final output
    # @param context [RunContext] The current run context
    # @param agent [Agent] This agent
    # @param output [Object] The final output produced
    def on_end(context, agent, output)
      # Override in subclass
    end

    # Called when this agent is being handed off to
    # @param context [RunContext] The current run context
    # @param agent [Agent] This agent
    # @param source [Agent] The agent handing off to this agent
    def on_handoff(context, agent, source)
      # Override in subclass
    end

    # Called before this agent invokes a tool
    # @param context [RunContext] The current run context
    # @param agent [Agent] This agent
    # @param tool [FunctionTool] The tool about to be invoked
    # @param arguments [Hash] The arguments to be passed to the tool
    def on_tool_start(context, agent, tool, arguments = {})
      # Override in subclass
    end

    # Called after this agent invokes a tool
    # @param context [RunContext] The current run context
    # @param agent [Agent] This agent
    # @param tool [FunctionTool] The tool that was invoked
    # @param result [Object] The result returned by the tool
    def on_tool_end(context, agent, tool, result)
      # Override in subclass
    end

    # Called when an error occurs in this agent
    # @param context [RunContext] The current run context
    # @param agent [Agent] This agent
    # @param error [Exception] The error that occurred
    def on_error(context, agent, error)
      # Override in subclass
    end
  end

  ##
  # Composite hooks that combines multiple hooks
  #
  # CompositeRunHooks allows you to combine multiple hook implementations
  # into a single hook object. This is useful for complex scenarios where
  # you need multiple independent behaviors (logging, metrics, audit, etc.)
  # to respond to the same lifecycle events.
  #
  # All registered hooks are called in the order they were added. If any
  # hook raises an exception, subsequent hooks will still be called.
  #
  # @example Combine multiple concerns
  #   logging_hooks = LoggingHooks.new
  #   metrics_hooks = MetricsHooks.new
  #   audit_hooks = AuditHooks.new
  #
  #   composite = RubyAIAgentsFactory::CompositeRunHooks.new([logging_hooks, metrics_hooks])
  #   composite.add_hook(audit_hooks)
  #
  #   config = RubyAIAgentsFactory::RunConfig.new(hooks: composite)
  #   runner.run(messages, config: config)
  #
  # @example Dynamic hook management
  #   composite = RubyAIAgentsFactory::CompositeRunHooks.new
  #   composite.add_hook(BasicLoggingHooks.new)
  #   
  #   if Rails.env.production?
  #     composite.add_hook(ProductionMetricsHooks.new)
  #     composite.add_hook(AlertingHooks.new)
  #   end
  class CompositeRunHooks < RunHooks
    def initialize(hooks = [])
      @hooks = hooks
    end

    def add_hook(hook)
      @hooks << hook
    end

    def on_agent_start(context, agent)
      @hooks.each { |hook| hook.on_agent_start(context, agent) }
    end

    def on_agent_end(context, agent, output)
      @hooks.each { |hook| hook.on_agent_end(context, agent, output) }
    end

    def on_handoff(context, from_agent, to_agent)
      @hooks.each { |hook| hook.on_handoff(context, from_agent, to_agent) }
    end

    def on_tool_start(context, agent, tool, arguments = {})
      @hooks.each { |hook| hook.on_tool_start(context, agent, tool, arguments) }
    end

    def on_tool_end(context, agent, tool, result)
      @hooks.each { |hook| hook.on_tool_end(context, agent, tool, result) }
    end

    def on_error(context, agent, error)
      @hooks.each { |hook| hook.on_error(context, agent, error) }
    end
  end

  ##
  # Async versions of hooks for async execution
  #
  # The AsyncHooks module provides async-compatible versions of the standard
  # hook classes. These hooks support both synchronous and asynchronous execution
  # patterns, making them suitable for async/await-style code.
  #
  # The async hooks provide both sync and async versions of each method:
  # - Standard methods (on_agent_start, etc.) for sync compatibility
  # - Async methods (on_agent_start_async, etc.) for async execution
  #
  # @example Async hook implementation
  #   class AsyncLoggingHooks < RubyAIAgentsFactory::AsyncHooks::RunHooks
  #     def on_agent_start_async(context, agent)
  #       # Async logging to external service
  #       LoggingService.log_async({
  #         event: 'agent_start',
  #         agent: agent.name,
  #         run_id: context.run_id
  #       })
  #     end
  #
  #     def on_tool_end_async(context, agent, tool, result)
  #       # Async metrics collection
  #       MetricsCollector.record_async(
  #         'tool.execution',
  #         tags: { agent: agent.name, tool: tool.name }
  #       )
  #     end
  #   end
  #
  # @example Mixed sync/async usage
  #   class HybridHooks < RubyAIAgentsFactory::AsyncHooks::RunHooks
  #     def on_agent_start(context, agent)
  #       # Immediate sync logging
  #       puts "Agent #{agent.name} starting"
  #     end
  #
  #     def on_agent_start_async(context, agent)
  #       # Async external notification
  #       NotificationService.notify_async("Agent started: #{agent.name}")
  #     end
  #   end
  module AsyncHooks
    class RunHooks < RubyAIAgentsFactory::RunHooks
      # Async versions - override these in async subclasses
      def on_agent_start_async(context, agent)
        on_agent_start(context, agent)
      end

      def on_agent_end_async(context, agent, output)
        on_agent_end(context, agent, output)
      end

      def on_handoff_async(context, from_agent, to_agent)
        on_handoff(context, from_agent, to_agent)
      end

      def on_tool_start_async(context, agent, tool, arguments = {})
        on_tool_start(context, agent, tool, arguments)
      end

      def on_tool_end_async(context, agent, tool, result)
        on_tool_end(context, agent, tool, result)
      end

      def on_error_async(context, agent, error)
        on_error(context, agent, error)
      end
    end

    class AgentHooks < RubyAIAgentsFactory::AgentHooks
      # Async versions - override these in async subclasses
      def on_start_async(context, agent)
        on_start(context, agent)
      end

      def on_end_async(context, agent, output)
        on_end(context, agent, output)
      end

      def on_handoff_async(context, agent, source)
        on_handoff(context, agent, source)
      end

      def on_tool_start_async(context, agent, tool, arguments = {})
        on_tool_start(context, agent, tool, arguments)
      end

      def on_tool_end_async(context, agent, tool, result)
        on_tool_end(context, agent, tool, result)
      end

      def on_error_async(context, agent, error)
        on_error(context, agent, error)
      end
    end
  end
end
