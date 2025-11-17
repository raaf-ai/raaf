# Requirements: RAAF Eval Active Record Integration & Metrics

## Overview

Phase 4 of RAAF Eval focuses on connecting evaluations to Active Record models and providing comprehensive metrics and analytics. This enables tracking evaluation history against real application data and provides aggregate metrics for performance monitoring.

## Context from Roadmap

**From `.agent-os/product/roadmap.md` Phase 4:**

**Goal:** Connect evaluations to Active Record models and provide comprehensive metrics

**Success Criteria:** Can link evaluations to models, view aggregate metrics, and track performance over time

## User Stories

### Story 1: Link Evaluations to Application Models

As a RAAF developer, I want to link evaluation runs to specific Active Record models (e.g., a Product, User, or Campaign), so that I can track which production entities have been evaluated and view their evaluation history.

**Workflow:**
1. Developer creates an evaluation run for a specific agent/span
2. System allows linking evaluation to any Active Record model via polymorphic association
3. Developer can view all evaluations related to a specific model instance
4. Evaluation results page shows which model the evaluation relates to

**Problem Solved:** Currently evaluations exist in isolation without connection to the application models they're testing. This makes it hard to understand evaluation history in the context of real production entities.

### Story 2: View Aggregate Evaluation Metrics

As a team lead, I want to view aggregate metrics across all evaluations (success rates, token usage, latency, cost), so that I can understand overall agent performance and identify optimization opportunities.

**Workflow:**
1. User navigates to Metrics Dashboard in unified RAAF UI
2. System displays aggregate metrics:
   - Success rate percentage across all evaluations
   - Average/min/max token usage
   - Average/P50/P95/P99 latency
   - Total estimated cost
3. User can filter metrics by agent, model, time range, or linked model type
4. Metrics update in real-time as new evaluations complete

**Problem Solved:** No visibility into aggregate performance across evaluations. Users must manually analyze individual evaluation results.

### Story 3: Track Agent Performance Trends Over Time

As a developer, I want to see how agent performance changes over time as I modify prompts and models, so that I can identify regressions and validate improvements.

**Workflow:**
1. User selects an agent in the metrics dashboard
2. System displays time-series charts showing:
   - Success rate trend over last 7/30/90 days
   - Token usage trend
   - Latency trend
   - Cost trend
3. User can see when configuration changes were made (linked to evaluation runs)
4. Drill-down shows specific evaluations contributing to each data point

**Problem Solved:** Currently no way to visualize agent performance over time. Difficult to correlate changes with performance impact.

### Story 4: Compare Performance Against Baselines

As a QA engineer, I want to establish baseline evaluations and compare new evaluation runs against them, so that I can detect regressions before deploying changes.

**Workflow:**
1. User marks an evaluation run as "baseline" for a specific agent
2. Subsequent evaluation runs automatically compare against baseline
3. System flags metrics that are worse than baseline (lower success rate, higher latency, higher cost)
4. Comparison view shows side-by-side baseline vs current metrics
5. Can have multiple baselines (per model, per configuration, etc.)

**Problem Solved:** No systematic way to detect regressions. Comparisons are manual and ad-hoc.

## Feature Requirements

### Must-Have Features (from roadmap)

1. **Active Record Polymorphic Associations**
   - Evaluation runs can link to any AR model via polymorphic association
   - Schema: `evaluatable_type` (string), `evaluatable_id` (integer)
   - Support querying evaluations by linked model
   - UI for selecting/linking models during evaluation creation

2. **Metrics Calculation Engine**
   - Calculate aggregate metrics: success rates, token usage, latency, cost
   - Support time-based aggregation (hourly, daily, weekly, monthly)
   - Group by multiple dimensions: agent, model, evaluator, linked model type
   - Incremental updates (don't recalculate everything on each evaluation)

3. **Metrics Dashboard**
   - Aggregate metrics view integrated into unified RAAF dashboard
   - Real-time metric updates as evaluations complete
   - Filterable by agent, model, time range, linked model type
   - Export metrics to CSV/JSON

4. **Historical Tracking**
   - Time-series storage for performance trends
   - Charts showing trends over 7/30/90 day windows
   - Correlation with configuration changes
   - Drill-down from aggregate to individual evaluations

5. **Baseline Comparison**
   - Mark evaluation runs as baselines
   - Automatic comparison of new runs against baselines
   - Regression detection and flagging
   - Side-by-side baseline vs current comparison view

### Should-Have Features (from roadmap)

1. **Automated Regression Detection**
   - Automatic flagging when metrics worse than baseline
   - Configurable thresholds (e.g., "flag if success rate drops > 5%")
   - Notification system for detected regressions
   - Regression analysis report

2. **Custom Metric Definitions**
   - Allow users to define domain-specific metrics
   - Custom calculation logic (Ruby code or SQL)
   - Custom metric displays in dashboard
   - Export custom metrics alongside standard metrics

3. **Metric Alerting System**
   - Configure alerts when metrics cross thresholds
   - Multiple channels: email, Slack, webhooks
   - Alert aggregation and deduplication
   - Alert history and acknowledgment

## Technical Specifications

### Database Schema Changes

**Evaluation Runs Table Updates:**
```ruby
add_column :evaluation_runs, :evaluatable_type, :string
add_column :evaluation_runs, :evaluatable_id, :integer
add_index :evaluation_runs, [:evaluatable_type, :evaluatable_id]
```

**New Tables:**

**1. Evaluation Metrics (aggregated metrics):**
```ruby
create_table :evaluation_metrics do |t|
  t.string :agent_name, null: false
  t.string :model_name
  t.string :evaluatable_type
  t.string :metric_type, null: false # "success_rate", "token_usage", "latency", "cost"
  t.string :aggregation_period, null: false # "hour", "day", "week", "month"
  t.datetime :period_start, null: false
  t.decimal :value, precision: 20, scale: 6
  t.integer :sample_count
  t.jsonb :metadata # min, max, p50, p95, p99 for some metrics
  t.timestamps

  t.index [:agent_name, :metric_type, :period_start]
  t.index [:period_start, :aggregation_period]
end
```

**2. Evaluation Baselines:**
```ruby
create_table :evaluation_baselines do |t|
  t.references :evaluation_run, null: false, foreign_key: true
  t.string :agent_name, null: false
  t.string :model_name
  t.string :baseline_type, null: false # "default", "model_specific", "configuration_specific"
  t.boolean :active, default: true
  t.text :description
  t.jsonb :metrics_snapshot # captured metrics at baseline time
  t.timestamps

  t.index [:agent_name, :baseline_type, :active]
end
```

### API Endpoints (raaf-rails)

**Metrics API:**
```
GET /raaf/eval/metrics?agent=X&time_range=7d&metric=success_rate
GET /raaf/eval/metrics/trends?agent=X&period=day
POST /raaf/eval/baselines (create baseline)
GET /raaf/eval/baselines?agent=X
DELETE /raaf/eval/baselines/:id (deactivate baseline)
```

### UI Components (Phlex)

**New Components in raaf-rails:**
1. `RAAF::Rails::Evaluation::MetricsDashboard` - Main metrics dashboard
2. `RAAF::Rails::Evaluation::MetricsPanel` - Individual metric display
3. `RAAF::Rails::Evaluation::TrendChart` - Time-series chart component
4. `RAAF::Rails::Evaluation::BaselineComparison` - Baseline vs current comparison
5. `RAAF::Rails::Evaluation::ModelLinker` - UI for linking evaluations to AR models

### Background Jobs

**Metrics Aggregation Jobs:**
- `EvaluationMetricsAggregationJob` - Calculate and store aggregate metrics
- `BaselineComparisonJob` - Compare new evaluations against baselines
- `RegressionDetectionJob` - Check for regressions and trigger alerts

Run after each evaluation completes, or scheduled periodically for efficiency.

## Dependencies

From roadmap Phase 4 dependencies:
- Phase 1 completion (evaluation storage) ✅
- Phase 3 completion (UI for displaying metrics) ✅
- Background job infrastructure (Sidekiq/GoodJob) - required for metric aggregation

## Acceptance Criteria

1. Evaluation runs can be linked to any Active Record model via polymorphic association
2. Metrics dashboard displays aggregate success rate, token usage, latency, and cost
3. Time-series charts show agent performance trends over configurable time windows
4. Users can mark evaluation runs as baselines and see regression detection
5. Metrics update in near-real-time (< 5 min lag) as evaluations complete
6. Export functionality works for all metrics (CSV/JSON)
7. All features integrated into unified RAAF dashboard UI (not separate interface)

## Out of Scope (for Phase 4)

- Real-time alerting system (Phase 4 should-have, may defer to Phase 5)
- Custom metric definitions (Phase 4 should-have, may defer to Phase 5)
- Advanced statistical analysis (correlations, predictions)
- Multi-project/multi-team metrics aggregation
- Integration with external monitoring tools (DataDog, New Relic, etc.)

## Notes

- This phase builds on the unified UI architecture from DEC-004
- All UI components integrate into raaf-rails, not separate eval UI
- Metrics should be efficient to calculate (use background jobs, incremental updates)
- Consider using PostgreSQL materialized views for complex aggregations
