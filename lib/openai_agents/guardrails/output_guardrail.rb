# frozen_string_literal: true

require_relative "base"

module OpenAIAgents
  module Guardrails
    # Output guardrails check the final output of an agent
    # They can validate if the output passes certain criteria
    class OutputGuardrail
      attr_reader :guardrail_function, :name

      # @param guardrail_function [Proc, Method] Function that checks the output
      # @param name [String, nil] Name of the guardrail for tracing
      def initialize(guardrail_function, name: nil)
        unless guardrail_function.respond_to?(:call)
          raise ArgumentError, "Guardrail function must respond to :call"
        end
        
        @guardrail_function = guardrail_function
        @name = name
      end

      # Get the name of this guardrail
      # @return [String] The name or function name
      def get_name
        @name || (
          @guardrail_function.respond_to?(:name) ? 
          @guardrail_function.name.to_s : 
          "guardrail"
        )
      end

      # Run the guardrail check
      # @param context [RunContextWrapper] The run context
      # @param agent [Agent] The agent that produced the output
      # @param agent_output [Object] The output to check
      # @return [OutputGuardrailResult] The result of the check
      def run(context, agent, agent_output)
        output = @guardrail_function.call(context, agent, agent_output)
        
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

        OutputGuardrailResult.new(
          guardrail: self, 
          agent: agent,
          agent_output: agent_output,
          output: output
        )
      rescue StandardError => e
        # Wrap errors in guardrail output
        output = GuardrailFunctionOutput.new(
          output_info: { error: e.message },
          tripwire_triggered: true
        )
        OutputGuardrailResult.new(
          guardrail: self,
          agent: agent,
          agent_output: agent_output,
          output: output
        )
      end

      # Async version for compatibility
      def run_async(context, agent, agent_output)
        if defined?(Async)
          Async do
            run(context, agent, agent_output)
          end
        else
          run(context, agent, agent_output)
        end
      end
    end

    # Decorator/builder methods for creating output guardrails
    module OutputGuardrailBuilder
      # Create an output guardrail from a block or callable
      # @example
      #   guardrail = output_guardrail do |context, agent, output|
      #     # Check logic here
      #     GuardrailFunctionOutput.new(tripwire_triggered: false)
      #   end
      #
      # @example With name
      #   guardrail = output_guardrail(name: "length_check") do |context, agent, output|
      #     # Check logic
      #   end
      def output_guardrail(name: nil, &block)
        OutputGuardrail.new(block, name: name)
      end

      # Convert a method to an output guardrail
      # @example
      #   def check_output(context, agent, output)
      #     # Check logic
      #   end
      #   
      #   guardrail = output_guardrail_from_method(method(:check_output))
      def output_guardrail_from_method(method, name: nil)
        OutputGuardrail.new(method, name: name)
      end
    end

    # Include builder methods
    extend OutputGuardrailBuilder
  end
end