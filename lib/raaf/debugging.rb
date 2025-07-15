# frozen_string_literal: true

require "json"
require "time"
require "logger"
require "set"
require_relative "tracing/spans"

module RubyAIAgentsFactory
  ##
  # Debugging System for OpenAI Agents
  #
  # This module provides comprehensive debugging capabilities for agent workflows,
  # including breakpoints, step-by-step execution, performance monitoring, and
  # execution history tracking. It's designed to help developers understand and
  # optimize agent behavior during development and testing.
  #
  # == Features
  #
  # * **Breakpoint System**: Set breakpoints at specific execution points
  # * **Step Mode**: Step through agent execution line by line
  # * **Variable Watching**: Monitor specific variables during execution
  # * **Performance Metrics**: Track execution times and resource usage
  # * **Execution History**: Record and replay agent execution flows
  # * **Interactive Debugging**: Real-time debugging with user input
  # * **Export Capabilities**: Export debug sessions for analysis
  #
  # @example Basic debugging setup
  #   debugger = RubyAIAgentsFactory::Debugging::Debugger.new
  #   debugger.breakpoint("agent_run_start")
  #   debugger.enable_step_mode
  #   
  #   debug_runner = RubyAIAgentsFactory::Debugging::DebugRunner.new(
  #     agent: agent,
  #     debugger: debugger
  #   )
  #   result = debug_runner.run(messages, debug: true)
  #
  # @example Advanced debugging with monitoring
  #   debugger = RubyAIAgentsFactory::Debugging::Debugger.new
  #   debugger.watch_variable("message_count") { @conversation.length }
  #   debugger.breakpoint("tool_call:search")
  #   
  #   # Agent execution will pause at breakpoints and show watched variables
  #   result = debug_runner.run(messages)
  #   debugger.show_performance_metrics
  #   debugger.export_debug_session("my_debug_session.json")
  #
  # @author OpenAI Agents Ruby Team
  # @since 0.1.0
  # @see RubyAIAgentsFactory::Debugging::DebugRunner For debug-enabled agent execution
  module Debugging
    ##
    # Enhanced debugger for agent workflows
    #
    # The Debugger class provides comprehensive debugging capabilities including
    # breakpoints, step-by-step execution, variable watching, performance monitoring,
    # and execution history tracking.
    #
    # @example Setting up debugging
    #   debugger = Debugger.new(output: $stdout, log_level: Logger::DEBUG)
    #   debugger.breakpoint("agent_run_start")
    #   debugger.watch_variable("token_count") { current_token_count }
    #
    # @example Performance monitoring
    #   debugger.debug_agent_run(agent, messages) do
    #     # Agent execution code here
    #   end
    #   debugger.show_performance_metrics
    class Debugger
      attr_reader :breakpoints, :step_mode, :watch_variables

      ##
      # Initialize the debugger with output and logging configuration
      #
      # @param output [IO] output stream for debug messages (default: $stdout)
      # @param log_level [Integer] logging level (default: Logger::DEBUG)
      #
      # @example Create debugger with custom output
      #   debugger = Debugger.new(
      #     output: File.open("debug.log", "w"),
      #     log_level: Logger::INFO
      #   )
      def initialize(output: $stdout, log_level: ::Logger::DEBUG)
        @output = output
        @logger = ::Logger.new(output)
        @logger.level = log_level
        @breakpoints = Set.new
        @step_mode = false
        @watch_variables = {}
        @call_stack = []
        @execution_history = []
        @performance_metrics = {}
      end

      ##
      # Set a breakpoint at a specific location
      #
      # @param location [String] breakpoint location identifier
      # @return [void]
      #
      # @example Set breakpoints at different execution points
      #   debugger.breakpoint("agent_run_start")
      #   debugger.breakpoint("tool_call:search")
      #   debugger.breakpoint("handoff:agent1:agent2")
      def breakpoint(location)
        @breakpoints.add(location)
        debug("Breakpoint set at: #{location}")
      end

      def remove_breakpoint(location)
        @breakpoints.delete(location)
        debug("Breakpoint removed from: #{location}")
      end

      def enable_step_mode
        @step_mode = true
        debug("Step mode enabled")
      end

      def disable_step_mode
        @step_mode = false
        debug("Step mode disabled")
      end

      ##
      # Watch a variable during execution
      #
      # @param name [String] variable name for identification
      # @yield [] block that returns the current value of the variable
      # @return [void]
      #
      # @example Watch conversation length
      #   debugger.watch_variable("message_count") { @conversation.length }
      #
      # @example Watch agent state
      #   debugger.watch_variable("current_agent") { @current_agent&.name }
      def watch_variable(name, &getter)
        @watch_variables[name] = getter
        debug("Watching variable: #{name}")
      end

      def unwatch_variable(name)
        @watch_variables.delete(name)
        debug("Stopped watching variable: #{name}")
      end

      def debug_agent_run(agent, messages)
        debug("=" * 60)
        debug("DEBUGGING AGENT RUN")
        debug("Agent: #{agent.name}")
        debug("Model: #{agent.model}")
        debug("Messages: #{messages.length}")
        debug("=" * 60)

        # Check breakpoint
        check_breakpoint("agent_run_start")

        # Record execution
        execution_record = {
          timestamp: Time.now.utc,
          type: "agent_run",
          agent: agent.name,
          input_messages: messages.length,
          context: capture_context
        }

        @execution_history << execution_record

        measure_performance("agent_run") do
          yield if block_given?
        end
      end

      def debug_tool_call(tool_name, args)
        debug("TOOL CALL: #{tool_name}")
        debug("Arguments: #{args.inspect}")

        check_breakpoint("tool_call:#{tool_name}")

        execution_record = {
          timestamp: Time.now.utc,
          type: "tool_call",
          tool: tool_name,
          args: args,
          context: capture_context
        }

        @execution_history << execution_record

        result = nil
        duration = measure_performance("tool_call:#{tool_name}") do
          result = yield if block_given?
        end

        debug("Tool result: #{result}")
        debug("Execution time: #{duration}ms")

        result
      end

      def debug_handoff(from_agent, to_agent, reason = nil)
        debug("HANDOFF: #{from_agent} -> #{to_agent}")
        debug("Reason: #{reason}") if reason

        check_breakpoint("handoff:#{from_agent}:#{to_agent}")

        execution_record = {
          timestamp: Time.now.utc,
          type: "handoff",
          from_agent: from_agent,
          to_agent: to_agent,
          reason: reason,
          context: capture_context
        }

        @execution_history << execution_record

        yield if block_given?
      end

      def debug_llm_call(model, messages)
        debug("LLM CALL: #{model}")
        debug("Input messages: #{messages.length}")

        # Log message details in debug mode
        messages.each_with_index do |msg, idx|
          debug("  Message #{idx + 1} (#{msg[:role]}): #{msg[:content][0..100]}...")
        end

        check_breakpoint("llm_call")

        execution_record = {
          timestamp: Time.now.utc,
          type: "llm_call",
          model: model,
          input_messages: messages.length,
          context: capture_context
        }

        @execution_history << execution_record

        result = nil
        duration = measure_performance("llm_call") do
          result = yield if block_given?
        end

        if result
          debug("LLM response received")
          debug("Response tokens: #{result.dig("usage", "completion_tokens") || "unknown"}")
          debug("Execution time: #{duration}ms")
        end

        result
      end

      def inspect_agent(agent)
        output = []
        output << "AGENT INSPECTION: #{agent.name}"
        output << ("-" * 40)
        output << "Model: #{agent.model}"
        output << "Instructions: #{agent.instructions || "None"}"
        output << "Max turns: #{agent.max_turns}"
        output << "Tools (#{agent.tools.length}):"

        agent.tools.each do |tool|
          output << "  - #{tool.name}: #{tool.description}"
        end

        output << "Handoffs (#{agent.handoffs.length}):"
        agent.handoffs.each do |handoff_agent|
          output << "  - #{handoff_agent.name}"
        end

        debug(output.join("\n"))
      end

      def inspect_conversation(messages)
        output = []
        output << "CONVERSATION INSPECTION (#{messages.length} messages)"
        output << ("-" * 50)

        messages.each_with_index do |msg, idx|
          role_icon = case msg[:role]
                      when "user" then "👤"
                      when "assistant" then "🤖"
                      when "system" then "⚙️"
                      when "tool" then "🔧"
                      else "❓"
                      end

          content_preview = msg[:content].to_s[0..200]
          content_preview += "..." if msg[:content].to_s.length > 200

          output << "#{idx + 1}. #{role_icon} #{msg[:role].upcase}"
          output << "   #{content_preview}"

          if msg[:tool_calls]
            output << "   Tool calls: #{msg[:tool_calls].length}"
            msg[:tool_calls].each do |tool_call|
              output << "     - #{tool_call.dig("function", "name")}"
            end
          end

          output << ""
        end

        debug(output.join("\n"))
      end

      def show_performance_metrics
        output = []
        output << "PERFORMANCE METRICS"
        output << ("=" * 40)

        if @performance_metrics.empty?
          output << "No metrics available"
        else
          @performance_metrics.each do |operation, stats|
            avg_time = stats[:total_time] / stats[:count]
            output << "#{operation}:"
            output << "  Calls: #{stats[:count]}"
            output << "  Total time: #{stats[:total_time].round(2)}ms"
            output << "  Average time: #{avg_time.round(2)}ms"
            output << "  Min time: #{stats[:min_time].round(2)}ms"
            output << "  Max time: #{stats[:max_time].round(2)}ms"
            output << ""
          end
        end

        debug(output.join("\n"))
      end

      def show_execution_history(limit: 20)
        output = []
        output << "EXECUTION HISTORY (last #{limit})"
        output << ("=" * 50)

        recent_history = @execution_history.last(limit)

        recent_history.each_with_index do |record, idx|
          timestamp = record[:timestamp].strftime("%H:%M:%S.%3N")
          type_icon = case record[:type]
                      when "agent_run" then "🤖"
                      when "tool_call" then "🔧"
                      when "handoff" then "↔️"
                      when "llm_call" then "🧠"
                      else "❓"
                      end

          output << "#{idx + 1}. [#{timestamp}] #{type_icon} #{record[:type].upcase}"

          case record[:type]
          when "agent_run"
            output << "   Agent: #{record[:agent]}"
          when "tool_call"
            output << "   Tool: #{record[:tool]}"
            output << "   Args: #{record[:args].keys.join(", ")}"
          when "handoff"
            output << "   From: #{record[:from_agent]} -> To: #{record[:to_agent]}"
          when "llm_call"
            output << "   Model: #{record[:model]}"
          end

          output << ""
        end

        debug(output.join("\n"))
      end

      def export_debug_session(filename = nil)
        filename ||= "debug_session_#{Time.now.strftime("%Y%m%d_%H%M%S")}.json"

        debug_data = {
          timestamp: Time.now.utc.iso8601,
          execution_history: @execution_history,
          performance_metrics: @performance_metrics,
          breakpoints: @breakpoints.to_a,
          watch_variables: @watch_variables.keys,
          summary: {
            total_executions: @execution_history.length,
            session_duration: session_duration,
            performance_summary: performance_summary
          }
        }

        File.write(filename, JSON.pretty_generate(debug_data))
        debug("Debug session exported to: #{filename}")
      end

      def clear_history
        @execution_history.clear
        @performance_metrics.clear
        debug("Debug history cleared")
      end

      def debug(message)
        @logger.debug(message)
      end

      def info(message)
        @logger.info(message)
      end

      def warn(message)
        @logger.warn(message)
      end

      def error(message)
        @logger.error(message)
      end

      private

      def check_breakpoint(location)
        return unless @breakpoints.include?(location) || @step_mode

        debug("🔴 BREAKPOINT HIT: #{location}")
        debug("Call stack depth: #{@call_stack.length}")

        # Show watched variables
        show_watched_variables

        # Wait for user input in step mode
        return unless @step_mode

        @output.print("Debug> Press Enter to continue (or 'q' to quit step mode): ")
        input = $stdin.gets&.strip

        if input == "q"
          disable_step_mode
        elsif input&.start_with?("inspect")
          # Handle inspection commands
          handle_inspect_command(input)
        end
      end

      def show_watched_variables
        return if @watch_variables.empty?

        debug("WATCHED VARIABLES:")
        @watch_variables.each do |name, getter|
          value = getter.call
          debug("  #{name}: #{value.inspect}")
        rescue StandardError => e
          debug("  #{name}: ERROR - #{e.message}")
        end
      end

      def handle_inspect_command(command)
        # Simple inspection command handler
        case command
        when /inspect stack/
          debug("Call stack: #{@call_stack.inspect}")
        when /inspect history/
          show_execution_history(limit: 10)
        when /inspect metrics/
          show_performance_metrics
        end
      end

      def capture_context
        {
          call_stack_depth: @call_stack.length,
          watched_variables: capture_watched_variables,
          memory_usage: capture_memory_usage
        }
      end

      def capture_watched_variables
        result = {}
        @watch_variables.each do |name, getter|
          result[name] = getter.call
        rescue StandardError => e
          result[name] = "ERROR: #{e.message}"
        end
        result
      end

      def capture_memory_usage
        if defined?(GC)
          {
            heap_allocated_pages: GC.stat[:heap_allocated_pages],
            heap_sorted_length: GC.stat[:heap_sorted_length],
            heap_allocatable_pages: GC.stat[:heap_allocatable_pages],
            heap_available_slots: GC.stat[:heap_available_slots],
            heap_live_slots: GC.stat[:heap_live_slots],
            heap_free_slots: GC.stat[:heap_free_slots]
          }
        else
          {}
        end
      end

      def measure_performance(operation)
        start_time = Time.now

        begin
          result = yield

          # Record successful execution
          duration = (Time.now - start_time) * 1000 # Convert to milliseconds
          record_performance(operation, duration)

          result
        rescue StandardError => e
          # Record failed execution
          duration = (Time.now - start_time) * 1000
          record_performance("#{operation}_failed", duration)

          error("Performance measurement error in #{operation}: #{e.message}")
          raise
        end
      end

      def record_performance(operation, duration)
        @performance_metrics[operation] ||= {
          count: 0,
          total_time: 0.0,
          min_time: Float::INFINITY,
          max_time: 0.0
        }

        stats = @performance_metrics[operation]
        stats[:count] += 1
        stats[:total_time] += duration
        stats[:min_time] = [stats[:min_time], duration].min
        stats[:max_time] = [stats[:max_time], duration].max

        duration
      end

      def session_duration
        return 0 if @execution_history.empty?

        start_time = @execution_history.first[:timestamp]
        end_time = @execution_history.last[:timestamp]

        (end_time - start_time) * 1000 # Convert to milliseconds
      end

      def performance_summary
        return {} if @performance_metrics.empty?

        total_operations = @performance_metrics.values.sum { |stats| stats[:count] }
        total_time = @performance_metrics.values.sum { |stats| stats[:total_time] }

        {
          total_operations: total_operations,
          total_time_ms: total_time.round(2),
          average_time_per_operation: total_operations.positive? ? (total_time / total_operations).round(2) : 0,
          operations_by_type: @performance_metrics.transform_values { |stats| stats[:count] }
        }
      end
    end

    ##
    # Debug-enabled runner
    #
    # The DebugRunner wraps the standard Runner with debugging capabilities,
    # allowing step-by-step execution, breakpoint handling, and performance
    # monitoring during agent execution.
    #
    # @example Basic debug runner usage
    #   debugger = Debugger.new
    #   debug_runner = DebugRunner.new(agent: agent, debugger: debugger)
    #   result = debug_runner.run(messages, debug: true)
    #
    # @example With custom tracer
    #   tracer = Tracing::SpanTracer.new
    #   debug_runner = DebugRunner.new(
    #     agent: agent,
    #     debugger: debugger,
    #     tracer: tracer
    #   )
    class DebugRunner
      ##
      # Initialize debug runner with agent and debugging tools
      #
      # @param agent [Agent] the agent to run with debugging
      # @param debugger [Debugger, nil] debugger instance (creates new if nil)
      # @param tracer [Tracing::SpanTracer, nil] optional tracer for execution monitoring
      def initialize(agent:, debugger: nil, tracer: nil)
        @agent = agent
        @debugger = debugger || Debugger.new
        @tracer = tracer
      end

      ##
      # Run agent with optional debugging enabled
      #
      # @param messages [Array<Hash>] conversation messages
      # @param debug [Boolean] whether to enable debugging features
      # @return [Hash] agent execution result
      #
      # @example Run with debugging
      #   result = debug_runner.run(messages, debug: true)
      #
      # @example Run without debugging overhead
      #   result = debug_runner.run(messages, debug: false)
      def run(messages, debug: true)
        if debug
          @debugger.debug_agent_run(@agent, messages) do
            run_with_debugging(messages)
          end
        else
          run_without_debugging(messages)
        end
      end

      private

      def run_with_debugging(messages)
        @debugger.inspect_agent(@agent)
        @debugger.inspect_conversation(messages)

        # Create regular runner and intercept its methods
        runner = Runner.new(agent: @agent, tracer: @tracer)

        # Override runner methods to add debugging
        runner.define_singleton_method(:create_completion) do |messages, agent|
          @debugger.debug_llm_call(agent.model, messages) do
            super(messages, agent)
          end
        end

        # Run the agent
        result = runner.run(messages)

        @debugger.show_performance_metrics
        result
      end

      def run_without_debugging(messages)
        runner = Runner.new(agent: @agent, tracer: @tracer)
        runner.run(messages)
      end
    end
  end
end
