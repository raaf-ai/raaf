# Continuous Evaluation Migration Guide

> **Version:** 2.0.0
> **Last Updated:** 2025-11-25
> **Breaking Change:** Yes

This guide explains how to migrate from the deprecated DSL-based history configuration to the new database-driven continuous evaluation system.

## Overview

### Why We're Moving to Database Configuration

The original DSL-based `history do...end` blocks had several limitations:

1. **Code Deployment Required**: Changing evaluation settings required code changes and deployments
2. **No Runtime Flexibility**: Could not adjust sampling rates or enable/disable evaluators without redeploying
3. **Limited Visibility**: No dashboard to see what evaluations were configured
4. **No Centralized Management**: Each evaluator had its own configuration scattered across files

The new database-driven system provides:

- **Runtime Configuration**: Change evaluation policies without code deployments
- **Centralized Dashboard**: Manage all evaluation policies from a single UI
- **Sampling Control**: Configure sampling rates, daily limits, and priorities
- **Cost Management**: Control LLM evaluation costs with fine-grained limits
- **Analytics**: View pass rates, trends, and comparisons over time

## Breaking Changes

### Removed Features

The following DSL features have been **removed** (not deprecated):

```ruby
# REMOVED - These will raise RAAF::Eval::DeprecatedDSLError

# In RAAF::Eval.define blocks:
history do
  auto_save true
  retention_days 30
  retention_count 100
  tags environment: 'production'
end

# In EvaluatorDefinition modules:
history baseline: true, last_n: 10, auto_save: true

# Direct method calls:
evaluator_config.configure_history(auto_save: true)
```

### Deprecated Classes

The following classes emit deprecation warnings and will be removed in version 3.0:

- `RAAF::Eval::Storage::HistoricalStorage` - Use `ContinuousEvaluationResult` instead
- `RAAF::Eval::Storage::RetentionPolicy` - Retention is now managed via `EvaluationPolicy`
- `RAAF::Eval::Storage::QueryBuilder` - Use ActiveRecord queries on new models

## Migration Steps

### Step 1: Identify Existing History Configuration

Run the check task to find deprecated usage in your codebase:

```bash
rails raaf:continuous_evaluation:check_deprecated
```

This scans your evaluator files for:
- `history do...end` blocks
- `history` method calls with options
- `HistoryDSL` class references
- `configure_history` method calls

### Step 2: Remove DSL History Configuration

Remove all `history` blocks from your evaluator definitions:

```ruby
# BEFORE (will raise error):
class MyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'output', as: :output

  evaluate_field :output do
    evaluate_with :semantic_similarity, threshold: 0.85
  end

  # REMOVE THIS BLOCK
  history baseline: true, last_n: 10, auto_save: true
end

# AFTER (correct):
class MyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'output', as: :output

  evaluate_field :output do
    evaluate_with :semantic_similarity, threshold: 0.85
  end

  # History configuration moved to database EvaluationPolicy
end
```

Similarly for `RAAF::Eval.define` blocks:

```ruby
# BEFORE (will raise error):
evaluator = RAAF::Eval.define do
  select 'output', as: :output

  evaluate_field :output do
    evaluate_with :semantic_similarity, threshold: 0.85
  end

  # REMOVE THIS BLOCK
  history do
    auto_save true
    retention_days 30
    tags environment: 'production'
  end
end

# AFTER (correct):
evaluator = RAAF::Eval.define do
  select 'output', as: :output

  evaluate_field :output do
    evaluate_with :semantic_similarity, threshold: 0.85
  end

  # No history block - use EvaluationPolicy instead
end
```

### Step 3: Run Database Migrations

Ensure you have the continuous evaluation tables:

```bash
rails db:migrate
```

This creates the following tables:
- `raaf_evaluation_policies` - Evaluation configuration
- `raaf_evaluation_queue` - Pending evaluations queue
- `raaf_continuous_evaluation_results` - Evaluation results storage
- `raaf_evaluation_metrics` - Pre-aggregated metrics for dashboards

### Step 4: Create Evaluation Policies

#### Option A: Using the RAAF Dashboard UI

1. Navigate to the RAAF Dashboard
2. Click "Evaluations" in the navigation
3. Click "Policies" > "New Policy"
4. Configure:
   - **Name**: Unique policy identifier
   - **Evaluators**: Select which evaluators to run
   - **Agent Pattern**: Which agents to evaluate (e.g., `DmuDiscovery`)
   - **Environment**: Target environment (e.g., `production`)
   - **Sample Rate**: Percentage of spans to evaluate (0-100)
   - **Daily Limit**: Maximum evaluations per day (cost control)
   - **Retention Days**: How long to keep results

#### Option B: Using Rails Console or Code

```ruby
# Create a policy programmatically
RAAF::Eval::Models::Continuous::EvaluationPolicy.create!(
  name: "production_quality_check",
  description: "Quality evaluation for production agents",
  enabled: true,

  # Evaluators to run
  evaluators: [
    { name: "semantic_similarity", config: { threshold: 0.85 } },
    { name: "token_efficiency", config: { max_tokens: 4000 } }
  ],

  # Targeting
  agent_pattern: "DmuDiscovery",
  environment_pattern: "production",
  model_pattern: nil, # All models

  # Sampling
  sample_rate: 10.0,        # Evaluate 10% of spans
  sample_every_n: nil,      # Alternative: evaluate every Nth span
  max_daily_evaluations: 1000, # Cost control

  # Storage
  retention_days: 30,       # Keep results for 30 days

  # Processing
  priority: 10              # Higher = processed first
)
```

#### Option C: Using the Migration Rake Task

```bash
rails raaf:continuous_evaluation:migrate
```

This automatically creates disabled policies for all registered evaluators. You can then enable and configure them via the dashboard.

### Step 5: Verify Migration

1. **List all policies**:
   ```bash
   rails raaf:continuous_evaluation:list
   ```

2. **Check for deprecated usage**:
   ```bash
   rails raaf:continuous_evaluation:check_deprecated
   ```

3. **Test evaluation**:
   - Create a test span
   - Verify the policy matches and queues the evaluation
   - Check results in the dashboard

## Configuration Mapping

| Old DSL Setting | New Policy Setting |
|-----------------|-------------------|
| `auto_save true` | `enabled: true` + `sample_rate: 100.0` |
| `retention_days 30` | `retention_days: 30` |
| `retention_count 100` | Not directly supported - use `max_daily_evaluations` |
| `tags { env: 'prod' }` | Policy stored with metadata in `details` column |
| `baseline true` | Use dashboard comparison features |
| `last_n 10` | Query with `ContinuousEvaluationResult.order(created_at: :desc).limit(10)` |

## Querying Results

### Old Pattern (Deprecated)

```ruby
# DEPRECATED - emits warning
runs = RAAF::Eval::Storage::HistoricalStorage.query(
  evaluator_name: "quality_check",
  tags: { environment: "production" }
)
```

### New Pattern

```ruby
# Using the new ContinuousEvaluationResult model
results = RAAF::Eval::Models::Continuous::ContinuousEvaluationResult
  .where(evaluator_name: "quality_check")
  .where(environment: "production")
  .order(created_at: :desc)
  .limit(100)

# Get pass rate
pass_rate = results.passed.count.to_f / results.count * 100

# Get average score
avg_score = results.average(:score)

# Using pre-aggregated metrics for dashboards
metrics = RAAF::Eval::Models::Continuous::EvaluationMetric
  .where(agent_name: "DmuDiscovery")
  .where(period_type: "daily")
  .where(period_start: 7.days.ago..)
  .order(:period_start)
```

## Common Migration Scenarios

### Scenario 1: Simple Auto-Save Evaluator

**Before:**
```ruby
class QualityEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'output', as: :output
  evaluate_field :output do
    evaluate_with :coherence, min_score: 0.7
  end

  history auto_save: true
end
```

**After:**
```ruby
# In evaluator file (remove history):
class QualityEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'output', as: :output
  evaluate_field :output do
    evaluate_with :coherence, min_score: 0.7
  end
end

# In database (create policy):
RAAF::Eval::Models::Continuous::EvaluationPolicy.create!(
  name: "quality_evaluator_policy",
  enabled: true,
  evaluators: [{ name: "quality_evaluator" }],
  sample_rate: 100.0  # Evaluate all spans (equivalent to auto_save)
)
```

### Scenario 2: Retention-Limited Evaluator

**Before:**
```ruby
evaluator = RAAF::Eval.define do
  select 'usage.total_tokens', as: :tokens
  evaluate_field :tokens do
    evaluate_with :token_limit, max_tokens: 4000
  end

  history do
    auto_save true
    retention_days 14
    retention_count 500
  end
end
```

**After:**
```ruby
# Evaluator (no history block):
evaluator = RAAF::Eval.define do
  select 'usage.total_tokens', as: :tokens
  evaluate_field :tokens do
    evaluate_with :token_limit, max_tokens: 4000
  end
end

# Policy in database:
RAAF::Eval::Models::Continuous::EvaluationPolicy.create!(
  name: "token_limit_policy",
  enabled: true,
  evaluators: [{
    name: "token_limit",
    config: { max_tokens: 4000 }
  }],
  retention_days: 14,
  max_daily_evaluations: 500  # Closest equivalent to retention_count
)
```

### Scenario 3: Environment-Specific Configuration

**Before:** Required different code paths or environment checks in DSL.

**After:**
```ruby
# Create separate policies for each environment
["development", "staging", "production"].each do |env|
  RAAF::Eval::Models::Continuous::EvaluationPolicy.create!(
    name: "quality_check_#{env}",
    enabled: env == "production",  # Only enable production
    environment_pattern: env,
    sample_rate: env == "production" ? 10.0 : 100.0,
    evaluators: [{ name: "quality_check" }]
  )
end
```

## Troubleshooting

### Error: `RAAF::Eval::DeprecatedDSLError`

**Cause:** Your code contains `history do...end` blocks or `history` method calls.

**Solution:** Remove all history DSL usage and create database policies instead.

### Warning: `[DEPRECATION WARNING] RAAF::Eval::Storage::HistoricalStorage`

**Cause:** Code is using the deprecated `HistoricalStorage` class.

**Solution:** Update code to use `ContinuousEvaluationResult` model:

```ruby
# Old
RAAF::Eval::Storage::HistoricalStorage.save(...)
RAAF::Eval::Storage::HistoricalStorage.query(...)

# New
RAAF::Eval::Models::Continuous::ContinuousEvaluationResult.create!(...)
RAAF::Eval::Models::Continuous::ContinuousEvaluationResult.where(...)
```

### Evaluations Not Running

1. **Check policy is enabled:**
   ```ruby
   policy = RAAF::Eval::Models::Continuous::EvaluationPolicy.find_by(name: "...")
   policy.enabled? # Should be true
   ```

2. **Check sample rate:**
   ```ruby
   policy.sample_rate # Should be > 0
   ```

3. **Check pattern matching:**
   ```ruby
   # Ensure your span matches the policy patterns
   policy.agent_pattern     # e.g., "DmuDiscovery"
   policy.environment_pattern # e.g., "production"
   ```

4. **Check daily limit:**
   ```ruby
   policy.evaluations_today_count # Should be < max_daily_evaluations
   ```

### Missing Historical Data

The new system uses different tables. Historical data in `raaf_eval_runs` (the old table) is not automatically migrated. To preserve historical data:

1. Export old data before migration
2. Or keep the old table for historical queries
3. New evaluations will use the new tables going forward

## Support

If you encounter issues during migration:

1. Check `docs/CONTINUOUS_EVAL_MIGRATION.md` (this file)
2. Run `rails raaf:continuous_evaluation:check_deprecated` to find issues
3. Review the [RAAF_EVAL.md](../RAAF_EVAL.md) documentation
4. Open an issue on the RAAF GitHub repository
