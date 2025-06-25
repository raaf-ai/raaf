# frozen_string_literal: true

require_relative "base"

module OpenAIAgents
  module Guardrails
    # Input guardrails are checks that run in parallel to the agent's execution
    # They can check if input messages are off-topic or take over control if unexpected input is detected
    class InputGuardrail
      attr_reader :guardrail_function, :name

      # @param guardrail_function [Proc, Method] Function that checks the input
      # @param name [String, nil] Name of the guardrail for tracing
      def initialize(guardrail_function, name: nil)
        raise ArgumentError, "Guardrail function must respond to :call" unless guardrail_function.respond_to?(:call)

        @guardrail_function = guardrail_function
        @name = name
      end

      # Get the name of this guardrail
      # @return [String] The name or function name
      def get_name
        @name || (
          if @guardrail_function.respond_to?(:name)
            @guardrail_function.name.to_s
          else
            "guardrail"
          end
        )
      end

      # Run the guardrail check
      # @param context [RunContextWrapper] The run context
      # @param agent [Agent] The agent being run
      # @param input [String, Array] The input to check
      # @return [InputGuardrailResult] The result of the check
      def run(context, agent, input)
        output = @guardrail_function.call(context, agent, input)

        # Convert simple boolean returns to GuardrailFunctionOutput
        output = case output
                 when GuardrailFunctionOutput
                   output
                 when true, false
                   GuardrailFunctionOutput.new(tripwire_triggered: output == true)
                 when Hash
                   GuardrailFunctionOutput.new(
                     output_info: output[:output_info],
                     tripwire_triggered: output[:tripwire_triggered] || false
                   )
                 else
                   GuardrailFunctionOutput.new(output_info: output, tripwire_triggered: false)
                 end

        InputGuardrailResult.new(guardrail: self, output: output)
      rescue StandardError => e
        # Wrap errors in guardrail output
        output = GuardrailFunctionOutput.new(
          output_info: { error: e.message },
          tripwire_triggered: true
        )
        InputGuardrailResult.new(guardrail: self, output: output)
      end

      # Async version for compatibility
      def run_async(context, agent, input)
        if defined?(Async)
          Async do
            run(context, agent, input)
          end
        else
          run(context, agent, input)
        end
      end
    end

    # Decorator/builder methods for creating input guardrails
    module InputGuardrailBuilder
      # Create an input guardrail from a block or callable
      # @example
      #   guardrail = input_guardrail do |context, agent, input|
      #     # Check logic here
      #     GuardrailFunctionOutput.new(tripwire_triggered: false)
      #   end
      #
      # @example With name
      #   guardrail = input_guardrail(name: "profanity_check") do |context, agent, input|
      #     # Check logic
      #   end
      def input_guardrail(name: nil, &block)
        InputGuardrail.new(block, name: name)
      end

      # Convert a method to an input guardrail
      # @example
      #   def check_input(context, agent, input)
      #     # Check logic
      #   end
      #
      #   guardrail = input_guardrail_from_method(method(:check_input))
      def input_guardrail_from_method(method, name: nil)
        InputGuardrail.new(method, name: name)
      end
    end

    # Include builder methods
    extend InputGuardrailBuilder
  end
end
