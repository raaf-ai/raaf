# frozen_string_literal: true

module RAAF

  module Guardrails

    ##
    # Output from a guardrail validation function
    #
    # This class encapsulates the result of a guardrail's validation logic,
    # including any additional information about what was found and whether
    # a tripwire condition was met.
    #
    # @example Creating a guardrail output
    #   output = GuardrailFunctionOutput.new(
    #     output_info: { detected_pii: ["SSN", "email"], redacted_count: 2 },
    #     tripwire_triggered: true
    #   )
    #
    class GuardrailFunctionOutput

      # @!attribute [r] output_info
      #   @return [Object] Additional information about the validation result
      # @!attribute [r] tripwire_triggered
      #   @return [Boolean] Whether the tripwire condition was met
      attr_reader :output_info, :tripwire_triggered

      ##
      # Initialize a new guardrail function output
      #
      # @param output_info [Object] Optional information about the guardrail's findings
      # @param tripwire_triggered [Boolean] Whether the tripwire was triggered
      #
      def initialize(output_info: nil, tripwire_triggered: false)
        @output_info = output_info
        @tripwire_triggered = tripwire_triggered
      end

      ##
      # Convert to hash representation
      #
      # @return [Hash] Hash with output_info and tripwire_triggered keys
      #
      def to_h
        {
          output_info: @output_info,
          tripwire_triggered: @tripwire_triggered
        }
      end

    end

    ##
    # Result of running an input guardrail
    #
    # This class wraps the guardrail that was executed along with its output,
    # providing a complete picture of the validation that occurred.
    #
    class InputGuardrailResult

      # @!attribute [r] guardrail
      #   @return [InputGuardrail] The guardrail that was run
      # @!attribute [r] output
      #   @return [GuardrailFunctionOutput] The validation result
      attr_reader :guardrail, :output

      ##
      # Initialize a new input guardrail result
      #
      # @param guardrail [InputGuardrail] The guardrail that was run
      # @param output [GuardrailFunctionOutput] The output of the guardrail function
      #
      def initialize(guardrail:, output:)
        @guardrail = guardrail
        @output = output
      end

      ##
      # Check if the tripwire was triggered
      #
      # @return [Boolean] true if tripwire was triggered
      #
      def tripwire_triggered?
        @output.tripwire_triggered
      end

    end

    ##
    # Result of running an output guardrail
    #
    # This class extends InputGuardrailResult with additional context about
    # the agent and its output that was validated.
    #
    class OutputGuardrailResult

      # @!attribute [r] guardrail
      #   @return [OutputGuardrail] The guardrail that was run
      # @!attribute [r] agent
      #   @return [Agent] The agent whose output was validated
      # @!attribute [r] agent_output
      #   @return [Object] The actual output from the agent
      # @!attribute [r] output
      #   @return [GuardrailFunctionOutput] The validation result
      attr_reader :guardrail, :agent, :agent_output, :output

      ##
      # Initialize a new output guardrail result
      #
      # @param guardrail [OutputGuardrail] The guardrail that was run
      # @param agent [Agent] The agent that was checked
      # @param agent_output [Object] The output of the agent
      # @param output [GuardrailFunctionOutput] The output of the guardrail function
      #
      def initialize(guardrail:, agent:, agent_output:, output:)
        @guardrail = guardrail
        @agent = agent
        @agent_output = agent_output
        @output = output
      end

      ##
      # Check if the tripwire was triggered
      #
      # @return [Boolean] true if tripwire was triggered
      #
      def tripwire_triggered?
        @output.tripwire_triggered
      end

    end

  end

end
