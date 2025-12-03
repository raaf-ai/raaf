#!/usr/bin/env ruby
# frozen_string_literal: true

##
# Statistical LLM Judge Example
#
# This example demonstrates the statistically rigorous LLM-as-a-Judge evaluation
# system based on Lee et al. "How to Correctly Report LLM-as-a-Judge Evaluations"
# (arXiv:2511.21140).
#
# Key concepts demonstrated:
# 1. Creating and managing calibration sets
# 2. Calibrating a judge with ground-truth data
# 3. Computing bias-corrected accuracy
# 4. Constructing proper confidence intervals
# 5. Using multi-judge consensus
# 6. Detecting and mitigating biases
#
# @see https://arxiv.org/abs/2511.21140
# @see https://github.com/UW-Madison-Lee-Lab/LLM-judge-reporting

require "bundler/setup"
require "raaf"
require "raaf/eval"
require "raaf/eval/llm_judge"

# ============================================================================
# Part 1: Creating a Calibration Set
# ============================================================================

puts "=" * 60
puts "Part 1: Creating a Calibration Set"
puts "=" * 60

# A calibration set contains samples with known ground-truth labels.
# This is essential for measuring the judge's sensitivity and specificity.

calibration = RAAF::Eval::LLMJudge::CalibrationSet.new(
  metadata: {
    version: "1.0.0",
    domain: "math_qa",
    description: "Calibration set for math question answering"
  }
)

# Add positive samples (correct answers)
positive_samples = [
  { input: "What is 2 + 2?", output: "4" },
  { input: "What is 5 * 3?", output: "15" },
  { input: "What is 10 / 2?", output: "5" },
  { input: "What is 7 - 4?", output: "3" },
  { input: "What is 3^2?", output: "9" },
  { input: "What is sqrt(16)?", output: "4" },
  { input: "What is 100 / 10?", output: "10" },
  { input: "What is 6 * 7?", output: "42" },
  { input: "What is 15 - 8?", output: "7" },
  { input: "What is 4 + 9?", output: "13" },
  { input: "What is 8 * 8?", output: "64" },
  { input: "What is 20 / 4?", output: "5" }
]

positive_samples.each do |sample|
  calibration.add(
    input: sample[:input],
    output: sample[:output],
    ground_truth: true,
    context: { type: "arithmetic" }
  )
end

# Add negative samples (incorrect answers)
negative_samples = [
  { input: "What is 2 + 2?", output: "5" },
  { input: "What is 5 * 3?", output: "12" },
  { input: "What is 10 / 2?", output: "4" },
  { input: "What is 7 - 4?", output: "2" },
  { input: "What is 3^2?", output: "6" },
  { input: "What is sqrt(16)?", output: "8" },
  { input: "What is 100 / 10?", output: "1000" },
  { input: "What is 6 * 7?", output: "36" },
  { input: "What is 15 - 8?", output: "23" },
  { input: "What is 4 + 9?", output: "11" },
  { input: "What is 8 * 8?", output: "16" },
  { input: "What is 20 / 4?", output: "80" }
]

negative_samples.each do |sample|
  calibration.add(
    input: sample[:input],
    output: sample[:output],
    ground_truth: false,
    context: { type: "arithmetic" }
  )
end

# Display statistics
stats = calibration.statistics
puts "\nCalibration Set Statistics:"
puts "  Total samples: #{stats[:total_samples]}"
puts "  Positive samples (m1): #{stats[:positive_samples]}"
puts "  Negative samples (m0): #{stats[:negative_samples]}"
puts "  Balance ratio: #{stats[:balance_ratio].round(2)}"
puts "  Valid for calibration: #{calibration.valid?}"

# Save calibration set for future use
calibration.save("/tmp/math_qa_calibration.json")
puts "\nCalibration set saved to /tmp/math_qa_calibration.json"

# ============================================================================
# Part 2: Calibrating a Statistical Judge
# ============================================================================

puts "\n" + "=" * 60
puts "Part 2: Calibrating a Statistical Judge"
puts "=" * 60

# Create a statistical judge
judge = RAAF::Eval::LLMJudge::StatisticalJudge.new(
  model: "gpt-4o",
  temperature: 0.0,  # Use temperature 0 for consistency
  cache: true
)

# Define evaluation criteria
criteria = "Is the mathematical answer correct? Evaluate if the output is the correct " \
           "numerical answer to the input question."

# Calibrate the judge
puts "\nCalibrating judge with #{calibration.size} samples..."
calibration_result = judge.calibrate(calibration, criteria: criteria)

puts "\nCalibration Results:"
puts "  Sensitivity (q1): #{calibration_result[:sensitivity].round(3)}"
puts "  Specificity (q0): #{calibration_result[:specificity].round(3)}"
puts "  True Positives: #{calibration_result[:true_positives]}"
puts "  True Negatives: #{calibration_result[:true_negatives]}"
puts "  False Positives: #{calibration_result[:false_positives]}"
puts "  False Negatives: #{calibration_result[:false_negatives]}"
puts "  Better than random: #{judge.better_than_random?}"

# ============================================================================
# Part 3: Bias-Corrected Evaluation
# ============================================================================

puts "\n" + "=" * 60
puts "Part 3: Bias-Corrected Evaluation"
puts "=" * 60

# Test samples to evaluate
test_samples = [
  { input: "What is 11 + 13?", output: "24" },
  { input: "What is 9 * 9?", output: "81" },
  { input: "What is 144 / 12?", output: "12" },
  { input: "What is 25 - 17?", output: "8" },
  { input: "What is 7 + 8?", output: "15" },
  { input: "What is 6 * 6?", output: "35" },       # Incorrect - should be 36
  { input: "What is 50 / 5?", output: "10" },
  { input: "What is 19 - 7?", output: "12" },
  { input: "What is 4 * 5?", output: "20" },
  { input: "What is 30 / 6?", output: "6" }        # Incorrect - should be 5
]

puts "\nEvaluating #{test_samples.size} test samples..."

# Evaluate with bias correction and 95% confidence interval
results = judge.evaluate_batch(
  test_samples,
  criteria: criteria,
  alpha: 0.05  # 95% confidence interval
)

puts "\nEvaluation Results:"
puts "  Passed: #{results[:passed_count]} / #{results[:total_count]}"
puts "  Raw accuracy: #{(results[:raw_accuracy] * 100).round(1)}%"
puts "  Bias-corrected accuracy: #{(results[:bias_corrected_accuracy] * 100).round(1)}%"

ci = results[:confidence_interval]
puts "\nConfidence Interval (95%):"
puts "  Point estimate: #{(ci[:point_estimate] * 100).round(1)}%"
puts "  Lower bound: #{(ci[:lower] * 100).round(1)}%"
puts "  Upper bound: #{(ci[:upper] * 100).round(1)}%"
puts "  Standard error: #{ci[:standard_error].round(4)}"

puts "\nVariance Decomposition:"
puts "  From test data: #{ci[:variance_decomposition][:test_variance].round(6)}"
puts "  From calibration: #{ci[:variance_decomposition][:calibration_variance].round(6)}"

puts "\nSample Sizes:"
puts "  Test samples (n): #{ci[:sample_sizes][:test_n]}"
puts "  Calibration positive (m1): #{ci[:sample_sizes][:calibration_m1]}"
puts "  Calibration negative (m0): #{ci[:sample_sizes][:calibration_m0]}"

# ============================================================================
# Part 4: Understanding Bias Correction
# ============================================================================

puts "\n" + "=" * 60
puts "Part 4: Understanding Bias Correction"
puts "=" * 60

# Demonstrate how bias correction works
puts "\nBias Correction Formula: θ = (p + q₀ - 1) / (q₀ + q₁ - 1)"
puts "\nWhere:"
puts "  p = raw proportion judged as correct"
puts "  q₀ = specificity (true negative rate)"
puts "  q₁ = sensitivity (true positive rate)"

raw_p = results[:raw_accuracy]
q0 = results[:calibration][:specificity]
q1 = results[:calibration][:sensitivity]

puts "\nFor our evaluation:"
puts "  p = #{raw_p.round(3)}"
puts "  q₀ = #{q0.round(3)}"
puts "  q₁ = #{q1.round(3)}"

numerator = raw_p + q0 - 1
denominator = q0 + q1 - 1
corrected = numerator / denominator

puts "\nCalculation:"
puts "  Numerator = #{raw_p.round(3)} + #{q0.round(3)} - 1 = #{numerator.round(3)}"
puts "  Denominator = #{q0.round(3)} + #{q1.round(3)} - 1 = #{denominator.round(3)}"
puts "  θ = #{numerator.round(3)} / #{denominator.round(3)} = #{corrected.round(3)}"
puts "\nBias-corrected accuracy: #{(corrected * 100).round(1)}%"

# ============================================================================
# Part 5: Multi-Judge Consensus (Simulated)
# ============================================================================

puts "\n" + "=" * 60
puts "Part 5: Multi-Judge Consensus"
puts "=" * 60

puts "\nNote: This example uses simulated multi-model evaluation."
puts "In production, you would use actual different models."

# For demonstration, we'll show the API usage
puts <<~EXAMPLE

  Example code for multi-judge consensus:

  ```ruby
  evaluator = RAAF::Eval::LLMJudge::MultiJudgeEvaluator.new(
    models: ["gpt-4o", "claude-3-5-sonnet", "gemini-1.5-pro"]
  )

  result = evaluator.evaluate(
    input: "What is 11 + 13?",
    output: "24",
    criteria: "Is the mathematical answer correct?"
  )

  puts "Consensus: \#{result[:consensus]}"
  puts "Agreement rate: \#{result[:agreement_rate]}"
  puts "Positive votes: \#{result[:positive_votes]} / \#{result[:total_judges]}"

  result[:individual_votes].each do |vote|
    puts "\#{vote[:judge]}: \#{vote[:passed]}"
  end
  ```

EXAMPLE

# ============================================================================
# Part 6: Bias Detection and Mitigation
# ============================================================================

puts "\n" + "=" * 60
puts "Part 6: Bias Detection and Mitigation"
puts "=" * 60

# Position bias mitigation
puts "\nPosition Bias Mitigation:"
puts <<~EXAMPLE

  Example: Position-debiased comparison

  ```ruby
  debiaser = RAAF::Eval::LLMJudge::BiasMitigation::PositionDebiaser.new(
    judge: judge,
    permutations: 2
  )

  result = debiaser.compare(
    input: "Explain what 2 + 2 means",
    output_a: "2 + 2 equals 4, which is the sum of 2 and 2.",
    output_b: "The answer is 4.",
    criteria: "Which explanation is more complete?"
  )

  puts "Winner: \#{result[:winner]}"
  puts "Position bias detected: \#{result[:position_bias_detected]}"
  puts "Consistent across orderings: \#{result[:consistent]}"
  ```

EXAMPLE

# Length bias analysis example
puts "\nLength Bias Analysis:"
puts <<~EXAMPLE

  Example: Detecting length bias in evaluations

  ```ruby
  analyzer = RAAF::Eval::LLMJudge::BiasMitigation::LengthBiasAnalyzer.new

  # Collect evaluations with outputs and scores
  evaluations = results[:individual_results].map.with_index do |r, i|
    { output: test_samples[i][:output], score: r[:confidence] }
  end

  analysis = analyzer.analyze_length_correlation(evaluations)

  puts "Correlation: \#{analysis[:correlation].round(3)}"
  puts "Bias detected: \#{analysis[:bias_detected]}"
  puts "Direction: \#{analysis[:bias_direction]}"
  puts "Strength: \#{analysis[:bias_strength]}"
  ```

EXAMPLE

# ============================================================================
# Part 7: Optimal Calibration Allocation
# ============================================================================

puts "\n" + "=" * 60
puts "Part 7: Optimal Calibration Allocation"
puts "=" * 60

puts "\nWhen you have a fixed budget for calibration samples, the adaptive"
puts "allocation algorithm helps you minimize uncertainty by optimally"
puts "distributing samples between positive and negative classes."

puts <<~EXAMPLE

  Example: Optimal allocation with 200 sample budget

  ```ruby
  # Start with a small pilot set for initial estimates
  pilot_set = calibration.stratified_split(ratio: 0.1, seed: 42).first

  allocation = judge.optimal_calibration_allocation(
    total_budget: 200,
    pilot_set: pilot_set,
    expected_positive_rate: 0.6  # Expect 60% correct in test data
  )

  puts "Allocate \#{allocation[:m0]} negative samples"
  puts "Allocate \#{allocation[:m1]} positive samples"
  puts "Ratio m1/m0: \#{allocation[:ratio].round(2)}"
  puts "Expected variance reduction: \#{allocation[:expected_variance_reduction]}%"
  ```

EXAMPLE

# ============================================================================
# Summary
# ============================================================================

puts "\n" + "=" * 60
puts "Summary"
puts "=" * 60

puts <<~SUMMARY

  This example demonstrated the key features of RAAF's statistical LLM judge:

  1. CalibrationSet: Manages ground-truth labeled data for measuring
     judge accuracy (sensitivity and specificity).

  2. StatisticalJudge: Provides bias-corrected evaluation using the
     formula from Lee et al. (2025).

  3. Confidence Intervals: Accounts for uncertainty from both test
     and calibration datasets.

  4. MultiJudgeEvaluator: Uses multiple models to reduce individual
     biases and increase reliability.

  5. BiasMitigation: Tools for detecting and correcting position,
     length, and format biases.

  For more details, see:
  - Paper: https://arxiv.org/abs/2511.21140
  - Code: https://github.com/UW-Madison-Lee-Lab/LLM-judge-reporting
  - Documentation: eval/docs/LLM_JUDGE_GUIDE.md

SUMMARY

puts "\nExample completed successfully!"
