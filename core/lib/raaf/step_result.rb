# frozen_string_literal: true

module RAAF

  ##
  # Immutable result of a single execution step
  #
  # This class represents the complete result of processing one step in an agent conversation,
  # including the original input, model response, generated items, and the next action to take.
  # Using immutable data structures prevents state mutation bugs that cause brittleness.
  #
  # @example Creating a step result
  #   step_result = StepResult.new(
  #     original_input: "Hello",
  #     model_response: response_object,
  #     pre_step_items: previous_items,
  #     new_step_items: current_items,
  #     next_step: NextStepRunAgain.new
  #   )
  #
  # @example Accessing combined items
  #   all_items = step_result.generated_items
  #
  StepResult = Data.define(
    :original_input,      # String | Array<Hash> - The input before run() was called
    :model_response,      # Hash - The model response for the current step
    :pre_step_items,      # Array<Hash> - Items generated before current step
    :new_step_items,      # Array<Hash> - Items generated during current step
    :next_step # NextStep* - The next action to take
  ) do
    ##
    # Get all items generated during the agent run
    #
    # Combines pre_step_items and new_step_items to provide the complete
    # list of items generated after the original_input.
    #
    # @return [Array<Hash>] All generated items
    def generated_items
      pre_step_items + new_step_items
    end

    ##
    # Check if this step result indicates the conversation should continue
    #
    # @return [Boolean] true if should continue, false if final output
    def should_continue?
      next_step.is_a?(NextStepRunAgain)
    end

    ##
    # Check if this step result indicates a handoff occurred
    #
    # @return [Boolean] true if handoff occurred
    def handoff_occurred?
      next_step.is_a?(NextStepHandoff)
    end

    ##
    # Check if this step result indicates final output
    #
    # @return [Boolean] true if final output reached
    def final_output?
      next_step.is_a?(NextStepFinalOutput)
    end

    ##
    # Get the final output if this is a final output step
    #
    # @return [Object, nil] The final output or nil if not final
    def final_output
      return nil unless final_output?

      next_step.output
    end

    ##
    # Get the handoff target agent if this is a handoff step
    #
    # @return [Agent, nil] The target agent or nil if not handoff
    def handoff_agent
      return nil unless handoff_occurred?

      next_step.new_agent
    end
  end

  ##
  # Next step: Continue with another turn
  #
  NextStepRunAgain = Data.define do
    def to_s
      "NextStepRunAgain"
    end
  end

  ##
  # Next step: Handoff to another agent
  #
  NextStepHandoff = Data.define(:new_agent) do
    def to_s
      "NextStepHandoff(agent: #{new_agent&.name})"
    end
  end

  ##
  # Next step: Return final output
  #
  NextStepFinalOutput = Data.define(:output) do
    def to_s
      "NextStepFinalOutput(#{output&.class&.name})"
    end
  end

end
