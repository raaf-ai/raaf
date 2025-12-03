# RAAF Eval - AI Agent Evaluation Framework

> **Status**: Production Ready (Phase 1-3 Complete)
> **Version**: 1.0.0
> **Last Updated**: 2025-01-12

## Overview

RAAF Eval is a comprehensive AI agent evaluation and testing framework for Ruby AI Agents Factory (RAAF). It enables systematic testing and validation of agent behavior when changing LLMs, parameters, or prompts through two complementary interfaces:

- **raaf-eval** - Core evaluation engine with RSpec integration for automated testing
- **raaf-eval-ui** - Interactive web UI for exploratory evaluation and optimization

## Quick Links

### Getting Started
- **[Installation & Quick Start](eval/README.md)** - Get up and running in 5 minutes
- **[Comprehensive Tutorial](eval/GETTING_STARTED.md)** - Step-by-step guide with examples
- **[RSpec Integration Guide](eval/RSPEC_INTEGRATION.md)** - Write evaluation tests

### Core Documentation
- **[Architecture Overview](eval/ARCHITECTURE.md)** - System design and components
- **[API Reference](eval/API.md)** - Complete API documentation
- **[Metrics System](eval/METRICS.md)** - Understanding evaluation metrics
- **[Performance Benchmarks](eval/PERFORMANCE.md)** - Performance characteristics
- **[Statistical LLM Judge Guide](eval/docs/LLM_JUDGE_GUIDE.md)** - Bias-corrected LLM-as-a-Judge evaluation

### UI Documentation
- **[UI Installation](eval-ui/README.md)** - Setting up the web interface
- **[Integration Guide](eval-ui/INTEGRATION_GUIDE.md)** - Integrating with RAAF ecosystem
- **[Contributing](eval-ui/CONTRIBUTING.md)** - Development guidelines

### Technical Reference
- **[Database Schema](eval/MIGRATIONS.md)** - Database structure and migrations

## What Can You Do?

### 1. Automated Testing (raaf-eval)

Write RSpec tests to validate agent behavior across configurations:

```ruby
RSpec.describe "GPT-4 vs Claude comparison" do
  it "maintains quality when switching models" do
    # Find baseline span from production
    baseline = find_span(agent: "CustomerSupportAgent", status: "completed")

    # Evaluate with Claude instead of GPT-4
    result = evaluate_span(baseline) do |config|
      config.model = "claude-3-5-sonnet-20241022"
      config.provider = "anthropic"
    end

    # Assert quality maintained
    expect(result).to maintain_semantic_similarity(threshold: 0.85)
    expect(result).not_to regress_from_baseline
  end
end
```

**40+ RSpec matchers available** for performance, quality, regression, safety, and more.

### 2. Interactive Optimization (raaf-eval-ui)

Use the web UI for exploratory testing:

1. **Browse Spans** - Filter production traces by agent, model, status
2. **Edit Prompts** - Monaco Editor with syntax highlighting and diff view
3. **Modify Settings** - Adjust model, temperature, max_tokens
4. **Run Evaluations** - Real-time execution with progress updates
5. **Compare Results** - Side-by-side diff with metrics and deltas
6. **Save Sessions** - Resume evaluation experiments

## Key Features

### Core Capabilities
- ✅ **Span Serialization** - Capture production agent executions
- ✅ **Configuration Override** - Test model, parameter, prompt changes
- ✅ **Baseline Comparison** - Automatic regression detection
- ✅ **Comprehensive Metrics** - Token usage, latency, quality, safety

### RSpec Integration (Phase 2)
- ✅ **8 Matcher Categories** - Performance, quality, regression, statistical, safety, structural, LLM, custom
- ✅ **40+ Built-in Matchers** - Complete testing vocabulary
- ✅ **Fluent DSL** - Clean, readable test syntax
- ✅ **CI/CD Ready** - Run in automated pipelines

### Web UI (Phase 3)
- ✅ **Span Browser** - Filter, search, paginate production spans
- ✅ **Prompt Editor** - Monaco Editor with diff view
- ✅ **Settings Form** - AI configuration interface
- ✅ **Real-time Progress** - Turbo Streams updates
- ✅ **Results Comparison** - Side-by-side metrics
- ✅ **Session Management** - Save and resume experiments

### Statistical LLM Judge (NEW)
Based on [Lee et al. "How to Correctly Report LLM-as-a-Judge Evaluations"](https://arxiv.org/abs/2511.21140):
- ✅ **Bias-Corrected Accuracy** - Corrects for judge sensitivity/specificity
- ✅ **Calibration Support** - Ground-truth labeled calibration sets
- ✅ **Confidence Intervals** - Accounts for test and calibration uncertainty
- ✅ **Multi-Judge Consensus** - Aggregate multiple models for reliability
- ✅ **Bias Mitigation** - Position, length, and format bias detection
- ✅ **RSpec Matchers** - `have_bias_corrected_accuracy`, `satisfy_judge_consensus`, etc.

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────┐
│                    RAAF Eval System                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Production Spans → Serialization → Evaluation Engine   │
│                                            ↓             │
│                                       Metrics System     │
│                                            ↓             │
│                                    Result Storage        │
│                                                          │
│  Interfaces:                                            │
│  • RSpec Matchers (automated testing)                   │
│  • Web UI (interactive experimentation)                 │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Two-Gem Architecture

**raaf-eval** (Core Engine):
- Span serialization and deserialization
- Evaluation execution engine
- Metrics calculation (quantitative, qualitative, statistical)
- RSpec integration and matchers
- Database models and persistence

**raaf-eval-ui** (Web Interface):
- Rails engine with Phlex components
- Span browser with filtering
- Prompt editor with Monaco
- Real-time execution tracking
- Results visualization
- Session persistence

See **[Architecture Details](eval/ARCHITECTURE.md)** for complete system design.

## Installation

### Core Evaluation Engine

```ruby
# Gemfile
gem 'raaf-eval'
```

```bash
bundle install
cd eval
bundle exec rake db:migrate
```

### Web UI (Optional)

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

See **[Installation Guide](eval/README.md)** for detailed setup.

## Usage Examples

### Quick Evaluation

```ruby
require 'raaf/eval'

# Get baseline span from production
baseline_span = RAAF::Eval::SpanAccessor.new.find_by_id("span_123")

# Create evaluation with configuration changes
engine = RAAF::Eval::EvaluationEngine.new
run = engine.create_run(
  name: "Model Comparison",
  baseline_span: RAAF::Eval::SpanSerializer.serialize(baseline_span),
  configurations: [
    { name: "GPT-4", changes: { model: "gpt-4o" } },
    { name: "Claude", changes: { model: "claude-3-5-sonnet-20241022", provider: "anthropic" } }
  ]
)

# Execute and view results
results = engine.execute_run(run)
results.each do |result|
  puts "#{result.configuration.name}: #{result.token_metrics[:total_tokens]} tokens"
end
```

### RSpec Testing

```ruby
RSpec.describe "Agent quality validation" do
  it "maintains output quality across prompt changes" do
    baseline = latest_span_for("ResearchAgent")

    result = evaluate_span(baseline) do |config|
      config.instructions = "Enhanced instructions with more context..."
    end

    expect(result).to maintain_semantic_similarity(threshold: 0.9)
    expect(result).to have_no_safety_violations
    expect(result).to pass_llm_judge(criteria: "accuracy and completeness")
  end
end
```

See **[Getting Started Guide](eval/GETTING_STARTED.md)** for comprehensive examples.

## Metrics System

RAAF Eval provides four categories of metrics:

### 1. Quantitative Metrics
- **Token Usage** - Input, output, total tokens with cost calculation
- **Latency** - Request, processing, total time
- **Accuracy** - Exact match, containment, structural validation
- **Length** - Character and word counts with deltas

### 2. Qualitative Metrics (AI-Powered)
- **Semantic Similarity** - Cosine similarity via embeddings
- **Bias Detection** - Protected attribute mentions
- **Hallucination Detection** - Unsupported claim identification
- **Tone Analysis** - Sentiment and formality assessment

### 3. Statistical Metrics
- **Confidence Intervals** - 95% confidence bounds
- **Statistical Significance** - p-values and significance tests
- **Effect Size** - Cohen's d for practical significance

### 4. Custom Metrics
- **Domain-Specific KPIs** - Define your own metrics
- **Business Logic Validation** - Custom assertion logic

See **[Metrics Documentation](eval/METRICS.md)** for complete reference.

## RSpec Matchers Reference

### Performance Matchers
- `complete_within(ms)` - Execution time limit
- `use_fewer_tokens_than(baseline)` - Token efficiency
- `reduce_tokens_by_at_least(percent)` - Token reduction
- `have_latency_under(ms)` - Response time

### Quality Matchers
- `maintain_semantic_similarity(threshold)` - Meaning preservation
- `have_output_length_within(range)` - Length constraints
- `match_baseline_structure` - Structural consistency
- `pass_llm_judge(criteria)` - AI quality assessment

### Regression Matchers
- `not_regress_from_baseline` - Overall quality check
- `maintain_baseline_quality` - Quality preservation
- `improve_over_baseline` - Quality improvement

### Safety Matchers
- `have_no_safety_violations` - Content safety
- `detect_no_bias` - Bias detection
- `detect_no_hallucinations` - Factual accuracy

**[Complete Matcher Reference](eval/RSPEC_INTEGRATION.md#available-matchers)**

## Integration with RAAF Ecosystem

### Current Integration

RAAF Eval integrates with:
- **raaf-core** - Agent execution and tracing
- **raaf-tracing** - Span data access
- **raaf-providers** - Multi-provider support

### Future Integration (Phase 4.5)

When RAAF tracing dashboard UI exists:
- **"Evaluate This Span"** buttons in trace views
- **"View Original Trace"** links in eval results
- **Unified navigation** between monitoring and evaluation
- **Shared authentication** and authorization

See **[Integration Guide](eval-ui/INTEGRATION_GUIDE.md)** for patterns and recommendations.

## Performance

RAAF Eval is designed for production use:

- **Serialization**: < 10ms per span
- **Evaluation**: ~100-500ms per execution (depends on LLM)
- **Metrics**: < 5ms quantitative, ~200ms qualitative
- **Database**: < 50ms query time for 10,000+ records
- **UI**: < 100ms page load, < 50ms component render

See **[Performance Benchmarks](eval/PERFORMANCE.md)** for detailed analysis.

## Continuous Evaluation (Phase 6) 🆕

### Overview

Continuous Evaluation automatically evaluates AI agent spans as they are created in production, enabling real-time quality monitoring, regression detection, and compliance tracking without manual intervention.

**Key Benefits:**
- **Automatic Quality Monitoring** - Catch regressions and issues without manual testing
- **Production Insights** - Understand actual agent behavior in real-world scenarios
- **Compliance Verification** - Ensure agents meet regulatory and policy requirements
- **Cost-Optimized** - Smart sampling and daily limits prevent runaway costs

### Architecture

Continuous evaluation runs asynchronously using background jobs to ensure zero impact on production performance:

```
Production Span Created → Policy Matcher → Queue Entry → Background Job → Evaluators → Results
                              ↓                              ↓                    ↓
                         Active Policies              Priority Processing    Metrics Aggregation
```

### Configuration

#### Creating Evaluation Policies

Policies define which spans to evaluate and how:

```ruby
# Via Rails UI (recommended)
# Navigate to /eval/continuous/policies and click "New Policy"

# Via Console
policy = RAAF::Eval::Models::EvaluationPolicy.create!(
  name: "Production GPT-4 Monitoring",
  agent_name: "CustomerSupportAgent",
  environment: "production",
  model_pattern: "gpt-4*",         # Wildcard matching
  sampling_mode: "percentage",      # all, percentage, or every_n
  sample_rate: 10,                  # Sample 10% of matching spans
  max_daily_evaluations: 1000,      # Cost control
  priority: 80,                      # Higher priority processes first
  evaluators: [
    {
      "type" => "llm_judge",
      "name" => "quality_judge",
      "config" => { "criteria" => "accuracy and helpfulness" }
    },
    {
      "type" => "rule_based",
      "name" => "pii_detector",
      "config" => {}
    }
  ],
  active: true
)
```

#### Targeting Options

Policies can target spans using flexible patterns:

- **agent_name**: Exact match or wildcard (`"Support*"` matches SupportAgent, SupportBot, etc.)
- **environment**: `"production"`, `"staging"`, `"development"`, or `"all"`
- **model_pattern**: Wildcard patterns (`"gpt-4*"`, `"claude*"`, `"*sonnet*"`)
- **version_pattern**: Agent version matching (optional)

#### Sampling Strategies

Control evaluation volume and costs with sampling:

- **`all`**: Evaluate every matching span (use with caution in production)
- **`percentage`**: Random sampling (e.g., 10% of spans)
- **`every_n`**: Deterministic sampling (e.g., every 5th span)

Combined with `max_daily_evaluations` for cost caps.

### Available Evaluators

Evaluators are discovered from the DSL registry and include:

#### Built-in Evaluators

- **LLM Judges**: Quality assessment using AI models
  - `quality_judge` - Overall quality evaluation
  - `accuracy_judge` - Factual accuracy verification
  - `helpfulness_judge` - User value assessment

- **Rule-Based**: Deterministic checks
  - `pii_detector` - PII/sensitive data detection
  - `profanity_checker` - Content moderation
  - `length_validator` - Output length constraints

- **Statistical**: Performance analysis
  - `latency_monitor` - Response time tracking
  - `token_analyzer` - Token usage optimization
  - `error_rate_tracker` - Failure pattern detection

#### Custom Evaluators

Register custom evaluators via DSL:

```ruby
class ComplianceEvaluator < RAAF::Eval::DSL::Evaluators::Base
  def evaluate(span_data, expected_output)
    # Custom compliance logic
    passed = check_regulatory_compliance(span_data)
    build_result(passed: passed, score: passed ? 1.0 : 0.0)
  end
end

# Automatically discovered by continuous evaluation
RAAF::Eval::DSL::EvaluatorRegistry.register(:compliance, ComplianceEvaluator)
```

### Dashboard Features

The continuous evaluation dashboard provides:

#### Policy Management (`/eval/continuous/policies`)
- Create, edit, and delete policies
- Enable/disable policies instantly
- View policy match statistics
- Test policy matching with sample spans

#### Queue Monitoring (`/eval/continuous/queue`)
- Real-time queue depth and processing rate
- Priority-ordered evaluation list
- Failed evaluation retry management
- Performance metrics and bottleneck identification

#### Results Browser (`/eval/continuous/results`)
- Filter by policy, agent, time range
- Aggregate good/average/bad rates
- Drill down to individual evaluations
- Export results for analysis

#### Analytics (`/eval/continuous/analytics`)
- Time-series charts of evaluation metrics
- Agent performance trends
- Cost tracking and optimization recommendations
- Alerting threshold configuration

### Background Jobs

Continuous evaluation uses three types of background jobs:

#### EvaluationJob
Processes individual span evaluations:
- Fetches span data
- Runs configured evaluators
- Stores results
- Updates metrics

```ruby
# Automatically enqueued when spans are created
# Priority based on policy configuration
# Retries on transient failures
```

#### MetricsAggregationJob
Computes aggregate metrics hourly:
- Success rates by agent/model
- Average scores and trends
- Cost analysis
- Alert threshold checking

```ruby
# Runs every hour via cron
# Updates dashboard analytics
```

#### ResetDailyCountersJob
Resets daily evaluation quotas:
- Runs at midnight UTC
- Resets all policy counters
- Archives daily statistics

### API Reference

#### REST Endpoints

```ruby
# List all policies
GET /api/v1/eval/continuous/policies

# Create new policy
POST /api/v1/eval/continuous/policies
{
  "name": "Production Monitoring",
  "agent_name": "SupportAgent",
  "sampling_mode": "percentage",
  "sample_rate": 10,
  "evaluators": [...]
}

# Get evaluation results
GET /api/v1/eval/continuous/results?policy_id=123&start_date=2025-01-01

# Queue status
GET /api/v1/eval/continuous/queue/status
```

#### Response Formats

```json
// Policy List Response
{
  "policies": [
    {
      "id": 1,
      "name": "Production GPT-4 Monitoring",
      "agent_name": "CustomerSupportAgent",
      "active": true,
      "match_count_today": 150,
      "evaluation_count_today": 15,
      "success_rate": 0.93
    }
  ],
  "meta": {
    "total": 5,
    "page": 1
  }
}

// Queue Status Response
{
  "queue": {
    "depth": 42,
    "processing_rate": 10.5,
    "estimated_wait_time_seconds": 4,
    "failed_count": 2,
    "workers_active": 3
  }
}
```

### Performance Characteristics

- **Span Creation Overhead**: < 5ms (async hook only)
- **Evaluation Latency**: 100ms - 5s (depends on evaluators)
- **Queue Processing**: 10-50 evaluations/second/worker
- **Storage Growth**: ~2KB per evaluation result
- **Dashboard Load Time**: < 200ms for 10,000 results

### Best Practices

1. **Start with Low Sampling Rates**: Begin with 1-5% sampling in production
2. **Use Daily Limits**: Always set `max_daily_evaluations` to control costs
3. **Prioritize Critical Agents**: Use priority scores to evaluate important agents first
4. **Monitor Queue Depth**: Scale workers if queue consistently > 1000
5. **Archive Old Results**: Move results > 30 days to cold storage
6. **Test Policies in Staging**: Validate policies work before production deployment

### Troubleshooting

**High Queue Depth:**
- Increase worker count
- Reduce sampling rates
- Check for slow evaluators

**Missing Evaluations:**
- Verify policy is active
- Check policy matching criteria
- Ensure daily limit not reached
- Review job failure logs

**Inconsistent Results:**
- Check evaluator configurations
- Verify span data completeness
- Review sampling methodology

## Development Status

### Phase 1: Foundation (✅ Complete)
- Database schema and migrations
- Span serialization and deserialization
- Evaluation execution engine
- Basic metrics system

### Phase 2: RSpec Integration (✅ Complete)
- 40+ RSpec matchers across 8 categories
- Fluent evaluation DSL
- Helper methods and test utilities
- CI/CD integration support

### Phase 3: Web UI (✅ Complete)
- Span browser with filtering
- Prompt editor with Monaco
- Settings configuration form
- Real-time execution tracking
- Results comparison view
- Session management

### Phase 4: Metrics & Active Record (Planned)
- Active Record model linking
- Historical performance tracking
- Baseline management
- Automated regression detection

### Phase 4.5: Tracing Integration (Future)
- Deep integration with tracing dashboard
- Cross-navigation between systems
- Unified RAAF platform experience

### Phase 6: Continuous Evaluation (✅ Complete)
- Policy-based automatic evaluation
- Background job processing
- Evaluator discovery from DSL
- Dashboard for monitoring and configuration
- API endpoints for programmatic access

See **[Product Roadmap](.agent-os/product/roadmap.md)** for complete timeline.

## Contributing

We welcome contributions! See:
- **[Contributing Guide](eval-ui/CONTRIBUTING.md)** - Development setup and guidelines
- **[Architecture Documentation](eval/ARCHITECTURE.md)** - System design
- **[GitHub Issues](https://github.com/raaf-ai/ruby-ai-agents-factory/issues)** - Bug reports and features

## License

MIT License - see LICENSE file for details.

## Documentation Map

### For Users
1. Start: **[README](eval/README.md)** - Quick start
2. Learn: **[Getting Started](eval/GETTING_STARTED.md)** - Tutorial
3. Test: **[RSpec Integration](eval/RSPEC_INTEGRATION.md)** - Writing tests
4. UI: **[UI Setup](eval-ui/README.md)** - Web interface

### For Developers
1. **[Architecture](eval/ARCHITECTURE.md)** - System design
2. **[API Reference](eval/API.md)** - Complete API
3. **[Metrics](eval/METRICS.md)** - Metrics system
4. **[Performance](eval/PERFORMANCE.md)** - Benchmarks

### For Integrators
1. **[Integration Guide](eval-ui/INTEGRATION_GUIDE.md)** - RAAF ecosystem integration
2. **[Migrations](eval/MIGRATIONS.md)** - Database schema
3. **[Contributing](eval-ui/CONTRIBUTING.md)** - Development guide

---

**Questions?** Open an issue on [GitHub](https://github.com/raaf-ai/ruby-ai-agents-factory/issues) or check existing documentation.
