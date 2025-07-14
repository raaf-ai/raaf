# frozen_string_literal: true

require_relative "base"

module OpenAIAgents
  module Guardrails
    ##
    # Input guardrails validate user messages before agent processing
    #
    # Input guardrails are checks that run in parallel to the agent's execution.
    # They can validate user inputs for safety, appropriateness, and compliance
    # with business rules. When a tripwire is triggered, execution halts immediately.
    #
    # The guardrail function receives three parameters:
    # - context: RunContextWrapper with conversation state
    # - agent: The agent that will process the input
    # - input: The user's input message(s)
    #
    # @example Creating a simple input guardrail
    #   guardrail = InputGuardrail.new(
    #     ->(context, agent, input) {
    #       if input.include?("password")
    #         GuardrailFunctionOutput.new(
    #           output_info: { reason: "Detected password in input" },
    #           tripwire_triggered: true
    #         )
    #       else
    #         GuardrailFunctionOutput.new(tripwire_triggered: false)
    #       end
    #     },
    #     name: "password_detector"
    #   )
    #
    # @example Using with an agent
    #   agent.add_input_guardrail(guardrail)
    #
    class InputGuardrail
      # @!attribute [r] guardrail_function
      #   @return [Proc, Method] The validation function
      # @!attribute [r] name
      #   @return [String, nil] Optional name for identification
      attr_reader :guardrail_function, :name

      ##
      # Initialize a new input guardrail
      #
      # The guardrail function should accept three parameters:
      # - context [RunContextWrapper]: The current run context
      # - agent [Agent]: The agent that will process the input
      # - input [String, Array]: The user input to validate
      #
      # And return either:
      # - A GuardrailFunctionOutput object
      # - A boolean (true = tripwire triggered, false = safe)
      # - A hash with :output_info and :tripwire_triggered keys
      #
      # @param guardrail_function [Proc, Method] Function that validates the input
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
      # Run the guardrail check on user input
      #
      # Executes the guardrail function and normalizes the output into
      # an InputGuardrailResult. Handles various return types from the
      # guardrail function for flexibility.
      #
      # @param context [RunContextWrapper] The current run context with conversation state
      # @param agent [Agent] The agent that will process the input
      # @param input [String, Array] The user input to validate
      #
      # @return [InputGuardrailResult] The validation result
      #
      # @example Running a check
      #   result = guardrail.run(context, agent, "Check this input")
      #   if result.tripwire_triggered?
      #     raise InputGuardrailTripwireTriggered.new(
      #       "Input blocked",
      #       triggered_by: guardrail.get_name
      #     )
      #   end
      #
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

      ##
      # Asynchronous version of run for concurrent execution
      #
      # Provides async execution when the Async gem is available,
      # otherwise falls back to synchronous execution.
      #
      # @param context [RunContextWrapper] The run context
      # @param agent [Agent] The agent being run
      # @param input [String, Array] The input to check
      #
      # @return [Async::Task, InputGuardrailResult] Async task or direct result
      #
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

    ##
    # Builder methods for creating input guardrails with DSL-style syntax
    #
    # This module provides convenient factory methods for creating input
    # guardrails using blocks or method references. It's included in the
    # Guardrails module to provide module-level builder methods.
    #
    module InputGuardrailBuilder
      ##
      # Create an input guardrail from a block
      #
      # Provides a DSL-style method for creating guardrails inline.
      # The block receives context, agent, and input parameters.
      #
      # @param name [String, nil] Optional name for the guardrail
      # @yield [context, agent, input] Block that validates the input
      # @yieldparam context [RunContextWrapper] The run context
      # @yieldparam agent [Agent] The agent processing the input
      # @yieldparam input [String, Array] The user input
      # @yieldreturn [GuardrailFunctionOutput, Boolean, Hash] The validation result
      #
      # @return [InputGuardrail] The created guardrail
      #
      # @example Simple boolean return
      #   guardrail = input_guardrail do |context, agent, input|
      #     !input.include?("banned_word")  # false = safe, true = triggered
      #   end
      #
      # @example With detailed output
      #   guardrail = input_guardrail(name: "profanity_check") do |context, agent, input|
      #     if contains_profanity?(input)
      #       GuardrailFunctionOutput.new(
      #         output_info: { detected_words: ["word1", "word2"] },
      #         tripwire_triggered: true
      #       )
      #     else
      #       GuardrailFunctionOutput.new(tripwire_triggered: false)
      #     end
      #   end
      #
      def input_guardrail(name: nil, &block)
        InputGuardrail.new(block, name: name)
      end

      ##
      # Convert a method reference to an input guardrail
      #
      # Allows using existing methods as guardrails by passing
      # a method reference obtained with Ruby's method() function.
      #
      # @param method [Method] Method reference that validates input
      # @param name [String, nil] Optional name, defaults to method name
      #
      # @return [InputGuardrail] The created guardrail
      #
      # @example Using an instance method
      #   class SecurityChecker
      #     def check_sql_injection(context, agent, input)
      #       if input.match?(/('|(--|;)|(\*|%))/i)
      #         GuardrailFunctionOutput.new(
      #           output_info: { threat: "SQL injection attempt" },
      #           tripwire_triggered: true
      #         )
      #       else
      #         GuardrailFunctionOutput.new(tripwire_triggered: false)
      #       end
      #     end
      #   end
      #
      #   checker = SecurityChecker.new
      #   guardrail = input_guardrail_from_method(
      #     checker.method(:check_sql_injection)
      #   )
      #
      # @example Using a module method
      #   module Validators
      #     def self.check_input(context, agent, input)
      #       # Validation logic
      #       GuardrailFunctionOutput.new(tripwire_triggered: false)
      #     end
      #   end
      #
      #   guardrail = input_guardrail_from_method(
      #     Validators.method(:check_input),
      #     name: "custom_validator"
      #   )
      #
      def input_guardrail_from_method(method, name: nil)
        InputGuardrail.new(method, name: name)
      end
    end

    # Include builder methods
    extend InputGuardrailBuilder
  end
end
