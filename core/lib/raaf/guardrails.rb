# frozen_string_literal: true

module RAAF
  module Guardrails
    ##
    # Base error class for guardrail violations
    class GuardrailError < RAAF::Error; end

    ##
    # Raised when an input guardrail is triggered
    class InputGuardrailTripwireTriggered < GuardrailError
      attr_reader :triggered_by, :content, :metadata

      def initialize(message, triggered_by: nil, content: nil, metadata: nil)
        super(message)
        @triggered_by = triggered_by
        @content = content
        @metadata = metadata
      end
    end

    ##
    # Raised when an output guardrail is triggered
    class OutputGuardrailTripwireTriggered < GuardrailError
      attr_reader :triggered_by, :content, :metadata

      def initialize(message, triggered_by: nil, content: nil, metadata: nil)
        super(message)
        @triggered_by = triggered_by
        @content = content
        @metadata = metadata
      end
    end

    ##
    # Result object for guardrail execution
    class GuardrailResult
      attr_accessor :output, :tripwire_triggered

      def initialize(output: nil, tripwire_triggered: false)
        @output = output
        @tripwire_triggered = tripwire_triggered
      end

      def tripwire_triggered?
        @tripwire_triggered
      end

      ##
      # Output wrapper for guardrail results
      class Output
        attr_accessor :output_info

        def initialize(output_info: nil)
          @output_info = output_info || {}
        end
      end
    end

    ##
    # Base class for input guardrails
    class InputGuardrail
      attr_reader :name, :instructions, :validation_proc

      def initialize(name: nil, instructions: nil, &block)
        @name = name || self.class.name
        @instructions = instructions
        @validation_proc = block
      end

      def get_name
        @name
      end

      def run(context_wrapper, agent, input)
        result = GuardrailResult.new
        result.output = GuardrailResult::Output.new

        if @validation_proc
          validation_result = @validation_proc.call(input)
          
          if validation_result.is_a?(String)
            # String result means the input was blocked
            result.tripwire_triggered = true
            result.output.output_info = { blocked_reason: validation_result }
          elsif validation_result == false
            # False means input was blocked
            result.tripwire_triggered = true
            result.output.output_info = { blocked_reason: "Input blocked by guardrail" }
          end
          # nil or true means input is allowed
        end

        result
      end
    end

    ##
    # Base class for output guardrails
    class OutputGuardrail
      attr_reader :name, :instructions, :filter_proc

      def initialize(name: nil, instructions: nil, &block)
        @name = name || self.class.name
        @instructions = instructions
        @filter_proc = block
      end

      def get_name
        @name
      end

      def run(context_wrapper, agent, output)
        result = GuardrailResult.new
        result.output = GuardrailResult::Output.new

        if @filter_proc
          filtered_output = @filter_proc.call(output)
          
          if filtered_output != output
            # Output was modified, return the filtered version
            result.output.output_info = { original_output: output, filtered_output: filtered_output }
          end
        end

        result
      end
    end

    ##
    # Simple length-based input guardrail
    class LengthInputGuardrail < InputGuardrail
      def initialize(max_length:, name: "LengthGuardrail")
        super(name: name, instructions: "Block inputs longer than #{max_length} characters") do |input|
          if input.length > max_length
            "Input too long: #{input.length} characters (max: #{max_length})"
          else
            nil
          end
        end
      end
    end

    ##
    # Simple profanity filter output guardrail
    class ProfanityOutputGuardrail < OutputGuardrail
      PROFANITY_WORDS = %w[damn hell].freeze

      def initialize(name: "ProfanityFilter")
        super(name: name, instructions: "Filter profanity from output") do |output|
          filtered = output.dup
          PROFANITY_WORDS.each do |word|
            filtered.gsub!(/\b#{Regexp.escape(word)}\b/i, "[filtered]")
          end
          filtered
        end
      end
    end
  end
end