# frozen_string_literal: true

require_relative "step_processor"
require_relative "step_result" 
require_relative "logging"

module RAAF

  ##
  # Unified step executor for RAAF execution
  #
  # This class provides the primary execution interface for step processing,
  # replacing all legacy tool/handoff coordination with atomic step processing.
  #
  # Usage in Runner:
  #   executor = UnifiedStepExecutor.new(runner: self)
  #   result = executor.execute_step(model_response, agent, context_wrapper, config)
  #
  class UnifiedStepExecutor

    include Logger

    attr_reader :runner, :step_processor

    ##
    # Initialize unified step executor
    #
    # @param runner [Runner] The runner instance for integration
    #
    def initialize(runner:)
      @runner = runner
      @step_processor = StepProcessor.new
    end

    ##
    # Execute a step using unified processing
    #
    # This method provides atomic step processing for all agent execution,
    # handling tools, handoffs, and final output determination.
    #
    # @param model_response [Hash] Raw model response from provider
    # @param agent [Agent] Current agent
    # @param context_wrapper [RunContextWrapper] Current context
    # @param config [RunConfig] Current configuration
    # @param original_input [String, Array<Hash>] Original input to run
    # @param pre_step_items [Array<Hash>] Items before this step
    # @return [StepResult] Complete step result
    #
    def execute_step(model_response:, agent:, context_wrapper:, config:, 
                    original_input: "", pre_step_items: [])
      
      log_debug("🚀 STEP: Starting step execution", agent: agent.name)

      begin
        # Use StepProcessor for atomic step processing  
        step_result = @step_processor.execute_step(
          original_input: original_input,
          pre_step_items: pre_step_items,
          model_response: model_response,
          agent: agent,
          context_wrapper: context_wrapper,
          runner: @runner,
          config: config
        )

        # Reset tool choice if needed
        @step_processor.maybe_reset_tool_choice(agent)

        log_debug("✅ STEP: Step execution completed", 
                  next_step: step_result.next_step.class.name,
                  items_generated: step_result.new_step_items.size)

        step_result

      rescue => error
        log_exception(error, message: "❌ STEP: Step execution failed", agent: agent.name)
        
        # Create error step result
        error_step_result = create_error_step_result(
          original_input, model_response, pre_step_items, error
        )

        error_step_result
      end
    end

    ##
    # Convert StepResult to Runner-compatible format
    #
    # Converts StepResult to the format expected by the Runner's execution loop.
    #
    # @param step_result [StepResult] Step result from unified processing
    # @return [Hash] Runner-compatible format result
    #
    def to_runner_format(step_result)
      {
        done: step_result.final_output?,
        handoff: step_result.handoff_occurred? ? { assistant: step_result.handoff_agent&.name } : nil,
        generated_items: step_result.new_step_items,
        final_output: step_result.final_output,
        should_continue: step_result.should_continue?
      }
    end

    private

    ##
    # Create error step result for failed executions
    #
    def create_error_step_result(original_input, model_response, pre_step_items, error)
      error_item = {
        type: "message",
        role: "assistant", 
        content: "Error processing step: #{error.message}",
        agent: "system"
      }

      StepResult.new(
        original_input: original_input,
        model_response: model_response,
        pre_step_items: pre_step_items,
        new_step_items: [error_item],
        next_step: NextStepFinalOutput.new("Error: #{error.message}")
      )
    end

  end

end