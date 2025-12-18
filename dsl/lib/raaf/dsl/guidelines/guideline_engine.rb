# frozen_string_literal: true

require "concurrent"
require_relative "guideline"
require_relative "guideline_result"

module RAAF
  module DSL
    module Guidelines
      # GuidelineEngine matches guidelines to context/input and builds constraint text
      #
      # The engine implements a hybrid matching strategy:
      # 1. Fast rule-based matching (Regex, Keyword, Schema, Proc conditions)
      # 2. LLM-based fallback for complex conditions that can't be evaluated programmatically
      #
      # @example Basic usage
      #   engine = GuidelineEngine.new(agent: my_agent)
      #   applicable = engine.applicable_guidelines(context, input)
      #   constraint_text = engine.build_constraint_text(applicable)
      #
      # @example With LLM provider for fallback conditions
      #   engine = GuidelineEngine.new(agent: my_agent, llm_provider: provider)
      #   applicable = engine.applicable_guidelines(context, input)
      #
      class GuidelineEngine
        attr_reader :agent, :llm_provider

        # @param agent [RAAF::DSL::Agent] The agent instance to evaluate guidelines for
        # @param llm_provider [Object, nil] Optional LLM provider for LLMCondition evaluation
        # @param cache_enabled [Boolean] Whether to cache condition evaluations (default: true)
        def initialize(agent:, llm_provider: nil, cache_enabled: true)
          @agent = agent
          @llm_provider = llm_provider
          @cache_enabled = cache_enabled
          @cache = Concurrent::Map.new if cache_enabled
        end

        # Find all guidelines that apply to the given context and input
        #
        # @param context [Hash] The execution context (agent context variables)
        # @param input [String, Hash] The user input or message
        # @return [Array<Guideline>] Applicable guidelines sorted by priority
        def applicable_guidelines(context, input)
          return [] unless @agent.class.has_guidelines?

          execution_log = GuidelineExecutionLog.new(agent_name: @agent.class.agent_name)

          applicable = @agent.class.agent_guidelines.select do |guideline|
            match_result = evaluate_guideline(guideline, context, input)

            execution_log.add_match_result(
              guideline.match_result(matched: match_result == true, match_reason: match_result.to_s)
            )

            match_result == true
          end

          # Sort by priority (critical > high > normal > low)
          sorted = applicable.sort_by(&:priority_order)

          execution_log.complete!
          log_execution(execution_log) if sorted.any?

          sorted
        end

        # Build constraint text to inject into the agent's prompt
        #
        # @param guidelines [Array<Guideline>] Guidelines to include in constraints
        # @return [String] Formatted constraint text for prompt injection
        def build_constraint_text(guidelines)
          return "" if guidelines.empty?

          constraints = guidelines.map.with_index do |guideline, index|
            priority_marker = priority_marker_for(guideline.priority)
            "#{index + 1}. #{priority_marker}[#{guideline.name}] #{guideline.action}"
          end

          <<~CONSTRAINT_TEXT

            ## BEHAVIORAL GUIDELINES (MUST Follow)

            The following guidelines have been dynamically matched to this request.
            You MUST comply with ALL of these requirements in your response.

            #{constraints.join("\n")}

            CRITICAL: Failure to follow these guidelines will result in response rejection.
          CONSTRAINT_TEXT
        end

        # Evaluate all guidelines and return a full execution log
        #
        # @param context [Hash] The execution context
        # @param input [String, Hash] The user input
        # @return [GuidelineExecutionLog] Complete execution log with all match results
        def evaluate_all(context, input)
          execution_log = GuidelineExecutionLog.new(agent_name: @agent.class.agent_name)

          return execution_log unless @agent.class.has_guidelines?

          @agent.class.agent_guidelines.each do |guideline|
            match_result = evaluate_guideline(guideline, context, input)
            reason = case match_result
                     when true then "matched"
                     when false then "not matched"
                     when :requires_llm_evaluation then "deferred to LLM"
                     else match_result.to_s
                     end

            execution_log.add_match_result(
              guideline.match_result(matched: match_result == true, match_reason: reason)
            )
          end

          applicable = execution_log.applied_guidelines
          unless applicable.empty?
            execution_log.set_constraint_text(build_constraint_text(applicable))
          end

          execution_log.complete!
          execution_log
        end

        # Clear the condition evaluation cache
        def clear_cache!
          @cache&.clear
        end

        private

        # Evaluate a single guideline's condition
        #
        # @param guideline [Guideline] The guideline to evaluate
        # @param context [Hash] The execution context
        # @param input [String, Hash] The user input
        # @return [Boolean, Symbol] true/false for match, :requires_llm_evaluation if deferred
        def evaluate_guideline(guideline, context, input)
          cache_key = build_cache_key(guideline, context, input) if @cache_enabled

          if @cache_enabled && @cache.key?(cache_key)
            return @cache[cache_key]
          end

          result = guideline.applies?(context, input)

          # Handle LLM condition fallback
          if result == :requires_llm_evaluation
            result = evaluate_llm_condition(guideline, context, input)
          end

          @cache[cache_key] = result if @cache_enabled

          result
        end

        # Evaluate an LLM-based condition using the provider
        #
        # @param guideline [Guideline] The guideline with LLM condition
        # @param context [Hash] The execution context
        # @param input [String, Hash] The user input
        # @return [Boolean] Whether the condition matches
        def evaluate_llm_condition(guideline, context, input)
          return false unless @llm_provider

          begin
            condition = guideline.condition
            if condition.respond_to?(:evaluate_with_llm)
              condition.evaluate_with_llm(@llm_provider, context, input)
            else
              RAAF.logger.warn "[Guidelines] Condition cannot be evaluated with LLM: #{guideline.name}"
              false
            end
          rescue StandardError => e
            RAAF.logger.error "[Guidelines] LLM condition evaluation failed for #{guideline.name}: #{e.message}"
            false
          end
        end

        # Build a cache key for condition evaluation
        def build_cache_key(guideline, context, input)
          context_digest = Digest::MD5.hexdigest(context.to_json) rescue "ctx"
          input_digest = Digest::MD5.hexdigest(input.to_s)
          "#{guideline.name}:#{context_digest}:#{input_digest}"
        end

        # Get priority marker for display
        def priority_marker_for(priority)
          case priority
          when :critical then "🔴 "
          when :high then "🟠 "
          when :normal then ""
          when :low then "🟢 "
          else ""
          end
        end

        # Log guideline execution
        def log_execution(execution_log)
          return unless RAAF.logger

          RAAF.logger.info execution_log.summary
        end
      end
    end
  end
end
