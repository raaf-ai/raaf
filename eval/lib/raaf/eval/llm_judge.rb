# frozen_string_literal: true

##
# RAAF Eval LLM Judge Module
#
# Provides statistically rigorous LLM-as-a-Judge evaluation with bias correction
# and proper confidence interval construction.
#
# This module implements recommendations from:
# - Lee et al. "How to Correctly Report LLM-as-a-Judge Evaluations" (arXiv:2511.21140)
# - CSHaitao/Awesome-LLMs-as-Judges survey
#
# ## Key Components
#
# - {CalibrationSet} - Manages ground-truth labeled calibration data
# - {StatisticalJudge} - Bias-corrected single LLM judge
# - {MultiJudgeEvaluator} - Consensus-based multi-model evaluation
# - {BiasMitigation} - Tools for detecting and mitigating judge biases
#
# ## Quick Start
#
#   require 'raaf/eval/llm_judge'
#
#   # Create and calibrate a judge
#   judge = RAAF::Eval::LLMJudge::StatisticalJudge.new(model: "gpt-4o")
#
#   calibration = RAAF::Eval::LLMJudge::CalibrationSet.new
#   calibration.add(input: "2+2=?", output: "4", ground_truth: true)
#   calibration.add(input: "2+2=?", output: "5", ground_truth: false)
#   # ... add more samples
#
#   judge.calibrate(calibration, criteria: "Is the answer correct?")
#
#   # Evaluate with bias correction
#   results = judge.evaluate_batch(test_samples, criteria: "Is the answer correct?")
#   puts results[:bias_corrected_accuracy]
#   puts results[:confidence_interval]
#
# @see https://arxiv.org/abs/2511.21140 "How to Correctly Report LLM-as-a-Judge Evaluations"
# @see https://github.com/UW-Madison-Lee-Lab/LLM-judge-reporting Python reference implementation
# @see https://github.com/CSHaitao/Awesome-LLMs-as-Judges Comprehensive LLM judge survey
#
module RAAF
  module Eval
    module LLMJudge
      autoload :CalibrationSet, "raaf/eval/llm_judge/calibration_set"
      autoload :StatisticalJudge, "raaf/eval/llm_judge/statistical_judge"
      autoload :MultiJudgeEvaluator, "raaf/eval/llm_judge/multi_judge_evaluator"
      autoload :BiasMitigation, "raaf/eval/llm_judge/bias_mitigation"

      # Re-export error classes
      class InsufficientCalibrationDataError < StandardError; end
      class JudgeNotCalibratedError < StandardError; end
      class JudgeNotBetterThanRandomError < StandardError; end
    end
  end
end
