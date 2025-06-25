# frozen_string_literal: true

require_relative "../errors"

module OpenAIAgents
  module Guardrails
    # Base exceptions for guardrails
    class GuardrailError < Error; end
    class TripwireException < GuardrailError
      attr_reader :triggered_by, :content, :metadata

      def initialize(message, triggered_by:, content: nil, metadata: {})
        super(message)
        @triggered_by = triggered_by
        @content = content
        @metadata = metadata
      end
    end
    
    class InputGuardrailTripwireTriggered < TripwireException; end
    class OutputGuardrailTripwireTriggered < TripwireException; end

    # Output from a guardrail function
    class GuardrailFunctionOutput
      attr_reader :output_info, :tripwire_triggered

      # @param output_info [Object] Optional information about the guardrail's output
      # @param tripwire_triggered [Boolean] Whether the tripwire was triggered
      def initialize(output_info: nil, tripwire_triggered: false)
        @output_info = output_info
        @tripwire_triggered = tripwire_triggered
      end

      def to_h
        {
          output_info: @output_info,
          tripwire_triggered: @tripwire_triggered
        }
      end
    end

    # Result of running an input guardrail
    class InputGuardrailResult
      attr_reader :guardrail, :output

      # @param guardrail [InputGuardrail] The guardrail that was run
      # @param output [GuardrailFunctionOutput] The output of the guardrail function
      def initialize(guardrail:, output:)
        @guardrail = guardrail
        @output = output
      end

      def tripwire_triggered?
        @output.tripwire_triggered
      end
    end

    # Result of running an output guardrail
    class OutputGuardrailResult
      attr_reader :guardrail, :agent, :agent_output, :output

      # @param guardrail [OutputGuardrail] The guardrail that was run
      # @param agent [Agent] The agent that was checked
      # @param agent_output [Object] The output of the agent
      # @param output [GuardrailFunctionOutput] The output of the guardrail function
      def initialize(guardrail:, agent:, agent_output:, output:)
        @guardrail = guardrail
        @agent = agent
        @agent_output = agent_output
        @output = output
      end

      def tripwire_triggered?
        @output.tripwire_triggered
      end
    end
  end
end