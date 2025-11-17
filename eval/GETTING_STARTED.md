# RAAF Eval - Getting Started Guide

> **Complete tutorial for RAAF Eval evaluation framework**
> Version: 1.0.0 | Last Updated: 2025-01-12

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [Core Concepts](#core-concepts)
4. [Basic Usage](#basic-usage)
5. [RSpec Testing](#rspec-testing)
6. [Web UI Usage](#web-ui-usage)
7. [Advanced Patterns](#advanced-patterns)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)

## Installation

### Prerequisites

- Ruby 3.3+
- PostgreSQL database
- RAAF core and tracing gems

### Install Core Evaluation Engine

```ruby
# Gemfile
gem 'raaf-eval'
```

```bash
bundle install
```

### Database Setup

```bash
# From eval directory
cd vendor/local_gems/raaf/eval
bundle exec rake db:migrate

# Or in Rails app
rails db:migrate
```

This creates four tables:
- `evaluation_runs` - Top-level evaluation records
- `evaluation_spans` - Serialized span snapshots
- `evaluation_configurations` - Configuration variants
- `evaluation_results` - Results and metrics

### Optional: Install Web UI

```ruby
# Gemfile
gem 'raaf-eval-ui'
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount RAAF::Eval::UI::Engine, at: "/eval"
end
```

```bash
bundle install
rails raaf_eval_ui:install:migrations
rails db:migrate
```

See **[UI Setup Guide](../eval-ui/README.md)** for configuration options.

## Quick Start

### 1. Simple Model Comparison

```ruby
require 'raaf/eval'

# Get a baseline span (from production or create one)
baseline_span = {
  span_id: "span_001",
  trace_id: "trace_001",
  agent_name: "HelpfulAssistant",
  metadata: {
    model: "gpt-4o",
    instructions: "You are a helpful assistant.",
    messages: [
      { role: "user", content: "What is the capital of France?" }
    ],
    output: "The capital of France is Paris.",
    usage: { total_tokens: 50, input_tokens: 20, output_tokens: 30 }
  }
}

# Create evaluation engine
engine = RAAF::Eval::EvaluationEngine.new

# Create run comparing two models
run = engine.create_run(
  name: "GPT-4 vs Claude Comparison",
  baseline_span: baseline_span,
  configurations: [
    { name: "GPT-4", changes: { model: "gpt-4o" } },
    { name: "Claude", changes: { model: "claude-3-5-sonnet-20241022", provider: "anthropic" } }
  ]
)

# Execute evaluations
results = engine.execute_run(run)

# View results
results.each do |result|
  puts "#{result.configuration.name}:"
  puts "  Tokens: #{result.token_metrics[:total_tokens]}"
  puts "  Latency: #{result.latency_metrics[:total_ms]}ms"
  puts "  Cost: $#{result.token_metrics[:total_cost]}"
  puts "  Quality: #{result.baseline_comparison[:quality_change]}"
  puts
end
```

### 2. Simple RSpec Test

```ruby
# spec/evaluations/model_comparison_spec.rb
require 'raaf/eval/rspec'

RSpec.describe "Model comparison evaluation" do
  it "Claude maintains quality vs GPT-4" do
    baseline = find_span(agent: "HelpfulAssistant")

    result = evaluate_span(baseline) do |config|
      config.model = "claude-3-5-sonnet-20241022"
      config.provider = "anthropic"
    end

    # 3-tier labeling system (good/average/bad)
    expect(result).to be_good                    # Result quality is "good"
    expect(result).to be_at_least("average")     # At least "average" quality
    expect(result[:label]).to eq("good")         # Direct label check
    expect(result[:score]).to be >= 0.8          # Score threshold
  end
end
```

Run with: `bundle exec rspec spec/evaluations/`

## Core Concepts

### 1. Spans

**Spans** are execution records from RAAF's tracing system. Each span captures:
- Agent configuration (model, instructions, parameters)
- Input messages
- Output response
- Token usage and latency
- Tool calls and handoffs

### 2. Serialization

**Serialization** captures complete span state for reproduction:

```ruby
# Serialize a span from production
span_accessor = RAAF::Eval::SpanAccessor.new
production_span = span_accessor.find_by_id("span_123")
serialized = RAAF::Eval::SpanSerializer.serialize(production_span)

# Serialized data includes:
serialized[:span_id]        # Original span ID
serialized[:agent_name]     # Agent identifier
serialized[:metadata]       # Complete execution context
```

### 3. Configuration Overrides

**Configuration overrides** modify agent behavior:

```ruby
# Override model
{ model: "claude-3-5-sonnet-20241022" }

# Override provider and model
{ model: "claude-3-5-sonnet-20241022", provider: "anthropic" }

# Override temperature
{ temperature: 0.3 }

# Override instructions
{ instructions: "New system prompt..." }

# Override max_tokens
{ max_tokens: 4096 }

# Multiple overrides
{
  model: "gpt-4o",
  temperature: 0.7,
  max_tokens: 2048
}
```

### 4. Evaluation Runs

**Evaluation runs** test multiple configurations:

```ruby
run = engine.create_run(
  name: "Temperature sensitivity test",
  baseline_span: serialized_span,
  configurations: [
    { name: "Low temp", changes: { temperature: 0.2 } },
    { name: "Medium temp", changes: { temperature: 0.7 } },
    { name: "High temp", changes: { temperature: 1.0 } }
  ]
)
```

### 5. Metrics

**Metrics** quantify evaluation results:

**Quantitative**:
- Token usage (input, output, total)
- Latency (request, processing, total)
- Cost (calculated from token usage)
- Length (characters, words)

**Qualitative** (AI-powered):
- Semantic similarity
- Bias detection
- Hallucination detection
- Tone analysis

**Statistical**:
- Confidence intervals
- Significance testing
- Effect size (Cohen's d)

## Basic Usage

### Finding Baseline Spans

#### From Production Traces

```ruby
# Create span accessor
accessor = RAAF::Eval::SpanAccessor.new

# Find by ID
span = accessor.find_by_id("span_123")

# Find by agent name
spans = accessor.find_by_agent("CustomerSupportAgent")

# Find by model
spans = accessor.find_by_model("gpt-4o")

# Find successful spans
spans = accessor.find_successful(agent: "ResearchAgent")

# Find failed spans
spans = accessor.find_failed(agent: "ResearchAgent")

# Complex query
spans = accessor.query(
  agent_name: "SalesAgent",
  model: "gpt-4o",
  status: "completed",
  created_after: 1.day.ago
)
```

#### Creating Test Spans

```ruby
# Minimal test span
test_span = {
  span_id: "test_001",
  trace_id: "trace_001",
  agent_name: "TestAgent",
  metadata: {
    model: "gpt-4o",
    instructions: "Test instructions",
    messages: [{ role: "user", content: "Test input" }],
    output: "Test output"
  }
}

# Complete test span with usage
test_span = {
  span_id: "test_002",
  trace_id: "trace_002",
  agent_name: "CompleteAgent",
  metadata: {
    model: "gpt-4o",
    temperature: 0.7,
    max_tokens: 1024,
    instructions: "You are a test agent.",
    messages: [
      { role: "user", content: "Test question" }
    ],
    output: "Test response with detailed information.",
    usage: {
      input_tokens: 20,
      output_tokens: 15,
      total_tokens: 35
    },
    latency: {
      request_ms: 50,
      processing_ms: 150,
      total_ms: 200
    }
  }
}
```

### Creating Evaluations

#### Single Configuration

```ruby
engine = RAAF::Eval::EvaluationEngine.new

result = engine.execute(
  baseline_span: baseline,
  configuration: { model: "claude-3-5-sonnet-20241022", provider: "anthropic" }
)

# Access results
puts result[:output]
puts result[:usage][:total_tokens]
puts result[:latency][:total_ms]
```

#### Multiple Configurations

```ruby
run = engine.create_run(
  name: "Multi-model comparison",
  baseline_span: baseline,
  configurations: [
    { name: "GPT-4", changes: { model: "gpt-4o" } },
    { name: "Claude", changes: { model: "claude-3-5-sonnet-20241022", provider: "anthropic" } },
    { name: "Gemini", changes: { model: "gemini-2.0-flash-exp", provider: "gemini" } }
  ]
)

results = engine.execute_run(run)
```

### Viewing Results

#### Basic Metrics

```ruby
results.each do |result|
  config = result.configuration
  metrics = result.token_metrics

  puts "Configuration: #{config.name}"
  puts "  Model: #{config.changes[:model]}"
  puts "  Tokens: #{metrics[:total_tokens]}"
  puts "  Cost: $#{metrics[:total_cost]}"
end
```

#### Baseline Comparison

```ruby
results.each do |result|
  comparison = result.baseline_comparison

  puts "#{result.configuration.name}:"
  puts "  Quality: #{comparison[:quality_change]}"
  puts "  Token delta: #{comparison[:token_delta]}"
  puts "  Latency delta: #{comparison[:latency_delta]}ms"
  puts "  Regression detected: #{comparison[:regression_detected]}"
end
```

#### Detailed Analysis

```ruby
result = results.first

# Token metrics
token_metrics = result.token_metrics
puts "Input tokens: #{token_metrics[:input_tokens]}"
puts "Output tokens: #{token_metrics[:output_tokens]}"
puts "Total tokens: #{token_metrics[:total_tokens]}"
puts "Cost: $#{token_metrics[:total_cost]}"

# Latency metrics
latency = result.latency_metrics
puts "Request time: #{latency[:request_ms]}ms"
puts "Processing time: #{latency[:processing_ms]}ms"
puts "Total time: #{latency[:total_ms]}ms"

# Length metrics
length = result.length_metrics
puts "Characters: #{length[:character_count]}"
puts "Words: #{length[:word_count]}"

# Qualitative metrics (if enabled)
qualitative = result.qualitative_metrics
puts "Semantic similarity: #{qualitative[:semantic_similarity]}"
puts "Bias detected: #{qualitative[:bias_detected]}"
puts "Hallucinations: #{qualitative[:hallucination_detected]}"
```

## RSpec Testing

### Setup

```ruby
# spec/spec_helper.rb or spec/support/raaf_eval.rb
require 'raaf/eval/rspec'

RSpec.configure do |config|
  config.include RAAF::Eval::RSpec::Helpers
end
```

### Basic Tests

#### Model Comparison

```ruby
RSpec.describe "Model performance comparison" do
  it "Claude matches GPT-4 quality" do
    baseline = find_span(agent: "HelpfulAssistant", model: "gpt-4o")

    result = evaluate_span(baseline) do |config|
      config.model = "claude-3-5-sonnet-20241022"
      config.provider = "anthropic"
    end

    expect(result).to maintain_semantic_similarity(threshold: 0.85)
    expect(result).not_to regress_from_baseline
  end
end
```

#### Temperature Testing

```ruby
RSpec.describe "Temperature sensitivity" do
  it "lower temperature reduces variability" do
    baseline = find_span(agent: "CreativeWriter", temperature: 1.0)

    result = evaluate_span(baseline) do |config|
      config.temperature = 0.3
    end

    expect(result).to have_output_length_within(0.8..1.2)
    expect(result).to maintain_baseline_structure
  end
end
```

#### Prompt Optimization

```ruby
RSpec.describe "Prompt improvements" do
  it "enhanced prompt improves quality" do
    baseline = find_span(agent: "ResearchAgent")

    result = evaluate_span(baseline) do |config|
      config.instructions = <<~PROMPT
        You are a research assistant.
        Provide detailed, well-sourced answers.
        Include citations when appropriate.
      PROMPT
    end

    expect(result).to improve_over_baseline
    expect(result).to pass_llm_judge(criteria: "thoroughness and citations")
  end
end
```

### Using Matchers

#### Performance Matchers

```ruby
expect(result).to complete_within(1000)  # ms
expect(result).to use_fewer_tokens_than(baseline)
expect(result).to reduce_tokens_by_at_least(20)  # percent
expect(result).to have_latency_under(500)  # ms
```

#### Quality Matchers

```ruby
expect(result).to maintain_semantic_similarity(threshold: 0.9)
expect(result).to have_output_length_within(0.8..1.2)
expect(result).to match_baseline_structure
expect(result).to pass_llm_judge(criteria: "accuracy and completeness")
```

#### Regression Matchers

```ruby
expect(result).not_to regress_from_baseline
expect(result).to maintain_baseline_quality
expect(result).to improve_over_baseline
```

#### Safety Matchers

```ruby
expect(result).to have_no_safety_violations
expect(result).to detect_no_bias
expect(result).to detect_no_hallucinations
```

See **[RSpec Integration Guide](RSPEC_INTEGRATION.md)** for complete matcher reference.

## Web UI Usage

### Accessing the UI

Navigate to the mounted path (e.g., `http://localhost:3000/eval`).

### Workflow

1. **Browse Spans**
   - Filter by agent, model, status
   - Search by content or metadata
   - Sort and paginate results
   - Select span for evaluation

2. **Edit Configuration**
   - Modify AI settings (model, temperature, max_tokens)
   - Edit system prompt with Monaco Editor
   - View diff against baseline
   - Syntax highlighting and autocomplete

3. **Run Evaluation**
   - Click "Run Evaluation"
   - Real-time progress updates
   - Background job execution
   - Automatic result storage

4. **Compare Results**
   - Side-by-side output comparison
   - Metrics panel with deltas
   - Quality indicators
   - Regression warnings

5. **Save Session**
   - Save evaluation configuration
   - Resume later
   - Share with team
   - Export results

See **[UI Guide](../eval-ui/README.md)** for detailed UI documentation.

## Advanced Patterns

### Custom Metrics

```ruby
# Define custom metric
class CustomMetric < RAAF::Eval::Metrics::BaseMetric
  def calculate(baseline, result)
    # Your metric logic
    {
      custom_score: calculate_score(result),
      baseline_score: calculate_score(baseline),
      delta: calculate_delta(baseline, result)
    }
  end
end

# Use in evaluation
engine = RAAF::Eval::EvaluationEngine.new(
  custom_metrics: [CustomMetric.new]
)
```

### Batch Evaluation

```ruby
# Evaluate multiple spans with same configuration
accessor = RAAF::Eval::SpanAccessor.new
spans = accessor.find_by_agent("CustomerSupportAgent").limit(100)

results = spans.map do |span|
  engine.execute(
    baseline_span: RAAF::Eval::SpanSerializer.serialize(span),
    configuration: { model: "claude-3-5-sonnet-20241022", provider: "anthropic" }
  )
end

# Aggregate results
avg_tokens = results.sum { |r| r[:usage][:total_tokens] } / results.size
avg_latency = results.sum { |r| r[:latency][:total_ms] } / results.size
```

### A/B Testing Pattern

```ruby
# Test two prompt variants
prompts = {
  control: "You are a helpful assistant.",
  variant: "You are an expert assistant providing detailed, accurate responses."
}

results = {}
prompts.each do |name, prompt|
  run = engine.create_run(
    name: "Prompt A/B Test - #{name}",
    baseline_span: baseline,
    configurations: [
      { name: name, changes: { instructions: prompt } }
    ]
  )

  results[name] = engine.execute_run(run)
end

# Compare results
control_quality = results[:control].first.qualitative_metrics[:semantic_similarity]
variant_quality = results[:variant].first.qualitative_metrics[:semantic_similarity]

puts "Control: #{control_quality}"
puts "Variant: #{variant_quality}"
puts "Winner: #{variant_quality > control_quality ? 'Variant' : 'Control'}"
```

### Progressive Optimization

```ruby
# Start with baseline
current_config = baseline_config

# Test variations
candidates = [
  { temperature: 0.7 },
  { temperature: 0.5 },
  { max_tokens: 2048 },
  { max_tokens: 4096 }
]

best_result = nil
best_score = 0

candidates.each do |variation|
  test_config = current_config.merge(variation)

  result = engine.execute(
    baseline_span: baseline,
    configuration: test_config
  )

  score = calculate_quality_score(result)

  if score > best_score
    best_score = score
    best_result = result
    current_config = test_config
  end
end

puts "Best configuration: #{current_config}"
puts "Quality score: #{best_score}"
```

## Best Practices

### 1. Baseline Selection

✅ **DO**:
- Use production spans from successful executions
- Select representative examples covering common scenarios
- Include edge cases and challenging inputs
- Document baseline selection criteria

❌ **DON'T**:
- Use failed or error spans as baselines
- Cherry-pick only easy examples
- Use synthetic/fake data exclusively
- Change baselines frequently without documentation

### 2. Configuration Changes

✅ **DO**:
- Change one variable at a time for clear attribution
- Document the hypothesis for each change
- Test multiple values for numeric parameters
- Keep detailed notes on configuration rationale

❌ **DON'T**:
- Change multiple parameters simultaneously
- Make arbitrary changes without hypotheses
- Test configurations randomly
- Skip documentation of changes

### 3. Metrics Interpretation

✅ **DO**:
- Use multiple metrics for comprehensive evaluation
- Set realistic thresholds based on requirements
- Consider statistical significance for small differences
- Track metrics over time for trends

❌ **DON'T**:
- Rely on single metric
- Set arbitrary thresholds
- Over-interpret small differences
- Ignore regression warnings

### 4. Testing Strategy

✅ **DO**:
- Write RSpec tests for critical agent behaviors
- Run evaluations in CI/CD pipelines
- Use web UI for exploratory testing
- Maintain evaluation test suite alongside unit tests

❌ **DON'T**:
- Skip automated testing
- Rely only on manual evaluation
- Ignore test failures
- Test only happy paths

### 5. Performance

✅ **DO**:
- Batch similar evaluations
- Cache span serialization
- Use background jobs for UI evaluations
- Monitor evaluation costs

❌ **DON'T**:
- Run redundant evaluations
- Serialize spans repeatedly
- Block UI on long-running evaluations
- Ignore LLM API costs

## Troubleshooting

### Common Issues

#### Database Connection Errors

```ruby
# Error: PG::ConnectionBad
# Solution: Configure database connection

RAAF::Eval.configure do |config|
  config.database_url = ENV['DATABASE_URL']
end

RAAF::Eval.configuration.establish_connection!
```

#### Span Not Found

```ruby
# Error: RAAF::Eval::SpanNotFoundError
# Solution: Verify span exists in tracing system

accessor = RAAF::Eval::SpanAccessor.new
spans = accessor.query(agent_name: "MyAgent")
puts "Found #{spans.count} spans"
```

#### Serialization Failures

```ruby
# Error: RAAF::Eval::SerializationError
# Solution: Ensure span has required fields

required_fields = [:span_id, :agent_name, :metadata]
span.keys.include?(required_fields)  # Should be true
```

#### Provider Configuration

```ruby
# Error: Provider not configured
# Solution: Ensure API keys are set

ENV['OPENAI_API_KEY'] = "your-key"
ENV['ANTHROPIC_API_KEY'] = "your-key"

# Or configure in evaluation
config = {
  model: "claude-3-5-sonnet-20241022",
  provider: "anthropic",
  api_key: ENV['ANTHROPIC_API_KEY']
}
```

#### Metrics Calculation Errors

```ruby
# Error: Insufficient data for metrics
# Solution: Ensure baseline has usage data

baseline[:metadata][:usage]  # Should exist
baseline[:metadata][:output]  # Should exist
```

### Getting Help

1. **Check Documentation**:
   - [API Reference](API.md)
   - [Architecture](ARCHITECTURE.md)
   - [Metrics System](METRICS.md)

2. **Enable Debug Logging**:
   ```ruby
   RAAF.logger.level = Logger::DEBUG
   ```

3. **GitHub Issues**:
   - Search existing issues
   - Provide minimal reproduction
   - Include error messages and stack traces

## Next Steps

- **[RSpec Integration](RSPEC_INTEGRATION.md)** - Write evaluation tests
- **[Web UI Setup](../eval-ui/README.md)** - Install and configure UI
- **[Metrics Reference](METRICS.md)** - Deep dive into metrics
- **[API Documentation](API.md)** - Complete API reference
- **[Architecture](ARCHITECTURE.md)** - System design details

---

**Questions?** Check the **[Documentation Map](../RAAF_EVAL.md#documentation-map)** or open an issue on GitHub.
