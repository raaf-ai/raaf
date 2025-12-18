# frozen_string_literal: true

require_relative "condition"
require_relative "guideline_result"

module RAAF
  module DSL
    module Guidelines
      # Core Guideline class representing a behavioral constraint for AI agents
      #
      # Guidelines are first-class entities that define:
      # - WHEN to apply (condition)
      # - WHAT behavior is required (action)
      # - HOW to verify compliance (verification - optional)
      #
      # @example Basic guideline
      #   guideline :no_fabrication,
      #     condition: ->(_ctx, _input) { true },
      #     action: "Only use data from tools/context, never fabricate"
      #
      # @example Schema-based condition
      #   guideline :gdpr_compliance,
      #     condition: { field: :region, operator: :in, value: %w[EU EEA] },
      #     action: "Include GDPR compliance notice"
      #
      # @example Regex-based condition
      #   guideline :cite_sources,
      #     condition: /company|business|organization/i,
      #     action: "Include source URLs for all company data"
      #
      class Guideline
        PRIORITIES = %i[critical high normal low].freeze

        attr_reader :name, :condition, :action, :verification, :priority, :enabled, :metadata

        # @param name [Symbol] Unique identifier for the guideline
        # @param condition [Regexp, Hash, Proc, Condition, TrueClass] When the guideline applies
        # @param action [String] The behavioral requirement (injected into prompt)
        # @param verification [String, Proc, nil] Optional verification instructions for self-critique
        # @param priority [Symbol] Evaluation order (:critical, :high, :normal, :low)
        # @param enabled [Boolean] Whether the guideline is active
        # @param metadata [Hash] Optional metadata (tags, description, etc.)
        def initialize(
          name:,
          condition:,
          action:,
          verification: nil,
          priority: :normal,
          enabled: true,
          metadata: {}
        )
          @name = name.to_sym
          @condition = Condition.wrap(condition)
          @action = action
          @verification = verification
          @priority = validate_priority(priority)
          @enabled = enabled
          @metadata = metadata
        end

        # Check if this guideline applies to the given context and input
        # @param context [Hash] The execution context (agent context variables)
        # @param input [String, Hash] The user input or message
        # @return [Boolean, Symbol] true/false, or :requires_llm_evaluation
        def applies?(context, input)
          return false unless @enabled

          @condition.matches?(context, input)
        end

        # Check if this guideline requires LLM-based condition evaluation
        def requires_llm_condition?
          @condition.is_a?(LLMCondition)
        end

        # Get verification prompt for self-critique
        # @param output [String, Hash] The agent's output to verify
        # @return [String] The verification prompt
        def verification_prompt(output)
          case @verification
          when String
            @verification
          when Proc
            @verification.call(output)
          when nil
            default_verification_prompt(output)
          else
            @verification.to_s
          end
        end

        # Priority sort value (lower = higher priority)
        def priority_order
          case @priority
          when :critical then 0
          when :high then 1
          when :normal then 2
          when :low then 3
          else 2
          end
        end

        # Create a match result for this guideline
        def match_result(matched:, match_reason: nil)
          GuidelineMatchResult.new(
            guideline: self,
            matched: matched,
            match_reason: match_reason
          )
        end

        def to_h
          {
            name: @name,
            action: @action,
            priority: @priority,
            enabled: @enabled,
            condition_type: @condition.class.name.split("::").last,
            has_verification: !@verification.nil?,
            metadata: @metadata
          }
        end

        def to_s
          "[#{@priority}] #{@name}: #{@action.truncate(60)}"
        end

        def inspect
          "#<Guideline:#{@name} priority=#{@priority} enabled=#{@enabled} condition=#{@condition}>"
        end

        private

        def validate_priority(priority)
          priority = priority.to_sym
          unless PRIORITIES.include?(priority)
            raise ArgumentError, "Invalid priority: #{priority}. Valid: #{PRIORITIES.join(', ')}"
          end

          priority
        end

        def default_verification_prompt(_output)
          <<~VERIFICATION
            Verify that the response follows this guideline:
            GUIDELINE: #{@name}
            REQUIREMENT: #{@action}

            Check if the response complies with this requirement.
            If it does NOT comply, explain specifically what is wrong.
          VERIFICATION
        end
      end
    end
  end
end
