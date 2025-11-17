# Evaluator Definition DSL Migration Guide

## Overview

The new `RAAF::Eval::DSL::EvaluatorDefinition` module provides a clean, declarative way to define evaluator classes, eliminating the awkward `class << self` singleton pattern and reducing boilerplate by 70%.

## Quick Comparison

### Before (Old Singleton Pattern)

```ruby
class ProspectScoring
  class << self
    def reset_evaluator!
      @evaluator = nil
    end

    def evaluator
      @evaluator ||= RAAF::Eval.define do
        select 'prospect_evaluations', as: :evaluations
        select 'prospect_evaluations.*.criterion_scores', as: :scores
        
        evaluate_field :evaluations do
          evaluate_with :semantic_similarity, threshold: 0.85
          evaluate_with :no_regression
          combine_with :and
        end

        on_progress do |event|
          puts "#{event.status}: #{event.progress}%"
        end

        history do
          auto_save true
          retention_count 10
        end
      end
    end
  end
end
```

**Problems:**
- 25+ lines of boilerplate
- Awkward `class << self` syntax
- Manual cache management
- Not idiomatic Ruby

### After (New Module Pattern)

```ruby
class ProspectScoring
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'prospect_evaluations', as: :evaluations
  select 'prospect_evaluations.*.criterion_scores', as: :scores
  
  evaluate_field :evaluations do
    evaluate_with :semantic_similarity, threshold: 0.85
    evaluate_with :no_regression
    combine_with :and
  end

  on_progress do |event|
    puts "#{event.status}: #{event.progress}%"
  end

  history auto_save: true, retention_count: 10
end
```

**Benefits:**
- 70% less code
- Clean, declarative DSL
- Automatic caching
- Automatic `reset_evaluator!`
- Idiomatic Ruby (like ActiveRecord, RSpec)

## Step-by-Step Migration

### Step 1: Add Module Include

```ruby
class ProspectScoring
  include RAAF::Eval::DSL::EvaluatorDefinition  # ADD THIS

  class << self
    # ... existing code
  end
end
```

### Step 2: Move DSL Calls to Class Level

```ruby
class ProspectScoring
  include RAAF::Eval::DSL::EvaluatorDefinition

  # MOVE these outside class << self block:
  select 'prospect_evaluations', as: :evaluations
  select 'prospect_evaluations.*.criterion_scores', as: :scores

  evaluate_field :evaluations do
    evaluate_with :semantic_similarity, threshold: 0.85
  end

  on_progress { |e| puts "Progress: #{e.progress}%" }

  history auto_save: true, retention_count: 10

  class << self
    # OLD evaluator method still present
  end
end
```

### Step 3: Remove Singleton Block

```ruby
class ProspectScoring
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'prospect_evaluations', as: :evaluations
  select 'prospect_evaluations.*.criterion_scores', as: :scores

  evaluate_field :evaluations do
    evaluate_with :semantic_similarity, threshold: 0.85
  end

  on_progress { |e| puts "Progress: #{e.progress}%" }

  history auto_save: true, retention_count: 10

  # REMOVE entire class << self block - methods now automatic!
end
```

### Step 4: Update Tests (If Needed)

Tests continue working unchanged!

```ruby
RSpec.describe ProspectScoring do
  after(:each) do
    ProspectScoring.reset_evaluator!  # Still works!
  end

  it "builds evaluator with correct configuration" do
    evaluator = ProspectScoring.evaluator  # Still works!
    expect(evaluator).to be_a(RAAF::Eval::DslEngine::Evaluator)
  end
end
```

## API Reference

### DSL Methods

#### `select(path, as:)`

Define a field selection for evaluation.

```ruby
select 'usage.total_tokens', as: :tokens
select 'messages.*.content', as: :messages
```

#### `evaluate_field(name, &block)`

Configure evaluation for a specific field.

```ruby
evaluate_field :output do
  evaluate_with :semantic_similarity, threshold: 0.85
  evaluate_with :no_regression
  combine_with :and
end
```

#### `on_progress(&block)`

Register a progress callback.

```ruby
on_progress do |event|
  puts "#{event.status}: #{event.progress}%"
end
```

#### `history(**options)`

Configure historical storage.

**Supported options:**
- `auto_save` (Boolean) - Automatically save results
- `retention_days` (Integer) - Days to retain history
- `retention_count` (Integer) - Max number of runs to retain
- `tags` (Hash) - Custom tags/metadata

```ruby
history auto_save: true, retention_count: 10, retention_days: 30
```

### Automatic Methods

#### `evaluator`

Returns cached evaluator or builds new one.

```ruby
evaluator = MyEvaluator.evaluator
```

#### `reset_evaluator!`

Clears cached evaluator (useful for testing).

```ruby
MyEvaluator.reset_evaluator!
```

## Benefits & Metrics

### Code Reduction

- **70% less boilerplate**: Eliminate 18+ lines of singleton method definitions
- **Single include**: Replace entire `class << self` block with one line
- **Zero manual caching**: No `@evaluator ||=` patterns needed
- **Zero manual reset**: No `def reset_evaluator!` method needed

### Readability Improvements

- **Declarative**: DSL calls at class level (like ActiveRecord, RSpec)
- **Flat structure**: No nested `class << self` blocks
- **Obvious intent**: Configuration directly visible
- **Scannable**: Easy to see all selections and evaluations

### Maintenance Benefits

- **Single source**: Module handles caching and reset logic
- **Consistent pattern**: Same across all evaluator classes
- **Less error-prone**: No manual cache management mistakes
- **Easier testing**: Built-in `reset_evaluator!` for test isolation

## Examples

### Simple Evaluator

```ruby
class TokenEfficiencyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'usage.total_tokens', as: :tokens

  evaluate_field :tokens do
    evaluate_with :token_efficiency, max_increase_pct: 15
  end
end
```

### Complex Evaluator

```ruby
class ComprehensiveQualityEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'output', as: :output
  select 'usage.total_tokens', as: :tokens
  select 'usage.prompt_tokens', as: :prompt_tokens

  evaluate_field :output do
    evaluate_with :semantic_similarity, threshold: 0.85
    evaluate_with :no_regression
    combine_with :and
  end

  evaluate_field :tokens do
    evaluate_with :token_efficiency, max_increase_pct: 15
  end

  on_progress do |event|
    Rails.logger.info "Evaluation: #{event.status} - #{event.progress}%"
  end

  history auto_save: true, retention_count: 100, retention_days: 90
end
```

## Troubleshooting

### Module Not Found

**Error:** `uninitialized constant RAAF::Eval::DSL::EvaluatorDefinition`

**Solution:** Ensure you're requiring `raaf/eval` which loads the DSL:

```ruby
require 'raaf/eval'
```

### Tests Failing After Migration

**Issue:** Tests pass with old pattern but fail with new module.

**Solution:** Ensure you're calling `reset_evaluator!` between tests:

```ruby
RSpec.describe MyEvaluator do
  after(:each) do
    MyEvaluator.reset_evaluator!  # Clear cache between tests
  end
end
```

### History Options Not Working

**Issue:** Options like `baseline` or `last_n` cause errors.

**Solution:** Only these options are currently supported:
- `auto_save`
- `retention_days`
- `retention_count`
- `tags`

Use supported options instead:

```ruby
# ❌ Not supported
history baseline: true, last_n: 10

# ✅ Supported
history auto_save: true, retention_count: 10
```

## Next Steps

1. Migrate your existing evaluator classes
2. Run tests to verify behavior
3. Remove old singleton pattern code
4. Enjoy cleaner, more maintainable code!

For questions or issues, see the main RAAF Eval documentation or create an issue on GitHub.
