# frozen_string_literal: true

require_relative "base"

module RAAF
  module Guardrails
    ##
    # GuidelineGuardrail verifies agent responses against behavioral guidelines
    #
    # This guardrail integrates RAAF's Parlant-inspired behavioral guidelines system
    # with the guardrails framework. It runs self-critique on agent responses to
    # verify compliance with applicable guidelines.
    #
    # The guardrail can be configured to either:
    # - Block responses that violate guidelines (strict mode)
    # - Warn about violations but allow responses (permissive mode)
    # - Log violations for monitoring without blocking (monitor mode)
    #
    # @example Basic usage (strict mode)
    #   guardrail = GuidelineGuardrail.new(
    #     llm_provider: provider,
    #     mode: :strict
    #   )
    #   agent.add_output_guardrail(guardrail)
    #
    # @example Permissive mode with logging
    #   guardrail = GuidelineGuardrail.new(
    #     llm_provider: provider,
    #     mode: :permissive,
    #     on_violation: ->(result) { Rails.logger.warn "Guideline violation: #{result}" }
    #   )
    #
    class GuidelineGuardrail
      MODES = %i[strict permissive monitor].freeze
      DEFAULT_MODE = :strict

      attr_reader :llm_provider, :mode, :name, :critique_model

      ##
      # Initialize a new guideline guardrail
      #
      # @param llm_provider [Object] LLM provider for self-critique requests
      # @param mode [Symbol] Operation mode (:strict, :permissive, :monitor)
      # @param critique_model [String] Model to use for critique (default: gpt-4o-mini)
      # @param timeout [Integer] Timeout for critique requests in seconds
      # @param name [String] Name for this guardrail instance
      # @param on_violation [Proc] Callback when violations are detected
      #
      def initialize(
        llm_provider:,
        mode: DEFAULT_MODE,
        critique_model: nil,
        timeout: 30,
        name: "guideline_compliance",
        on_violation: nil
      )
        @llm_provider = llm_provider
        @mode = validate_mode(mode)
        @critique_model = critique_model || "gpt-4o-mini"
        @timeout = timeout
        @name = name
        @on_violation = on_violation
      end

      ##
      # Get the name of this guardrail
      #
      # @return [String] The guardrail name
      #
      def get_name
        @name
      end

      ##
      # Run the guardrail check on agent output
      #
      # Evaluates the agent's response against applicable guidelines using
      # the SelfCritiqueEngine. Returns a result indicating whether the
      # response complies with all guidelines.
      #
      # @param context [RunContextWrapper] The current run context
      # @param agent [Agent] The agent that generated the output
      # @param agent_output [Object] The agent's response to validate
      #
      # @return [OutputGuardrailResult] The validation result
      #
      def run(context, agent, agent_output)
        # Check if agent has guidelines
        unless agent.class.respond_to?(:has_guidelines?) && agent.class.has_guidelines?
          return safe_result(agent, agent_output)
        end

        # Get applicable guidelines
        guideline_engine = RAAF::DSL::Guidelines::GuidelineEngine.new(
          agent: agent,
          llm_provider: @llm_provider
        )

        # Extract context hash from RunContextWrapper if needed
        context_hash = extract_context(context)
        input = extract_input(context)

        applicable_guidelines = guideline_engine.applicable_guidelines(context_hash, input)

        # If no guidelines apply, response is safe
        return safe_result(agent, agent_output) if applicable_guidelines.empty?

        # Run self-critique
        critique_engine = RAAF::DSL::Guidelines::SelfCritiqueEngine.new(
          llm_provider: @llm_provider,
          critique_model: @critique_model,
          timeout: @timeout
        )

        critique_result = critique_engine.critique(
          output: agent_output,
          guidelines: applicable_guidelines,
          context: context_hash
        )

        # Handle based on critique result and mode
        build_guardrail_result(agent, agent_output, critique_result, applicable_guidelines)
      rescue StandardError => e
        RAAF.logger.error "[GuidelineGuardrail] Error during critique: #{e.message}"
        RAAF.logger.error e.backtrace.first(5).join("\n") if e.backtrace

        # Fail open on errors - allow response through
        safe_result(agent, agent_output, error: e.message)
      end

      ##
      # Async version of run for concurrent execution
      #
      def run_async(context, agent, agent_output)
        if defined?(Async)
          Async { run(context, agent, agent_output) }
        else
          run(context, agent, agent_output)
        end
      end

      private

      def validate_mode(mode)
        mode_sym = mode.to_sym
        unless MODES.include?(mode_sym)
          raise ArgumentError, "Invalid mode: #{mode}. Must be one of: #{MODES.join(', ')}"
        end

        mode_sym
      end

      def extract_context(context)
        case context
        when Hash
          context
        when RAAF::ContextVariables, RAAF::DSL::ContextVariables
          context.to_h
        else
          context.respond_to?(:to_h) ? context.to_h : {}
        end
      rescue StandardError
        {}
      end

      def extract_input(context)
        case context
        when Hash
          context[:input] || context[:message] || ""
        else
          context.respond_to?(:input) ? context.input : ""
        end
      rescue StandardError
        ""
      end

      def safe_result(agent, agent_output, error: nil)
        output = GuardrailFunctionOutput.new(
          output_info: {
            guidelines_checked: 0,
            passed: true,
            error: error
          },
          tripwire_triggered: false
        )

        OutputGuardrailResult.new(
          guardrail: self,
          agent: agent,
          agent_output: agent_output,
          output: output
        )
      end

      def build_guardrail_result(agent, agent_output, critique_result, guidelines)
        # Call violation callback if violations detected
        if critique_result.failed? && @on_violation
          @on_violation.call(critique_result)
        end

        # Log violations
        if critique_result.failed?
          log_violations(critique_result, guidelines)
        end

        # Determine if tripwire should be triggered based on mode
        tripwire_triggered = case @mode
                             when :strict
                               critique_result.failed?
                             when :permissive
                               false # Never block in permissive mode
                             when :monitor
                               false # Never block in monitor mode
                             else
                               critique_result.failed?
                             end

        output = GuardrailFunctionOutput.new(
          output_info: {
            guidelines_checked: guidelines.size,
            guidelines_names: guidelines.map(&:name),
            passed: critique_result.passed?,
            violations: critique_result.violations,
            violation_count: critique_result.violation_count,
            mode: @mode,
            evaluation_duration_ms: critique_result.evaluation_duration_ms
          },
          tripwire_triggered: tripwire_triggered
        )

        OutputGuardrailResult.new(
          guardrail: self,
          agent: agent,
          agent_output: agent_output,
          output: output
        )
      end

      def log_violations(critique_result, guidelines)
        RAAF.logger.warn "[GuidelineGuardrail] #{critique_result.violation_count} guideline violation(s) detected"

        critique_result.violations.each do |violation|
          RAAF.logger.warn "  - [#{violation[:guideline_name]}] #{violation[:reason]}"
        end
      end
    end

    ##
    # Builder methods for GuidelineGuardrail
    #
    module GuidelineGuardrailBuilder
      ##
      # Create a guideline guardrail with the given configuration
      #
      # @param llm_provider [Object] LLM provider for critique
      # @param mode [Symbol] Operation mode
      # @param name [String] Guardrail name
      # @param kwargs [Hash] Additional options
      #
      # @return [GuidelineGuardrail]
      #
      def guideline_guardrail(llm_provider:, mode: :strict, name: "guideline_compliance", **kwargs)
        GuidelineGuardrail.new(
          llm_provider: llm_provider,
          mode: mode,
          name: name,
          **kwargs
        )
      end
    end

    extend GuidelineGuardrailBuilder
  end
end
