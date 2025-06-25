# frozen_string_literal: true

module OpenAIAgents
  # Base class for run-level lifecycle hooks
  # Subclass and override the methods you need
  class RunHooks
    # Called before an agent is invoked. Called each time the current agent changes.
    # @param context [RunContext] The current run context
    # @param agent [Agent] The agent about to be invoked
    def on_agent_start(context, agent)
      # Override in subclass
    end

    # Called when an agent produces a final output
    # @param context [RunContext] The current run context
    # @param agent [Agent] The agent that produced the output
    # @param output [Object] The final output produced
    def on_agent_end(context, agent, output)
      # Override in subclass
    end

    # Called when a handoff occurs between agents
    # @param context [RunContext] The current run context
    # @param from_agent [Agent] The agent handing off
    # @param to_agent [Agent] The agent being handed off to
    def on_handoff(context, from_agent, to_agent)
      # Override in subclass
    end

    # Called before a tool is invoked
    # @param context [RunContext] The current run context
    # @param agent [Agent] The agent invoking the tool
    # @param tool [FunctionTool] The tool about to be invoked
    # @param arguments [Hash] The arguments to be passed to the tool
    def on_tool_start(context, agent, tool, arguments = {})
      # Override in subclass
    end

    # Called after a tool is invoked
    # @param context [RunContext] The current run context
    # @param agent [Agent] The agent that invoked the tool
    # @param tool [FunctionTool] The tool that was invoked
    # @param result [Object] The result returned by the tool
    def on_tool_end(context, agent, tool, result)
      # Override in subclass
    end

    # Called when an error occurs during agent execution
    # @param context [RunContext] The current run context
    # @param agent [Agent] The agent where the error occurred
    # @param error [Exception] The error that occurred
    def on_error(context, agent, error)
      # Override in subclass
    end
  end

  # Base class for agent-specific lifecycle hooks
  # Set this on agent.hooks to receive events for that specific agent
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

  # Composite hooks that combines multiple hooks
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

  # Async versions of hooks for async execution
  module AsyncHooks
    class RunHooks < OpenAIAgents::RunHooks
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

    class AgentHooks < OpenAIAgents::AgentHooks
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
