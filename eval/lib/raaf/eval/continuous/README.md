# Continuous Evaluation System

This directory contains the core components for RAAF's continuous evaluation system, which automatically evaluates AI agent spans in production.

## Architecture Overview

```
SpanRecord (created) → PolicyMatcher → EvaluationQueue → EvaluationJob → Results
                           ↓                                    ↓
                    EvaluationPolicy                    EvaluatorDiscovery
```

## Key Components

### Core Classes

- **`PolicyMatcher`** - Determines which policies apply to a given span
- **`EvaluatorDiscovery`** - Discovers and builds evaluators from DSL registry
- **`SpanEnqueuer`** - Handles span creation hooks and queue management
- **`QueueProcessor`** - Processes evaluation queue items in background
- **`MetricsAggregator`** - Aggregates evaluation results for analytics

### Database Models (`models/continuous/`)

- **`EvaluationPolicy`** - Configuration for automatic evaluation rules
- **`EvaluationQueueItem`** - Queue entries for pending evaluations
- **`ContinuousEvaluationResult`** - Results from automatic evaluations
- **`ContinuousEvaluationMetric`** - Aggregated metrics and trends

## Usage

### Setting Up a Policy

```ruby
# Create a policy to monitor production agents
policy = RAAF::Eval::Models::EvaluationPolicy.create!(
  name: "Production Quality Monitor",
  agent_name: "CustomerSupportAgent",
  environment: "production",
  sampling_mode: "percentage",
  sample_rate: 10,  # Evaluate 10% of spans
  max_daily_evaluations: 1000,
  evaluators: [
    { "type" => "llm_judge", "name" => "quality_judge" }
  ],
  active: true
)
```

### Manual Testing

```ruby
# Test policy matching
span = SpanRecord.last
matcher = RAAF::Eval::Continuous::PolicyMatcher.new(span)
policies = matcher.policies_to_evaluate
puts "Found #{policies.count} policies for this span"

# Test evaluator discovery
available = RAAF::Eval::Continuous::EvaluatorDiscovery.available_evaluators
puts "Available evaluators: #{available.join(', ')}"

# Manually enqueue a span
enqueuer = RAAF::Eval::Continuous::SpanEnqueuer.new(span)
enqueuer.enqueue_if_needed
```

## Background Jobs

The system uses three background jobs (found in `rails/app/jobs/raaf/rails/`):

1. **`EvaluationJob`** - Processes individual evaluations
2. **`MetricsAggregationJob`** - Computes hourly metrics
3. **`ResetDailyCountersJob`** - Resets daily quotas at midnight

## Configuration

### Environment Variables

```bash
# Maximum queue depth before throttling
RAAF_EVAL_MAX_QUEUE_DEPTH=10000

# Number of evaluation workers
RAAF_EVAL_WORKER_COUNT=4

# Enable continuous evaluation
RAAF_CONTINUOUS_EVALUATION_ENABLED=true
```

### Rails Configuration

```ruby
# config/initializers/raaf_eval.rb
RAAF::Eval.configure do |config|
  config.continuous_evaluation = true
  config.max_queue_depth = 10_000
  config.worker_pool_size = 4
end
```

## Dashboard Routes

The Rails engine provides these routes:

- `/eval/continuous` - Main dashboard
- `/eval/continuous/policies` - Policy management
- `/eval/continuous/queue` - Queue monitoring
- `/eval/continuous/results` - Results browser
- `/eval/continuous/analytics` - Analytics and charts

## Development

### Adding a Custom Evaluator

```ruby
# app/evaluators/compliance_evaluator.rb
class ComplianceEvaluator < RAAF::Eval::DSL::Evaluators::Base
  def evaluate(span_data, expected_output)
    # Your evaluation logic
    passed = check_compliance(span_data)
    build_result(passed: passed, score: passed ? 1.0 : 0.0)
  end
end

# Register it
RAAF::Eval::DSL::EvaluatorRegistry.register(:compliance, ComplianceEvaluator)
```

### Testing

```ruby
# spec/continuous/policy_matcher_spec.rb
RSpec.describe RAAF::Eval::Continuous::PolicyMatcher do
  let(:span) { create(:span_record, agent_name: "TestAgent") }
  let(:policy) { create(:evaluation_policy, agent_name: "Test*") }

  it "matches spans by pattern" do
    matcher = described_class.new(span)
    expect(matcher.matching_policies).to include(policy)
  end
end
```

## Monitoring

Key metrics to monitor:

- **Queue Depth** - Should stay under 1000 in steady state
- **Processing Rate** - Target 10+ evaluations/second/worker
- **Daily Quota Usage** - Track against max_daily_evaluations
- **Evaluation Success Rate** - Should be > 95%
- **Worker Utilization** - Scale if consistently > 80%

## See Also

- [RAAF_EVAL.md](../../../../RAAF_EVAL.md#continuous-evaluation-phase-6-) - User documentation
- [Product Roadmap](../../../../.agent-os/product/roadmap.md) - Phase 6 specification
- [Migration Guide](../../../db/migrate/) - Database migrations