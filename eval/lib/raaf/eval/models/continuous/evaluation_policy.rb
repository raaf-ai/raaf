# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # EvaluationPolicy defines configuration for automatic span evaluation in production.
      # Policies determine which spans to evaluate, how to sample them, and what evaluators to run.
      #
      # @example Creating a production monitoring policy
      #   policy = EvaluationPolicy.create!(
      #     name: "GPT-4 Production Monitor",
      #     agent_name: "CustomerSupportAgent",
      #     environment: "production",
      #     model_pattern: "gpt-4*",
      #     sampling_mode: "every_n",
      #     sample_every_n: 10,
      #     max_daily_evaluations: 1000,
      #     evaluators: [
      #       { "type" => "llm_judge", "name" => "quality_judge", "config" => {} }
      #     ]
      #   )
      #
      # @example Pattern matching with wildcards
      #   policy.agent_name = "Support*"      # Matches SupportAgent, SupportBot, etc.
      #   policy.model_pattern = "*sonnet*"   # Matches any model containing "sonnet"
      #
      # @see PolicyMatcher Determines which policies match a span
      # @see EvaluatorDiscovery Discovers available evaluators from DSL registry
      class EvaluationPolicy < ActiveRecord::Base
        self.table_name = "raaf_evaluation_policies"

        # Associations
        has_many :evaluation_queue_items,
                 class_name: "RAAF::Eval::Models::EvaluationQueueItem",
                 foreign_key: :evaluation_policy_id,
                 dependent: :nullify
        has_many :continuous_evaluation_results,
                 class_name: "RAAF::Eval::Models::ContinuousEvaluationResult",
                 foreign_key: :evaluation_policy_id,
                 dependent: :nullify

        # Validations
        validates :name, presence: true, uniqueness: true
        validates :agent_name, presence: true, unless: :agent_names_from_evaluators?
        validates :sampling_mode, presence: true, inclusion: { in: %w[every_n all] }
        validates :sample_every_n, presence: true, numericality: { greater_than: 0 }, if: :every_n_sampling?
        validates :priority, numericality: { in: 0..100 }
        validate :validate_evaluators_structure
        before_validation :derive_agent_name_from_evaluators

        # Scopes
        scope :active, -> { where(active: true) }
        scope :inactive, -> { where(active: false) }
        scope :for_agent, ->(name) { where(agent_name: name) }
        scope :by_priority, -> { order(priority: :desc) }

        ##
        # Check if this policy has only manual trigger mode checks.
        # @return [Boolean] true if all checks are manual trigger mode
        def manual?
          !has_automatic_checks?
        end

        ##
        # Check if this policy has at least one automatic trigger mode check.
        # Used by PolicyMatcher to determine if the policy should auto-evaluate.
        # @return [Boolean] true if any check has trigger_mode "automatic" or unset
        def automatic?
          has_automatic_checks?
        end

        ##
        # Check if this policy has at least one check configured for automatic evaluation.
        # @return [Boolean] true if any check has trigger_mode "automatic" or unset
        def has_automatic_checks?
          evaluator_configs.any? do |evaluator|
            trigger_modes = evaluator[:check_trigger_modes] || evaluator["check_trigger_modes"] || {}
            checks = evaluator[:checks] || evaluator["checks"] || []

            # If no trigger modes defined, all checks are automatic by default
            return true if trigger_modes.empty?

            # Check if any check has automatic trigger mode
            checks.any? do |check|
              mode = trigger_modes[check.to_s] || trigger_modes[check.to_sym] || "automatic"
              mode == "automatic"
            end
          end
        end

        ##
        # Check if this policy uses per-check trigger modes (vs policy-level).
        # @return [Boolean] true if any evaluator has check_trigger_modes defined
        def uses_per_check_trigger_modes?
          evaluator_configs.any? do |evaluator|
            trigger_modes = evaluator[:check_trigger_modes] || evaluator["check_trigger_modes"]
            trigger_modes.present? && trigger_modes.any?
          end
        end

        ##
        # Get evaluators filtered to only include automatic checks.
        # Used for automatic evaluation when spans are created.
        # @return [Array<Hash>] Evaluators with only automatic checks
        def evaluators_for_auto_evaluation
          evaluator_configs.filter_map do |evaluator|
            trigger_modes = evaluator[:check_trigger_modes] || evaluator["check_trigger_modes"] || {}
            checks = evaluator[:checks] || evaluator["checks"] || []

            # Filter to only automatic checks
            auto_checks = checks.select do |check|
              mode = trigger_modes[check.to_s] || trigger_modes[check.to_sym] || "automatic"
              mode == "automatic"
            end

            # Skip evaluator if no automatic checks
            next nil if auto_checks.empty?

            # Return evaluator with only automatic checks
            evaluator.merge("checks" => auto_checks)
          end.compact
        end

        ##
        # Get all evaluators (used for manual evaluation via UI).
        # @return [Array<Hash>] All configured evaluators
        def evaluators_for_manual_evaluation
          evaluator_configs
        end

        ##
        # Check if a span matches this policy's targeting criteria.
        # Uses pattern matching with wildcard support for flexible targeting.
        #
        # @param span_data [Hash] Span data with :agent_name, :environment, :model keys
        # @return [Boolean] true if the span matches all targeting criteria
        #
        # @example Check if a span matches
        #   span = { agent_name: "CustomerSupportAgent", environment: "production", model: "gpt-4o" }
        #   policy.matches_span?(span) #=> true
        def matches_span?(span_data)
          return false unless matches_agent?(span_data[:agent_name])
          return false unless matches_environment?(span_data[:environment])
          return false unless matches_model?(span_data[:model])
          return false unless matches_version?(span_data[:version])
          true
        end

        ##
        # Determine if this span should be sampled for evaluation.
        # Implements sampling strategies to control evaluation volume and costs.
        #
        # @return [Boolean] true if the span should be evaluated
        #
        # @example Different sampling modes
        #   policy.sampling_mode = "all"      # Evaluate every matching span
        #   policy.sampling_mode = "every_n"  # Deterministic (e.g., every 5th)
        def should_sample?
          return false if at_daily_limit?

          case sampling_mode
          when "all"
            true
          when "every_n"
            check_and_increment_counter
          else
            false
          end
        end

        ##
        # Check if daily evaluation limit has been reached
        # @return [Boolean]
        def at_daily_limit?
          return false if max_daily_evaluations.nil?
          reset_daily_counter_if_needed
          today_evaluation_count >= max_daily_evaluations
        end

        ##
        # Increment the evaluation counter for today
        def increment_evaluation_count!
          reset_daily_counter_if_needed
          increment!(:today_evaluation_count)
        end

        ##
        # Reset the daily counter
        def reset_daily_counter!
          update!(today_evaluation_count: 0, count_reset_date: Date.current)
        end

        ##
        # Get evaluator configurations
        # @return [Array<Hash>]
        def evaluator_configs
          evaluators || []
        end

        private

        def every_n_sampling?
          sampling_mode == "every_n"
        end

        ##
        # Check if evaluators have agent_name defined
        # @return [Boolean]
        def agent_names_from_evaluators?
          return false if evaluators.blank?

          evaluators.any? { |e| e["agent_name"].present? || e[:agent_name].present? }
        end

        ##
        # Derive agent_name from evaluators if not set
        def derive_agent_name_from_evaluators
          return if agent_name.present?
          return if evaluators.blank?

          agent_names = evaluators.filter_map do |e|
            e["agent_name"] || e[:agent_name]
          end.uniq

          if agent_names.size == 1
            self.agent_name = agent_names.first
          elsif agent_names.any?
            self.agent_name = agent_names.join(", ")
          end
        end

        def matches_agent?(name)
          return false if name.nil?
          return true if agent_name.blank? || agent_name == "all"

          # Handle comma-separated agent names (from policies with multiple evaluators)
          # Match if the span's agent name matches ANY of the patterns
          if agent_name.include?(",")
            agent_name.split(",").map(&:strip).any? { |pattern| pattern_matches?(pattern, name) }
          else
            pattern_matches?(agent_name, name)
          end
        end

        def matches_environment?(env)
          return true if environment.blank? || environment == "all"
          environment == env
        end

        def matches_model?(model)
          return true if model_pattern.blank? || model_pattern == "all"
          return false if model.nil?
          pattern_matches?(model_pattern, model)
        end

        def matches_version?(version)
          return true if version_pattern.blank? || version_pattern == "all"
          return true if version.nil? # Allow nil versions
          pattern_matches?(version_pattern, version)
        end

        ##
        # Match pattern with wildcard support
        # @param pattern [String] Pattern with optional * wildcards
        # @param value [String] Value to match
        # @return [Boolean]
        def pattern_matches?(pattern, value)
          return true if pattern == "all"

          # Convert wildcard pattern to regex
          regex_pattern = "^" + Regexp.escape(pattern).gsub('\*', '.*') + "$"
          Regexp.new(regex_pattern, Regexp::IGNORECASE).match?(value)
        end

        ##
        # Check counter for every_n sampling and increment
        # @return [Boolean] true if this span should be sampled
        def check_and_increment_counter
          # Atomically increment and check
          new_count = self.class.where(id: id)
                          .update_all("sample_counter = sample_counter + 1")

          reload
          (sample_counter % sample_every_n) == 0
        end

        def reset_daily_counter_if_needed
          return if count_reset_date == Date.current

          reset_daily_counter!
        end

        def validate_evaluators_structure
          return if evaluators.nil?

          unless evaluators.is_a?(Array)
            errors.add(:evaluators, "must be an array")
            return
          end

          evaluators.each_with_index do |evaluator, index|
            unless evaluator.is_a?(Hash)
              errors.add(:evaluators, "item at index #{index} must be a hash")
              next
            end

            unless evaluator["type"].present?
              errors.add(:evaluators, "item at index #{index} must have a 'type' field")
            end

            unless evaluator["name"].present?
              errors.add(:evaluators, "item at index #{index} must have a 'name' field")
            end
          end
        end
      end
    end
  end
end
