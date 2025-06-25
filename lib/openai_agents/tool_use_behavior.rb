module OpenAIAgents
  # Tool use behavior configuration matching Python implementation
  module ToolUseBehavior
    # Base class for all tool use behaviors
    class Base
      def process_tool_result(agent, tool_calls, results, conversation)
        raise NotImplementedError, "Subclasses must implement process_tool_result"
      end

      def should_continue?(agent, tool_calls, results, conversation)
        true
      end
    end

    # Default behavior: continue running LLM after tool calls
    class RunLLMAgain < Base
      def process_tool_result(agent, tool_calls, results, conversation)
        # Add tool results to conversation and continue
        results.each do |result|
          conversation << result
        end

        { continue: true, done: false }
      end
    end

    # Stop on first tool call - don't continue after tools
    class StopOnFirstTool < Base
      def process_tool_result(agent, tool_calls, results, conversation)
        # Add tool results but mark as done
        results.each do |result|
          conversation << result
        end

        { continue: false, done: true }
      end
    end

    # Stop at specific tools
    class StopAtTools < Base
      attr_reader :tool_names

      def initialize(tool_names)
        @tool_names = Array(tool_names).map(&:to_s)
      end

      def process_tool_result(agent, tool_calls, results, conversation)
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

    # Custom function to determine what to do after tool calls
    class CustomFunction < Base
      attr_reader :function

      def initialize(function)
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

    # Tools to final output - specific tools produce final output
    class ToolsToFinalOutput < Base
      attr_reader :tool_names, :output_extractor

      def initialize(tool_names, output_extractor: nil)
        @tool_names = Array(tool_names).map(&:to_s)
        @output_extractor = output_extractor || ->(results) { results.last[:content] }
      end

      def process_tool_result(agent, tool_calls, results, conversation)
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
