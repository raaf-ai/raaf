# frozen_string_literal: true

module RAAF

  ##
  # Tool Use Behavior Configuration System
  #
  # This module provides a flexible system for controlling how agents behave after
  # tool calls are executed. It matches the Python RAAF implementation
  # and allows fine-grained control over agent execution flow.
  #
  # == Behavior Types
  #
  # * **RunLLMAgain**: Continue agent execution after tool calls (default)
  # * **StopOnFirstTool**: Stop execution immediately after any tool call
  # * **StopAtTools**: Stop only when specific tools are called
  # * **CustomFunction**: Use custom logic to determine continuation
  # * **ToolsToFinalOutput**: Treat specific tool outputs as final results
  #
  # == Usage Patterns
  #
  # Tool use behaviors control the agent's execution flow, determining whether
  # the agent should continue processing after tools are called or stop and
  # return results immediately.
  #
  # @example Default behavior (continue after tools)
  #   agent = Agent.new(
  #     name: "Assistant",
  #     tool_use_behavior: ToolUseBehavior.run_llm_again
  #   )
  #
  # @example Stop after first tool call
  #   agent = Agent.new(
  #     name: "ToolUser",
  #     tool_use_behavior: ToolUseBehavior.stop_on_first_tool
  #   )
  #
  # @example Stop at specific tools
  #   behavior = ToolUseBehavior.stop_at_tools("search", "calculator")
  #   agent = Agent.new(name: "Searcher", tool_use_behavior: behavior)
  #
  # @example Custom behavior logic
  #   custom_behavior = ToolUseBehavior.custom_function do |agent, tool_calls, results, conversation|
  #     # Stop if error occurred
  #     results.any? { |r| r[:content].include?("error") } ? false : true
  #   end
  #
  # @example Tools as final output
  #   behavior = ToolUseBehavior.tools_to_final_output("generate_report") do |results, tools|
  #     # Extract final report from tool results
  #     results.find { |r| r[:tool_name] == "generate_report" }[:content]
  #   end
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see RAAF::Agent For agent configuration with behaviors
  module ToolUseBehavior

    ##
    # Base class for all tool use behaviors
    #
    # Defines the interface that all tool use behavior implementations must follow.
    # Subclasses must implement process_tool_result to define custom behavior logic.
    #
    # @abstract Subclass and override {#process_tool_result} to implement custom behavior
    class Base

      ##
      # Process tool execution results and determine continuation behavior
      #
      # @param agent [Agent] the agent that executed the tools
      # @param tool_calls [Array<Hash>] the tool calls that were made
      # @param results [Array<Hash>] the results from tool execution
      # @param conversation [Array<Hash>] the current conversation history
      # @return [Hash] behavior result with :continue and :done keys
      #
      # @abstract Subclasses must implement this method
      def process_tool_result(agent, tool_calls, results, conversation)
        raise NotImplementedError, "Subclasses must implement process_tool_result"
      end

      ##
      # Determine if agent execution should continue
      #
      # @param agent [Agent] the agent that executed the tools
      # @param tool_calls [Array<Hash>] the tool calls that were made
      # @param results [Array<Hash>] the results from tool execution
      # @param conversation [Array<Hash>] the current conversation history
      # @return [Boolean] true if execution should continue
      def should_continue?(_agent, _tool_calls, _results, _conversation)
        true
      end

    end

    ##
    # Default behavior: continue running LLM after tool calls
    #
    # This is the standard behavior where the agent continues execution after
    # tool calls complete. Tool results are added to the conversation and the
    # agent processes them to generate further responses.
    #
    # @example Standard agent workflow
    #   behavior = ToolUseBehavior::RunLLMAgain.new
    #   # Agent calls tool -> Tool executes -> Results added -> Agent continues
    class RunLLMAgain < Base

      ##
      # Add tool results to conversation and continue execution
      #
      # @param agent [Agent] the agent that executed the tools
      # @param tool_calls [Array<Hash>] the tool calls that were made
      # @param results [Array<Hash>] the results from tool execution
      # @param conversation [Array<Hash>] the current conversation history
      # @return [Hash] {continue: true, done: false}
      def process_tool_result(_agent, _tool_calls, results, conversation)
        # Add tool results to conversation and continue
        results.each do |result|
          conversation << result
        end

        { continue: true, done: false }
      end

    end

    ##
    # Stop on first tool call - don't continue after tools
    #
    # This behavior causes the agent to stop execution immediately after any
    # tool is called and executed. Useful for agents that should perform one
    # action and return results without further processing.
    #
    # @example Single-action agent
    #   behavior = ToolUseBehavior::StopOnFirstTool.new
    #   # Agent calls tool -> Tool executes -> Agent stops and returns
    class StopOnFirstTool < Base

      ##
      # Add tool results to conversation and stop execution
      #
      # @param agent [Agent] the agent that executed the tools
      # @param tool_calls [Array<Hash>] the tool calls that were made
      # @param results [Array<Hash>] the results from tool execution
      # @param conversation [Array<Hash>] the current conversation history
      # @return [Hash] {continue: false, done: true}
      def process_tool_result(_agent, _tool_calls, results, conversation)
        # Add tool results but mark as done
        results.each do |result|
          conversation << result
        end

        { continue: false, done: true }
      end

    end

    ##
    # Stop at specific tools
    #
    # This behavior allows selective stopping based on which tools are called.
    # The agent continues execution after most tool calls but stops when any
    # of the specified tools are executed.
    #
    # @example Stop when search or database tools are used
    #   behavior = ToolUseBehavior::StopAtTools.new(["search", "database_query"])
    #   # Agent continues for most tools but stops after search/database
    class StopAtTools < Base

      attr_reader :tool_names

      ##
      # Initialize with list of tools that should trigger stopping
      #
      # @param tool_names [Array<String>, String] tool names that should cause stopping
      def initialize(tool_names)
        super()
        @tool_names = Array(tool_names).map(&:to_s)
      end

      def process_tool_result(_agent, tool_calls, results, conversation)
        # Check if any of the called tools are in our stop list
        should_stop = tool_calls.any? do |tool_call|
          tool_name = tool_call.dig("function", "name")
          @tool_names.include?(tool_name)
        end

        results.each do |result|
          conversation << result
        end

        { continue: !should_stop, done: should_stop }
      end

    end

    ##
    # Custom function to determine what to do after tool calls
    #
    # This behavior allows complete customization of post-tool execution logic
    # by providing a custom function that receives execution context and returns
    # continuation decisions.
    #
    # @example Custom error handling
    #   behavior = ToolUseBehavior::CustomFunction.new do |agent, tool_calls, results, conversation|
    #     # Stop if any tool returned an error
    #     has_error = results.any? { |r| r[:content].include?("error") }
    #     !has_error  # Continue only if no errors
    #   end
    class CustomFunction < Base

      attr_reader :function

      ##
      # Initialize with custom function
      #
      # @param function [Proc] function that determines continuation behavior
      # @yield [agent, tool_calls, results, conversation] custom logic parameters
      # @yieldreturn [Boolean, Hash] true/false for continue or hash with :continue/:done keys
      def initialize(function)
        super()
        @function = function
      end

      def process_tool_result(agent, tool_calls, results, conversation)
        # Call custom function to determine behavior
        custom_result = @function.call(agent, tool_calls, results, conversation)

        # Normalize result
        case custom_result
        when true, false
          { continue: custom_result, done: !custom_result }
        when Hash
          {
            continue: custom_result.fetch(:continue, true),
            done: custom_result.fetch(:done, false)
          }
        else
          { continue: true, done: false }
        end
      end

    end

    ##
    # Tools to final output - specific tools produce final output
    #
    # This behavior treats specific tool outputs as the final result of agent
    # execution. When designated tools are called, their output becomes the
    # final response without further agent processing.
    #
    # @example Report generation tool as final output
    #   behavior = ToolUseBehavior::ToolsToFinalOutput.new(["generate_report"]) do |results, tools|
    #     # Extract the report content as final output
    #     results.find { |r| r[:tool_name] == "generate_report" }[:content]
    #   end
    class ToolsToFinalOutput < Base

      attr_reader :tool_names, :output_extractor

      def initialize(tool_names, output_extractor: nil)
        super()
        @tool_names = Array(tool_names).map(&:to_s)
        @output_extractor = output_extractor || ->(results) { results.last[:content] }
      end

      def process_tool_result(_agent, tool_calls, results, conversation)
        # Check if any called tools are in our final output list
        final_tools = tool_calls.select do |tool_call|
          tool_name = tool_call.dig("function", "name")
          @tool_names.include?(tool_name)
        end

        if final_tools.any?
          # Extract final output using custom function
          final_output = @output_extractor.call(results, final_tools)

          # Add final output as assistant message
          if final_output
            conversation << {
              role: "assistant",
              content: final_output.to_s
            }
          end

          { continue: false, done: true, final_output: final_output }
        else
          # Regular tool behavior - add results and continue
          results.each do |result|
            conversation << result
          end

          { continue: true, done: false }
        end
      end

    end

    # Factory methods for creating behaviors
    class << self

      def run_llm_again
        RunLLMAgain.new
      end

      def stop_on_first_tool
        StopOnFirstTool.new
      end

      def stop_at_tools(*tool_names)
        StopAtTools.new(tool_names)
      end

      def custom_function(&block)
        CustomFunction.new(block)
      end

      def tools_to_final_output(*tool_names, output_extractor: nil)
        ToolsToFinalOutput.new(tool_names, output_extractor: output_extractor)
      end

      # Parse string/symbol behaviors
      def from_config(config)
        case config
        when "run_llm_again", :run_llm_again
          run_llm_again
        when "stop_on_first_tool", :stop_on_first_tool
          stop_on_first_tool
        when Base
          config
        when Proc
          custom_function(&config)
        else
          run_llm_again # Default
        end
      end

    end

  end

end
