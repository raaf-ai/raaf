# Database Schema

This is the database schema implementation for the spec detailed in @.agent-os/specs/2025-11-06-raaf-eval-foundation/spec.md

> Created: 2025-11-06
> Version: 1.0.0

## Schema Overview

The evaluation system requires 4 core tables:
1. **evaluation_runs** - Top-level evaluation execution record
2. **evaluation_spans** - Serialized span snapshots
3. **evaluation_configurations** - Configuration variants for evaluation
4. **evaluation_results** - Results and metrics for each evaluation

## Table: evaluation_runs

Represents a single evaluation execution that may include multiple configuration variants.

```ruby
create_table :evaluation_runs do |t|
  t.string :name, null: false, index: true
  t.text :description
  t.string :status, null: false, default: "pending"
  # Status enum: pending, running, completed, failed, cancelled

  t.string :baseline_span_id, null: false
  t.string :initiated_by # User or system identifier

  t.jsonb :metadata, default: {}
  # Metadata includes: tags, annotations, related_issue_numbers, etc.

  t.datetime :started_at
  t.datetime :completed_at
  t.timestamps
end

add_index :evaluation_runs, :status
add_index :evaluation_runs, :created_at
add_index :evaluation_runs, :baseline_span_id
add_index :evaluation_runs, :metadata, using: :gin
```

**Rationale:**
- `baseline_span_id` links to the original span being evaluated
- `status` tracks evaluation lifecycle for monitoring
- `metadata` JSONB allows flexible tagging and annotation
- GIN index on metadata enables fast tag-based queries

## Table: evaluation_spans

Stores complete serialized span data for baseline and evaluation runs.

```ruby
create_table :evaluation_spans do |t|
  t.string :span_id, null: false, index: { unique: true }
  t.string :trace_id, null: false, index: true
  t.string :parent_span_id, index: true

  t.string :span_type, null: false
  # Type enum: agent, response, tool, handoff

  t.jsonb :span_data, null: false
  # Complete span serialization including:
  # - agent_name, model, instructions, parameters
  # - input_messages[], output_messages[]
  # - tool_calls[], handoffs[]
  # - context_variables{}
  # - metadata{} (timestamps, tokens, latency, cost)
  # - provider_details{}
  # - error_info (if any)

  t.string :source, null: false
  # Source enum: production_trace, evaluation_run, manual_upload

  t.references :evaluation_run, foreign_key: true, index: true
  # NULL for baseline/production spans, set for evaluation-generated spans

  t.timestamps
end

add_index :evaluation_spans, :span_type
add_index :evaluation_spans, :span_data, using: :gin
add_index :evaluation_spans, [:trace_id, :parent_span_id]
```

**Rationale:**
- `span_data` JSONB holds complete span information for reproduction
- GIN index enables querying within span data (e.g., find spans with specific model)
- `source` distinguishes production traces from evaluation-generated spans
- Foreign key to evaluation_run links evaluation results back to runs

## Table: evaluation_configurations

Defines configuration variants to test against baseline.

```ruby
create_table :evaluation_configurations do |t|
  t.references :evaluation_run, null: false, foreign_key: true, index: true

  t.string :name, null: false
  # e.g., "GPT-4 High Temp", "Claude with Modified Prompt"

  t.string :configuration_type, null: false
  # Type enum: model_change, parameter_change, prompt_change, provider_change, combined

  t.jsonb :changes, null: false
  # Changes specification:
  # {
  #   model: "claude-3-5-sonnet-20241022",
  #   provider: "anthropic",
  #   parameters: { temperature: 0.9, max_tokens: 2000 },
  #   instructions: "new prompt text",
  #   tools: ["tool1", "tool2"]
  # }

  t.integer :execution_order, default: 0
  # Order to execute configurations (for sequential dependencies)

  t.jsonb :metadata, default: {}
  # Additional context: hypothesis, expected_outcome, etc.

  t.timestamps
end

add_index :evaluation_configurations, [:evaluation_run_id, :execution_order]
add_index :evaluation_configurations, :configuration_type
add_index :evaluation_configurations, :changes, using: :gin
```

**Rationale:**
- `changes` JSONB provides flexibility for any configuration modification
- `execution_order` supports dependent evaluations (e.g., prompt A/B test)
- `configuration_type` enables filtering by change category

## Table: evaluation_results

Stores evaluation execution results with comprehensive metrics.

```ruby
create_table :evaluation_results do |t|
  t.references :evaluation_run, null: false, foreign_key: true, index: true
  t.references :evaluation_configuration, null: false, foreign_key: true, index: true
  t.string :result_span_id, null: false, index: true
  # Links to evaluation_spans for the new execution result

  t.string :status, null: false, default: "pending"
  # Status enum: pending, running, completed, failed

  # Quantitative Metrics (JSONB for flexibility)
  t.jsonb :token_metrics, default: {}
  # { total_tokens, input_tokens, output_tokens, reasoning_tokens, cost }

  t.jsonb :latency_metrics, default: {}
  # { total_time_ms, time_to_first_token_ms, time_per_token_ms, api_latency_ms }

  t.jsonb :accuracy_metrics, default: {}
  # { exact_match, fuzzy_match, bleu_score, f1_score }

  t.jsonb :structural_metrics, default: {}
  # { output_length, format_valid, schema_valid }

  # Qualitative AI Comparator Metrics
  t.jsonb :ai_comparison, default: {}
  # {
  #   semantic_similarity_score: 0.85,
  #   coherence_score: 0.90,
  #   hallucination_detected: false,
  #   bias_detected: { gender: false, race: false, region: false },
  #   tone_consistency: 0.88,
  #   factuality_score: 0.92,
  #   comparison_reasoning: "explanation text"
  # }

  t.string :ai_comparison_status
  # Status enum: pending, completed, failed, skipped

  # Statistical Analysis
  t.jsonb :statistical_analysis, default: {}
  # {
  #   confidence_intervals: { token_diff: [min, max] },
  #   significance_test: { p_value, significant },
  #   variance: { token_usage: value },
  #   effect_size: { cohens_d: value }
  # }

  # Custom Metrics
  t.jsonb :custom_metrics, default: {}
  # Domain-specific metrics defined by user

  # Comparison to Baseline
  t.jsonb :baseline_comparison, default: {}
  # {
  #   token_delta: { absolute: 100, percentage: 10.5 },
  #   latency_delta: { absolute_ms: 50, percentage: 5.2 },
  #   quality_change: "improved|degraded|unchanged",
  #   regression_detected: false
  # }

  # Error Information
  t.text :error_message
  t.text :error_backtrace

  t.datetime :started_at
  t.datetime :completed_at
  t.timestamps
end

add_index :evaluation_results, :status
add_index :evaluation_results, :result_span_id
add_index :evaluation_results, [:evaluation_run_id, :status]
add_index :evaluation_results, :token_metrics, using: :gin
add_index :evaluation_results, :ai_comparison, using: :gin
add_index :evaluation_results, :baseline_comparison, using: :gin
```

**Rationale:**
- Separate JSONB columns for metric categories enable targeted queries
- `ai_comparison_status` tracks async AI comparator execution
- `statistical_analysis` supports rigorous metric reporting
- `baseline_comparison` enables quick regression detection
- GIN indexes on metric columns support complex filtering

## Migrations

### Migration 1: Create evaluation tables

```ruby
class CreateEvaluationTables < ActiveRecord::Migration[7.0]
  def change
    # Create evaluation_runs
    create_table :evaluation_runs do |t|
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "pending"
      t.string :baseline_span_id, null: false
      t.string :initiated_by
      t.jsonb :metadata, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :evaluation_runs, :name
    add_index :evaluation_runs, :status
    add_index :evaluation_runs, :created_at
    add_index :evaluation_runs, :baseline_span_id
    add_index :evaluation_runs, :metadata, using: :gin

    # Create evaluation_spans
    create_table :evaluation_spans do |t|
      t.string :span_id, null: false
      t.string :trace_id, null: false
      t.string :parent_span_id
      t.string :span_type, null: false
      t.jsonb :span_data, null: false
      t.string :source, null: false
      t.references :evaluation_run, foreign_key: true
      t.timestamps
    end

    add_index :evaluation_spans, :span_id, unique: true
    add_index :evaluation_spans, :trace_id
    add_index :evaluation_spans, :parent_span_id
    add_index :evaluation_spans, :span_type
    add_index :evaluation_spans, :span_data, using: :gin
    add_index :evaluation_spans, [:trace_id, :parent_span_id]

    # Create evaluation_configurations
    create_table :evaluation_configurations do |t|
      t.references :evaluation_run, null: false, foreign_key: true
      t.string :name, null: false
      t.string :configuration_type, null: false
      t.jsonb :changes, null: false
      t.integer :execution_order, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :evaluation_configurations, [:evaluation_run_id, :execution_order]
    add_index :evaluation_configurations, :configuration_type
    add_index :evaluation_configurations, :changes, using: :gin

    # Create evaluation_results
    create_table :evaluation_results do |t|
      t.references :evaluation_run, null: false, foreign_key: true
      t.references :evaluation_configuration, null: false, foreign_key: true
      t.string :result_span_id, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :token_metrics, default: {}
      t.jsonb :latency_metrics, default: {}
      t.jsonb :accuracy_metrics, default: {}
      t.jsonb :structural_metrics, default: {}
      t.jsonb :ai_comparison, default: {}
      t.string :ai_comparison_status
      t.jsonb :statistical_analysis, default: {}
      t.jsonb :custom_metrics, default: {}
      t.jsonb :baseline_comparison, default: {}
      t.text :error_message
      t.text :error_backtrace
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :evaluation_results, :status
    add_index :evaluation_results, :result_span_id
    add_index :evaluation_results, [:evaluation_run_id, :status]
    add_index :evaluation_results, :token_metrics, using: :gin
    add_index :evaluation_results, :ai_comparison, using: :gin
    add_index :evaluation_results, :baseline_comparison, using: :gin
  end
end
```

## Data Integrity Constraints

### Foreign Key Relationships
- `evaluation_spans.evaluation_run_id` → `evaluation_runs.id` (optional, NULL for baseline spans)
- `evaluation_configurations.evaluation_run_id` → `evaluation_runs.id` (required)
- `evaluation_results.evaluation_run_id` → `evaluation_runs.id` (required)
- `evaluation_results.evaluation_configuration_id` → `evaluation_configurations.id` (required)

### Validation Rules
- `evaluation_runs.status` must be in: pending, running, completed, failed, cancelled
- `evaluation_spans.span_type` must be in: agent, response, tool, handoff
- `evaluation_spans.source` must be in: production_trace, evaluation_run, manual_upload
- `evaluation_configurations.configuration_type` must be in: model_change, parameter_change, prompt_change, provider_change, combined
- `evaluation_results.status` must be in: pending, running, completed, failed
- `evaluation_results.ai_comparison_status` must be in: pending, completed, failed, skipped

### Indexes for Performance

**Query Pattern: Find recent evaluation runs**
- Index: `evaluation_runs(created_at DESC)`
- Usage: Dashboard showing latest evaluations

**Query Pattern: Find all results for a run**
- Index: `evaluation_results(evaluation_run_id, status)`
- Usage: Results page showing run details

**Query Pattern: Find evaluations using specific model**
- Index: `evaluation_spans(span_data) USING gin`
- Usage: Filter spans by model/provider/configuration

**Query Pattern: Find regressions**
- Index: `evaluation_results(baseline_comparison) USING gin`
- Usage: Alert system checking for degraded performance

## Storage Estimates

Assuming typical span sizes:
- Small span (simple agent): ~5 KB serialized
- Medium span (agent with tools): ~20 KB serialized
- Large span (multi-turn with handoffs): ~100 KB serialized

For 1000 evaluation runs with 5 configurations each:
- evaluation_runs: 1000 rows × ~1 KB = 1 MB
- evaluation_spans: 5000 spans × 20 KB avg = 100 MB
- evaluation_configurations: 5000 rows × ~2 KB = 10 MB
- evaluation_results: 5000 rows × ~10 KB = 50 MB
- **Total: ~161 MB for 1000 runs**

JSONB storage is efficient with PostgreSQL compression, and GIN indexes add ~30% overhead.

## Backup and Retention Strategy

- **Hot Data**: Last 30 days, full indexes, fast access
- **Warm Data**: 30-90 days, reduced indexes, acceptable performance
- **Cold Data**: 90+ days, archived to separate table, slow queries acceptable
- **Retention**: Keep indefinitely unless explicitly deleted (evaluations are valuable historical data)
