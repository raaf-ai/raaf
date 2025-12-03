# frozen_string_literal: true

require_relative "../../llm_judge/calibration_set"
require_relative "../../llm_judge/statistical_judge"
require_relative "../../llm_judge/multi_judge_evaluator"
require_relative "../../llm_judge/bias_mitigation"

module RAAF
  module Eval
    module RSpec
      module Matchers
        ##
        # Statistical LLM matchers providing bias-corrected evaluation
        # with proper confidence intervals.
        #
        # These matchers implement recommendations from:
        # - Lee et al. "How to Correctly Report LLM-as-a-Judge Evaluations" (arXiv:2511.21140)
        # - CSHaitao/Awesome-LLMs-as-Judges survey
        #
        # @example Basic usage with calibration
        #   calibration = RAAF::Eval::LLMJudge::CalibrationSet.new
        #   # ... add calibration samples
        #
        #   expect(result).to have_bias_corrected_accuracy(above: 0.8)
        #     .calibrated_with(calibration)
        #     .with_confidence(0.95)
        #
        # @see https://arxiv.org/abs/2511.21140
        #
        module StatisticalLLMMatchers
          ##
          # Matcher for bias-corrected accuracy with confidence intervals
          #
          # @example
          #   expect(results).to have_bias_corrected_accuracy(above: 0.8)
          #     .calibrated_with(calibration_set)
          #     .using_model("gpt-4o")
          #     .with_criteria("Is the output correct?")
          #     .with_confidence(0.95)
          #
          ::RSpec::Matchers.define :have_bias_corrected_accuracy do |threshold_opts|
            match do |samples|
              @samples = samples
              @threshold = threshold_opts[:above] || threshold_opts[:at_least] || 0.5

              raise ArgumentError, "Must call .calibrated_with(calibration_set)" unless @calibration_set
              raise ArgumentError, "Must call .with_criteria(criteria)" unless @criteria

              # Create and calibrate judge
              @judge = RAAF::Eval::LLMJudge::StatisticalJudge.new(
                model: @model || "gpt-4o",
                temperature: 0.0
              )
              @judge.calibrate(@calibration_set, criteria: @criteria)

              # Evaluate batch
              alpha = 1 - (@confidence_level || 0.95)
              @results = @judge.evaluate_batch(@samples, criteria: @criteria, alpha: alpha)

              # Check if lower bound of CI is above threshold
              if @require_statistical_significance
                @results[:confidence_interval][:lower] >= @threshold
              else
                @results[:bias_corrected_accuracy] >= @threshold
              end
            end

            chain :calibrated_with do |calibration_set|
              @calibration_set = calibration_set
            end

            chain :using_model do |model|
              @model = model
            end

            chain :with_criteria do |criteria|
              @criteria = criteria
            end

            chain :with_confidence do |level|
              @confidence_level = level
              @require_statistical_significance = true
            end

            failure_message do
              ci = @results[:confidence_interval]
              "Expected bias-corrected accuracy above #{@threshold}, but got:\n" \
                "  Point estimate: #{format('%.3f', @results[:bias_corrected_accuracy])}\n" \
                "  #{((ci[:confidence_level]) * 100).round}% CI: [#{format('%.3f', ci[:lower])}, #{format('%.3f', ci[:upper])}]\n" \
                "  Sensitivity: #{format('%.3f', @results[:calibration][:sensitivity])}\n" \
                "  Specificity: #{format('%.3f', @results[:calibration][:specificity])}"
            end

            description do
              "have bias-corrected accuracy above #{@threshold}"
            end
          end

          ##
          # Matcher for statistically significant improvement over baseline
          #
          # @example
          #   expect(new_results).to have_significant_improvement_over(baseline_results)
          #     .calibrated_with(calibration_set)
          #     .with_criteria("Is the output correct?")
          #     .at_confidence(0.95)
          #
          ::RSpec::Matchers.define :have_significant_improvement_over do |baseline|
            match do |samples|
              @samples = samples
              @baseline = baseline

              raise ArgumentError, "Must call .calibrated_with(calibration_set)" unless @calibration_set
              raise ArgumentError, "Must call .with_criteria(criteria)" unless @criteria

              alpha = 1 - (@confidence_level || 0.95)

              # Create and calibrate judge
              @judge = RAAF::Eval::LLMJudge::StatisticalJudge.new(
                model: @model || "gpt-4o",
                temperature: 0.0
              )
              @judge.calibrate(@calibration_set, criteria: @criteria)

              # Evaluate both
              @new_results = @judge.evaluate_batch(@samples, criteria: @criteria, alpha: alpha)
              @baseline_results = @judge.evaluate_batch(@baseline, criteria: @criteria, alpha: alpha)

              # Check if new CI lower bound > baseline CI upper bound (non-overlapping)
              @new_results[:confidence_interval][:lower] > @baseline_results[:confidence_interval][:upper]
            end

            chain :calibrated_with do |calibration_set|
              @calibration_set = calibration_set
            end

            chain :using_model do |model|
              @model = model
            end

            chain :with_criteria do |criteria|
              @criteria = criteria
            end

            chain :at_confidence do |level|
              @confidence_level = level
            end

            failure_message do
              new_ci = @new_results[:confidence_interval]
              baseline_ci = @baseline_results[:confidence_interval]

              "Expected statistically significant improvement, but confidence intervals overlap:\n" \
                "  New:      #{format('%.3f', @new_results[:bias_corrected_accuracy])} " \
                "[#{format('%.3f', new_ci[:lower])}, #{format('%.3f', new_ci[:upper])}]\n" \
                "  Baseline: #{format('%.3f', @baseline_results[:bias_corrected_accuracy])} " \
                "[#{format('%.3f', baseline_ci[:lower])}, #{format('%.3f', baseline_ci[:upper])}]"
            end
          end

          ##
          # Matcher for multi-judge consensus
          #
          # @example
          #   expect(output).to satisfy_judge_consensus(
          #     judges: ["gpt-4o", "claude-3-5-sonnet", "gemini-1.5-pro"],
          #     criteria: "Is the output helpful and accurate?"
          #   ).with_agreement(above: 0.66)
          #
          ::RSpec::Matchers.define :satisfy_judge_consensus do |options|
            match do |output|
              @output = output
              @judges = options[:judges] || ["gpt-4o"]
              @criteria = options[:criteria]
              @input = options[:input] || ""

              raise ArgumentError, "Must provide :criteria" unless @criteria

              # Create multi-judge evaluator
              @evaluator = RAAF::Eval::LLMJudge::MultiJudgeEvaluator.new(
                models: @judges,
                default_strategy: @strategy || :majority
              )

              # Evaluate
              @result = @evaluator.evaluate(
                input: @input,
                output: @output.is_a?(Hash) ? @output[:output] : @output.to_s,
                criteria: @criteria
              )

              # Check consensus and agreement
              consensus_met = @result[:consensus]
              agreement_met = @min_agreement.nil? || @result[:agreement_rate] >= @min_agreement

              consensus_met && agreement_met
            end

            chain :with_agreement do |opts|
              @min_agreement = opts[:above] || opts[:at_least]
            end

            chain :using_strategy do |strategy|
              @strategy = strategy
            end

            failure_message do
              votes = @result[:individual_votes].map { |v| "#{v[:judge]}: #{v[:passed]}" }.join(", ")
              "Expected consensus with agreement >= #{@min_agreement || 0.5}, but:\n" \
                "  Consensus: #{@result[:consensus]}\n" \
                "  Agreement rate: #{format('%.2f', @result[:agreement_rate])}\n" \
                "  Votes: #{votes}"
            end
          end

          ##
          # Matcher for checking position bias in comparisons
          #
          # @example
          #   expect(comparison).to be_free_of_position_bias
          #     .when_comparing(output_a, output_b)
          #     .with_criteria("Which is better?")
          #
          ::RSpec::Matchers.define :be_free_of_position_bias do
            match do |_subject|
              raise ArgumentError, "Must call .when_comparing(a, b)" unless @output_a && @output_b
              raise ArgumentError, "Must call .with_criteria(criteria)" unless @criteria

              judge = RAAF::Eval::LLMJudge::StatisticalJudge.new(
                model: @model || "gpt-4o",
                temperature: 0.0
              )

              debiaser = RAAF::Eval::LLMJudge::BiasMitigation::PositionDebiaser.new(judge: judge)

              @result = debiaser.compare(
                input: @input || "",
                output_a: @output_a,
                output_b: @output_b,
                criteria: @criteria
              )

              !@result[:position_bias_detected]
            end

            chain :when_comparing do |output_a, output_b|
              @output_a = output_a
              @output_b = output_b
            end

            chain :for_input do |input|
              @input = input
            end

            chain :with_criteria do |criteria|
              @criteria = criteria
            end

            chain :using_model do |model|
              @model = model
            end

            failure_message do
              "Position bias detected in comparison:\n" \
                "  Forward result: #{@result[:forward_result][:prefers_first] ? 'prefers first' : 'prefers second'}\n" \
                "  Reverse result: #{@result[:reverse_result][:prefers_first] ? 'prefers first' : 'prefers second'}\n" \
                "  Results are inconsistent, indicating position bias"
            end
          end

          ##
          # Matcher for checking judge consistency
          #
          # @example
          #   expect(judge).to be_consistent_on(sample)
          #     .with_criteria("Is this correct?")
          #     .across(5).repetitions
          #
          ::RSpec::Matchers.define :be_consistent_on do |sample|
            match do |judge|
              @sample = sample
              @judge = judge

              raise ArgumentError, "Must call .with_criteria(criteria)" unless @criteria

              checker = RAAF::Eval::LLMJudge::BiasMitigation::ConsistencyChecker.new(
                judge: @judge,
                repetitions: @repetitions || 3
              )

              @result = checker.check(
                input: @sample[:input] || "",
                output: @sample[:output],
                criteria: @criteria
              )

              @result[:consistent] && @result[:confidence_variance] < (@max_variance || 0.1)
            end

            chain :with_criteria do |criteria|
              @criteria = criteria
            end

            chain :across do |count|
              @repetitions = count
              self
            end

            chain :repetitions
            # Just for readability, no-op

            chain :with_max_confidence_variance do |variance|
              @max_variance = variance
            end

            failure_message do
              "Expected judge to be consistent, but:\n" \
                "  Agreement rate: #{format('%.2f', @result[:agreement_rate])}\n" \
                "  Confidence variance: #{format('%.4f', @result[:confidence_variance])}\n" \
                "  Passed ratio: #{format('%.2f', @result[:passed_ratio])}"
            end
          end

          ##
          # Matcher for verifying calibration quality
          #
          # @example
          #   expect(judge).to have_valid_calibration
          #     .with_sensitivity(above: 0.7)
          #     .with_specificity(above: 0.7)
          #
          ::RSpec::Matchers.define :have_valid_calibration do
            match do |judge|
              @judge = judge

              return false unless @judge.calibrated?
              return false unless @judge.better_than_random?

              sensitivity_ok = @min_sensitivity.nil? || @judge.sensitivity >= @min_sensitivity
              specificity_ok = @min_specificity.nil? || @judge.specificity >= @min_specificity

              sensitivity_ok && specificity_ok
            end

            chain :with_sensitivity do |opts|
              @min_sensitivity = opts[:above] || opts[:at_least]
            end

            chain :with_specificity do |opts|
              @min_specificity = opts[:above] || opts[:at_least]
            end

            failure_message do
              if !@judge.calibrated?
                "Judge is not calibrated"
              elsif !@judge.better_than_random?
                "Judge is not better than random (sensitivity + specificity <= 1.0)"
              else
                "Calibration quality below threshold:\n" \
                  "  Sensitivity: #{format('%.3f', @judge.sensitivity)} (min: #{@min_sensitivity || 'none'})\n" \
                  "  Specificity: #{format('%.3f', @judge.specificity)} (min: #{@min_specificity || 'none'})"
              end
            end
          end

          ##
          # Matcher for checking length bias
          #
          # @example
          #   expect(evaluations).to be_free_of_length_bias
          #     .with_max_correlation(0.3)
          #
          ::RSpec::Matchers.define :be_free_of_length_bias do
            match do |evaluations|
              @evaluations = evaluations

              analyzer = RAAF::Eval::LLMJudge::BiasMitigation::LengthBiasAnalyzer.new
              @analysis = analyzer.analyze_length_correlation(evaluations)

              !@analysis[:bias_detected] ||
                (@max_correlation && @analysis[:correlation].abs <= @max_correlation)
            end

            chain :with_max_correlation do |max|
              @max_correlation = max
            end

            failure_message do
              "Length bias detected:\n" \
                "  Correlation: #{format('%.3f', @analysis[:correlation])}\n" \
                "  Direction: #{@analysis[:bias_direction]}\n" \
                "  Strength: #{@analysis[:bias_strength]}"
            end
          end

          ##
          # Matcher for inter-rater reliability
          #
          # @example
          #   expect(multi_judge).to have_high_inter_rater_reliability
          #     .on(samples)
          #     .with_criteria("Is this correct?")
          #     .with_fleiss_kappa(above: 0.6)
          #
          ::RSpec::Matchers.define :have_high_inter_rater_reliability do
            match do |evaluator|
              @evaluator = evaluator

              raise ArgumentError, "Must call .on(samples)" unless @samples
              raise ArgumentError, "Must call .with_criteria(criteria)" unless @criteria

              @reliability = @evaluator.inter_rater_reliability(@samples, criteria: @criteria)

              kappa_ok = @min_kappa.nil? || @reliability[:fleiss_kappa] >= @min_kappa
              agreement_ok = @min_agreement.nil? ||
                             @reliability[:mean_pairwise_agreement] >= @min_agreement

              kappa_ok && agreement_ok
            end

            chain :on do |samples|
              @samples = samples
            end

            chain :with_criteria do |criteria|
              @criteria = criteria
            end

            chain :with_fleiss_kappa do |opts|
              @min_kappa = opts[:above] || opts[:at_least]
            end

            chain :with_mean_agreement do |opts|
              @min_agreement = opts[:above] || opts[:at_least]
            end

            failure_message do
              "Inter-rater reliability below threshold:\n" \
                "  Fleiss' Kappa: #{format('%.3f', @reliability[:fleiss_kappa])} " \
                "(min: #{@min_kappa || 'none'})\n" \
                "  Mean pairwise agreement: #{format('%.3f', @reliability[:mean_pairwise_agreement])} " \
                "(min: #{@min_agreement || 'none'})"
            end
          end
        end
      end
    end
  end
end
