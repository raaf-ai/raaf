# frozen_string_literal: true

require_relative "matchers/base"
require_relative "matchers/quality_matchers"
require_relative "matchers/performance_matchers"
require_relative "matchers/regression_matchers"
require_relative "matchers/safety_matchers"
require_relative "matchers/statistical_matchers"
require_relative "matchers/structural_matchers"
require_relative "matchers/llm_matchers"
require_relative "matchers/g_eval_matchers"
require_relative "matchers/rag_matchers"
require_relative "matchers/agentic_matchers"

module RAAF
  module Eval
    module RSpec
      ##
      # Custom RSpec matchers for evaluation assertions
      #
      # This module provides domain-specific matchers for asserting on
      # evaluation results.
      module Matchers
        # Quality matchers
        ::RSpec::Matchers.define :maintain_quality do
          include QualityMatchers::MaintainQuality
        end

        ::RSpec::Matchers.define :have_similar_output_to do
          include QualityMatchers::HaveSimilarOutputTo
        end

        ::RSpec::Matchers.define :have_coherent_output do
          include QualityMatchers::HaveCoherentOutput
        end

        ::RSpec::Matchers.define :not_hallucinate do
          include QualityMatchers::NotHallucinate
        end

        # Performance matchers
        ::RSpec::Matchers.define :use_tokens do
          include PerformanceMatchers::UseTokens
        end

        ::RSpec::Matchers.define :complete_within do
          include PerformanceMatchers::CompleteWithin
        end

        ::RSpec::Matchers.define :cost_less_than do
          include PerformanceMatchers::CostLessThan
        end

        # Regression matchers
        ::RSpec::Matchers.define :have_regressions do
          include RegressionMatchers::HaveRegressions
        end
        ::RSpec::Matchers.define_negated_matcher :not_have_regressions, :have_regressions

        ::RSpec::Matchers.define :perform_better_than do
          include RegressionMatchers::PerformBetterThan
        end

        ::RSpec::Matchers.define :have_acceptable_variance do
          include RegressionMatchers::HaveAcceptableVariance
        end

        # Safety matchers
        ::RSpec::Matchers.define :have_bias do
          include SafetyMatchers::HaveBias
        end
        ::RSpec::Matchers.define_negated_matcher :have_no_bias, :have_bias
        ::RSpec::Matchers.define_negated_matcher :not_have_bias, :have_bias

        ::RSpec::Matchers.define :be_safe do
          include SafetyMatchers::BeSafe
        end

        ::RSpec::Matchers.define :comply_with_policy do
          include SafetyMatchers::ComplyWithPolicy
        end

        # Statistical matchers
        ::RSpec::Matchers.define :be_statistically_significant do
          include StatisticalMatchers::BeStatisticallySignificant
        end

        ::RSpec::Matchers.define :have_effect_size do
          include StatisticalMatchers::HaveEffectSize
        end

        ::RSpec::Matchers.define :have_confidence_interval do
          include StatisticalMatchers::HaveConfidenceInterval
        end

        # Structural matchers
        ::RSpec::Matchers.define :have_valid_format do
          include StructuralMatchers::HaveValidFormat
        end

        ::RSpec::Matchers.define :match_schema do
          include StructuralMatchers::MatchSchema
        end

        ::RSpec::Matchers.define :have_length do
          include StructuralMatchers::HaveLength
        end

        # LLM-powered matchers
        ::RSpec::Matchers.define :satisfy_llm_check do
          include LLMMatchers::SatisfyLLMCheck
        end

        ::RSpec::Matchers.define :satisfy_llm_criteria do
          include LLMMatchers::SatisfyLLMCriteria
        end

        ::RSpec::Matchers.define :be_judged_as do
          include LLMMatchers::BeJudgedAs
        end
      end
    end
  end
end

# Auto-include matchers in RSpec
RSpec.configure do |config|
  config.include RAAF::Eval::RSpec::Matchers
end
