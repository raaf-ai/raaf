# RAAF Eval API Documentation

> Version: 1.0.0
> Last Updated: 2025-11-07
> Complete API Reference

## Core Classes

### RAAF::Eval::Engine

The main evaluation engine for re-executing agents with modified configurations.

#### Constructor

```ruby
Engine.new(span:, configuration_overrides: {})
```

**Parameters**:
- `span` (Hash) - Baseline span to evaluate
- `configuration_overrides` (Hash) - Configuration changes to apply

**Example**:
```ruby
engine = RAAF::Eval::Engine.new(
  span: baseline_span,
  configuration_overrides: {
    model: "claude-3-5-sonnet-20241022",
    temperature: 0.7
  }
)
```

#### Methods

##### #execute(async: false)

Executes the evaluation.

**Parameters**:
- `async` (Boolean) - Whether to run asynchronously (default: false)

**Returns**: Hash with evaluation results

**Example**:
```ruby
result = engine.execute

# Result structure:
{
  success: true,
  output: "...",
  messages: [...],
  usage: { total_tokens: 150, input_tokens: 75, output_tokens: 75 },
  latency_ms: 1500,
  baseline_output: "...",
  baseline_usage: { total_tokens: 160, ... },
  configuration: { model: "claude-3-5-sonnet-20241022", ... }
}
```

**Error Handling**:
```ruby
result = engine.execute

if result[:success]
  puts "Evaluation succeeded"
  puts result[:output]
else
  puts "Evaluation failed: #{result[:error]}"
  puts result[:backtrace]
end
```

---

### RAAF::Eval::Metrics::TokenMetrics

Calculates token usage and cost metrics.

#### Methods

##### #calculate(baseline_span, result_span)

Calculates token metrics comparing baseline and result.

**Parameters**:
- `baseline_span` (Hash) - Original span data
- `result_span` (Hash) - Evaluation result span data

**Returns**: Hash with token metrics

**Example**:
```ruby
token_metrics = RAAF::Eval::Metrics::TokenMetrics.new
result = token_metrics.calculate(baseline_span, result_span)

# Result structure:
{
  baseline_total_tokens: 150,
  baseline_input_tokens: 75,
  baseline_output_tokens: 75,
  baseline_reasoning_tokens: 10,
  baseline_cost: 0.00225,

  result_total_tokens: 140,
  result_input_tokens: 75,
  result_output_tokens: 65,
  result_reasoning_tokens: 8,
  result_cost: 0.00210,

  token_delta: -10,
  token_delta_percentage: -6.67,
  cost_delta: -0.00015,
  cost_delta_percentage: -6.67
}
```

---

### RAAF::Eval::Metrics::LatencyMetrics

Measures execution performance and timing.

#### Methods

##### #calculate(baseline_span, result_span)

Calculates latency metrics.

**Parameters**:
- `baseline_span` (Hash) - Original span data
- `result_span` (Hash) - Evaluation result span data

**Returns**: Hash with latency metrics

**Example**:
```ruby
latency_metrics = RAAF::Eval::Metrics::LatencyMetrics.new
result = latency_metrics.calculate(baseline_span, result_span)

# Result structure:
{
  baseline_latency_ms: 1500,
  baseline_ttft_ms: 300,
  baseline_time_per_token_ms: 16,

  result_latency_ms: 1300,
  result_ttft_ms: 280,
  result_time_per_token_ms: 20,

  latency_delta_ms: -200,
  latency_delta_percentage: -13.33,
  ttft_delta_ms: -20,
  improvement: true
}
```

---

### RAAF::Eval::Metrics::AccuracyMetrics

Compares output similarity and accuracy.

#### Methods

##### #calculate(baseline_span, result_span)

Calculates accuracy metrics.

**Parameters**:
- `baseline_span` (Hash) - Original span data
- `result_span` (Hash) - Evaluation result span data

**Returns**: Hash with accuracy metrics

**Example**:
```ruby
accuracy_metrics = RAAF::Eval::Metrics::AccuracyMetrics.new
result = accuracy_metrics.calculate(baseline_span, result_span)

# Result structure:
{
  exact_match: false,
  fuzzy_match_score: 0.87,
  edit_distance: 15,
  word_overlap: 0.92,
  bleu_score: 0.85,
  character_accuracy: 0.95
}
```

---

### RAAF::Eval::Metrics::StructuralMetrics

Validates output structure and format.

#### Methods

##### #calculate(baseline_span, result_span)

Calculates structural metrics.

**Parameters**:
- `baseline_span` (Hash) - Original span data
- `result_span` (Hash) - Evaluation result span data

**Returns**: Hash with structural metrics

**Example**:
```ruby
structural_metrics = RAAF::Eval::Metrics::StructuralMetrics.new
result = structural_metrics.calculate(baseline_span, result_span)

# Result structure:
{
  baseline_length: 250,
  result_length: 230,
  length_delta: -20,
  length_delta_percentage: -8.0,

  format_valid: true,
  has_code_blocks: true,
  code_block_count: 2,
  has_lists: true,
  has_links: false,

  schema_valid: true,
  schema_errors: []
}
```

---

### RAAF::Eval::Metrics::AIComparator

Uses AI to compare outputs qualitatively.

#### Constructor

```ruby
AIComparator.new(model: "gpt-4o", timeout: 30)
```

**Parameters**:
- `model` (String) - AI model to use for comparison (default: "gpt-4o")
- `timeout` (Integer) - Timeout in seconds (default: 30)

#### Methods

##### #calculate(baseline_span, result_span)

Performs AI-powered comparison.

**Parameters**:
- `baseline_span` (Hash) - Original span data
- `result_span` (Hash) - Evaluation result span data

**Returns**: Hash with AI comparison results

**Example**:
```ruby
ai_comparator = RAAF::Eval::Metrics::AIComparator.new
result = ai_comparator.calculate(baseline_span, result_span)

# Result structure:
{
  semantic_similarity_score: 0.88,
  coherence_score: 0.92,
  relevance_score: 0.95,

  hallucination_detected: false,
  hallucination_details: [],

  bias_detected: {
    gender: false,
    race: false,
    region: false,
    age: false
  },
  bias_details: [],

  tone_consistency: 0.90,
  tone_shift: "neutral → friendly",
  formality_level: "professional",

  factuality_score: 0.95,
  factual_claims_verified: 5,
  factual_errors: 0,

  toxicity_detected: false,
  pii_detected: false,
  policy_compliant: true,

  comparison_reasoning: "...",
  evaluation_model: "gpt-4o",
  evaluation_cost: 0.002,
  evaluation_latency_ms: 2500
}
```

**Async Usage**:
```ruby
# Run asynchronously to avoid blocking
comparison_future = Thread.new do
  ai_comparator.calculate(baseline_span, result_span)
end

# Continue with other work...

# Get result when ready
ai_result = comparison_future.value
```

---

### RAAF::Eval::Metrics::StatisticalAnalyzer

Provides statistical analysis of evaluation results.

#### Methods

##### #analyze(baseline_metrics, result_metrics)

Analyzes statistical significance.

**Parameters**:
- `baseline_metrics` (Array<Hash>) - Array of baseline measurements
- `result_metrics` (Array<Hash>) - Array of result measurements

**Returns**: Hash with statistical analysis

**Example**:
```ruby
analyzer = RAAF::Eval::Metrics::StatisticalAnalyzer.new

baseline_metrics = 30.times.map do
  { tokens: 100 + rand(20), latency: 1500 + rand(500) }
end

result_metrics = 30.times.map do
  { tokens: 95 + rand(15), latency: 1300 + rand(400) }
end

result = analyzer.analyze(baseline_metrics, result_metrics)

# Result structure:
{
  baseline_mean: 150.5,
  result_mean: 142.3,
  baseline_std_dev: 12.5,
  result_std_dev: 10.8,

  baseline_ci: [145.2, 155.8],
  result_ci: [138.1, 146.5],
  ci_overlap: false,

  t_statistic: -2.45,
  p_value: 0.018,
  significant: true,
  alpha: 0.05,

  cohens_d: 0.72,
  effect_size_interpretation: "medium",

  baseline_sample_size: 30,
  result_sample_size: 30,
  sufficient_samples: true
}
```

---

### RAAF::Eval::BaselineComparator

Detects performance regressions.

#### Methods

##### #compare(baseline_span, result_span)

Compares result against baseline and detects regressions.

**Parameters**:
- `baseline_span` (Hash) - Original span data
- `result_span` (Hash) - Evaluation result span data

**Returns**: Hash with comparison and regression detection

**Example**:
```ruby
comparator = RAAF::Eval::BaselineComparator.new
result = comparator.compare(baseline_span, result_span)

# Result structure:
{
  token_regression: false,
  token_threshold_exceeded: false,

  latency_regression: false,
  latency_threshold_exceeded: false,

  quality_regression: false,
  quality_score_delta: 0.05,

  regression_detected: false,
  regression_types: [],
  regression_severity: "none",

  token_delta: -10,
  latency_delta_ms: 50,
  cost_delta: 0.0001,

  recommendation: "Configuration change is safe to deploy",
  safe_to_deploy: true
}
```

---

### RAAF::Eval::Metrics::CustomMetric

Base class for custom metrics.

#### Creating Custom Metrics

```ruby
class MyMetric < RAAF::Eval::Metrics::CustomMetric
  def initialize
    super("my_metric")
  end

  def calculate(baseline_span, result_span)
    # Your calculation logic
    {
      my_field: "value",
      score: 0.85
    }
  end

  def async?
    false  # Set to true for async metrics
  end
end
```

#### Registry Methods

##### CustomMetric::Registry.register(metric)

Registers a custom metric.

**Parameters**:
- `metric` (CustomMetric) - Metric instance to register

**Example**:
```ruby
RAAF::Eval::Metrics::CustomMetric::Registry.register(MyMetric.new)
```

##### CustomMetric::Registry.get(name)

Retrieves a registered metric.

**Parameters**:
- `name` (String) - Metric name

**Returns**: CustomMetric instance or nil

**Example**:
```ruby
metric = RAAF::Eval::Metrics::CustomMetric::Registry.get("my_metric")
result = metric.calculate(baseline_span, result_span)
```

##### CustomMetric::Registry.all

Returns all registered metrics.

**Returns**: Hash of metric name => metric instance

**Example**:
```ruby
all_metrics = RAAF::Eval::Metrics::CustomMetric::Registry.all

all_metrics.each do |name, metric|
  puts "#{name}: #{metric.class}"
end
```

##### CustomMetric::Registry.clear!

Clears all registered metrics (useful for testing).

**Example**:
```ruby
RAAF::Eval::Metrics::CustomMetric::Registry.clear!
```

---

## Module-Level Methods

### RAAF::Eval.find_span(span_id)

Finds a span by ID.

**Parameters**:
- `span_id` (String) - The span ID

**Returns**: Hash with span data

**Raises**: `SpanNotFoundError` if span not found

**Example**:
```ruby
span = RAAF::Eval.find_span("span_123")
```

### RAAF::Eval.latest_span(agent:)

Finds the latest span for an agent.

**Parameters**:
- `agent` (String) - The agent name

**Returns**: Hash with span data

**Raises**: `SpanNotFoundError` if no span found

**Example**:
```ruby
span = RAAF::Eval.latest_span(agent: "CustomerSupport")
```

### RAAF::Eval.query_spans(**filters)

Queries spans with filters.

**Parameters**:
- `filters` (Hash) - Filtering criteria

**Returns**: Array of span hashes

**Example**:
```ruby
spans = RAAF::Eval.query_spans(
  agent_name: "CustomerSupport",
  model: "gpt-4o",
  start_date: 7.days.ago,
  status: "success"
)
```

### RAAF::Eval.configure

Configures RAAF Eval.

**Example**:
```ruby
RAAF::Eval.configure do |config|
  config.database_url = "postgresql://localhost/raaf_eval"
  config.default_model = "gpt-4o"
  config.ai_comparator_timeout = 30
end
```

---

## Data Structures

### Span Hash

```ruby
{
  span_id: "span_123",
  trace_id: "trace_456",
  parent_span_id: "span_122",
  agent_name: "CustomerSupport",
  metadata: {
    model: "gpt-4o",
    instructions: "You are a helpful assistant.",
    messages: [
      { role: "user", content: "Hello" },
      { role: "assistant", content: "Hi there!" }
    ],
    output: "Hi there!",
    usage: {
      total_tokens: 50,
      input_tokens: 20,
      output_tokens: 30,
      reasoning_tokens: 5
    },
    timestamps: {
      start: "2025-11-07T10:00:00Z",
      end: "2025-11-07T10:00:01.5Z"
    },
    tool_calls: [...],
    handoffs: [...],
    cost: 0.002,
    latency_ms: 1500
  }
}
```

### Configuration Overrides

```ruby
{
  model: "claude-3-5-sonnet-20241022",    # Model to use
  provider: "anthropic",                   # Provider name
  temperature: 0.7,                        # 0.0-2.0
  max_tokens: 1000,                        # Max output tokens
  top_p: 0.9,                              # 0.0-1.0
  instructions: "New instructions",        # System prompt
  tools: ["tool1", "tool2"]                # Available tools
}
```

## Error Classes

### RAAF::Eval::Error

Base error class for all RAAF Eval errors.

### RAAF::Eval::ConfigurationError

Raised when configuration is invalid.

**Example**:
```ruby
begin
  engine = RAAF::Eval::Engine.new(
    span: nil,  # Invalid!
    configuration_overrides: {}
  )
rescue RAAF::Eval::ConfigurationError => e
  puts "Configuration error: #{e.message}"
end
```

### RAAF::Eval::EvaluationError

Raised when evaluation execution fails.

**Example**:
```ruby
begin
  result = engine.execute
rescue RAAF::Eval::EvaluationError => e
  puts "Evaluation failed: #{e.message}"
end
```

### RAAF::Eval::SpanNotFoundError

Raised when span cannot be found.

**Example**:
```ruby
begin
  span = RAAF::Eval.find_span("nonexistent")
rescue RAAF::Eval::SpanNotFoundError => e
  puts "Span not found: #{e.message}"
end
```

---

## Constants

### RAAF::Eval::VERSION

Current version of RAAF Eval.

```ruby
RAAF::Eval::VERSION
# => "1.0.0"
```

---

## Complete Example

```ruby
require 'raaf/eval'

# 1. Get baseline span
baseline_span = RAAF::Eval.latest_span(agent: "CustomerSupport")

# 2. Create evaluation engine
engine = RAAF::Eval::Engine.new(
  span: baseline_span,
  configuration_overrides: {
    model: "claude-3-5-sonnet-20241022",
    temperature: 0.7
  }
)

# 3. Execute evaluation
result = engine.execute

# 4. Calculate metrics
token_metrics = RAAF::Eval::Metrics::TokenMetrics.new
latency_metrics = RAAF::Eval::Metrics::LatencyMetrics.new
accuracy_metrics = RAAF::Eval::Metrics::AccuracyMetrics.new

result_span = {
  span_id: "result_001",
  metadata: {
    output: result[:output],
    usage: result[:usage],
    latency_ms: result[:latency_ms]
  }
}

token_data = token_metrics.calculate(baseline_span, result_span)
latency_data = latency_metrics.calculate(baseline_span, result_span)
accuracy_data = accuracy_metrics.calculate(baseline_span, result_span)

# 5. Check for regressions
comparator = RAAF::Eval::BaselineComparator.new
comparison = comparator.compare(baseline_span, result_span)

# 6. Display results
puts "Token delta: #{token_data[:token_delta_percentage]}%"
puts "Latency delta: #{latency_data[:latency_delta_percentage]}%"
puts "Fuzzy match: #{accuracy_data[:fuzzy_match_score]}"
puts "Regression detected: #{comparison[:regression_detected]}"
puts "Safe to deploy: #{comparison[:safe_to_deploy]}"
```

---

## See Also

- [Usage Guide](USAGE_GUIDE.md)
- [Metrics Guide](METRICS.md)
- [Performance Guide](PERFORMANCE.md)
- [Architecture Guide](ARCHITECTURE.md)
