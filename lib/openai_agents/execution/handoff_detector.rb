# frozen_string_literal: true

require_relative "../logging"

module OpenAIAgents
  module Execution
    ##
    # Detects and processes agent handoff requests
    #
    # This class handles the logic for detecting when an agent wants to
    # transfer control to another agent and managing that transition.
    #
    class HandoffDetector
      include Logger

      ##
      # Initialize handoff detector
      #
      # @param agent [Agent] The current agent
      # @param runner [Runner] The runner for accessing handoff agents
      #
      def initialize(agent, runner)
        @agent = agent
        @runner = runner
      end

      ##
      # Check if a message indicates a handoff is needed
      #
      # @param message [Hash] Assistant message to check
      # @param current_agent [Agent] Current active agent
      # @return [Hash] Result with :handoff_occurred and optionally :new_agent
      #
      def check_for_handoff(message, current_agent)
        # Check if the message indicates a handoff is needed
        return { handoff_occurred: false } unless message[:content]

        # Delegate to runner's handoff detection
        handoff_target = @runner.detect_handoff_in_content(message[:content], current_agent)
        
        if handoff_target
          process_handoff_request(handoff_target, current_agent)
        else
          { handoff_occurred: false }
        end
      end

      ##
      # Process tool calls to check for handoff tools
      #
      # Some agents may use tool calls to request handoffs rather than
      # text-based patterns.
      #
      # @param tool_calls [Array<Hash>] Tool calls to examine
      # @param current_agent [Agent] Current active agent
      # @return [Hash] Result with :handoff_occurred and optionally :new_agent
      #
      def check_tool_calls_for_handoff(tool_calls, current_agent)
        handoff_tool_call = tool_calls.find { |tc| is_handoff_tool?(tc) }
        
        if handoff_tool_call
          target_agent_name = extract_handoff_target(handoff_tool_call)
          process_handoff_request(target_agent_name, current_agent)
        else
          { handoff_occurred: false }
        end
      end

      ##
      # Check if handoffs are available for the current agent
      #
      # @param agent [Agent] Agent to check
      # @return [Boolean] true if agent has handoff capabilities
      #
      def handoffs_available?(agent = @agent)
        agent.respond_to?(:handoffs) && !agent.handoffs.empty?
      end

      private

      ##
      # Process a detected handoff request
      #
      # Attempts to find the target agent and create a handoff result.
      # Logs the handoff attempt and handles cases where the target
      # agent cannot be found.
      #
      # @param target_agent_name [String] Name of agent to handoff to
      # @param current_agent [Agent] Current active agent
      # @return [Hash] Handoff result with success/failure information
      # @private
      #
      def process_handoff_request(target_agent_name, current_agent)
        # Find the target agent
        target_agent = @runner.find_handoff_agent(target_agent_name, current_agent)
        
        if target_agent
          log_info("Handoff detected", from: current_agent.name, to: target_agent.name)
          {
            handoff_occurred: true,
            new_agent: target_agent,
            target_name: target_agent_name
          }
        else
          log_warn("Handoff target not found", target: target_agent_name, current_agent: current_agent.name)
          { handoff_occurred: false, error: "Target agent '#{target_agent_name}' not found" }
        end
      end

      ##
      # Check if a tool call is a handoff request
      #
      # Examines the function name to determine if it matches
      # common handoff tool patterns.
      #
      # @param tool_call [Hash] Tool call to examine
      # @return [Boolean] true if this is a handoff tool call
      # @private
      #
      def is_handoff_tool?(tool_call)
        function_name = tool_call.dig("function", "name") || tool_call[:function][:name]
        
        # Check for common handoff tool patterns
        handoff_patterns = %w[handoff transfer_to delegate_to switch_to]
        handoff_patterns.any? { |pattern| function_name&.downcase&.include?(pattern) }
      end

      ##
      # Extract the target agent name from a handoff tool call
      #
      # Parses the tool call arguments to find the target agent name,
      # checking common parameter names used for handoff targets.
      #
      # @param tool_call [Hash] Handoff tool call
      # @return [String, nil] Target agent name or nil if not found
      # @private
      #
      def extract_handoff_target(tool_call)
        arguments_str = tool_call.dig("function", "arguments") || tool_call[:function][:arguments]
        
        begin
          arguments = JSON.parse(arguments_str, symbolize_names: true)
          # Look for common parameter names for target agent
          arguments[:agent] || arguments[:target] || arguments[:to] || arguments[:agent_name]
        rescue JSON::ParserError
          log_warn("Failed to parse handoff tool arguments", arguments: arguments_str)
          nil
        end
      end
    end
  end
end