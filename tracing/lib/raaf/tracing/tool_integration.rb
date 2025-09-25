# frozen_string_literal: true

module RAAF
  module Tracing
    # Tool integration module for seamless agent context detection and span parenting
    #
    # This module provides tools with the ability to detect when they're running
    # within an agent context and automatically create child spans of the agent span.
    # This ensures proper trace hierarchy without requiring explicit agent passing.
    #
    # @example Tool with automatic agent context detection
    #   class MyTool
    #     include RAAF::Tracing::ToolIntegration
    #
    #     def execute
    #       with_tool_tracing do
    #         # Tool implementation
    #         "Tool executed"
    #       end
    #     end
    #   end
    #
    module ToolIntegration
      def self.included(base)
        base.include(Traceable)
        base.trace_as :tool
      end

      # Executes a block with tool tracing, automatically detecting agent context
      #
      # This method checks for an active agent context and creates appropriate
      # span hierarchy. If an agent is detected, the tool span becomes a child
      # of the agent span. Otherwise, it creates a root span.
      #
      # @param method_name [Symbol, String, nil] Name of the method being traced
      # @param explicit_parent [Object, nil] Explicit parent component (overrides detection)
      # @param metadata [Hash] Additional metadata to include in span
      # @yield Block to execute within the span context
      # @return [Object] Result of the block execution
      #
      # @example Basic usage
      #   def my_tool_method
      #     with_tool_tracing(:execute) do
      #       perform_tool_work
      #     end
      #   end
      #
      # @example With explicit parent
      #   def my_tool_method(agent)
      #     with_tool_tracing(:execute, explicit_parent: agent) do
      #       perform_tool_work
      #     end
      #   end
      #
      def with_tool_tracing(method_name = nil, explicit_parent: nil, **metadata, &block)
        # Determine parent component: explicit > detected agent > none
        parent_component = explicit_parent || detect_agent_context

        # Add tool-specific metadata
        tool_metadata = {
          "tool.name" => self.class.name,
          "tool.method" => method_name&.to_s
        }
        tool_metadata["tool.agent_context"] = parent_component.class.name if parent_component

        # Execute with tracing
        with_tracing(method_name, parent_component: parent_component, **tool_metadata, **metadata, &block)
      end

      # Detects if there's an active agent context in the current execution
      #
      # This method uses multiple strategies to detect agent context:
      # 1. Thread-local storage (for explicit context passing)
      # 2. Call stack analysis (for automatic detection)
      # 3. Instance variable checking (for dependency injection)
      #
      # @return [Object, nil] Detected agent instance or nil if no context found
      #
      def detect_agent_context
        # Strategy 1: Check thread-local storage for explicitly set agent
        if Thread.current[:current_agent]&.respond_to?(:traced?) && Thread.current[:current_agent].traced?
          return Thread.current[:current_agent]
        end

        # Strategy 2: Check instance variable for injected agent context
        if instance_variable_defined?(:@agent_context) && @agent_context&.respond_to?(:traced?) && @agent_context.traced?
          return @agent_context
        end

        # Strategy 3: Check for parent component passed during initialization
        if instance_variable_defined?(:@parent_component) && @parent_component&.respond_to?(:traced?) && @parent_component.traced?
          return @parent_component
        end

        # Strategy 4: Call stack analysis (more expensive, used as fallback)
        detect_agent_from_call_stack
      end

      # Analyzes the call stack to detect if we're running within an agent context
      #
      # This method examines the call stack to find evidence of agent execution.
      # It looks for method names and class patterns that indicate agent activity.
      #
      # @return [Object, nil] Detected agent or nil if no agent found in call stack
      #
      def detect_agent_from_call_stack
        # Get current call stack
        caller_locations = caller_locations(0)

        # Look for agent-related patterns in the call stack
        caller_locations.each do |location|
          # Check if the location indicates we're within an agent execution
          if agent_execution_pattern?(location)
            # Try to extract agent instance from call stack context
            # This is implementation-specific and may require cooperation from the runner
            return extract_agent_from_location(location)
          end
        end

        nil
      end

      # Sets the current agent context for tool execution
      #
      # This method is typically called by the runner before tool execution
      # to establish the agent context for automatic detection.
      #
      # @param agent [Object] The agent instance to set as context
      # @return [void]
      #
      def self.set_agent_context(agent, root_span = nil)
        Thread.current[:current_agent] = agent
        Thread.current[:original_agent_span] = root_span
      end

      # Clears the current agent context
      #
      # This method should be called after tool execution to clean up
      # the thread-local agent context.
      #
      # @return [void]
      #
      def self.clear_agent_context
        Thread.current[:current_agent] = nil
        Thread.current[:original_agent_span] = nil
        Thread.current[:raaf_agent_context_stack] = nil
      end

      # Executes a block with agent context set for tools
      #
      # This is a convenience method for runners to establish agent context
      # around tool execution blocks.
      #
      # @param agent [Object] The agent instance to set as context
      # @yield Block to execute with agent context
      # @return [Object] Result of the block execution
      #
      def self.with_agent_context(agent, root_span = nil, &block)
        stack = Thread.current[:raaf_agent_context_stack] ||= []
        previous_agent = Thread.current[:current_agent]
        previous_original_span = Thread.current[:original_agent_span]

        original_agent_span = root_span
        original_agent_span ||= agent.current_span if agent.respond_to?(:current_span)

        stack.push({ agent: agent, span: original_agent_span })

        Thread.current[:current_agent] = agent
        Thread.current[:original_agent_span] = original_agent_span

        begin
          block.call
        ensure
          stack.pop
          Thread.current[:current_agent] = previous_agent
          Thread.current[:original_agent_span] = previous_original_span
        end
      end

      # Captures the active agent context for propagation across threads/fibers.
      # Returns nil if no context is available.
      def self.capture_context
        agent = Thread.current[:current_agent]
        return nil unless agent

        {
          agent: agent,
          span: Thread.current[:original_agent_span]
        }
      end

      # Re-establishes a previously captured agent context for the duration of the block.
      def self.with_captured_context(context, &block)
        return block.call unless context && context[:agent]

        with_agent_context(context[:agent], context[:span], &block)
      end

      private

      # Checks if a call stack location indicates agent execution
      #
      # @param location [Thread::Backtrace::Location] Call stack location to check
      # @return [Boolean] true if location indicates agent execution
      #
      def agent_execution_pattern?(location)
        path = location.path
        method_name = location.label

        # Look for patterns that indicate agent execution
        return true if path.include?('step_processor') && method_name.include?('execute')
        return true if path.include?('runner') && method_name.include?('run')
        return true if method_name.include?('agent') && method_name.include?('execute')

        false
      end

      # Attempts to extract agent instance from call stack location
      #
      # This is a placeholder for more sophisticated agent extraction.
      # In practice, this would require cooperation from the runner to store
      # agent references in accessible locations.
      #
      # @param location [Thread::Backtrace::Location] Call stack location
      # @return [Object, nil] Extracted agent or nil
      #
      def extract_agent_from_location(location)
        # This is a simplified implementation
        # In a real system, you might:
        # 1. Use binding information to access local variables
        # 2. Leverage a registry of active agents
        # 3. Use thread-local storage set by the runner

        # For now, we rely on thread-local storage set by the runner
        # but we still need to check if the agent is currently being traced
        current_agent = Thread.current[:current_agent]
        if current_agent&.respond_to?(:traced?) && current_agent.traced?
          current_agent
        else
          nil
        end
      end
    end
  end
end
