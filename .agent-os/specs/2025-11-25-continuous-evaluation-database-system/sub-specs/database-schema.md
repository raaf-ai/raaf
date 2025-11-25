# Database Schema

This is the database schema implementation for the spec detailed in @.agent-os/specs/2025-11-25-continuous-evaluation-database-system/spec.md

> Created: 2025-11-25
> Version: 1.0.0

## Schema Overview

The continuous evaluation system requires 4 new tables:

1. **raaf_evaluation_policies** - Configuration for automatic evaluation (replaces DSL)
2. **raaf_evaluation_queue** - Queue for pending evaluations
3. **raaf_evaluation_results** - All automated evaluation results
4. **raaf_evaluation_metrics** - Pre-aggregated metrics for dashboards

## Table: raaf_evaluation_policies

Defines which spans should be evaluated and how. Replaces the DSL `history do...end` configuration.

```ruby
create_table :raaf_evaluation_policies do |t|
  # Identity
  t.string :name, null: false
  t.text :description

  # Targeting criteria
  t.string :agent_name, null: false              # Supports wildcards: "Dmu*", "*Agent"
  t.string :environment, default: 'all'          # 'production', 'staging', 'development', 'all'
  t.string :model_pattern, default: 'all'        # Supports wildcards: "gpt-4*", "claude-*"
  t.string :version_pattern, default: 'all'      # Supports wildcards: "1.*", "2.0"

  # Sampling configuration
  t.string :sampling_mode, default: 'percentage' # 'percentage', 'every_n', 'all'
  t.integer :sample_rate, default: 100           # 1-100 for percentage mode
  t.integer :sample_every_n                      # For every_n mode: evaluate 1 in N spans
  t.integer :sample_counter, default: 0          # Internal counter for every_n mode
  t.integer :max_daily_evaluations               # Cost control limit (NULL = unlimited)
  t.integer :today_evaluation_count, default: 0  # Reset daily by scheduled job
  t.date :count_reset_date                       # Track when counter was last reset

  # Queue settings
  t.integer :priority, default: 50               # 0 (lowest) to 100 (highest)
  t.string :queue_name, default: 'raaf_evaluations'
  t.integer :max_concurrent_evaluations, default: 5
  t.integer :max_retries, default: 3

  # Retention
  t.integer :retention_days, default: 90
  t.integer :retention_count                     # Keep at least N results (optional)

  # Evaluators configuration (JSONB array)
  t.jsonb :evaluators, default: []
  # Example:
  # [
  #   { "type": "rule_based", "name": "token_limit", "config": { "max_tokens": 4000 } },
  #   { "type": "rule_based", "name": "latency_check", "config": { "max_ms": 5000 } },
  #   { "type": "llm_judge", "name": "quality_check", "config": {
  #       "model": "gpt-4o-mini",
  #       "criteria": ["accuracy", "completeness", "tone"]
  #     }
  #   }
  # ]

  # Metadata
  t.jsonb :metadata, default: {}                 # Custom tags, team, compliance info
  t.boolean :active, default: true
  t.timestamps
end

# Indexes
add_index :raaf_evaluation_policies, :name, unique: true
add_index :raaf_evaluation_policies, :agent_name
add_index :raaf_evaluation_policies, :active
add_index :raaf_evaluation_policies, [:agent_name, :environment, :active],
          name: 'idx_eval_policies_targeting'
add_index :raaf_evaluation_policies, :metadata, using: :gin
```

**Rationale:**
- `agent_name` with wildcard support enables flexible targeting
- `sampling_mode` allows percentage-based or count-based sampling
- `sample_counter` enables stateful "1 in N" sampling
- `evaluators` JSONB array allows flexible evaluator configuration
- `max_daily_evaluations` provides cost control
- `priority` enables important policies to be processed first

## Table: raaf_evaluation_queue

Tracks pending and in-progress evaluations. Provides visibility into queue status.

```ruby
create_table :raaf_evaluation_queue do |t|
  # References
  t.string :span_id, null: false
  t.string :trace_id, null: false
  t.references :evaluation_policy, foreign_key: { to_table: :raaf_evaluation_policies }

  # Status tracking
  t.string :status, null: false, default: 'pending'
  # 'pending', 'running', 'completed', 'failed', 'cancelled'

  # Queue management
  t.integer :priority, default: 50
  t.integer :attempts, default: 0
  t.integer :max_attempts, default: 3

  # Timing
  t.datetime :scheduled_at
  t.datetime :started_at
  t.datetime :completed_at
  t.datetime :next_retry_at

  # Error tracking
  t.text :error_message
  t.text :error_class

  # Metadata
  t.jsonb :metadata, default: {}
  t.timestamps
end

# Indexes
add_index :raaf_evaluation_queue, :span_id
add_index :raaf_evaluation_queue, :status
add_index :raaf_evaluation_queue, [:status, :priority, :scheduled_at],
          name: 'idx_eval_queue_processing'
add_index :raaf_evaluation_queue, [:status, :created_at],
          name: 'idx_eval_queue_status_time'
add_index :raaf_evaluation_queue, :evaluation_policy_id
```

**Rationale:**
- Separate from Solid Queue's internal tables for visibility/reporting
- `attempts` and `max_attempts` track retry behavior
- `next_retry_at` enables exponential backoff
- Status indexes optimized for queue monitoring UI

## Table: raaf_evaluation_results

Stores all automated evaluation results with full metrics and provenance.

```ruby
create_table :raaf_evaluation_results do |t|
  # Span reference
  t.string :span_id, null: false
  t.string :trace_id, null: false

  # Policy reference
  t.references :evaluation_policy, foreign_key: { to_table: :raaf_evaluation_policies }, null: true
  t.references :queue_item, foreign_key: { to_table: :raaf_evaluation_queue }, null: true

  # Provenance
  t.string :evaluation_type, null: false, default: 'automated'  # 'automated' only for now
  t.string :evaluator_name, null: false         # e.g., 'token_limit', 'quality_check'
  t.string :evaluator_type, null: false         # 'rule_based', 'statistical', 'llm_judge'
  t.string :evaluator_version                   # For tracking evaluator changes

  # Context (denormalized for filtering/aggregation)
  t.string :agent_name, null: false
  t.string :agent_version
  t.string :model
  t.string :provider
  t.string :environment

  # Results
  t.string :status, null: false                 # 'passed', 'failed', 'warning', 'error'
  t.decimal :score, precision: 5, scale: 4     # 0.0000 to 1.0000
  t.jsonb :scores, default: {}                  # Multiple scores: { "quality": 0.85, "safety": 0.95 }
  t.jsonb :metrics, default: {}                 # { "latency_ms": 1200, "tokens": 500, "cost": 0.003 }
  t.text :reasoning                             # LLM judge reasoning or rule explanation
  t.jsonb :details, default: {}                 # Full evaluation result data

  # Timing
  t.integer :evaluation_duration_ms
  t.datetime :evaluation_started_at
  t.datetime :evaluation_completed_at

  # Metadata
  t.jsonb :metadata, default: {}
  t.timestamps
end

# Indexes for querying
add_index :raaf_evaluation_results, :span_id
add_index :raaf_evaluation_results, :trace_id
add_index :raaf_evaluation_results, :status
add_index :raaf_evaluation_results, :evaluator_name
add_index :raaf_evaluation_results, :created_at

# Indexes for filtering
add_index :raaf_evaluation_results, [:agent_name, :created_at],
          name: 'idx_eval_results_agent_time'
add_index :raaf_evaluation_results, [:agent_name, :environment, :created_at],
          name: 'idx_eval_results_agent_env_time'
add_index :raaf_evaluation_results, [:agent_name, :status, :created_at],
          name: 'idx_eval_results_agent_status_time'
add_index :raaf_evaluation_results, [:evaluator_name, :status, :created_at],
          name: 'idx_eval_results_evaluator_status_time'

# Indexes for aggregation
add_index :raaf_evaluation_results, [:agent_name, :model, :created_at],
          name: 'idx_eval_results_agent_model_time'

# JSONB indexes
add_index :raaf_evaluation_results, :scores, using: :gin
add_index :raaf_evaluation_results, :metadata, using: :gin
```

**Rationale:**
- Denormalized `agent_name`, `model`, `environment` for fast filtering without joins
- Separate `score` (overall) and `scores` (per-criterion) fields
- `evaluator_version` tracks which version of evaluator produced results
- Multiple time-based composite indexes for common query patterns
- GIN indexes on JSONB for flexible metadata queries

## Table: raaf_evaluation_metrics

Pre-aggregated metrics for fast dashboard queries.

```ruby
create_table :raaf_evaluation_metrics do |t|
  # Aggregation dimensions
  t.string :agent_name, null: false
  t.string :environment
  t.string :model
  t.string :evaluator_name
  t.string :period_type, null: false            # 'hourly', 'daily', 'weekly'
  t.datetime :period_start, null: false

  # Counts
  t.integer :total_evaluations, default: 0
  t.integer :passed_count, default: 0
  t.integer :failed_count, default: 0
  t.integer :warning_count, default: 0
  t.integer :error_count, default: 0

  # Score statistics
  t.decimal :avg_score, precision: 5, scale: 4
  t.decimal :min_score, precision: 5, scale: 4
  t.decimal :max_score, precision: 5, scale: 4
  t.decimal :stddev_score, precision: 5, scale: 4
  t.decimal :p50_score, precision: 5, scale: 4  # Median
  t.decimal :p90_score, precision: 5, scale: 4
  t.decimal :p95_score, precision: 5, scale: 4

  # Score distribution (for histograms)
  t.jsonb :score_distribution, default: {}
  # Example: { "0.0-0.1": 5, "0.1-0.2": 10, "0.2-0.3": 15, ... }

  # Performance metrics
  t.decimal :avg_evaluation_duration_ms, precision: 10, scale: 2
  t.decimal :total_evaluation_cost, precision: 10, scale: 4

  # Additional aggregates
  t.jsonb :additional_metrics, default: {}

  t.timestamps
end

# Unique constraint for upsert
add_index :raaf_evaluation_metrics,
          [:agent_name, :environment, :model, :evaluator_name, :period_type, :period_start],
          unique: true,
          name: 'idx_eval_metrics_unique'

# Query indexes
add_index :raaf_evaluation_metrics, [:agent_name, :period_type, :period_start],
          name: 'idx_eval_metrics_agent_period'
add_index :raaf_evaluation_metrics, [:period_type, :period_start],
          name: 'idx_eval_metrics_period'
add_index :raaf_evaluation_metrics, :period_start
```

**Rationale:**
- Pre-computed aggregates eliminate expensive real-time calculations
- Multiple dimension columns allow drilling down by agent/environment/model/evaluator
- `score_distribution` JSONB enables histogram rendering without additional queries
- Unique composite index enables efficient upsert operations
- `period_type` supports hourly (detailed), daily (default), weekly (long-term) views

## Migrations

### Migration 1: Create Evaluation Policies Table

```ruby
class CreateRaafEvaluationPolicies < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_evaluation_policies do |t|
      t.string :name, null: false
      t.text :description
      t.string :agent_name, null: false
      t.string :environment, default: 'all'
      t.string :model_pattern, default: 'all'
      t.string :version_pattern, default: 'all'
      t.string :sampling_mode, default: 'percentage'
      t.integer :sample_rate, default: 100
      t.integer :sample_every_n
      t.integer :sample_counter, default: 0
      t.integer :max_daily_evaluations
      t.integer :today_evaluation_count, default: 0
      t.date :count_reset_date
      t.integer :priority, default: 50
      t.string :queue_name, default: 'raaf_evaluations'
      t.integer :max_concurrent_evaluations, default: 5
      t.integer :max_retries, default: 3
      t.integer :retention_days, default: 90
      t.integer :retention_count
      t.jsonb :evaluators, default: []
      t.jsonb :metadata, default: {}
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :raaf_evaluation_policies, :name, unique: true
    add_index :raaf_evaluation_policies, :agent_name
    add_index :raaf_evaluation_policies, :active
    add_index :raaf_evaluation_policies, [:agent_name, :environment, :active],
              name: 'idx_eval_policies_targeting'
    add_index :raaf_evaluation_policies, :metadata, using: :gin
  end
end
```

### Migration 2: Create Evaluation Queue Table

```ruby
class CreateRaafEvaluationQueue < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_evaluation_queue do |t|
      t.string :span_id, null: false
      t.string :trace_id, null: false
      t.references :evaluation_policy, foreign_key: { to_table: :raaf_evaluation_policies }
      t.string :status, null: false, default: 'pending'
      t.integer :priority, default: 50
      t.integer :attempts, default: 0
      t.integer :max_attempts, default: 3
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :next_retry_at
      t.text :error_message
      t.text :error_class
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :raaf_evaluation_queue, :span_id
    add_index :raaf_evaluation_queue, :status
    add_index :raaf_evaluation_queue, [:status, :priority, :scheduled_at],
              name: 'idx_eval_queue_processing'
    add_index :raaf_evaluation_queue, [:status, :created_at],
              name: 'idx_eval_queue_status_time'
  end
end
```

### Migration 3: Create Evaluation Results Table

```ruby
class CreateRaafEvaluationResults < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_evaluation_results do |t|
      t.string :span_id, null: false
      t.string :trace_id, null: false
      t.references :evaluation_policy, foreign_key: { to_table: :raaf_evaluation_policies }
      t.references :queue_item, foreign_key: { to_table: :raaf_evaluation_queue }
      t.string :evaluation_type, null: false, default: 'automated'
      t.string :evaluator_name, null: false
      t.string :evaluator_type, null: false
      t.string :evaluator_version
      t.string :agent_name, null: false
      t.string :agent_version
      t.string :model
      t.string :provider
      t.string :environment
      t.string :status, null: false
      t.decimal :score, precision: 5, scale: 4
      t.jsonb :scores, default: {}
      t.jsonb :metrics, default: {}
      t.text :reasoning
      t.jsonb :details, default: {}
      t.integer :evaluation_duration_ms
      t.datetime :evaluation_started_at
      t.datetime :evaluation_completed_at
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :raaf_evaluation_results, :span_id
    add_index :raaf_evaluation_results, :trace_id
    add_index :raaf_evaluation_results, :status
    add_index :raaf_evaluation_results, :evaluator_name
    add_index :raaf_evaluation_results, :created_at
    add_index :raaf_evaluation_results, [:agent_name, :created_at],
              name: 'idx_eval_results_agent_time'
    add_index :raaf_evaluation_results, [:agent_name, :environment, :created_at],
              name: 'idx_eval_results_agent_env_time'
    add_index :raaf_evaluation_results, [:agent_name, :status, :created_at],
              name: 'idx_eval_results_agent_status_time'
    add_index :raaf_evaluation_results, [:evaluator_name, :status, :created_at],
              name: 'idx_eval_results_evaluator_status_time'
    add_index :raaf_evaluation_results, [:agent_name, :model, :created_at],
              name: 'idx_eval_results_agent_model_time'
    add_index :raaf_evaluation_results, :scores, using: :gin
    add_index :raaf_evaluation_results, :metadata, using: :gin
  end
end
```

### Migration 4: Create Evaluation Metrics Table

```ruby
class CreateRaafEvaluationMetrics < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_evaluation_metrics do |t|
      t.string :agent_name, null: false
      t.string :environment
      t.string :model
      t.string :evaluator_name
      t.string :period_type, null: false
      t.datetime :period_start, null: false
      t.integer :total_evaluations, default: 0
      t.integer :passed_count, default: 0
      t.integer :failed_count, default: 0
      t.integer :warning_count, default: 0
      t.integer :error_count, default: 0
      t.decimal :avg_score, precision: 5, scale: 4
      t.decimal :min_score, precision: 5, scale: 4
      t.decimal :max_score, precision: 5, scale: 4
      t.decimal :stddev_score, precision: 5, scale: 4
      t.decimal :p50_score, precision: 5, scale: 4
      t.decimal :p90_score, precision: 5, scale: 4
      t.decimal :p95_score, precision: 5, scale: 4
      t.jsonb :score_distribution, default: {}
      t.decimal :avg_evaluation_duration_ms, precision: 10, scale: 2
      t.decimal :total_evaluation_cost, precision: 10, scale: 4
      t.jsonb :additional_metrics, default: {}
      t.timestamps
    end

    add_index :raaf_evaluation_metrics,
              [:agent_name, :environment, :model, :evaluator_name, :period_type, :period_start],
              unique: true,
              name: 'idx_eval_metrics_unique'
    add_index :raaf_evaluation_metrics, [:agent_name, :period_type, :period_start],
              name: 'idx_eval_metrics_agent_period'
    add_index :raaf_evaluation_metrics, [:period_type, :period_start],
              name: 'idx_eval_metrics_period'
    add_index :raaf_evaluation_metrics, :period_start
  end
end
```

## Data Integrity Constraints

### Foreign Key Relationships

- `raaf_evaluation_queue.evaluation_policy_id` → `raaf_evaluation_policies.id`
- `raaf_evaluation_results.evaluation_policy_id` → `raaf_evaluation_policies.id` (optional)
- `raaf_evaluation_results.queue_item_id` → `raaf_evaluation_queue.id` (optional)

### Validation Rules (Model Level)

**EvaluationPolicy:**
- `name` must be unique
- `sampling_mode` must be in: 'percentage', 'every_n', 'all'
- `sample_rate` must be 1-100 when sampling_mode is 'percentage'
- `sample_every_n` must be > 0 when sampling_mode is 'every_n'
- `priority` must be 0-100
- `evaluators` must be valid JSON array with valid evaluator configs

**EvaluationQueue:**
- `status` must be in: 'pending', 'running', 'completed', 'failed', 'cancelled'

**EvaluationResult:**
- `evaluation_type` must be 'automated'
- `evaluator_type` must be in: 'rule_based', 'statistical', 'llm_judge'
- `status` must be in: 'passed', 'failed', 'warning', 'error'
- `score` must be 0.0 to 1.0 (if present)

**EvaluationMetric:**
- `period_type` must be in: 'hourly', 'daily', 'weekly'
- Unique constraint on dimension columns + period

## Storage Estimates

Assuming typical usage:
- 10,000 spans/day
- 10% sampling rate = 1,000 evaluations/day
- 3 evaluators per policy = 3,000 result rows/day
- 90-day retention

**Daily Storage:**
- `raaf_evaluation_results`: 3,000 rows × ~2 KB = 6 MB/day
- `raaf_evaluation_queue`: 1,000 rows × ~0.5 KB = 0.5 MB/day (mostly completed/cleaned)
- `raaf_evaluation_metrics`: ~100 rows × ~0.5 KB = 0.05 MB/day

**90-Day Total:**
- Results: ~540 MB
- Metrics: ~4.5 MB
- Queue: ~10 MB (with cleanup)
- **Total: ~555 MB**

With PostgreSQL JSONB compression, actual storage is typically 30-50% less.

## Retention and Cleanup

### Automated Cleanup Jobs

```ruby
# Clean up old results based on policy retention
class CleanupEvaluationResultsJob < ApplicationJob
  def perform
    EvaluationPolicy.find_each do |policy|
      cutoff = policy.retention_days.days.ago

      EvaluationResult
        .where(evaluation_policy: policy)
        .where('created_at < ?', cutoff)
        .in_batches
        .delete_all
    end
  end
end

# Clean up completed/failed queue items older than 7 days
class CleanupEvaluationQueueJob < ApplicationJob
  def perform
    EvaluationQueue
      .where(status: ['completed', 'failed', 'cancelled'])
      .where('completed_at < ?', 7.days.ago)
      .delete_all
  end
end

# Roll up hourly metrics to daily after 7 days
class RollupEvaluationMetricsJob < ApplicationJob
  def perform
    # Delete hourly metrics older than 7 days (keep daily/weekly)
    EvaluationMetric
      .where(period_type: 'hourly')
      .where('period_start < ?', 7.days.ago)
      .delete_all
  end
end
```

### Scheduled Jobs (Solid Queue)

```ruby
# config/initializers/solid_queue_schedule.rb
SolidQueue.schedule do
  # Reset daily evaluation counters at midnight
  job :reset_daily_counters, cron: '0 0 * * *'

  # Aggregate metrics every hour
  job :aggregate_hourly_metrics, cron: '5 * * * *'

  # Aggregate daily metrics at 1 AM
  job :aggregate_daily_metrics, cron: '0 1 * * *'

  # Cleanup old data at 3 AM
  job :cleanup_evaluation_results, cron: '0 3 * * *'
  job :cleanup_evaluation_queue, cron: '15 3 * * *'
  job :rollup_evaluation_metrics, cron: '30 3 * * *'
end
```
