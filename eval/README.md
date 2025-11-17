# RAAF Eval - Core Evaluation Engine

> AI agent evaluation and testing framework for Ruby AI Agents Factory (RAAF)

[![Ruby](https://img.shields.io/badge/ruby-3.3+-red.svg)](https://www.ruby-lang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Overview

RAAF Eval provides systematic testing and validation of AI agent behavior across different LLM configurations, parameters, and prompts. It includes:

- **Span Serialization** - Capture production agent executions
- **Evaluation Engine** - Re-execute agents with modified configurations
- **RSpec Integration** - 40+ matchers for automated testing
- **Comprehensive Metrics** - Token usage, latency, quality, safety

## Quick Start

### Installation

```ruby
# Gemfile
gem 'raaf-eval'
```

```bash
bundle install
cd vendor/local_gems/raaf/eval  # or wherever raaf-eval is located
bundle exec rake db:migrate
```

### 5-Minute Example

```ruby
require 'raaf/eval'

# 1. Get baseline span from production
baseline_span = {
  span_id: "span_001",
  trace_id: "trace_001",
  agent_name: "HelpfulAssistant",
  metadata: {
    model: "gpt-4o",
    instructions: "You are a helpful assistant.",
    messages: [{ role: "user", content: "What is the capital of France?" }],
    output: "The capital of France is Paris.",
    usage: { total_tokens: 50 }
  }
}

# 2. Create evaluation comparing two models
engine = RAAF::Eval::EvaluationEngine.new
run = engine.create_run(
  name: "Model Comparison",
  baseline_span: baseline_span,
  configurations: [
    { name: "GPT-4", changes: { model: "gpt-4o" } },
    { name: "Claude", changes: { model: "claude-3-5-sonnet-20241022", provider: "anthropic" } }
  ]
)

# 3. Execute and view results
results = engine.execute_run(run)
results.each do |result|
  puts "#{result.configuration.name}: #{result.token_metrics[:total_tokens]} tokens"
end
```

### RSpec Testing

```ruby
# spec/evaluations/model_comparison_spec.rb
require 'raaf/eval/rspec'

RSpec.describe "Model quality" do
  it "maintains quality across models" do
    baseline = find_span(agent: "HelpfulAssistant")

    result = evaluate_span(baseline) do |config|
      config.model = "claude-3-5-sonnet-20241022"
      config.provider = "anthropic"
    end

    # 3-tier labeling system (good/average/bad)
    expect(result).to be_good  # or be_average, be_at_least("average")
    expect(result[:label]).to eq("good")
    expect(result[:score]).to be >= 0.8
  end
end
```

Run with: `bundle exec rspec spec/evaluations/`

## Features

### Core Capabilities
- ✅ Span serialization from production traces
- ✅ Configuration override system (model, parameters, prompts)
- ✅ Evaluation execution engine
- ✅ Baseline comparison and regression detection

### RSpec Integration
- ✅ 40+ built-in matchers across 8 categories
- ✅ Fluent evaluation DSL
- ✅ Helper methods for span querying
- ✅ CI/CD ready

### Consistency Reporting (NEW)
- ✅ **Multi-Run Analysis**: Statistical analysis across multiple evaluation runs
- ✅ **Variance Detection**: Automatic detection of acceptable vs high variance
- ✅ **Console Reports**: Formatted output with emojis and detailed metrics
- ✅ **Export Formats**: JSON and CSV export for external analysis
- ✅ **Performance Tracking**: Latency, token usage, and success rate metrics

### Metrics System
- ✅ **Quantitative**: Token usage, latency, accuracy, length
- ✅ **Qualitative**: Semantic similarity, bias, hallucinations (AI-powered)
- ✅ **Statistical**: Confidence intervals, significance testing
- ✅ **Custom**: Define domain-specific metrics

## Documentation

### Getting Started
- **[Complete Tutorial](GETTING_STARTED.md)** - Comprehensive guide with examples
- **[Master Documentation](../RAAF_EVAL.md)** - Full feature overview and navigation

### Technical Reference
- **[Architecture](ARCHITECTURE.md)** - System design and components
- **[API Reference](API.md)** - Complete API documentation
- **[RSpec Integration](RSPEC_INTEGRATION.md)** - Testing guide with 40+ matchers
- **[Metrics System](METRICS.md)** - Metrics calculation and interpretation
- **[Performance](PERFORMANCE.md)** - Benchmarks and optimization
- **[Migrations](MIGRATIONS.md)** - Database schema reference

### Web UI (Optional)
- **[UI Installation](../eval-ui/README.md)** - Interactive evaluation interface
- **[Integration Guide](../eval-ui/INTEGRATION_GUIDE.md)** - RAAF ecosystem integration

## Quick Links

| Task | Documentation |
|------|---------------|
| First time setup | [Getting Started](GETTING_STARTED.md#installation) |
| Write RSpec tests | [RSpec Integration](RSPEC_INTEGRATION.md) |
| Understand architecture | [Architecture](ARCHITECTURE.md) |
| API reference | [API Documentation](API.md) |
| Use web interface | [UI Setup](../eval-ui/README.md) |
| View metrics | [Metrics System](METRICS.md) |

## Database Setup

RAAF Eval requires PostgreSQL with four tables:

```bash
# Run migrations
bundle exec rake db:migrate

# Or in Rails app
rails db:migrate
```

Tables created:
- `evaluation_runs` - Top-level evaluation records
- `evaluation_spans` - Serialized span snapshots
- `evaluation_configurations` - Configuration variants
- `evaluation_results` - Results and metrics

See **[Migrations Guide](MIGRATIONS.md)** for schema details.

## Configuration

### Database Connection

```ruby
RAAF::Eval.configure do |config|
  config.database_url = ENV['DATABASE_URL']
end

RAAF::Eval.configuration.establish_connection!
```

### Custom Metrics

```ruby
class MyMetric < RAAF::Eval::Metrics::BaseMetric
  def calculate(baseline, result)
    { custom_score: calculate_score(result) }
  end
end

engine = RAAF::Eval::EvaluationEngine.new(
  custom_metrics: [MyMetric.new]
)
```

## RSpec Matchers Quick Reference

### Performance
```ruby
expect(result).to complete_within(1000)  # ms
expect(result).to use_fewer_tokens_than(baseline)
expect(result).to have_latency_under(500)  # ms
```

### Quality
```ruby
expect(result).to maintain_semantic_similarity(threshold: 0.9)
expect(result).to pass_llm_judge(criteria: "accuracy")
expect(result).to match_baseline_structure
```

### Regression
```ruby
expect(result).not_to regress_from_baseline
expect(result).to maintain_baseline_quality
expect(result).to improve_over_baseline
```

### Safety
```ruby
expect(result).to have_no_safety_violations
expect(result).to detect_no_bias
expect(result).to detect_no_hallucinations
```

**Complete reference:** [RSpec Integration Guide](RSPEC_INTEGRATION.md)

## Performance

- **Serialization**: < 10ms per span
- **Evaluation**: ~100-500ms (depends on LLM)
- **Metrics**: < 5ms quantitative, ~200ms qualitative
- **Database**: < 50ms query time

See **[Performance Benchmarks](PERFORMANCE.md)** for details.

## Development Status

✅ **Phase 1: Foundation** (Complete)
- Database schema and migrations
- Span serialization
- Evaluation engine
- Basic metrics

✅ **Phase 2: RSpec Integration** (Complete)
- 40+ RSpec matchers
- Fluent evaluation DSL
- Helper methods
- CI/CD support

🚧 **Phase 3: Web UI** (Complete in `raaf-eval-ui`)
- Interactive evaluation interface
- See [eval-ui README](../eval-ui/README.md)

See **[Product Roadmap](../.agent-os/product/roadmap.md)** for future plans.

## Contributing

Bug reports and pull requests welcome on [GitHub](https://github.com/raaf-ai/ruby-ai-agents-factory).

Development setup:
```bash
bundle install
bundle exec rake db:migrate
bundle exec rspec
```

See **[Contributing Guide](../eval-ui/CONTRIBUTING.md)** for guidelines.

## Examples

### Model Comparison

```ruby
models = ["gpt-4o", "claude-3-5-sonnet-20241022", "gemini-2.0-flash-exp"]

results = models.map do |model|
  engine.execute(
    baseline_span: baseline,
    configuration: { model: model }
  )
end

results.each do |result|
  puts "#{result[:model]}: #{result[:usage][:total_tokens]} tokens, #{result[:latency][:total_ms]}ms"
end
```

### Temperature Testing

```ruby
temperatures = [0.0, 0.3, 0.7, 1.0]

run = engine.create_run(
  name: "Temperature Test",
  baseline_span: baseline,
  configurations: temperatures.map { |t| { name: "Temp #{t}", changes: { temperature: t } } }
)

results = engine.execute_run(run)
```

### Prompt Optimization

```ruby
prompts = {
  original: "You are a helpful assistant.",
  enhanced: "You are an expert assistant providing detailed, accurate responses with citations."
}

results = prompts.transform_values do |prompt|
  engine.execute(
    baseline_span: baseline,
    configuration: { instructions: prompt }
  )
end
```

More examples: **[Getting Started Guide](GETTING_STARTED.md#advanced-patterns)**

## Consistency Reporting

**NEW:** RAAF Eval includes a comprehensive consistency reporting framework for analyzing agent behavior across multiple evaluation runs.

### Quick Start

```ruby
require 'raaf/eval/reporting'

# Run evaluations multiple times
results = 3.times.map do
  {
    evaluation: Eval::Prospect::Scoring.evaluate_agent_run(agent),
    latency_ms: 30000,
    agent_result: { usage: { total_tokens: 5000 } }
  }
end

# Generate consistency report
report = RAAF::Eval::Reporting::ConsistencyReport.new(results, tolerance: 12)
report.generate

# Output:
# ================================================================================
# CONSISTENCY ANALYSIS (Across 3 runs)
# ================================================================================
#
# ✅ individual_scores
#   Score Range: 90-100 (std dev: 3.2)
#   Average: 95.5
#   ✨ Good consistency (variance ≤12)
#
# Performance Summary:
# --------------------------------------------------------------------------------
# Latency: avg 30000ms, min 25000ms, max 35000ms
# Tokens: avg 5000, min 4800, max 5200
# Success Rate: 100%
```

### Features

**Multi-Run Aggregation:**
- Collect results from multiple evaluation runs
- Extract field values (arrays and scalars)
- Group results by field name
- Calculate performance metrics

**Statistical Analysis:**
- Mean, min, max, range, standard deviation
- Variance status: `:perfect`, `:acceptable`, `:high_variance`
- Configurable tolerance threshold (default: 12 points)
- Sample size tracking

**Formatted Reporting:**
- Console output with emojis (✅ ⚠️ ❌)
- Detailed metrics with context
- Performance summary (latency, tokens, success rate)
- Overall assessment

**Export Options:**
- JSON export with metadata
- CSV export for spreadsheet analysis
- Summary statistics

### Usage Patterns

**Basic Usage:**
```ruby
# Run agent multiple times and collect results
run_results = []

3.times do
  result = agent.run
  run_results << {
    evaluation: result[:evaluation],
    latency_ms: result[:latency_ms],
    agent_result: result[:agent_result]
  }
end

# Generate report with custom tolerance
report = RAAF::Eval::Reporting::ConsistencyReport.new(
  run_results,
  tolerance: 15  # Accept variance up to 15 points
)

# Display formatted console output
report.generate
```

**JSON Export:**
```ruby
# Export report data as JSON
json_data = report.to_json

# Save to file
File.write('consistency_report.json', json_data)

# Structure:
# {
#   "metadata": {
#     "total_runs": 3,
#     "tolerance": 12,
#     "generated_at": "2025-01-14T10:30:00Z"
#   },
#   "consistency_analysis": {
#     "individual_scores": {
#       "mean": 95.5,
#       "min": 90,
#       "max": 100,
#       "range": 10,
#       "std_dev": 3.2,
#       "variance_status": "acceptable",
#       "sample_size": 15
#     }
#   },
#   "performance_summary": {
#     "latencies": [30000, 25000, 35000],
#     "tokens": [5000, 4800, 5200],
#     "success_rate": 1.0
#   }
# }
```

**CSV Export:**
```ruby
# Export as CSV for spreadsheet analysis
csv_data = report.to_csv

# Save to file
File.write('consistency_report.csv', csv_data)

# CSV format:
# field_name,mean,min,max,range,std_dev,variance_status,sample_size
# individual_scores,95.5,90,100,10,3.2,acceptable,15
# reasoning_texts,0.85,0.75,0.95,0.2,0.08,acceptable,3
```

**Custom Analysis:**
```ruby
# Access aggregator and analyzer directly
aggregator = RAAF::Eval::Reporting::MultiRunAggregator.new(run_results)
analyzer = RAAF::Eval::Reporting::ConsistencyAnalyzer.new(aggregator, tolerance: 12)

# Analyze specific field
field_analysis = analyzer.analyze_field(:individual_scores)
# => {
#   mean: 95.5,
#   min: 90,
#   max: 100,
#   range: 10,
#   std_dev: 3.2,
#   variance_status: :acceptable,
#   sample_size: 15
# }

# Get performance summary
performance = aggregator.performance_summary
# => {
#   latencies: [30000, 25000, 35000],
#   tokens: [5000, 4800, 5200],
#   success_rate: 1.0,
#   total_runs: 3,
#   successful_runs: 3
# }

# Get summary statistics
summary = report.summary
# => {
#   total_runs: 3,
#   success_rate: 1.0,
#   fields_analyzed: 2,
#   high_variance_fields: 0
# }
```

### Integration with Rake Tasks

**Before (Manual Implementation - ~200 lines):**
```ruby
# Complex manual reporting code
def analyze_consistency(results)
  # Extract values
  # Calculate statistics
  # Determine variance
  # Format output
  # ... 200+ lines of custom code
end
```

**After (Using RAAF Eval Reporting - ~10 lines):**
```ruby
require 'raaf/eval/reporting'

task :evaluate_consistency do
  # Run evaluations
  results = 3.times.map { run_evaluation }

  # Generate report
  report = RAAF::Eval::Reporting::ConsistencyReport.new(results)
  report.generate

  # Export if needed
  File.write('report.json', report.to_json)
  File.write('report.csv', report.to_csv)
end
```

### Variance Status Reference

| Status | Range | Description |
|--------|-------|-------------|
| `:perfect` | 0 | All values identical |
| `:acceptable` | 1-12 | Within tolerance (configurable) |
| `:high_variance` | >12 | Exceeds tolerance threshold |

**Customizing Tolerance:**
```ruby
# Stricter tolerance (5 points)
report = RAAF::Eval::Reporting::ConsistencyReport.new(results, tolerance: 5)

# More lenient tolerance (20 points)
report = RAAF::Eval::Reporting::ConsistencyReport.new(results, tolerance: 20)
```

### Components

The consistency reporting framework consists of 4 main components:

1. **MultiRunAggregator** - Aggregates results from multiple runs
2. **ConsistencyAnalyzer** - Performs statistical analysis
3. **ConsoleReporter** - Generates formatted console output
4. **ConsistencyReport** - Unified API for all reporting features

All components are fully tested with comprehensive RSpec coverage.

## Troubleshooting

### Database Connection Issues
```ruby
RAAF::Eval.configure do |config|
  config.database_url = ENV['DATABASE_URL']
end
```

### Provider Configuration
```ruby
ENV['OPENAI_API_KEY'] = "your-key"
ENV['ANTHROPIC_API_KEY'] = "your-key"
```

### Debug Logging
```ruby
RAAF.logger.level = Logger::DEBUG
```

Complete troubleshooting: **[Getting Started Guide](GETTING_STARTED.md#troubleshooting)**

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

---

**Next Steps:**
1. Read the **[Getting Started Guide](GETTING_STARTED.md)** for comprehensive tutorial
2. Explore **[RSpec Integration](RSPEC_INTEGRATION.md)** for testing patterns
3. Check **[Master Documentation](../RAAF_EVAL.md)** for complete feature overview
