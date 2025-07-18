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
      # Set starting agent
      first_agent = starting_agent || @agents.keys.first
      @handoff_context.instance_variable_set(:@current_agent, first_agent)

      log_info("Starting workflow", {
        starting_agent: first_agent,
        total_agents: @agents.size,
        message: initial_message
      })

      results = []
      current_message = initial_message

      # Execute workflow steps
      loop do
        current_agent_name = @handoff_context.current_agent
        
        # Get current agent
        agent_config = @agents[current_agent_name]
        unless agent_config
          return WorkflowResult.new(
            success: false,
            error: "Agent '#{current_agent_name}' not found",
            results: results
          )
        end

        # Run current agent
        agent_result = run_agent(agent_config, current_message)
        results << agent_result

        # Check for errors
        if agent_result[:success] == false
          return WorkflowResult.new(
            success: false,
            error: agent_result[:error],
            results: results
          )
        end

        # Check for workflow completion
        if workflow_completed?(agent_result)
          return WorkflowResult.new(
            success: true,
            results: results,
            final_agent: current_agent_name,
            handoff_context: @handoff_context
          )
        end

        # Check for handoff request
        if handoff_requested?(agent_result)
          handoff_result = execute_handoff(agent_result)
          
          if handoff_result[:success] == false
            return WorkflowResult.new(
              success: false,
              error: handoff_result[:error],
              results: results
            )
          end

          # Prepare message for next agent
          current_message = @handoff_context.build_handoff_message
          log_info("Handoff executed", handoff_result)
        else
          # No handoff requested but workflow not completed
          return WorkflowResult.new(
            success: false,
            error: "Agent '#{current_agent_name}' did not request handoff or complete workflow",
            results: results
          )
        end

        # Safety check to prevent infinite loops
        if results.size > 10
          return WorkflowResult.new(
            success: false,
            error: "Maximum workflow steps exceeded",
            results: results
          )
        end
      end
    end

    private

    ##
    # Run a single agent with handoff tools
    #
    # @param agent_config [Hash] Agent configuration
    # @param message [String] Message for the agent
    # @return [Hash] Agent execution result
    #
    def run_agent(agent_config, message)
      agent_name = agent_config[:name]
      agent_class = agent_config[:class]
      handoff_tools = agent_config[:handoff_tools] || []

      log_info("Running agent", {
        agent: agent_name,
        message_length: message.length,
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

      # Run agent
      runner = Runner.new(agent: agent, provider: @provider)
      result = runner.run(message)

      # Extract handoff information from result
      extract_agent_result(result, agent_name)
    end

    ##
    # Extract structured result from agent run
    #
    # @param result [RunResult] Agent run result
    # @param agent_name [String] Agent name
    # @return [Hash] Structured result
    #
    def extract_agent_result(result, agent_name)
      last_message = result.messages.last
      
      # Check for tool calls in the last message
      tool_calls = last_message[:tool_calls] || []
      
      handoff_requested = false
      workflow_completed = false
      
      tool_calls.each do |tool_call|
        function_name = tool_call.dig("function", "name")
        
        if function_name&.start_with?("handoff_to_")
          handoff_requested = true
        elsif function_name == "complete_workflow"
          workflow_completed = true
        end
      end

      {
        success: true,
        agent: agent_name,
        messages: result.messages,
        usage: result.usage,
        handoff_requested: handoff_requested,
        workflow_completed: workflow_completed,
        tool_calls: tool_calls
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
      agent_result[:workflow_completed] == true ||
        @handoff_context.shared_context[:workflow_completed] == true
    end

    ##
    # Execute handoff between agents
    #
    # @param agent_result [Hash] Current agent result
    # @return [Hash] Handoff result
    #
    def execute_handoff(agent_result)
      unless @handoff_context.handoff_pending?
        return {
          success: false,
          error: "No handoff prepared despite handoff request"
        }
      end

      # Execute the handoff
      handoff_result = @handoff_context.execute_handoff

      # Verify target agent exists
      target_agent = handoff_result[:current_agent]
      unless @agents.key?(target_agent)
        return {
          success: false,
          error: "Target agent '#{target_agent}' not found in orchestrator"
        }
      end

      handoff_result
    end
  end

  ##
  # Result of a complete workflow execution
  #
  class WorkflowResult
    attr_reader :success, :error, :results, :final_agent, :handoff_context

    def initialize(success:, results:, error: nil, final_agent: nil, handoff_context: nil)
      @success = success
      @error = error
      @results = results
      @final_agent = final_agent
      @handoff_context = handoff_context
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