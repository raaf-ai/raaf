# frozen_string_literal: true

require_relative "base"

module RubyAIAgentsFactory
  module Guardrails
    ##
    # Output guardrails validate agent responses before returning to users
    #
    # Output guardrails check the final output of an agent to ensure it meets
    # quality, safety, and compliance requirements. They run after the agent
    # generates a response but before it's returned to the user. When a tripwire
    # is triggered, the response is blocked and an exception is raised.
    #
    # The guardrail function receives three parameters:
    # - context: RunContextWrapper with conversation state
    # - agent: The agent that generated the output
    # - agent_output: The agent's response to validate
    #
    # @example Creating a simple output guardrail
    #   guardrail = OutputGuardrail.new(
    #     ->(context, agent, output) {
    #       if output.length > 1000
    #         GuardrailFunctionOutput.new(
    #           output_info: { length: output.length, limit: 1000 },
    #           tripwire_triggered: true
    #         )
    #       else
    #         GuardrailFunctionOutput.new(tripwire_triggered: false)
    #       end
    #     },
    #     name: "length_limiter"
    #   )
    #
    # @example Using with an agent
    #   agent.add_output_guardrail(guardrail)
    #
    class OutputGuardrail
      # @!attribute [r] guardrail_function
      #   @return [Proc, Method] The validation function
      # @!attribute [r] name
      #   @return [String, nil] Optional name for identification
      attr_reader :guardrail_function, :name

      ##
      # Initialize a new output guardrail
      #
      # The guardrail function should accept three parameters:
      # - context [RunContextWrapper]: The current run context
      # - agent [Agent]: The agent that generated the output
      # - agent_output [Object]: The output to validate
      #
      # And return either:
      # - A GuardrailFunctionOutput object
      # - A boolean (true = tripwire triggered, false = safe)
      # - A hash with :output_info and :tripwire_triggered keys
      #
      # @param guardrail_function [Proc, Method] Function that validates the output
      # @param name [String, nil] Optional name for tracing and debugging
      #
      # @raise [ArgumentError] If guardrail_function doesn't respond to :call
      #
      def initialize(guardrail_function, name: nil)
        raise ArgumentError, "Guardrail function must respond to :call" unless guardrail_function.respond_to?(:call)

        @guardrail_function = guardrail_function
        @name = name
      end

      ##
      # Get the name of this guardrail
      #
      # Returns the configured name, or attempts to derive one from the
      # guardrail function's name method if available.
      #
      # @return [String] The guardrail name for identification
      #
      def get_name
        @name || (
          if @guardrail_function.respond_to?(:name)
            @guardrail_function.name.to_s
          else
            "guardrail"
          end
        )
      end

      ##
      # Run the guardrail check on agent output
      #
      # Executes the guardrail function and normalizes the output into
      # an OutputGuardrailResult. Handles various return types from the
      # guardrail function for flexibility. Includes the agent and output
      # in the result for comprehensive error reporting.
      #
      # @param context [RunContextWrapper] The current run context with conversation state
      # @param agent [Agent] The agent that generated the output
      # @param agent_output [Object] The agent's response to validate
      #
      # @return [OutputGuardrailResult] The validation result with agent context
      #
      # @example Running a check
      #   result = guardrail.run(context, agent, "Agent response text")
      #   if result.tripwire_triggered?
      #     raise OutputGuardrailTripwireTriggered.new(
      #       "Output blocked: #{result.output.output_info}",
      #       triggered_by: guardrail.get_name,
      #       content: agent_output
      #     )
      #   end
      #
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

      ##
      # Asynchronous version of run for concurrent execution
      #
      # Provides async execution when the Async gem is available,
      # otherwise falls back to synchronous execution.
      #
      # @param context [RunContextWrapper] The run context
      # @param agent [Agent] The agent that produced the output
      # @param agent_output [Object] The output to check
      #
      # @return [Async::Task, OutputGuardrailResult] Async task or direct result
      #
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

    ##
    # Builder methods for creating output guardrails with DSL-style syntax
    #
    # This module provides convenient factory methods for creating output
    # guardrails using blocks or method references. It's included in the
    # Guardrails module to provide module-level builder methods.
    #
    module OutputGuardrailBuilder
      ##
      # Create an output guardrail from a block
      #
      # Provides a DSL-style method for creating guardrails inline.
      # The block receives context, agent, and agent_output parameters.
      #
      # @param name [String, nil] Optional name for the guardrail
      # @yield [context, agent, output] Block that validates the output
      # @yieldparam context [RunContextWrapper] The run context
      # @yieldparam agent [Agent] The agent that generated the output
      # @yieldparam output [Object] The agent's output
      # @yieldreturn [GuardrailFunctionOutput, Boolean, Hash] The validation result
      #
      # @return [OutputGuardrail] The created guardrail
      #
      # @example Simple length check
      #   guardrail = output_guardrail(name: "length_check") do |context, agent, output|
      #     output.length <= 500  # false = safe, true = triggered
      #   end
      #
      # @example With detailed validation
      #   guardrail = output_guardrail do |context, agent, output|
      #     if output.match?(/\b(?:api[_-]?key|password|secret)\b/i)
      #       GuardrailFunctionOutput.new(
      #         output_info: { 
      #           reason: "Detected sensitive information",
      #           pattern_matched: true 
      #         },
      #         tripwire_triggered: true
      #       )
      #     else
      #       GuardrailFunctionOutput.new(tripwire_triggered: false)
      #     end
      #   end
      #
      def output_guardrail(name: nil, &block)
        OutputGuardrail.new(block, name: name)
      end

      ##
      # Convert a method reference to an output guardrail
      #
      # Allows using existing methods as guardrails by passing
      # a method reference obtained with Ruby's method() function.
      #
      # @param method [Method] Method reference that validates output
      # @param name [String, nil] Optional name, defaults to method name
      #
      # @return [OutputGuardrail] The created guardrail
      #
      # @example Using a quality checker class
      #   class QualityChecker
      #     def check_response_quality(context, agent, output)
      #       score = calculate_quality_score(output)
      #       
      #       if score < 0.7
      #         GuardrailFunctionOutput.new(
      #           output_info: { 
      #             quality_score: score,
      #             threshold: 0.7,
      #             issues: ["low coherence", "off-topic"]
      #           },
      #           tripwire_triggered: true
      #         )
      #       else
      #         GuardrailFunctionOutput.new(
      #           output_info: { quality_score: score },
      #           tripwire_triggered: false
      #         )
      #       end
      #     end
      #     
      #     private
      #     
      #     def calculate_quality_score(output)
      #       # Quality scoring logic
      #       0.85
      #     end
      #   end
      #
      #   checker = QualityChecker.new
      #   guardrail = output_guardrail_from_method(
      #     checker.method(:check_response_quality),
      #     name: "quality_assurance"
      #   )
      #
      def output_guardrail_from_method(method, name: nil)
        OutputGuardrail.new(method, name: name)
      end
    end

    # Include builder methods
    extend OutputGuardrailBuilder
  end
end
