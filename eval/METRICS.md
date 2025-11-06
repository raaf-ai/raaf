# RAAF Eval Metrics System

> Version: 1.0.0
> Last Updated: 2025-11-07
> Comprehensive Guide to Metrics and Interpretation

## Overview

RAAF Eval provides a comprehensive metrics system for evaluating AI agent performance across multiple dimensions. Metrics are organized into four main categories: quantitative, qualitative, statistical, and custom.

## Metric Categories

### 1. Quantitative Metrics

Fast, deterministic metrics calculated from span data.

#### Token Metrics

Measures token usage and associated costs.

**Class**: `RAAF::Eval::Metrics::TokenMetrics`

**Calculated Fields**:
```ruby
{
  baseline_total_tokens: 150,        # Total tokens in baseline
  baseline_input_tokens: 75,         # Input tokens in baseline
  baseline_output_tokens: 75,        # Output tokens in baseline
  baseline_reasoning_tokens: 10,     # Reasoning tokens (if applicable)
  baseline_cost: 0.00225,            # Estimated cost in USD

  result_total_tokens: 140,          # Total tokens in result
  result_input_tokens: 75,           # Input tokens in result
  result_output_tokens: 65,          # Output tokens in result
  result_reasoning_tokens: 8,        # Reasoning tokens (if applicable)
  result_cost: 0.00210,              # Estimated cost in USD

  token_delta: -10,                  # Difference (result - baseline)
  token_delta_percentage: -6.67,     # Percentage change
  cost_delta: -0.00015,              # Cost difference in USD
  cost_delta_percentage: -6.67       # Cost percentage change
}
```

**Interpretation**:
- **Negative delta**: Result uses fewer tokens (usually better)
- **Positive delta**: Result uses more tokens (may indicate more detailed response)
- **Cost delta**: Direct cost impact of configuration change

**Example Usage**:
```ruby
token_metrics = RAAF::Eval::Metrics::TokenMetrics.new
result = token_metrics.calculate(baseline_span, result_span)

if result[:token_delta_percentage] < -10
  puts "Significant token reduction: #{result[:token_delta_percentage]}%"
elsif result[:token_delta_percentage] > 10
  puts "Significant token increase: #{result[:token_delta_percentage]}%"
end
```

#### Latency Metrics

Measures execution performance and speed.

**Class**: `RAAF::Eval::Metrics::LatencyMetrics`

**Calculated Fields**:
```ruby
{
  baseline_latency_ms: 1500,         # Baseline execution time
  baseline_ttft_ms: 300,             # Time to first token
  baseline_time_per_token_ms: 16,    # Average time per output token

  result_latency_ms: 1300,           # Result execution time
  result_ttft_ms: 280,               # Time to first token
  result_time_per_token_ms: 20,      # Average time per output token

  latency_delta_ms: -200,            # Time difference
  latency_delta_percentage: -13.33,  # Percentage change
  ttft_delta_ms: -20,                # TTFT difference
  improvement: true                  # Boolean: faster execution?
}
```

**Interpretation**:
- **Negative latency delta**: Result is faster (better)
- **TTFT delta**: Important for streaming/user experience
- **Time per token**: Efficiency of token generation

**Example Usage**:
```ruby
latency_metrics = RAAF::Eval::Metrics::LatencyMetrics.new
result = latency_metrics.calculate(baseline_span, result_span)

if result[:improvement]
  puts "✓ Performance improved by #{result[:latency_delta_percentage].abs}%"
else
  puts "⚠ Performance degraded by #{result[:latency_delta_percentage]}%"
end
```

#### Accuracy Metrics

Compares output similarity and accuracy.

**Class**: `RAAF::Eval::Metrics::AccuracyMetrics`

**Calculated Fields**:
```ruby
{
  exact_match: false,                # Boolean: identical outputs
  fuzzy_match_score: 0.87,           # Similarity score (0-1)
  edit_distance: 15,                 # Levenshtein distance
  word_overlap: 0.92,                # Ratio of common words
  bleu_score: 0.85,                  # BLEU score (NLP metric)
  character_accuracy: 0.95           # Character-level accuracy
}
```

**Interpretation**:
- **Exact match**: Perfect reproduction (may not be desirable)
- **Fuzzy match > 0.8**: High similarity, likely acceptable
- **Fuzzy match < 0.6**: Significant divergence, review needed
- **Edit distance**: Number of character changes needed
- **BLEU score**: Industry-standard NLP evaluation metric

**Example Usage**:
```ruby
accuracy_metrics = RAAF::Eval::Metrics::AccuracyMetrics.new
result = accuracy_metrics.calculate(baseline_span, result_span)

case result[:fuzzy_match_score]
when 0.9..1.0
  puts "Excellent match: #{(result[:fuzzy_match_score] * 100).round}%"
when 0.7..0.9
  puts "Good match: #{(result[:fuzzy_match_score] * 100).round}%"
when 0.5..0.7
  puts "Moderate match: #{(result[:fuzzy_match_score] * 100).round}%"
else
  puts "Poor match: #{(result[:fuzzy_match_score] * 100).round}%"
end
```

#### Structural Metrics

Validates output structure and format.

**Class**: `RAAF::Eval::Metrics::StructuralMetrics`

**Calculated Fields**:
```ruby
{
  baseline_length: 250,              # Baseline output length (chars)
  result_length: 230,                # Result output length (chars)
  length_delta: -20,                 # Length difference
  length_delta_percentage: -8.0,     # Percentage change

  format_valid: true,                # Boolean: valid format
  has_code_blocks: true,             # Boolean: contains code
  code_block_count: 2,               # Number of code blocks
  has_lists: true,                   # Boolean: contains lists
  has_links: false,                  # Boolean: contains URLs

  schema_valid: true,                # Boolean: matches expected schema
  schema_errors: []                  # Array of validation errors
}
```

**Interpretation**:
- **Length delta**: Indicates conciseness vs detail
- **Format validation**: Ensures output meets requirements
- **Code blocks**: Useful for technical content evaluation
- **Schema validation**: Critical for structured outputs (JSON, etc.)

**Example Usage**:
```ruby
structural_metrics = RAAF::Eval::Metrics::StructuralMetrics.new
result = structural_metrics.calculate(baseline_span, result_span)

unless result[:format_valid]
  puts "⚠ Format validation failed"
end

if result[:has_code_blocks]
  puts "✓ Contains #{result[:code_block_count]} code block(s)"
end
```

### 2. Qualitative Metrics (AI-Powered)

Advanced metrics using AI to evaluate subjective quality.

#### AI Comparator

Uses AI to compare outputs on multiple qualitative dimensions.

**Class**: `RAAF::Eval::Metrics::AIComparator`

**Calculated Fields**:
```ruby
{
  # Similarity Assessment
  semantic_similarity_score: 0.88,   # Semantic similarity (0-1)
  coherence_score: 0.92,             # Logical coherence (0-1)
  relevance_score: 0.95,             # Relevance to input (0-1)

  # Quality Checks
  hallucination_detected: false,     # Boolean: contains hallucinations
  hallucination_details: [],         # Array of detected hallucinations

  # Bias Detection
  bias_detected: {
    gender: false,                   # Gender bias present
    race: false,                     # Racial bias present
    region: false,                   # Regional/cultural bias
    age: false,                      # Age bias present
    other: false                     # Other bias types
  },
  bias_details: [],                  # Specific bias instances

  # Style Analysis
  tone_consistency: 0.90,            # Tone match to baseline (0-1)
  tone_shift: "neutral → friendly",  # Tone change description
  formality_level: "professional",   # Detected formality level

  # Factuality
  factuality_score: 0.95,            # Factual accuracy (0-1)
  factual_claims_verified: 5,        # Number of claims checked
  factual_errors: 0,                 # Number of factual errors

  # Safety & Compliance
  toxicity_detected: false,          # Boolean: toxic content
  pii_detected: false,               # Boolean: PII present
  policy_compliant: true,            # Boolean: meets policies

  # Explanation
  comparison_reasoning: "...",       # Detailed explanation

  # Metadata
  evaluation_model: "gpt-4o",        # Model used for comparison
  evaluation_cost: 0.002,            # Cost of AI comparison
  evaluation_latency_ms: 2500        # Time taken for comparison
}
```

**Interpretation**:
- **Semantic similarity > 0.8**: Outputs convey similar meaning
- **Hallucination detected**: Critical issue, requires review
- **Bias detection**: Important for fair, inclusive outputs
- **Factuality < 0.7**: Potential accuracy issues
- **Toxicity/PII**: Compliance and safety concerns

**Example Usage**:
```ruby
ai_comparator = RAAF::Eval::Metrics::AIComparator.new
result = ai_comparator.calculate(baseline_span, result_span)

# Check for critical issues
if result[:hallucination_detected]
  puts "⚠ CRITICAL: Hallucinations detected"
  puts result[:hallucination_details].join("\n")
end

if result[:bias_detected].values.any?
  biases = result[:bias_detected].select { |k, v| v }.keys
  puts "⚠ Bias detected: #{biases.join(', ')}"
end

# Check quality scores
if result[:semantic_similarity_score] < 0.7
  puts "⚠ Low semantic similarity: #{result[:semantic_similarity_score]}"
end
```

**Performance Note**: AI comparator is slow (1-5s) and should be run asynchronously:
```ruby
# Run async
comparison_future = Thread.new do
  ai_comparator.calculate(baseline_span, result_span)
end

# Get quantitative metrics immediately
token_result = token_metrics.calculate(baseline_span, result_span)
latency_result = latency_metrics.calculate(baseline_span, result_span)

# Get AI comparison when ready
ai_result = comparison_future.value
```

### 3. Statistical Metrics

Provides statistical rigor for evaluation results.

#### Statistical Analyzer

Calculates confidence intervals and significance tests.

**Class**: `RAAF::Eval::Metrics::StatisticalAnalyzer`

**Calculated Fields**:
```ruby
{
  # Sample Statistics
  baseline_mean: 150.5,              # Baseline mean value
  result_mean: 142.3,                # Result mean value
  baseline_std_dev: 12.5,            # Baseline std deviation
  result_std_dev: 10.8,              # Result std deviation

  # Confidence Intervals (95%)
  baseline_ci: [145.2, 155.8],       # Baseline 95% CI
  result_ci: [138.1, 146.5],         # Result 95% CI
  ci_overlap: false,                 # Boolean: CIs overlap

  # Significance Testing
  t_statistic: -2.45,                # T-test statistic
  p_value: 0.018,                    # P-value
  significant: true,                 # Boolean: p < 0.05
  alpha: 0.05,                       # Significance level

  # Effect Size
  cohens_d: 0.72,                    # Cohen's d (effect size)
  effect_size_interpretation: "medium", # Small/medium/large

  # Sample Info
  baseline_sample_size: 30,          # Number of baseline samples
  result_sample_size: 30,            # Number of result samples
  sufficient_samples: true           # Boolean: >= 10 samples each
}
```

**Interpretation**:
- **P-value < 0.05**: Statistically significant difference
- **CI overlap**: No significant difference if CIs overlap
- **Cohen's d**:
  - Small: 0.2 - 0.5
  - Medium: 0.5 - 0.8
  - Large: > 0.8
- **Sufficient samples**: Need >= 10 samples for reliable statistics

**Example Usage**:
```ruby
# Collect multiple samples
baseline_samples = 30.times.map { run_baseline_evaluation[:tokens] }
result_samples = 30.times.map { run_result_evaluation[:tokens] }

analyzer = RAAF::Eval::Metrics::StatisticalAnalyzer.new
stats = analyzer.analyze(
  baseline_samples.map { |t| { tokens: t } },
  result_samples.map { |t| { tokens: t } }
)

if stats[:significant]
  puts "✓ Statistically significant difference (p=#{stats[:p_value]})"
  puts "  Effect size: #{stats[:effect_size_interpretation]} (d=#{stats[:cohens_d]})"
else
  puts "  No significant difference found"
end
```

### 4. Custom Metrics

Domain-specific metrics defined by users.

#### Creating Custom Metrics

```ruby
class ResponseLengthMetric < RAAF::Eval::Metrics::CustomMetric
  def initialize
    super("response_length")
  end

  def calculate(baseline_span, result_span)
    baseline_output = extract_output(baseline_span)
    result_output = extract_output(result_span)

    {
      baseline_word_count: baseline_output.split.length,
      result_word_count: result_output.split.length,
      word_count_delta: result_output.split.length - baseline_output.split.length,
      meets_requirement: result_output.split.length.between?(50, 200)
    }
  end

  private

  def extract_output(span)
    span.dig(:metadata, :output) || span.dig(:output) || ""
  end
end
```

See [USAGE_GUIDE.md](USAGE_GUIDE.md#custom-metrics) for more examples.

## Regression Detection

### Baseline Comparator

Automatically detects performance regressions.

**Class**: `RAAF::Eval::BaselineComparator`

**Calculated Fields**:
```ruby
{
  # Token Regression
  token_regression: false,           # Boolean: token usage worse
  token_threshold_exceeded: false,   # Boolean: exceeded threshold

  # Latency Regression
  latency_regression: false,         # Boolean: slower
  latency_threshold_exceeded: false, # Boolean: exceeded threshold

  # Quality Regression
  quality_regression: false,         # Boolean: lower quality
  quality_score_delta: 0.05,         # Quality score change

  # Overall Assessment
  regression_detected: false,        # Boolean: any regression
  regression_types: [],              # Array of regression types
  regression_severity: "none",       # none/minor/major/critical

  # Deltas
  token_delta: -10,                  # Token difference
  latency_delta_ms: 50,              # Latency difference
  cost_delta: 0.0001,                # Cost difference

  # Recommendations
  recommendation: "...",             # Action recommendation
  safe_to_deploy: true               # Boolean: safe for production
}
```

**Example Usage**:
```ruby
comparator = RAAF::Eval::BaselineComparator.new
result = comparator.compare(baseline_span, result_span)

if result[:regression_detected]
  puts "⚠ REGRESSION DETECTED"
  puts "  Types: #{result[:regression_types].join(', ')}"
  puts "  Severity: #{result[:regression_severity]}"
  puts "  Safe to deploy: #{result[:safe_to_deploy]}"
  puts "\nRecommendation: #{result[:recommendation]}"
end
```

## Metric Interpretation Guide

### Token Metrics

| Delta | Interpretation | Action |
|-------|---------------|--------|
| < -20% | Significant reduction | Verify quality maintained |
| -20% to -10% | Notable reduction | Good optimization |
| -10% to +10% | Minimal change | Expected variation |
| +10% to +20% | Notable increase | Review if justified |
| > +20% | Significant increase | Investigate cause |

### Latency Metrics

| Delta | Interpretation | Action |
|-------|---------------|--------|
| < -30% | Major speedup | Excellent improvement |
| -30% to -10% | Moderate speedup | Good optimization |
| -10% to +10% | No significant change | Acceptable |
| +10% to +30% | Moderate slowdown | Review if acceptable |
| > +30% | Major slowdown | Investigate cause |

### Accuracy Metrics

| Fuzzy Match | Interpretation | Action |
|-------------|---------------|--------|
| 0.95 - 1.0 | Excellent match | High confidence |
| 0.80 - 0.95 | Good match | Acceptable |
| 0.60 - 0.80 | Moderate match | Review differences |
| < 0.60 | Poor match | Investigate divergence |

### AI Comparator Scores

| Score | Interpretation | Action |
|-------|---------------|--------|
| 0.9 - 1.0 | Excellent | High confidence |
| 0.7 - 0.9 | Good | Acceptable |
| 0.5 - 0.7 | Moderate | Review manually |
| < 0.5 | Poor | Requires attention |

## Metrics Aggregation

### Across Multiple Evaluations

```ruby
# Collect metrics from multiple evaluations
all_token_metrics = evaluations.map { |e| e[:token_metrics] }

# Calculate aggregates
avg_token_delta = all_token_metrics.sum { |m| m[:token_delta] } / all_token_metrics.length
success_rate = evaluations.count { |e| e[:success] }.to_f / evaluations.length

# Find regressions
regressions = evaluations.select { |e| e[:baseline_comparison][:regression_detected] }
regression_rate = regressions.length.to_f / evaluations.length

puts "Average token delta: #{avg_token_delta}"
puts "Success rate: #{(success_rate * 100).round(2)}%"
puts "Regression rate: #{(regression_rate * 100).round(2)}%"
```

### Metric Dashboards

```ruby
class MetricsDashboard
  def initialize(evaluations)
    @evaluations = evaluations
  end

  def summary
    {
      total_evaluations: @evaluations.length,
      success_rate: calculate_success_rate,
      avg_token_delta: calculate_avg_token_delta,
      avg_latency_delta: calculate_avg_latency_delta,
      avg_cost_delta: calculate_avg_cost_delta,
      regression_count: count_regressions,
      quality_scores: aggregate_quality_scores
    }
  end

  private

  def calculate_success_rate
    successes = @evaluations.count { |e| e[:success] }
    (successes.to_f / @evaluations.length * 100).round(2)
  end

  def calculate_avg_token_delta
    token_deltas = @evaluations.map { |e| e.dig(:token_metrics, :token_delta) || 0 }
    (token_deltas.sum.to_f / token_deltas.length).round(2)
  end

  # ... more aggregation methods
end
```

## Best Practices

1. **Use Multiple Metrics**: Don't rely on a single metric
2. **Run Multiple Iterations**: 30+ samples for statistical significance
3. **Async AI Comparator**: Don't block on slow AI metrics
4. **Set Thresholds**: Define acceptable ranges for your use case
5. **Monitor Trends**: Track metrics over time, not just point-in-time
6. **Domain-Specific Metrics**: Create custom metrics for your domain
7. **Cost vs Quality**: Balance cost optimization with quality requirements

## Limitations

1. **AI Comparator**: Depends on AI model quality and costs
2. **Statistical Analysis**: Requires sufficient samples (>= 10)
3. **Accuracy Metrics**: Text-based similarity may not capture semantic differences
4. **Custom Metrics**: Require domain expertise to implement correctly
5. **Baseline Quality**: Metrics assume baseline is "good" - validate baseline first

## Next Steps

- [Usage Guide](USAGE_GUIDE.md) - Learn how to use metrics in practice
- [Custom Metrics Examples](examples/custom_metric_implementation.rb) - See metric implementations
- [API Documentation](API.md) - Complete API reference
