# frozen_string_literal: true

module RAAF

  ##
  # Orchestrates multi-agent workflows with explicit handoff control
  #
  # This class replaces the implicit hook-based handoff system with
  # explicit orchestration, providing clear control flow and error handling.
  #
  class AgentOrchestrator

    include Logger

    attr_reader :handoff_context, :agents, :provider

    def initialize(agents:, provider: nil)
      @agents = agents
      @provider = provider || Models::ResponsesProvider.new
      @handoff_context = HandoffContext.new
    end

    ##
    # Run multi-agent workflow with explicit handoff control
    #
    # @param initial_message [String] Initial message for first agent
    # @param starting_agent [String] Name of the starting agent
    # @return [WorkflowResult] Complete workflow result
    #
    def run_workflow(initial_message, starting_agent: nil)
      # Normalize the initial message to ensure it's not nil
      initial_message = "" if initial_message.nil?

      # Set starting agent
      first_agent = starting_agent || @agents.keys.first
      @handoff_context.instance_variable_set(:@current_agent, first_agent)

      log_info("Starting workflow",
               starting_agent: first_agent,
               total_agents: @agents.size,
               message: initial_message)

      workflow_start_time = Time.now
      results = []
      current_message = initial_message

      # Execute workflow steps
      loop do
        current_agent_name = @handoff_context.current_agent

        # Get current agent
        agent_config = @agents[current_agent_name]

        log_debug("🔍 ORCHESTRATOR: Agent lookup",
                  current_agent_name: current_agent_name,
                  agent_config_present: !agent_config.nil?,
                  agent_config_class: agent_config&.class&.name,
                  agent_config_name: agent_config.respond_to?(:name) ? agent_config.name : nil,
                  handoff_context_current: @handoff_context.current_agent)

        unless agent_config
          return WorkflowResult.new(
            success: false,
            error: "Agent '#{current_agent_name}' not found",
            results: results,
            started_at: workflow_start_time
          )
        end

        # Run current agent
        agent_result = run_agent(agent_config, current_message)
        results << agent_result

        # Handle nil or malformed agent results
        if agent_result.nil?
          return WorkflowResult.new(
            success: false,
            error: "Agent returned nil result",
            results: results,
            started_at: workflow_start_time
          )
        end

        # Check for errors
        if agent_result[:success] == false
          return WorkflowResult.new(
            success: false,
            error: agent_result[:error] || "Agent execution failed",
            results: results,
            started_at: workflow_start_time
          )
        end

        # Check for workflow completion
        if workflow_completed?(agent_result)
          log_info("Workflow completed", agent: current_agent_name, results_count: results.size)
          return WorkflowResult.new(
            success: true,
            results: results,
            final_agent: current_agent_name,
            handoff_context: @handoff_context,
            started_at: workflow_start_time
          )
        end

        # Check for handoff request
        if handoff_requested?(agent_result)
          log_info("Handoff requested", from: current_agent_name, to: agent_result[:target_agent])
          handoff_result = execute_handoff(agent_result)

          if handoff_result[:success] == false
            return WorkflowResult.new(
              success: false,
              error: handoff_result[:error],
              results: results,
              started_at: workflow_start_time
            )
          end

          # Prepare message for next agent
          current_message = @handoff_context.build_handoff_message
          log_info("Handoff executed", **handoff_result)
        else
          # No handoff requested but workflow not completed
          return WorkflowResult.new(
            success: false,
            error: "Workflow incomplete: Agent '#{current_agent_name}' did not request handoff or complete workflow",
            results: results,
            started_at: workflow_start_time
          )
        end

        # Safety check to prevent infinite loops
        if results.size > 10
          return WorkflowResult.new(
            success: false,
            error: "Maximum workflow steps exceeded",
            results: results,
            started_at: workflow_start_time
          )
        end
      end
    end

    private

    ##
    # Find an agent by name
    #
    # @param agent_name [String] Name of the agent
    # @return [Agent, nil] The agent if found
    #
    def find_agent(agent_name)
      @agents[agent_name]
    end

    ##
    # Run a single agent with handoff tools
    #
    # @param agent_config [Hash] Agent configuration
    # @param message [String] Message for the agent
    # @return [Hash] Agent execution result
    #
    def run_agent(agent_config_or_agent, message)
      # Handle both Agent objects (for tests) and config hashes (for production)
      if agent_config_or_agent.is_a?(Agent)
        agent = agent_config_or_agent
        agent_name = agent.name
      else
        agent_config = agent_config_or_agent
        agent_name = agent_config[:name]
        agent_class = agent_config[:class]
        handoff_tools = agent_config[:handoff_tools] || []

        log_info("Running agent", {
                   agent: agent_name,
                   message_length: message&.length || 0,
                   handoff_tools: handoff_tools.map { |t| t[:target_agent] }
                 })

        # Create agent instance
        agent = agent_class.new(
          name: agent_name,
          instructions: agent_config[:instructions],
          model: agent_config[:model] || "gpt-4o"
        )

        # Add regular tools
        agent_config[:tools]&.each do |tool|
          agent.add_tool(tool)
        end

        # Add handoff tools
        handoff_tools.each do |handoff_config|
          handoff_tool = HandoffTool.create_handoff_tool(
            target_agent: handoff_config[:target_agent],
            handoff_context: @handoff_context,
            data_contract: handoff_config[:data_contract] || {}
          )
          agent.add_tool(handoff_tool)
        end

        # Add completion tool if this is a terminal agent
        if agent_config[:terminal]
          completion_tool = HandoffTool.create_completion_tool(
            handoff_context: @handoff_context,
            data_contract: agent_config[:completion_contract] || {}
          )
          agent.add_tool(completion_tool)
        end
      end

      # Run agent
      begin
        runner = Runner.new(agent: agent, provider: @provider)

        log_debug("🔍 ORCHESTRATOR: About to run agent",
                  agent: agent_name,
                  agent_object_name: agent.name,
                  message: message,
                  message_class: message.class.name,
                  provider_class: @provider.class.name)

        result = runner.run(message)

        log_debug("🔍 ORCHESTRATOR: Runner result details",
                  agent: agent_name,
                  result_class: result.class.name,
                  messages_count: result.messages.size,
                  has_tool_results: result.respond_to?(:tool_results) && result.tool_results&.any?,
                  all_messages: result.messages.map do |msg|
                    msg.slice(:role, :content, :tool_calls, :tool_call_id)
                  end)

        # Extract handoff information from result
        extract_agent_result(result, agent_name)
      rescue StandardError => e
        {
          success: false,
          error: "Agent execution failed: #{e.message}",
          agent: agent_name
        }
      end
    end

    ##
    # Extract structured result from agent run
    #
    # @param result [RunResult] Agent run result
    # @param agent_name [String] Agent name
    # @return [Hash] Structured result
    #
    def extract_agent_result(result, agent_name)
      # Handle both RunResult objects and plain hashes (for tests)
      messages = result.respond_to?(:messages) ? result.messages : result[:messages] || []
      usage = result.respond_to?(:usage) ? result.usage : result[:usage]

      # Extract tool_calls from RunResult if available
      result_tool_calls = result.respond_to?(:tool_calls) ? result.tool_calls : []

      log_debug("🔍 ORCHESTRATOR: Extracting result from runner",
                agent: agent_name,
                result_class: result.class.name,
                messages_count: messages.size,
                last_message: messages.last&.slice(:role, :content, :tool_calls),
                all_message_roles: messages.map { |m| m[:role] },
                result_tool_calls_count: result_tool_calls.size,
                result_tool_calls: result_tool_calls,
                all_messages_preview: messages.map { |m| "#{m[:role]}: #{m[:content]&.slice(0, 50)}..." })

      if messages.empty?
        return {
          success: true,
          agent: agent_name,
          messages: messages,
          usage: usage,
          handoff_requested: false,
          workflow_completed: false,
          tool_calls: []
        }
      end

      last_message = messages.last
      unless last_message
        return {
          success: true,
          agent: agent_name,
          messages: messages,
          usage: usage,
          handoff_requested: false,
          workflow_completed: false,
          tool_calls: []
        }
      end

      # Check for tool calls in the last message or from RunResult
      # Handle both string and symbol keys
      tool_calls = last_message[:tool_calls] || last_message["tool_calls"] || result_tool_calls || []

      # Also check if this is a tool response message
      if tool_calls.empty? && last_message[:role] == "tool"
        # Try to parse the tool response to see if it contains handoff info
        begin
          tool_content = begin
            JSON.parse(last_message[:content])
          rescue StandardError
            {}
          end
          if tool_content["assistant"]
            # This is a handoff response
            handoff_requested = true
            target_agent = tool_content["assistant"]
            log_debug("Detected handoff from tool response",
                      agent: agent_name,
                      target_agent: target_agent)
          end
        rescue StandardError => e
          log_debug("Failed to parse tool response", error: e.message)
        end
      end

      log_debug("Tool calls extraction",
                agent: agent_name,
                tool_calls_found: tool_calls.size,
                tool_calls: tool_calls,
                last_message_role: last_message[:role],
                last_message_content: last_message[:content])

      # Initialize variables if not already set by tool response parsing
      handoff_requested ||= false
      workflow_completed ||= false
      target_agent ||= nil
      handoff_data = {}

      tool_calls.each do |tool_call|
        function_name = tool_call.dig("function", "name") || tool_call.dig(:function, :name)

        if function_name&.start_with?("transfer_to_")
          handoff_requested = true
          # Extract target agent from function name (e.g., "transfer_to_support" -> "Support")
          target_agent = function_name.sub("transfer_to_", "").split("_").map(&:capitalize).join
          # Parse handoff arguments if present
          arguments_str = tool_call.dig("function", "arguments") || tool_call.dig(:function, :arguments)
          if arguments_str
            begin
              handoff_data = JSON.parse(arguments_str)
            rescue JSON::ParserError
              handoff_data = {}
            end
          end
        elsif function_name == "complete_workflow"
          workflow_completed = true
        end
      end

      log_debug("Extracted agent result",
                agent: agent_name,
                handoff_requested: handoff_requested,
                target_agent: target_agent,
                workflow_completed: workflow_completed,
                tool_calls_count: tool_calls.size)

      {
        success: true,
        agent: agent_name,
        messages: messages,
        usage: usage,
        handoff_requested: handoff_requested,
        workflow_completed: workflow_completed,
        tool_calls: tool_calls,
        target_agent: target_agent,
        handoff_data: handoff_data,
        reason: handoff_data["reason"] || handoff_data[:reason]
      }
    end

    ##
    # Check if agent requested handoff
    #
    # @param agent_result [Hash] Agent result
    # @return [Boolean] True if handoff requested
    #
    def handoff_requested?(agent_result)
      agent_result[:handoff_requested] == true
    end

    ##
    # Check if workflow is completed
    #
    # @param agent_result [Hash] Agent result
    # @return [Boolean] True if workflow completed
    #
    def workflow_completed?(agent_result)
      return true if agent_result.nil?
      return true if agent_result[:completion_signal] == true
      return true if agent_result[:workflow_completed] == true
      return true if @handoff_context.shared_context[:workflow_completed] == true

      # Check if no handoff is requested and no handoffs are available
      if agent_result[:handoff_requested] == false &&
         (agent_result[:available_handoffs].nil? || agent_result[:available_handoffs].empty?)
        return true
      end

      false
    end

    ##
    # Execute handoff between agents
    #
    # @param agent_result [Hash] Current agent result
    # @return [Hash] Handoff result
    #
    def execute_handoff(agent_result)
      target_agent = agent_result[:target_agent]
      handoff_data = agent_result[:handoff_data] || {}

      # Verify target agent exists
      unless @agents.key?(target_agent)
        return {
          success: false,
          error: "Target agent '#{target_agent}' not available in agents: #{@agents.keys}"
        }
      end

      # Prepare handoff in context
      @handoff_context.set_handoff(
        target_agent: target_agent,
        data: handoff_data,
        reason: agent_result[:reason] || "Agent handoff"
      )

      # Execute the handoff
      @handoff_context.execute_handoff
    end

  end

  ##
  # Result of a complete workflow execution
  #
  class WorkflowResult

    attr_reader :success, :error, :results, :final_agent, :handoff_context, :started_at, :completed_at

    def initialize(success:, results:, error: nil, final_agent: nil, handoff_context: nil, started_at: nil, completed_at: nil)
      @success = success
      @error = error
      @results = results
      @final_agent = final_agent
      @handoff_context = handoff_context
      @started_at = started_at || Time.now
      @completed_at = completed_at || Time.now
    end

    ##
    # Get all messages from the workflow
    #
    # @return [Array<Hash>] Combined messages from all agents
    #
    def all_messages
      @results.flat_map { |result| result[:messages] || [] }
    end

    ##
    # Check if the workflow was successful
    #
    # @return [Boolean] true if successful
    #
    def success?
      @success
    end

    ##
    # Get combined usage statistics
    #
    # @return [Hash] Combined usage from all agents
    #
    def total_usage
      usage = { input_tokens: 0, output_tokens: 0, total_tokens: 0 }

      @results.each do |result|
        agent_usage = result[:usage] || {}
        usage[:input_tokens] += agent_usage[:input_tokens] || 0
        usage[:output_tokens] += agent_usage[:output_tokens] || 0
        usage[:total_tokens] += agent_usage[:total_tokens] || 0
      end

      usage
    end

    ##
    # Get final results from handoff context
    #
    # @return [Hash] Final workflow results
    #
    def final_results
      @handoff_context&.shared_context&.fetch(:final_results, {}) || {}
    end

    ##
    # Convert to hash representation
    #
    # @return [Hash] Workflow result as hash
    #
    def to_h
      {
        success: @success,
        error: @error,
        final_agent: @final_agent,
        results: @results,
        total_usage: total_usage,
        final_results: final_results
      }
    end

  end

end
