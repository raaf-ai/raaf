# RAAF Eval RSpec Integration Guide

> **Complete Guide to Testing AI Agents with RSpec**
> Version: 2.0.0
> Last Updated: 2025-01-12

## Table of Contents

1. [Overview](#overview)
2. [Installation & Setup](#installation--setup)
3. [Quick Start](#quick-start)
4. [Helper Methods](#helper-methods)
5. [Evaluation DSL](#evaluation-dsl)
6. [Complete Matcher Reference](#complete-matcher-reference)
7. [Advanced Usage](#advanced-usage)
8. [CI/CD Integration](#cicd-integration)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

---

## Overview

RAAF Eval's RSpec integration provides a comprehensive testing framework for AI agents. It enables:

- **Automated Regression Testing**: Detect when agent changes degrade quality
- **Performance Validation**: Ensure latency and token usage remain acceptable
- **Safety & Bias Detection**: Verify outputs meet safety and fairness standards
- **Statistical Analysis**: Measure significance of performance changes
- **LLM-Powered Evaluation**: Use AI judges for subjective quality assessments

### Key Benefits

✅ **Native RSpec Integration** - Familiar test syntax and matchers
✅ **40+ Custom Matchers** - Comprehensive evaluation coverage
✅ **3-Tier Labeling System** - Nuanced quality assessment (good/average/bad)
✅ **Automatic Span Management** - No manual trace extraction
✅ **Statistical Rigor** - Confidence intervals, t-tests, effect sizes
✅ **Production-Ready** - Battle-tested in real RAAF projects

## 3-Tier Labeling System

RAAF Eval uses a three-tier labeling system for evaluation results:

- **good** - High quality, exceeds expectations
- **average** - Acceptable quality, room for improvement
- **bad** - Poor quality, requires attention

### Basic Label Matchers

```ruby
# Check specific labels
expect(result).to be_good                    # Label is "good"
expect(result).to be_average                 # Label is "average"
expect(result).to be_bad                     # Label is "bad"

# Check minimum quality level
expect(result).to be_at_least("average")     # Label is "average" or "good"
expect(result).to be_at_least("good")        # Label is "good"

# Direct field access
expect(result[:label]).to eq("good")         # Check label field
expect(result[:score]).to be >= 0.8          # Check score threshold
```

### Category-Specific Thresholds

Different evaluator categories use different thresholds:

| Category | Good Threshold | Average Threshold | Rationale |
|----------|---------------|-------------------|-----------|
| Quality | 0.8 | 0.6 | Balanced quality expectations |
| Performance | 0.85 | 0.7 | Higher bar for efficiency |
| Safety | 0.9 | 0.75 | Strictest for safety-critical |
| Structural | 0.9 | 0.7 | High precision for structure |
| Statistical | 0.8 | 0.6 | Standard statistical confidence |
| LLM | 0.8 | 0.6 | Balanced LLM judge expectations |

### Custom Thresholds

You can customize thresholds per evaluation:

```ruby
evaluate_field :output do
  evaluate_with :semantic_similarity,
    good_threshold: 0.85,
    average_threshold: 0.65
end
```

---

## Installation & Setup

### 1. Add to Gemfile

```ruby
gem 'raaf-eval', '~> 1.0'
```

### 2. Install

```bash
bundle install
bundle exec rake raaf_eval:install:migrations
bundle exec rake db:migrate
```

### 3. Configure RSpec

Create `spec/support/raaf_eval.rb`:

```ruby
require 'raaf/eval/rspec'

RSpec.configure do |config|
  # Include RAAF Eval helpers
  config.include RAAF::Eval::RSpec::Helpers

  # Configure LLM judge (optional)
  RAAF::Eval::RSpec.configure do |eval_config|
    eval_config.llm_judge_model = 'gpt-4o'
    eval_config.llm_judge_temperature = 0.3
    eval_config.llm_judge_cache = true
    eval_config.llm_judge_timeout = 30
  end
end
```

### 4. Database Setup

Ensure PostgreSQL is running and configured:

```ruby
# config/database.yml or ENV variable
RAAF_EVAL_DATABASE_URL=postgresql://localhost/raaf_eval_test
```

---

## Quick Start

### Basic Evaluation Test

```ruby
RSpec.describe "Customer Support Agent" do
  let(:agent) do
    RAAF::Agent.new(
      name: "SupportAgent",
      instructions: "You are a helpful customer support agent",
      model: "gpt-4o"
    )
  end

  it "maintains quality when switching to gpt-4o-mini" do
    # Run with original model
    baseline = RAAF::Runner.new(agent: agent).run("How do I reset my password?")

    # Store span for evaluation
    span = RAAF::Eval::SpanSerializer.serialize(baseline.last_span)

    # Evaluate with different model
    result = evaluate_span(span, configurations: {
      mini: { model: "gpt-4o-mini" }
    })

    # 3-tier labeling system assertions
    expect(result).to be_good                    # Quality is "good"
    expect(result).to be_at_least("average")     # At least "average"
    expect(result[:label]).to eq("good")         # Direct label check
    expect(result[:score]).to be >= 0.8          # Score threshold
  end
end
```

### Performance Testing

```ruby
it "improves latency with streaming" do
  result = evaluate_latest_span(configurations: {
    baseline: {},
    streaming: { stream: true }
  })

  expect(result[:streaming]).to be_faster_than(result[:baseline])
  expect(result[:streaming]).to have_tokens_within(0.8..1.2).of_baseline
end
```

---

## Helper Methods

### Core Helpers

#### `evaluate_span(span, configurations:)`

Evaluate a specific span with different configurations:

```ruby
span = find_span("span_id")

result = evaluate_span(span, configurations: {
  gpt4: { model: "gpt-4o" },
  gpt35: { model: "gpt-3.5-turbo" },
  mini: { model: "gpt-4o-mini" }
})

expect(result[:gpt4]).to maintain_quality
expect(result[:mini]).to be_faster_than(:gpt4)
```

**Parameters:**
- `span`: Serialized span object or span ID
- `configurations`: Hash of config_name => { settings_hash }

**Returns:** `EvaluationResult` object

#### `evaluate_latest_span(configurations:)`

Evaluate the most recently executed agent:

```ruby
# Run agent
runner.run("User query")

# Evaluate immediately
result = evaluate_latest_span(configurations: {
  test: { temperature: 0.5 }
})

expect(result).to have_valid_format.as(:json)
```

#### `find_span(id)`

Retrieve a specific span by ID:

```ruby
span = find_span("abc123")
puts span.inspect
```

#### `evaluate_run_result(run_result, agent:)`

**NEW:** Evaluate a fresh agent run (RunResult) directly without needing a pre-existing span:

```ruby
# Run agent and get RunResult
agent = MyAgent.new
runner = RAAF::Runner.new(agent: agent)
result = runner.run("What is 2+2?")

# Evaluate the RunResult directly
evaluation = evaluate_run_result(result, agent: agent)
  .with_configuration(temperature: 0.9)
  .run

expect(evaluation).to have_successful_execution
expect(evaluation).to include_content("4")
```

**Parameters:**
- `run_result`: RAAF::RunResult from `runner.run()`
- `agent`: Optional agent reference for config extraction (model, instructions, parameters)

**Returns:** `SpanEvaluator` for method chaining

**Use Cases:**
- Test new prompts/configs from scratch
- Develop agent behaviors without historical spans
- Run parametric tests across configurations

#### `evaluate_span` with RunResult

The `evaluate_span` helper also supports **auto-detection** of RunResult objects:

```ruby
result = runner.run("Test prompt")

# Auto-converts RunResult to span format
evaluate_span(result, agent: agent)
  .with_configuration(model: "claude-3-5-sonnet")
  .run
```

### Span vs RunResult Evaluation

| Aspect | Span-Based | RunResult-Based |
|--------|-----------|-----------------|
| **Starting Point** | Existing production/test span | Fresh agent execution |
| **Use Case** | Iterate on real scenarios | Test new prompts from scratch |
| **Context** | Preserves original execution | Creates new execution context |
| **Typical Workflow** | Debug/optimize existing runs | Develop/test new behaviors |

**Recommendation:** Use both approaches in your test suite:

```ruby
RSpec.describe "Agent Evaluation" do
  let(:agent) { MyAgent.new }

  # Test fresh runs
  context "direct evaluation" do
    it "responds correctly to new prompts" do
      result = RAAF::Runner.new(agent: agent).run("New test prompt")

      evaluation = evaluate_run_result(result, agent: agent)
        .with_configuration(temperature: 0.7)
        .run

      expect(evaluation).to have_successful_execution
    end
  end

  # Test historical spans
  context "span-based evaluation" do
    it "maintains quality when changing models" do
      baseline = find_span(agent: "MyAgent", prompt_contains: "research")

      result = evaluate_span(baseline)
        .with_configuration(model: "claude-3-5-sonnet")
        .run

      expect(result).not_to regress_from_baseline
    end
  end
end
```

#### `query_spans(filters)`

Search for spans matching criteria:

```ruby
spans = query_spans(
  agent_name: "SupportAgent",
  success: true,
  min_date: 1.week.ago
)

spans.each do |span|
  result = evaluate_span(span, configurations: { test: {} })
  expect(result).to_not have_regressions
end
```

**Available Filters:**
- `agent_name`: Filter by agent name
- `model`: Filter by model used
- `success`: true/false for successful/failed runs
- `min_date`, `max_date`: Time range
- `min_tokens`, `max_tokens`: Token usage range
- `min_latency`, `max_latency`: Latency range (ms)

#### `latest_span_for(agent_name)`

Get latest span for specific agent:

```ruby
span = latest_span_for("SupportAgent")
result = evaluate_span(span, configurations: { optimized: { temperature: 0 } })
```

---

## Evaluation DSL

### Fluent Evaluation Builder

The `SpanEvaluator` provides a fluent interface for building evaluations:

```ruby
# Method 1: Using helper
result = evaluate_span(span)
  .with_configuration(name: "test", model: "gpt-4o")
  .with_configuration(name: "baseline", model: "gpt-3.5-turbo")
  .execute

# Method 2: Direct instantiation
evaluator = SpanEvaluator.new(span)
evaluator.with_configuration(name: "optimized", temperature: 0.3, max_tokens: 500)
evaluator.with_configuration(name: "creative", temperature: 0.9, max_tokens: 1000)
result = evaluator.execute

# Multiple configs at once
result = evaluate_span(span)
  .with_configurations({
    fast: { model: "gpt-3.5-turbo", temperature: 0 },
    balanced: { model: "gpt-4o", temperature: 0.5 },
    creative: { model: "gpt-4o", temperature: 0.9 }
  })
  .execute
```

### Chaining Operations

```ruby
result = evaluate_span(span)
  .with_configuration(name: "test", model: "gpt-4o-mini")
  .with_timeout(30)
  .with_retries(3)
  .execute

expect(result).to maintain_quality.and be_faster_than(:baseline)
```

---

## Complete Matcher Reference

### Performance Matchers (6 matchers)

#### `be_faster_than(target)`

Assert latency improvement:

```ruby
expect(result).to be_faster_than(:baseline)
expect(result).to be_faster_than(500) # ms
expect(result[:optimized]).to be_faster_than(result[:baseline])
```

#### `expect_no_regression`

Detect performance regressions:

```ruby
expect(result).to expect_no_regression
expect(result).to expect_no_regression.of_severity(:high)
```

#### `expect_tokens_within(range)`

Validate token usage:

```ruby
expect(result).to expect_tokens_within(100..200)
expect(result).to expect_tokens_within(0.8..1.2).of_baseline
```

#### `expect_cost_under(amount)`

Ensure cost thresholds:

```ruby
expect(result).to expect_cost_under(0.01) # dollars
expect(result).to expect_cost_under(result[:baseline] * 1.5)
```

#### `expect_throughput_improved`

Measure throughput gains:

```ruby
expect(result[:parallel]).to expect_throughput_improved.over(:serial)
```

#### `expect_time_to_first_token_under(ms)`

Streaming latency:

```ruby
expect(result[:streaming]).to expect_time_to_first_token_under(500)
```

### Quality Matchers (7+ matchers)

#### `maintain_quality`

Core quality comparison:

```ruby
expect(result).to maintain_quality
expect(result).to maintain_quality.within(30).percent
expect(result).to maintain_quality.compared_to(:baseline)
```

#### `have_similar_output_to(target)`

Semantic similarity:

```ruby
expect(result).to have_similar_output_to(:baseline)
expect(result).to have_similar_output_to("expected output text")
expect(result).to have_similar_output_to(:baseline).within(20).percent
```

#### `expect_improved_quality`

Quality improvement assertion:

```ruby
expect(result[:gpt4]).to expect_improved_quality.over(:gpt35)
```

#### `expect_no_quality_regression`

Prevent quality degradation:

```ruby
expect(result).to expect_no_quality_regression
expect(result).to expect_no_quality_regression.with_threshold(0.7)
```

#### `expect_coherence_above(score)`

Coherence threshold (0.0-1.0):

```ruby
expect(result).to expect_coherence_above(0.8)
```

#### `expect_semantic_similarity_above(score)`

Similarity score (0.0-1.0):

```ruby
expect(result).to expect_semantic_similarity_above(0.75)
```

#### `expect_no_hallucinations`

Hallucination detection:

```ruby
expect(result).to expect_no_hallucinations
```

### Regression Matchers (5+ matchers)

#### `not_have_regressions`

General regression detection:

```ruby
expect(result).to_not have_regressions
expect(result).to_not have_regressions.of_severity(:high)
```

#### `perform_better_than(target)`

Multi-metric performance:

```ruby
expect(result).to perform_better_than(:baseline)
expect(result).to perform_better_than(:baseline).on_metrics(:quality, :latency, :tokens)
```

#### `have_acceptable_variance`

Variance checking:

```ruby
expect(result).to have_acceptable_variance
expect(result).to have_acceptable_variance.within(2).standard_deviations
expect(result).to have_acceptable_variance.for_metric(:latency)
```

### Statistical Matchers (6+ matchers)

#### `be_statistically_significant`

Statistical significance testing:

```ruby
expect(result).to be_statistically_significant
expect(result).to be_statistically_significant.at_level(0.05)
```

#### `have_effect_size`

Effect size measurement (Cohen's d):

```ruby
expect(result).to have_effect_size.above(0.5) # Medium effect
expect(result).to have_effect_size.above(0.8) # Large effect
```

#### `have_confidence_interval`

Confidence interval validation:

```ruby
expect(result).to have_confidence_interval.within(90, 110)
expect(result).to have_confidence_interval.at_confidence(0.95)
expect(result).to have_confidence_interval.at_confidence(0.99).within(80, 120)
```

### Safety Matchers (6+ matchers)

#### `not_have_bias`

Bias detection across dimensions:

```ruby
expect(result).to_not have_bias
expect(result).to_not have_bias.for_gender
expect(result).to_not have_bias.for_race
expect(result).to_not have_bias.for_region
```

#### `be_safe`

Safety and toxicity checking:

```ruby
expect(result).to be_safe
expect(result).to be_safe.with_toxicity_below(0.3)
```

#### `comply_with_policy`

Policy compliance:

```ruby
expect(result).to comply_with_policy.for("no_medical_advice")
expect(result).to comply_with_policy.for("no_financial_advice")
expect(result).to comply_with_policy.for("no_personal_data")
```

### Structural Matchers (5+ matchers)

#### `have_valid_format`

Format validation:

```ruby
expect(result).to have_valid_format.as(:json)
expect(result).to have_valid_format.as(:xml)
expect(result).to have_valid_format.as(:markdown)
expect(result).to have_valid_format.as(:html)
```

#### `match_schema(schema)`

Schema validation:

```ruby
schema = {
  name: String,
  age: Integer,
  email: String
}

expect(result).to match_schema(schema)
```

#### `have_length`

Length constraints:

```ruby
expect(result).to have_length.between(100, 500)
expect(result).to have_length.less_than(1000)
expect(result).to have_length.greater_than(50)
expect(result).to have_length.of(250)
```

### LLM Matchers (7+ matchers)

#### `satisfy_llm_check(prompt)`

Custom LLM-based checks:

```ruby
expect(result).to satisfy_llm_check("is helpful and informative")
expect(result).to satisfy_llm_check("explains Ruby clearly").using_model("gpt-4")
expect(result).to satisfy_llm_check("is comprehensive").with_confidence(0.8)
```

#### `satisfy_llm_criteria(criteria)`

Multi-criteria LLM evaluation:

```ruby
# Array format
criteria = [
  "is clear and easy to understand",
  "is technically accurate",
  "provides actionable examples"
]
expect(result).to satisfy_llm_criteria(criteria)

# Hash format with weights
criteria = {
  clarity: { description: "Easy to understand", weight: 2.0 },
  accuracy: { description: "Factually correct", weight: 1.5 },
  completeness: { description: "Covers all aspects", weight: 1.0 }
}
expect(result).to satisfy_llm_criteria(criteria).using_model("gpt-4")
```

#### `be_judged_as(description)`

Flexible quality judgments:

```ruby
expect(result).to be_judged_as("helpful")
expect(result).to be_judged_as("more technical").than(:baseline)
expect(result).to be_judged_as("better").than("previous output text")
expect(result).to be_judged_as("comprehensive").using_model("gpt-4")
```

---

## Advanced Usage

### Parallel Evaluation

Run multiple configurations simultaneously:

```ruby
result = evaluate_span(span)
  .with_configurations({
    fast: { model: "gpt-3.5-turbo" },
    balanced: { model: "gpt-4o" },
    precise: { model: "gpt-4o", temperature: 0 }
  })
  .execute

# All configs evaluated in parallel
expect(result[:fast]).to be_faster_than(result[:balanced])
expect(result[:precise]).to have_effect_size.above(0.5).compared_to(:fast)
```

### Custom Metrics

Define domain-specific metrics:

```ruby
class CodeQualityMetric < RAAF::Eval::Metrics::CustomMetric
  def calculate(output, context)
    lines = output.split("\n")
    {
      line_count: lines.size,
      has_tests: output.include?("describe"),
      complexity: calculate_complexity(lines)
    }
  end
end

# Register metric
RAAF::Eval::Metrics.register(:code_quality, CodeQualityMetric)

# Use in tests
result = evaluate_span(span, configurations: { test: {} })
expect(result[:test][:custom_metrics][:code_quality][:has_tests]).to be true
```

### Batch Testing

Test multiple spans:

```ruby
RSpec.describe "All Support Responses" do
  let(:recent_spans) { query_spans(agent_name: "SupportAgent", min_date: 1.week.ago) }

  it "maintains quality across all responses" do
    results = recent_spans.map do |span|
      evaluate_span(span, configurations: { test: { model: "gpt-4o-mini" } })
    end

    results.each do |result|
      expect(result).to maintain_quality.within(30).percent
      expect(result).to_not have_bias
      expect(result).to be_safe
    end
  end
end
```

### A/B Testing with Statistical Rigor

```ruby
it "proves gpt-4o significantly better than gpt-3.5-turbo" do
  # Run multiple trials
  trials = 10.times.map do
    evaluate_span(span, configurations: {
      gpt4: { model: "gpt-4o" },
      gpt35: { model: "gpt-3.5-turbo" }
    })
  end

  # Aggregate results
  aggregated = RAAF::Eval::StatisticalAnalyzer.aggregate(trials)

  # Assert statistical significance
  expect(aggregated).to be_statistically_significant.at_level(0.05)
  expect(aggregated).to have_effect_size.above(0.5)
  expect(aggregated).to have_confidence_interval.within(0.7, 0.9)
end
```

---

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/eval.yml
name: RAAF Eval Tests

on: [push, pull_request]

jobs:
  eval:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.3
          bundler-cache: true

      - name: Setup Database
        env:
          RAAF_EVAL_DATABASE_URL: postgresql://postgres:postgres@localhost:5432/raaf_eval_test
        run: |
          bundle exec rake raaf_eval:install:migrations
          bundle exec rake db:migrate

      - name: Run Evaluation Tests
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
          RAAF_EVAL_DATABASE_URL: postgresql://postgres:postgres@localhost:5432/raaf_eval_test
        run: bundle exec rspec spec/evaluations/
```

### GitLab CI

```yaml
# .gitlab-ci.yml
eval_tests:
  image: ruby:3.3
  services:
    - postgres:16
  variables:
    POSTGRES_DB: raaf_eval_test
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: postgres
    RAAF_EVAL_DATABASE_URL: postgresql://postgres:postgres@postgres:5432/raaf_eval_test
  script:
    - bundle install
    - bundle exec rake raaf_eval:install:migrations
    - bundle exec rake db:migrate
    - bundle exec rspec spec/evaluations/
```

---

## Best Practices

### 1. Organize Evaluation Tests

```ruby
# spec/evaluations/
# ├── support_agent_spec.rb
# ├── code_generator_spec.rb
# └── summarizer_spec.rb

# Use dedicated directory
RSpec.describe "Support Agent Evaluations", type: :evaluation do
  # Tests here
end
```

### 2. Use Shared Examples

```ruby
RSpec.shared_examples "maintains quality" do |config_name|
  it "maintains quality with #{config_name}" do
    result = evaluate_span(span, configurations: { test: config })
    expect(result).to maintain_quality.within(20).percent
    expect(result).to_not have_regressions
  end
end

RSpec.describe "Agent Quality" do
  let(:span) { latest_span_for("MyAgent") }

  it_behaves_like "maintains quality", "gpt-4o-mini"
  it_behaves_like "maintains quality", "gpt-3.5-turbo"
end
```

### 3. Tag Tests Appropriately

```ruby
RSpec.describe "Expensive Evaluations", :slow, :ai_judge do
  # Run with: bundle exec rspec --tag ~slow
end

RSpec.describe "Critical Path", :critical do
  # Run with: bundle exec rspec --tag critical
end
```

### 4. Cache Evaluation Results

```ruby
# Use let! for expensive evaluations
let!(:cached_result) do
  evaluate_span(span, configurations: { test: {} })
end

it "passes quality check" do
  expect(cached_result).to maintain_quality
end

it "is safe" do
  expect(cached_result).to be_safe
end
```

### 5. Document Expectations

```ruby
it "maintains semantic similarity above 75% when switching to mini model" do
  # Why: Cost optimization requires using cheaper model
  # Threshold: 75% based on user acceptance testing
  # Impact: Reduces inference cost by 90%

  result = evaluate_span(span, configurations: {
    mini: { model: "gpt-4o-mini" }
  })

  expect(result).to have_semantic_similarity_above(0.75)
end
```

---

## Troubleshooting

### Common Issues

#### Issue: "No spans found"

```ruby
# Problem: Agent hasn't been executed yet
runner.run("query") # Execute first
result = evaluate_latest_span(...) # Then evaluate
```

#### Issue: "Database connection failed"

```ruby
# Ensure database is configured
ENV['RAAF_EVAL_DATABASE_URL'] = 'postgresql://localhost/raaf_eval_test'

# Run migrations
bundle exec rake raaf_eval:install:migrations
bundle exec rake db:migrate
```

#### Issue: "LLM judge timeout"

```ruby
# Increase timeout
RAAF::Eval::RSpec.configure do |config|
  config.llm_judge_timeout = 60 # seconds
end
```

#### Issue: "Flaky statistical tests"

```ruby
# Increase sample size
10.times do # Instead of 3
  evaluate_span(span, configurations: {...})
end

# Use wider confidence intervals
expect(result).to have_confidence_interval.at_confidence(0.90) # Instead of 0.99
```

### Debug Mode

Enable detailed logging:

```ruby
# spec/spec_helper.rb
RAAF::Eval.configure do |config|
  config.log_level = :debug
  config.log_evaluations = true
end
```

### Performance Tips

1. **Use Parallel Evaluation**: Evaluates configs concurrently
2. **Cache Judge Results**: Enable LLM judge caching
3. **Limit Span Queries**: Use specific filters in `query_spans`
4. **Batch Similar Tests**: Group evaluations to reuse spans

---

## Additional Resources

- **API Reference**: See [API.md](API.md)
- **Metrics Guide**: See [METRICS.md](METRICS.md)
- **Architecture**: See [ARCHITECTURE.md](ARCHITECTURE.md)
- **Examples**: Check `examples/rspec/` directory

---

**Need Help?** Open an issue on GitHub or consult the [RAAF documentation](https://github.com/yourusername/raaf).

**Version**: 2.0.0 | **Last Updated**: 2025-01-12
