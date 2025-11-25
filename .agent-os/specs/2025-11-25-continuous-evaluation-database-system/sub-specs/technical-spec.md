# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-11-25-continuous-evaluation-database-system/spec.md

> Created: 2025-11-25
> Version: 1.0.0

## Technical Requirements

### Core Requirements

- Zero impact on production span creation (<5ms hook overhead)
- Async evaluation execution via Solid Queue
- Support for multiple evaluator types (rule-based, statistical, LLM judges)
- Configurable sampling (percentage-based, 1-in-N, daily limits)
- Pre-aggregated metrics for sub-100ms dashboard queries
- D3.js time-series visualizations
- Hard deprecation of DSL `history do...end` blocks

### Performance Requirements

| Metric | Target |
|--------|--------|
| Span creation overhead | <5ms |
| Queue insertion time | <10ms |
| Dashboard page load | <500ms |
| Metrics query time | <100ms |
| Evaluation throughput | 100+ evals/minute per worker |

### Integration Requirements

- Integrate with existing `raaf_tracing_spans` table via hooks
- Extend existing raaf-rails dashboard navigation
- Use existing Phlex component patterns
- Leverage existing authentication/authorization
- Compatible with existing evaluation engine (`RAAF::Eval::DslEngine::Evaluator`)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Span Creation                                │
│                   (raaf_tracing_spans)                              │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ after_commit callback
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Policy Matcher                                    │
│  RAAF::Eval::Continuous::PolicyMatcher                              │
│  - Find matching raaf_evaluation_policies                           │
│  - Apply sampling logic (sample_rate, sample_every_n)               │
│  - Check daily limits (max_daily_evaluations)                       │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ if should_evaluate?
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  Evaluation Queue                                    │
│               (raaf_evaluation_queue)                               │
│  - Solid Queue job enqueued                                         │
│  - Priority from policy                                             │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ Solid Queue processes job
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  Evaluation Executor Job                             │
│  RAAF::Eval::Continuous::EvaluationJob                              │
│  - Runs configured evaluators from policy                           │
│  - Rule-based evaluators (fast, no cost)                            │
│  - Statistical evaluators (moderate)                                │
│  - LLM judge evaluators (slow, costs tokens)                        │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                Evaluation Results                                    │
│            (raaf_evaluation_results)                                │
│  - One row per evaluator per span                                   │
│  - Full metrics, scores, reasoning                                  │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ async aggregation (every hour)
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Aggregated Metrics                                      │
│           (raaf_evaluation_metrics)                                 │
│  - Pre-computed for dashboard graphs                                │
│  - Hourly/daily/weekly rollups                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Component Design

### 1. Policy Matcher (`RAAF::Eval::Continuous::PolicyMatcher`)

Responsible for determining if a span should be evaluated based on active policies.

```ruby
module RAAF::Eval::Continuous
  class PolicyMatcher
    def initialize(span)
      @span = span
    end

    # Returns array of matching policies that should trigger evaluation
    def matching_policies
      EvaluationPolicy
        .active
        .where_matches_span(@span)
        .select { |policy| should_evaluate?(policy) }
    end

    private

    def should_evaluate?(policy)
      return false if daily_limit_reached?(policy)

      case policy.sampling_mode
      when 'percentage'
        rand(100) < policy.sample_rate
      when 'every_n'
        policy.increment_counter % policy.sample_every_n == 0
      else
        true
      end
    end

    def daily_limit_reached?(policy)
      return false if policy.max_daily_evaluations.nil?
      policy.today_evaluation_count >= policy.max_daily_evaluations
    end
  end
end
```

### 2. Span Creation Hook

After-commit callback on SpanRecord to trigger policy matching:

```ruby
# In RAAF::Rails::Tracing::SpanRecord
after_commit :enqueue_continuous_evaluations, on: :create

private

def enqueue_continuous_evaluations
  return unless RAAF::Eval::Continuous.enabled?

  RAAF::Eval::Continuous::PolicyMatcher.new(self).matching_policies.each do |policy|
    RAAF::Eval::Continuous::EvaluationJob.perform_later(
      span_id: span_id,
      policy_id: policy.id,
      priority: policy.priority
    )
  end
end
```

### 3. Evaluation Job (`RAAF::Eval::Continuous::EvaluationJob`)

Solid Queue job that executes evaluators:

```ruby
module RAAF::Eval::Continuous
  class EvaluationJob < ApplicationJob
    queue_as :raaf_evaluations

    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    discard_on RAAF::Eval::SpanNotFoundError

    def perform(span_id:, policy_id:)
      span = RAAF::Rails::Tracing::SpanRecord.find(span_id)
      policy = EvaluationPolicy.find(policy_id)
      queue_item = create_queue_item(span, policy)

      begin
        queue_item.mark_running!

        policy.evaluators.each do |evaluator_config|
          result = execute_evaluator(span, evaluator_config)
          store_result(span, policy, evaluator_config, result)
        end

        queue_item.mark_completed!
      rescue => e
        queue_item.mark_failed!(e.message)
        raise
      end
    end

    private

    def execute_evaluator(span, config)
      evaluator = EvaluatorRegistry.build(config)
      evaluator.evaluate(span_to_eval_format(span))
    end

    def store_result(span, policy, config, result)
      EvaluationResult.create!(
        span_id: span.span_id,
        trace_id: span.trace_id,
        evaluation_policy: policy,
        evaluation_type: 'automated',
        evaluator_name: config[:name],
        agent_name: extract_agent_name(span),
        model: extract_model(span),
        environment: Rails.env,
        status: result.passed? ? 'passed' : 'failed',
        score: result.score,
        scores: result.field_scores,
        reasoning: result.reasoning,
        metrics: extract_metrics(span),
        details: result.to_h
      )
    end
  end
end
```

### 4. Evaluator Discovery Service

The system leverages the existing `RAAF::Eval::DSL::EvaluatorRegistry` singleton to discover evaluators defined in end-user applications (like ProspectsRadar). This allows the UI to show a list of available evaluators that users can select when configuring policies.

```ruby
module RAAF::Eval::Continuous
  class EvaluatorDiscovery
    # Returns all registered evaluator names from the DSL registry
    # These include both built-in evaluators and custom evaluators
    # defined in end-user applications
    def self.available_evaluators
      RAAF::Eval::DSL::EvaluatorRegistry.instance.all_names
    end

    # Returns detailed information about each evaluator
    # for display in the UI
    def self.evaluator_details
      RAAF::Eval::DSL::EvaluatorRegistry.instance.all_names.map do |name|
        evaluator_class = RAAF::Eval::DSL::EvaluatorRegistry.instance.get(name)
        {
          name: name.to_s,
          class_name: evaluator_class.name,
          type: determine_evaluator_type(evaluator_class),
          description: evaluator_class.respond_to?(:description) ? evaluator_class.description : nil,
          configurable_options: extract_configurable_options(evaluator_class)
        }
      end
    end

    # Builds an evaluator instance from a policy configuration
    def self.build(config)
      name = config[:name].to_sym
      evaluator_class = RAAF::Eval::DSL::EvaluatorRegistry.instance.get(name)
      raise UnknownEvaluatorError, "Unknown evaluator: #{name}" unless evaluator_class

      evaluator_class.new(config[:config] || {})
    end

    private

    def self.determine_evaluator_type(evaluator_class)
      # Inspect the evaluator class to determine its type
      if evaluator_class.respond_to?(:evaluator_type)
        evaluator_class.evaluator_type
      elsif evaluator_class.name&.include?('LlmJudge')
        'llm_judge'
      elsif evaluator_class.name&.include?('Statistical')
        'statistical'
      else
        'rule_based'
      end
    end

    def self.extract_configurable_options(evaluator_class)
      return [] unless evaluator_class.respond_to?(:configurable_options)
      evaluator_class.configurable_options
    end
  end
end
```

### How Evaluator Discovery Works

1. **End-User Application Defines Evaluators**: In apps like ProspectsRadar, developers define custom evaluators using the DSL:

```ruby
# In ProspectsRadar app: app/evaluators/company_quality_evaluator.rb
class CompanyQualityEvaluator
  include RAAF::Eval::DSL::Evaluator

  evaluator_name :company_quality

  def evaluate(field_context, **options)
    # Custom evaluation logic
  end
end
```

2. **Evaluators Auto-Register**: When the Rails app boots, evaluators are automatically registered with `RAAF::Eval::DSL::EvaluatorRegistry.instance`.

3. **UI Fetches Available Evaluators**: The policy form calls the API endpoint to get the list of available evaluators:

```ruby
# In the PoliciesController
def new
  @policy = EvaluationPolicy.new(default_policy_attributes)
  @available_evaluators = RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details
end
```

4. **User Selects Evaluators in UI**: The form displays a multi-select or checkbox list of available evaluators with their descriptions and types.

5. **Policy Stores Evaluator Config**: Selected evaluators and their configurations are stored in the policy's `evaluators` JSONB column:

```json
{
  "evaluators": [
    { "name": "company_quality", "config": { "min_score": 0.7 } },
    { "name": "token_limit", "config": { "max_tokens": 4000 } }
  ]
}
```

### 5. Evaluator Execution in Jobs

The evaluation job uses EvaluatorDiscovery to build and execute evaluators:

```ruby
module RAAF::Eval::Continuous
  class EvaluationJob < ApplicationJob
    queue_as :raaf_evaluations

    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    discard_on RAAF::Eval::SpanNotFoundError

    def perform(span_id:, policy_id:)
      span = RAAF::Rails::Tracing::SpanRecord.find(span_id)
      policy = EvaluationPolicy.find(policy_id)
      queue_item = create_queue_item(span, policy)

      begin
        queue_item.mark_running!

        policy.evaluators.each do |evaluator_config|
          result = execute_evaluator(span, evaluator_config)
          store_result(span, policy, evaluator_config, result)
        end

        queue_item.mark_completed!
      rescue => e
        queue_item.mark_failed!(e.message)
        raise
      end
    end

    private

    def execute_evaluator(span, config)
      # Uses EvaluatorDiscovery to build from the DSL registry
      evaluator = EvaluatorDiscovery.build(config)
      evaluator.evaluate(span_to_eval_format(span))
    end

    def store_result(span, policy, config, result)
      EvaluationResult.create!(
        span_id: span.span_id,
        trace_id: span.trace_id,
        evaluation_policy: policy,
        evaluation_type: 'automated',
        evaluator_name: config[:name],
        agent_name: extract_agent_name(span),
        model: extract_model(span),
        environment: Rails.env,
        status: result.passed? ? 'passed' : 'failed',
        score: result.score,
        scores: result.field_scores,
        reasoning: result.reasoning,
        metrics: extract_metrics(span),
        details: result.to_h
      )
    end
  end
end
```

### 6. Metrics Aggregation Job

Scheduled job that pre-computes dashboard metrics:

```ruby
module RAAF::Eval::Continuous
  class MetricsAggregationJob < ApplicationJob
    queue_as :raaf_evaluations_low

    def perform(period_type: 'hourly')
      case period_type
      when 'hourly'
        aggregate_hourly_metrics
      when 'daily'
        aggregate_daily_metrics
      when 'weekly'
        aggregate_weekly_metrics
      end
    end

    private

    def aggregate_hourly_metrics
      # Get results from last 2 hours (overlap for safety)
      results = EvaluationResult.where(created_at: 2.hours.ago..)

      results.group(:agent_name, :environment, :evaluator_name)
             .group_by_hour(:created_at)
             .each do |group, records|
        upsert_metric(group, 'hourly', records)
      end
    end

    def upsert_metric(group, period_type, records)
      EvaluationMetric.upsert({
        agent_name: group[:agent_name],
        environment: group[:environment],
        evaluator_name: group[:evaluator_name],
        period_type: period_type,
        period_start: group[:created_at].beginning_of_hour,
        total_evaluations: records.count,
        passed_count: records.count(&:passed?),
        failed_count: records.count(&:failed?),
        avg_score: records.average(&:score),
        # ... more aggregations
      }, unique_by: [:agent_name, :environment, :evaluator_name, :period_type, :period_start])
    end
  end
end
```

## UI Components

### Dashboard Navigation Extension

Add "Evaluations" section to existing dashboard nav:

```ruby
# Extend existing navigation in raaf-rails
module RAAF::Rails::Tracing
  class Navigation < BaseComponent
    def navigation_items
      [
        # ... existing items ...
        { label: 'Evaluations', icon: 'bi-clipboard-check', children: [
          { label: 'Policies', path: evaluation_policies_path },
          { label: 'Queue', path: evaluation_queue_path },
          { label: 'Results', path: evaluation_results_path },
          { label: 'Analytics', path: evaluation_analytics_path }
        ]}
      ]
    end
  end
end
```

### D3.js Time-Series Chart Component

```ruby
module RAAF::Rails::Evaluation
  class PassRateChart < BaseComponent
    def initialize(data:, agent_name:, date_range:)
      @data = data
      @agent_name = agent_name
      @date_range = date_range
    end

    def view_template
      div(id: 'pass-rate-chart',
          class: 'w-full h-64',
          data: {
            controller: 'pass-rate-chart',
            pass_rate_chart_data_value: @data.to_json
          })
    end
  end
end
```

```javascript
// app/javascript/controllers/pass_rate_chart_controller.js
import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

export default class extends Controller {
  static values = { data: Array }

  connect() {
    this.renderChart()
  }

  renderChart() {
    const margin = { top: 20, right: 30, bottom: 30, left: 40 }
    const width = this.element.clientWidth - margin.left - margin.right
    const height = this.element.clientHeight - margin.top - margin.bottom

    const svg = d3.select(this.element)
      .append("svg")
      .attr("width", width + margin.left + margin.right)
      .attr("height", height + margin.top + margin.bottom)
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    const x = d3.scaleTime()
      .domain(d3.extent(this.dataValue, d => new Date(d.date)))
      .range([0, width])

    const y = d3.scaleLinear()
      .domain([0, 100])
      .range([height, 0])

    // Add axes
    svg.append("g")
      .attr("transform", `translate(0,${height})`)
      .call(d3.axisBottom(x))

    svg.append("g")
      .call(d3.axisLeft(y).tickFormat(d => d + "%"))

    // Add line
    const line = d3.line()
      .x(d => x(new Date(d.date)))
      .y(d => y(d.pass_rate))
      .curve(d3.curveMonotoneX)

    svg.append("path")
      .datum(this.dataValue)
      .attr("fill", "none")
      .attr("stroke", "#10b981")
      .attr("stroke-width", 2)
      .attr("d", line)

    // Add target line at 85%
    svg.append("line")
      .attr("x1", 0)
      .attr("x2", width)
      .attr("y1", y(85))
      .attr("y2", y(85))
      .attr("stroke", "#6b7280")
      .attr("stroke-dasharray", "4")
  }
}
```

## External Dependencies

### New Dependencies

| Dependency | Purpose | Justification |
|------------|---------|---------------|
| `solid_queue` | Background job processing | User requirement; PostgreSQL-based, no Redis needed |
| `d3-rails` or importmap D3 | Time-series charts | User requirement for analytics visualization |
| `groupdate` | Time-based grouping | Simplifies hourly/daily/weekly aggregations |

### Existing Dependencies (No Changes)

- `raaf-eval` - Evaluation engine
- `raaf-rails` - Dashboard integration
- `phlex` - UI components
- `turbo-rails` - Real-time updates
- `stimulus-rails` - JavaScript controllers

## Migration from DSL

### Hard Deprecation Strategy

1. **Remove** `history do...end` DSL support from evaluator definitions
2. **Provide** migration guide for converting DSL to database policies
3. **Add** rake task to help migrate existing configurations

```ruby
# Migration helper
namespace :raaf do
  namespace :eval do
    desc "Migrate DSL history configurations to database policies"
    task migrate_history_config: :environment do
      # Scan evaluator files for history blocks
      # Generate policy records
      # Output migration report
    end
  end
end
```

### Breaking Changes

- `RAAF::Eval::DSL::Builder#history` method removed
- `RAAF::Eval::DSL::HistoryDSL` class removed
- `RAAF::Eval::Storage::HistoricalStorage` deprecated (use database)
- `RAAF::Eval::Storage::RetentionPolicy` deprecated (use policy retention_days)

## Configuration

### Environment Variables

```bash
# Enable/disable continuous evaluation
RAAF_CONTINUOUS_EVAL_ENABLED=true

# Default queue name for evaluation jobs
RAAF_EVAL_QUEUE_NAME=raaf_evaluations

# Metrics aggregation schedule (cron format)
RAAF_EVAL_METRICS_AGGREGATION_SCHEDULE="0 * * * *"  # Every hour

# Maximum concurrent evaluations per policy
RAAF_EVAL_MAX_CONCURRENT_DEFAULT=5
```

### Solid Queue Configuration

```yaml
# config/solid_queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: [raaf_evaluations]
      threads: 5
      processes: 2
    - queues: [raaf_evaluations_low]
      threads: 2
      processes: 1
```

## Security Considerations

- Policy changes require appropriate authorization (admin/team lead)
- Audit log for all policy modifications
- Rate limiting on policy creation to prevent abuse
- Evaluator configurations validated before execution
- LLM judge API keys stored securely (existing RAAF provider config)
