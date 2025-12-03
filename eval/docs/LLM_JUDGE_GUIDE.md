# RAAF Eval: Statistical LLM-as-a-Judge Guide

> **Version:** 1.0.0
> **Last Updated:** 2025-12-03

This guide covers RAAF Eval's statistically rigorous LLM-as-a-Judge implementation, which provides bias-corrected evaluation with proper confidence intervals.

## Table of Contents

1. [Introduction](#introduction)
2. [The Problem with Raw LLM Judge Scores](#the-problem-with-raw-llm-judge-scores)
3. [Key Concepts](#key-concepts)
4. [Getting Started](#getting-started)
5. [Calibration](#calibration)
6. [Bias-Corrected Evaluation](#bias-corrected-evaluation)
7. [Confidence Intervals](#confidence-intervals)
8. [Multi-Judge Consensus](#multi-judge-consensus)
9. [Bias Mitigation](#bias-mitigation)
10. [RSpec Integration](#rspec-integration)
11. [Best Practices](#best-practices)
12. [API Reference](#api-reference)
13. [References](#references)

---

## Introduction

RAAF Eval's LLM Judge module provides statistically rigorous evaluation of AI outputs using LLMs as judges. Unlike naive approaches that report raw LLM judgment scores, our implementation:

- **Corrects for judge bias** using calibrated sensitivity and specificity
- **Provides proper confidence intervals** accounting for all sources of uncertainty
- **Supports multi-judge consensus** to reduce individual model biases
- **Includes bias detection and mitigation** for position, length, and format biases

This implementation is based on the research paper ["How to Correctly Report LLM-as-a-Judge Evaluations"](https://arxiv.org/abs/2511.21140) by Lee et al. (2025).

---

## The Problem with Raw LLM Judge Scores

### Why Raw Scores Are Biased

LLM judges have imperfect sensitivity and specificity:

| Metric | Definition | Problem |
|--------|------------|---------|
| **Sensitivity (q₁)** | P(Judge=correct \| Actually=correct) | False negatives when < 1.0 |
| **Specificity (q₀)** | P(Judge=incorrect \| Actually=incorrect) | False positives when < 1.0 |

When an LLM judge reports 70% of outputs as "correct," the true accuracy could be significantly different depending on the judge's error rates.

### Example: The Bias Problem

```
True accuracy: 60%
Judge sensitivity: 0.85 (misses 15% of correct outputs)
Judge specificity: 0.75 (incorrectly approves 25% of incorrect outputs)

Raw judge score: 0.85 × 0.60 + 0.25 × 0.40 = 0.61 (61%)

Without correction, we'd report 61% when truth is 60%.
But with different sensitivity/specificity, the same raw score could mean very different things!
```

### Two Sources of Uncertainty

Raw LLM judge evaluations also ignore two sources of uncertainty:

1. **Test dataset randomness**: Sampling variation from your test set
2. **Calibration dataset randomness**: Uncertainty in sensitivity/specificity estimates

Both must be accounted for in confidence intervals.

---

## Key Concepts

### Sensitivity (q₁) - True Positive Rate

The probability that the judge correctly identifies a correct output:

```
Sensitivity = P(Judge says "correct" | Output is actually correct)
```

A judge with sensitivity = 0.9 will correctly identify 90% of truly correct outputs, missing 10% (false negatives).

### Specificity (q₀) - True Negative Rate

The probability that the judge correctly identifies an incorrect output:

```
Specificity = P(Judge says "incorrect" | Output is actually incorrect)
```

A judge with specificity = 0.8 will correctly identify 80% of truly incorrect outputs, incorrectly approving 20% (false positives).

### Bias-Corrected Accuracy

The formula for bias-corrected accuracy from Lee et al.:

```
θ = (p + q₀ - 1) / (q₀ + q₁ - 1)

Where:
- p = raw proportion judged as correct
- q₀ = specificity
- q₁ = sensitivity
```

### Better Than Random Requirement

For the bias correction to be valid, the judge must satisfy:

```
q₀ + q₁ > 1
```

This ensures the judge performs better than random guessing.

---

## Getting Started

### Installation

The LLM Judge module is included in RAAF Eval:

```ruby
require 'raaf/eval'
require 'raaf/eval/llm_judge'
```

### Quick Start Example

```ruby
require 'raaf/eval/llm_judge'

# 1. Create a calibration set with ground-truth labels
calibration = RAAF::Eval::LLMJudge::CalibrationSet.new

# Add known correct examples
calibration.add(
  input: "What is the capital of France?",
  output: "Paris is the capital of France.",
  ground_truth: true
)

# Add known incorrect examples
calibration.add(
  input: "What is the capital of France?",
  output: "London is the capital of France.",
  ground_truth: false
)

# Add more samples (minimum 10 positive and 10 negative recommended)
# ...

# 2. Create and calibrate a judge
judge = RAAF::Eval::LLMJudge::StatisticalJudge.new(model: "gpt-4o")

calibration_result = judge.calibrate(
  calibration,
  criteria: "Is the answer factually correct and complete?"
)

puts "Sensitivity: #{calibration_result[:sensitivity]}"
puts "Specificity: #{calibration_result[:specificity]}"

# 3. Evaluate test samples with bias correction
test_samples = [
  { input: "What is 2+2?", output: "4" },
  { input: "What is 3+3?", output: "6" },
  # ...
]

results = judge.evaluate_batch(
  test_samples,
  criteria: "Is the answer mathematically correct?"
)

puts "Raw accuracy: #{results[:raw_accuracy]}"
puts "Bias-corrected accuracy: #{results[:bias_corrected_accuracy]}"
puts "95% CI: [#{results[:confidence_interval][:lower]}, #{results[:confidence_interval][:upper]}]"
```

---

## Calibration

### Why Calibration is Essential

Calibration measures how accurate your LLM judge is by comparing its judgments against ground-truth labels. Without calibration:

- You don't know if your judge has high or low false positive/negative rates
- You can't correct for systematic biases
- Your accuracy estimates may be significantly wrong

### Creating a Calibration Set

```ruby
calibration = RAAF::Eval::LLMJudge::CalibrationSet.new

# Add samples with known ground truth
calibration.add(
  input: "Summarize this article about climate change",
  output: "This article discusses rising global temperatures...",
  ground_truth: true,
  context: { domain: "science", difficulty: "medium" }
)

calibration.add(
  input: "Summarize this article about climate change",
  output: "The article is about cooking recipes.",
  ground_truth: false,
  context: { domain: "science", difficulty: "easy" }
)

# Check statistics
stats = calibration.statistics
puts "Total samples: #{stats[:total_samples]}"
puts "Positive samples: #{stats[:positive_samples]}"
puts "Negative samples: #{stats[:negative_samples]}"
puts "Balance ratio: #{stats[:balance_ratio]}"
```

### Calibration Set Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Positive samples (m₁) | 10 | 50+ |
| Negative samples (m₀) | 10 | 50+ |
| Balance ratio | 0.5-2.0 | Close to 1.0 |
| Domain coverage | Representative | Comprehensive |

### Saving and Loading Calibration Sets

```ruby
# Save to file
calibration.save("calibration_data.json")

# Load from file
loaded = RAAF::Eval::LLMJudge::CalibrationSet.load("calibration_data.json")

# Merge multiple sets
combined = RAAF::Eval::LLMJudge::CalibrationSet.merge(set1, set2, set3)
```

### Stratified Splitting for Cross-Validation

```ruby
# Split maintaining positive/negative ratio
train_set, test_set = calibration.stratified_split(ratio: 0.8, seed: 42)

puts "Training set: #{train_set.m1} positive, #{train_set.m0} negative"
puts "Test set: #{test_set.m1} positive, #{test_set.m0} negative"
```

### Domain-Specific Calibration

Filter calibration data for specific domains:

```ruby
# Create domain-specific calibration set
medical_calibration = calibration.filter(domain: "medical")
legal_calibration = calibration.filter(domain: "legal")

# Calibrate separate judges for each domain
medical_judge = StatisticalJudge.new(model: "gpt-4o")
medical_judge.calibrate(medical_calibration, criteria: "Is this medically accurate?")
```

---

## Bias-Corrected Evaluation

### Single Sample Evaluation

```ruby
judge = RAAF::Eval::LLMJudge::StatisticalJudge.new(model: "gpt-4o")
judge.calibrate(calibration, criteria: "Is the answer correct?")

result = judge.evaluate(
  input: "What is the speed of light?",
  output: "The speed of light is approximately 299,792 km/s.",
  criteria: "Is the answer scientifically accurate?"
)

puts "Passed: #{result[:passed]}"
puts "Confidence: #{result[:confidence]}"
puts "Reasoning: #{result[:reasoning]}"
```

### Batch Evaluation with Bias Correction

```ruby
results = judge.evaluate_batch(test_samples, criteria: "Is the answer correct?")

# Access results
puts "Raw accuracy: #{results[:raw_accuracy]}"
puts "Bias-corrected accuracy: #{results[:bias_corrected_accuracy]}"
puts "Passed count: #{results[:passed_count]} / #{results[:total_count]}"

# Calibration parameters used
puts "Sensitivity: #{results[:calibration][:sensitivity]}"
puts "Specificity: #{results[:calibration][:specificity]}"
```

### Understanding the Correction

```ruby
# Manual calculation example
raw_proportion = 0.75  # 75% judged as correct
sensitivity = 0.90     # Judge catches 90% of correct outputs
specificity = 0.80     # Judge correctly rejects 80% of incorrect outputs

# Bias-corrected accuracy
corrected = (raw_proportion + specificity - 1) / (specificity + sensitivity - 1)
# = (0.75 + 0.80 - 1) / (0.80 + 0.90 - 1)
# = 0.55 / 0.70
# ≈ 0.786

# The true accuracy is ~78.6%, not the raw 75%!
```

---

## Confidence Intervals

### Why Confidence Intervals Matter

Point estimates alone can be misleading. A 95% confidence interval tells you the range within which the true accuracy likely falls, accounting for:

1. **Sampling uncertainty** from your test set size
2. **Calibration uncertainty** from your calibration set size

### Computing Confidence Intervals

```ruby
results = judge.evaluate_batch(test_samples, criteria: "Is correct?", alpha: 0.05)

ci = results[:confidence_interval]
puts "Point estimate: #{ci[:point_estimate]}"
puts "95% CI: [#{ci[:lower]}, #{ci[:upper]}]"
puts "Standard error: #{ci[:standard_error]}"

# Variance decomposition
puts "Variance from test data: #{ci[:variance_decomposition][:test_variance]}"
puts "Variance from calibration: #{ci[:variance_decomposition][:calibration_variance]}"

# Sample sizes
puts "Test samples: #{ci[:sample_sizes][:test_n]}"
puts "Calibration positive: #{ci[:sample_sizes][:calibration_m1]}"
puts "Calibration negative: #{ci[:sample_sizes][:calibration_m0]}"
```

### Interpreting Confidence Intervals

```
Bias-corrected accuracy: 0.82
95% CI: [0.75, 0.89]

Interpretation:
- Point estimate is 82% accuracy
- We're 95% confident true accuracy is between 75% and 89%
- The width (14%) reflects our uncertainty
- Larger test/calibration sets would narrow this interval
```

### Optimal Calibration Allocation

Minimize uncertainty by optimally allocating your calibration budget:

```ruby
# You have 200 samples to allocate for calibration
# Use a small pilot set to estimate optimal allocation

pilot_set = small_calibration_set  # ~20 samples

allocation = judge.optimal_calibration_allocation(
  total_budget: 200,
  pilot_set: pilot_set,
  expected_positive_rate: 0.6  # Expect 60% of test outputs to be correct
)

puts "Allocate #{allocation[:m0]} negative samples"
puts "Allocate #{allocation[:m1]} positive samples"
puts "Expected variance reduction: #{allocation[:expected_variance_reduction]}%"
```

---

## Multi-Judge Consensus

### Why Use Multiple Judges?

Different LLM models have different biases. Using multiple judges and aggregating their decisions can:

- Reduce individual model biases
- Increase confidence in judgments
- Identify ambiguous cases needing human review

### Basic Multi-Judge Evaluation

```ruby
evaluator = RAAF::Eval::LLMJudge::MultiJudgeEvaluator.new(
  models: ["gpt-4o", "claude-3-5-sonnet-20241022", "gemini-1.5-pro"]
)

result = evaluator.evaluate(
  input: "Explain quantum entanglement",
  output: "Quantum entanglement is when two particles...",
  criteria: "Is the explanation accurate and understandable?"
)

puts "Consensus: #{result[:consensus]}"
puts "Agreement rate: #{result[:agreement_rate]}"
puts "Positive votes: #{result[:positive_votes]} / #{result[:total_judges]}"

# Individual votes
result[:individual_votes].each do |vote|
  puts "#{vote[:judge]}: #{vote[:passed]} (confidence: #{vote[:confidence]})"
end
```

### Aggregation Strategies

```ruby
# Majority vote (default)
result = evaluator.evaluate(input: "...", output: "...", criteria: "...")

# Weighted by calibration quality
result = evaluator.evaluate_weighted(input: "...", output: "...", criteria: "...")

# Require unanimous agreement
result = evaluator.evaluate_unanimous(input: "...", output: "...", criteria: "...")

# Custom threshold (e.g., 2/3 agreement)
result = evaluator.evaluate_threshold(
  input: "...",
  output: "...",
  criteria: "...",
  threshold: 0.66
)
```

### Calibrating All Judges

```ruby
# Calibrate all judges with the same calibration set
calibration_results = evaluator.calibrate_all(
  calibration_set,
  criteria: "Is the answer correct?"
)

# Now weighted voting uses calibration quality as weights
result = evaluator.evaluate_weighted(input: "...", output: "...", criteria: "...")

# Judges with higher sensitivity + specificity get more weight
result[:weights].each do |w|
  puts "#{w[:model]}: weight = #{w[:weight]}"
end
```

### Flagging for Human Review

Identify cases where judges disagree significantly:

```ruby
flagged = evaluator.flag_for_human_review(
  samples,
  criteria: "Is this correct?",
  disagreement_threshold: 0.5  # Flag when agreement < 50%
)

flagged.each do |item|
  puts "Sample needs review: #{item[:sample][:input]}"
  puts "Reason: #{item[:reason]}"
end
```

### Inter-Rater Reliability

Measure how well judges agree across your dataset:

```ruby
reliability = evaluator.inter_rater_reliability(samples, criteria: "Is correct?")

puts "Fleiss' Kappa: #{reliability[:fleiss_kappa]}"
puts "Mean pairwise agreement: #{reliability[:mean_pairwise_agreement]}"

# Interpretation of Kappa:
# < 0.20: Poor agreement
# 0.21-0.40: Fair agreement
# 0.41-0.60: Moderate agreement
# 0.61-0.80: Substantial agreement
# 0.81-1.00: Almost perfect agreement
```

---

## Bias Mitigation

### Position Bias

LLMs often prefer items appearing first or last in a comparison. Mitigate by evaluating in multiple orderings:

```ruby
debiaser = RAAF::Eval::LLMJudge::BiasMitigation::PositionDebiaser.new(
  judge: judge,
  permutations: 2  # Evaluate in both orderings
)

result = debiaser.compare(
  input: "Write a poem about Ruby",
  output_a: "Ruby shines like a gem...",
  output_b: "In the land of code...",
  criteria: "Which poem is more creative?"
)

puts "Winner: #{result[:winner]}"  # :a, :b, or :tie
puts "Position bias detected: #{result[:position_bias_detected]}"
puts "Consistent across orderings: #{result[:consistent]}"
```

### Ranking Multiple Outputs

```ruby
ranking = debiaser.rank(
  input: "Explain recursion",
  outputs: [explanation_1, explanation_2, explanation_3, explanation_4],
  criteria: "Which explanation is clearest?"
)

ranking[:ranking].each do |item|
  puts "Rank #{item[:index] + 1}: Score #{item[:score]}"
end

puts "Position bias detected in #{ranking[:position_bias_count]} / #{ranking[:total_comparisons]} comparisons"
```

### Length Bias Detection

Detect if your judge favors longer or shorter outputs:

```ruby
analyzer = RAAF::Eval::LLMJudge::BiasMitigation::LengthBiasAnalyzer.new

# Evaluations should have :output and :score
evaluations = [
  { output: "Short answer", score: 0.6 },
  { output: "This is a much longer and more detailed answer...", score: 0.9 },
  # ...
]

analysis = analyzer.analyze_length_correlation(evaluations)

puts "Correlation: #{analysis[:correlation]}"
puts "Bias detected: #{analysis[:bias_detected]}"
puts "Direction: #{analysis[:bias_direction]}"  # :prefers_longer or :prefers_shorter
puts "Strength: #{analysis[:bias_strength]}"    # :weak, :moderate, :strong, :very_strong
```

### Normalizing for Length Bias

```ruby
normalized = analyzer.normalize_for_length(evaluations)

normalized.each do |item|
  puts "Original score: #{item[:original_score]}"
  puts "Normalized score: #{item[:normalized_score]}"
  puts "Adjustment: #{item[:adjustment]}"
end
```

### Format Bias Detection

Check if the judge favors certain formatting styles:

```ruby
analyzer = RAAF::Eval::LLMJudge::BiasMitigation::FormatBiasAnalyzer.new

analysis = analyzer.analyze(evaluations)

puts "Format biases detected: #{analysis[:significant_biases]}"

analysis[:format_biases].each do |format, details|
  if details[:bias_detected]
    puts "#{format}: #{details[:direction]} (correlation: #{details[:correlation]})"
  end
end
```

### Consistency Checking

Verify your judge gives consistent results on the same input:

```ruby
checker = RAAF::Eval::LLMJudge::BiasMitigation::ConsistencyChecker.new(
  judge: judge,
  repetitions: 5
)

result = checker.check(
  input: "What is AI?",
  output: "AI is artificial intelligence...",
  criteria: "Is this definition accurate?"
)

puts "Consistent: #{result[:consistent]}"
puts "Agreement rate: #{result[:agreement_rate]}"
puts "Confidence variance: #{result[:confidence_variance]}"
```

---

## RSpec Integration

### Available Matchers

RAAF Eval provides statistical LLM matchers for testing:

```ruby
require 'raaf/eval/rspec'

RSpec.describe "Agent Output Quality" do
  let(:calibration) { load_calibration_set }
  let(:samples) { generate_test_samples }

  # Bias-corrected accuracy with confidence interval
  it "maintains high accuracy" do
    expect(samples).to have_bias_corrected_accuracy(above: 0.8)
      .calibrated_with(calibration)
      .with_criteria("Is the output correct?")
      .with_confidence(0.95)
  end

  # Statistically significant improvement
  it "improves over baseline" do
    expect(new_samples).to have_significant_improvement_over(baseline_samples)
      .calibrated_with(calibration)
      .with_criteria("Is the output correct?")
      .at_confidence(0.95)
  end

  # Multi-judge consensus
  it "satisfies multiple judges" do
    expect(output).to satisfy_judge_consensus(
      judges: ["gpt-4o", "claude-3-5-sonnet"],
      criteria: "Is this helpful?",
      input: "User question"
    ).with_agreement(above: 0.66)
  end

  # Position bias check
  it "is free of position bias" do
    expect(comparison).to be_free_of_position_bias
      .when_comparing(output_a, output_b)
      .with_criteria("Which is better?")
  end

  # Judge consistency
  it "has consistent judge" do
    expect(judge).to be_consistent_on(sample)
      .with_criteria("Is this correct?")
      .across(5).repetitions
  end

  # Calibration quality
  it "has valid calibration" do
    expect(judge).to have_valid_calibration
      .with_sensitivity(above: 0.8)
      .with_specificity(above: 0.8)
  end

  # Length bias check
  it "is free of length bias" do
    expect(evaluations).to be_free_of_length_bias
      .with_max_correlation(0.3)
  end

  # Inter-rater reliability
  it "has high inter-rater reliability" do
    expect(multi_judge).to have_high_inter_rater_reliability
      .on(samples)
      .with_criteria("Is this correct?")
      .with_fleiss_kappa(above: 0.6)
  end
end
```

### CI/CD Integration

```yaml
# .github/workflows/eval.yml
name: Evaluation Tests

on: [push, pull_request]

jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true

      - name: Run Evaluation Tests
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: |
          bundle exec rspec spec/eval --tag statistical_llm
```

---

## Best Practices

### 1. Always Calibrate Before Evaluating

```ruby
# ❌ Bad: Using uncalibrated judge
judge = StatisticalJudge.new(model: "gpt-4o")
results = judge.evaluate_batch(samples, criteria: "Is correct?")
# Warning: Results may be biased!

# ✅ Good: Calibrate first
judge = StatisticalJudge.new(model: "gpt-4o")
judge.calibrate(calibration_set, criteria: "Is correct?")
results = judge.evaluate_batch(samples, criteria: "Is correct?")
# Results include bias correction and confidence intervals
```

### 2. Use Sufficient Calibration Data

```ruby
# ❌ Bad: Too few calibration samples
calibration = CalibrationSet.new
calibration.add(input: "Q1", output: "A1", ground_truth: true)
calibration.add(input: "Q2", output: "A2", ground_truth: false)
# Only 2 samples - uncertainty will be very high!

# ✅ Good: Adequate calibration data
calibration = CalibrationSet.new
50.times { |i| calibration.add(..., ground_truth: true) }
50.times { |i| calibration.add(..., ground_truth: false) }
# 100 samples provides reasonable estimates
```

### 3. Report Confidence Intervals

```ruby
# ❌ Bad: Reporting only point estimate
puts "Accuracy: #{results[:bias_corrected_accuracy]}"

# ✅ Good: Report with uncertainty
ci = results[:confidence_interval]
puts "Accuracy: #{ci[:point_estimate].round(3)} " \
     "(#{(ci[:confidence_level] * 100).round}% CI: " \
     "[#{ci[:lower].round(3)}, #{ci[:upper].round(3)}])"
```

### 4. Use Multiple Judges for Important Decisions

```ruby
# ❌ Risky: Single judge for critical evaluation
result = single_judge.evaluate(...)

# ✅ Better: Multi-judge consensus
evaluator = MultiJudgeEvaluator.new(
  models: ["gpt-4o", "claude-3-5-sonnet", "gemini-1.5-pro"]
)
result = evaluator.evaluate(...)
# Requires 2/3 agreement by default
```

### 5. Check for Biases

```ruby
# ✅ Good: Verify judge isn't biased
position_check = debiaser.compare(output_a: a, output_b: b, ...)
raise "Position bias detected!" if position_check[:position_bias_detected]

length_analysis = length_analyzer.analyze_length_correlation(evaluations)
raise "Length bias detected!" if length_analysis[:bias_detected]
```

### 6. Domain-Specific Calibration

```ruby
# ✅ Best: Separate calibration for different domains
medical_judge = StatisticalJudge.new(model: "gpt-4o")
medical_judge.calibrate(medical_calibration, criteria: "Is medically accurate?")

legal_judge = StatisticalJudge.new(model: "gpt-4o")
legal_judge.calibrate(legal_calibration, criteria: "Is legally sound?")
```

### 7. Version Your Calibration Sets

```ruby
calibration = CalibrationSet.new(metadata: {
  version: "2.0.0",
  created_by: "evaluation_team",
  domain: "customer_support",
  notes: "Updated with edge cases from Q4 2024"
})

calibration.save("calibration_v2.0.0.json")
```

---

## API Reference

### CalibrationSet

```ruby
# Constructor
CalibrationSet.new(samples: [], metadata: {})

# Instance Methods
calibration.add(input:, output:, ground_truth:, context: {})
calibration.positive_samples  # Array of samples where ground_truth=true
calibration.negative_samples  # Array of samples where ground_truth=false
calibration.m1               # Count of positive samples
calibration.m0               # Count of negative samples
calibration.size             # Total sample count
calibration.valid?(min_positive: 10, min_negative: 10)
calibration.validate!(min_positive: 10, min_negative: 10)
calibration.split(ratio: 0.8, seed: nil)
calibration.stratified_split(ratio: 0.8, seed: nil)
calibration.filter(**criteria)
calibration.statistics
calibration.save(file_path)
calibration.to_json
calibration.to_h

# Class Methods
CalibrationSet.load(file_path)
CalibrationSet.from_json(json_string)
CalibrationSet.merge(*sets)
```

### StatisticalJudge

```ruby
# Constructor
StatisticalJudge.new(
  model: "gpt-4o",
  temperature: 0.0,
  cache: true,
  timeout: 30,
  criteria: nil
)

# Calibration
judge.calibrate(calibration_set, criteria:, min_samples: 10)
judge.calibrated?
judge.better_than_random?
judge.reset_calibration!

# Evaluation
judge.evaluate(input:, output:, criteria:)
judge.evaluate_batch(samples, criteria:, alpha: 0.05)
judge.bias_corrected_accuracy(raw_proportion)
judge.confidence_interval(raw_proportion, test_size, alpha: 0.05)

# Allocation
judge.optimal_calibration_allocation(total_budget:, pilot_set:, expected_positive_rate:)

# Properties
judge.model
judge.temperature
judge.sensitivity
judge.specificity
judge.calibration_set
judge.calibration_metadata
judge.summary
```

### MultiJudgeEvaluator

```ruby
# Constructor
MultiJudgeEvaluator.new(
  judges: nil,          # Array of StatisticalJudge
  models: nil,          # Array of model names
  default_strategy: :majority,
  temperature: 0.0,
  cache: true
)

# Calibration
evaluator.calibrate_all(calibration_set, criteria:)

# Evaluation
evaluator.evaluate(input:, output:, criteria:)
evaluator.evaluate_weighted(input:, output:, criteria:)
evaluator.evaluate_unanimous(input:, output:, criteria:)
evaluator.evaluate_threshold(input:, output:, criteria:, threshold: 0.66)
evaluator.evaluate_batch(samples, criteria:, strategy: nil)

# Analysis
evaluator.flag_for_human_review(samples, criteria:, disagreement_threshold: 0.5)
evaluator.inter_rater_reliability(samples, criteria:)
evaluator.judges_summary
```

### BiasMitigation

```ruby
# Position Debiasing
debiaser = BiasMitigation::PositionDebiaser.new(judge:, permutations: 2)
debiaser.compare(input:, output_a:, output_b:, criteria:)
debiaser.rank(input:, outputs:, criteria:)

# Length Bias Analysis
analyzer = BiasMitigation::LengthBiasAnalyzer.new
analyzer.analyze_length_correlation(evaluations)
analyzer.normalize_for_length(evaluations, target_correlation: 0.0)

# Format Bias Analysis
analyzer = BiasMitigation::FormatBiasAnalyzer.new
analyzer.analyze(evaluations)

# Consistency Checking
checker = BiasMitigation::ConsistencyChecker.new(judge:, repetitions: 3)
checker.check(input:, output:, criteria:)
checker.check_batch(samples, criteria:)
```

---

## References

### Primary Paper

> **Lee, C., Zeng, T., et al.** (2025). "How to Correctly Report LLM-as-a-Judge Evaluations." *arXiv preprint arXiv:2511.21140*.
>
> - Paper: https://arxiv.org/abs/2511.21140
> - Code: https://github.com/UW-Madison-Lee-Lab/LLM-judge-reporting

### Comprehensive Survey

> **CSHaitao et al.** (2024). "LLMs-as-Judges: A Comprehensive Survey on LLM-based Evaluation Methods."
>
> - Paper: https://arxiv.org/abs/2412.05579
> - Repository: https://github.com/CSHaitao/Awesome-LLMs-as-Judges

### Additional Resources

- [A Survey on LLM-as-a-Judge](https://arxiv.org/abs/2411.15594) - Another comprehensive survey
- [Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena](https://arxiv.org/abs/2306.05685) - Foundational work on LLM judges
- [G-Eval: NLG Evaluation using GPT-4](https://arxiv.org/abs/2303.16634) - Early influential work

---

## Changelog

### Version 1.0.0 (2025-12-03)

- Initial release of statistical LLM judge module
- Implemented bias-corrected accuracy from Lee et al. (2025)
- Added confidence interval construction with dual uncertainty sources
- Created CalibrationSet for managing ground-truth data
- Implemented MultiJudgeEvaluator for consensus evaluation
- Added comprehensive bias mitigation utilities
- Created RSpec matchers for statistical testing
