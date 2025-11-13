# Spec Requirements: RAAF Eval DSL API

## Initial Description

Create a comprehensive Domain-Specific Language (DSL) for the RAAF Eval framework that transforms the evaluation workflow from imperative method chaining to declarative configuration. The DSL will enable developers to define evaluators that specify field selections, attach multiple evaluator types per field with flexible logic, stream real-time progress with full metrics, automatically store historical results, and compare runs across configurations.

This enhancement addresses the current limitation where users must manually chain methods and combine RSpec matchers without a unified way to configure evaluations, track progress, or compare historical results systematically.

## Requirements Discussion

### First Round Questions

Based on the initial spec for RAAF Eval DSL API, I have clarifying questions organized by topic area:

#### 1. User Workflows & Primary Use Cases

**Q1:** The spec defines 22 built-in evaluators across 7 categories. In practice, what are the most common evaluation scenarios?
- **Example A**: "I want to verify my agent's output hasn't degraded when I switch from GPT-4 to Claude" (quality + regression focus)
- **Example B**: "I want to optimize token usage while maintaining output quality" (performance + quality focus)
- **Example C**: "I want to ensure bias-free, compliant outputs at scale" (safety + compliance focus)

Which of these patterns (or others) should the DSL optimize for with convenient shortcuts or presets?

**Q2:** When defining evaluations, how do users typically discover what fields are available?
- Should the DSL provide field introspection (e.g., `evaluator.available_fields` that queries a span structure)?
- Should there be auto-completion hints for nested paths?
- Or is consulting documentation sufficient?

**Q3:** For multi-configuration comparison (Story 5), what's the typical number of configurations being compared?
- 2-3 configurations (A/B testing)?
- 5-10 configurations (comprehensive model comparison)?
- 20+ configurations (hyperparameter grid search)?

This impacts how comparison results should be formatted and whether visualization helpers are needed.

#### 2. API Surface & Method Design

**Q4:** The spec shows `RAAF::Eval.define` as the entry point. Should this DSL support method chaining for fluent configuration?
```ruby
# Option A: Block-based (currently specified)
evaluator = RAAF::Eval.define do
  fields do
    select 'usage.total_tokens', as: :tokens
  end
  evaluate_field :output do
    use_evaluator :semantic_similarity, threshold: 0.85
  end
end

# Option B: Method chaining alternative
evaluator = RAAF::Eval.define
  .field('usage.total_tokens', as: :tokens)
  .evaluate(:output, with: :semantic_similarity, threshold: 0.85)
  .build
```

Should we support both patterns, or is block-based sufficient?

**Q5:** For the `evaluate_field` block, how should evaluator configuration parameters be passed?
```ruby
# Option A: Inline kwargs (currently specified)
evaluate_field :output do
  use_evaluator :semantic_similarity, threshold: 0.85
  use_evaluator :coherence, min_score: 0.8
  combine_with :and
end

# Option B: Nested configuration block
evaluate_field :output do
  use_evaluator :semantic_similarity do |config|
    config.threshold = 0.85
    config.embedding_model = 'text-embedding-3-large'
  end
  use_evaluator :coherence do |config|
    config.min_score = 0.8
  end
  combine_with :and
end
```

Which pattern is clearer for evaluators with many parameters?

**Q6:** Should field selection support wildcard/glob patterns for arrays?
```ruby
# Example: Evaluate all tool results
fields do
  select 'tools.*.result', as: :tool_results
end

# Example: Evaluate all messages
fields do
  select 'messages.*.content', as: :message_contents
end
```

How should wildcards work with evaluators (evaluate each item individually vs aggregate)?

**Q7:** For the `combine_with` lambda option, what's the signature?
```ruby
# Option A: Pass evaluator results array
combine_with ->(results) {
  results.select(&:passed).count >= 2  # At least 2 must pass
}

# Option B: Pass named evaluator results
combine_with ->(semantic:, coherence:, relevance:) {
  semantic.passed && (coherence.passed || relevance.passed)
}

# Option C: Both?
```

What's the most intuitive API for custom logic?

#### 3. Progress Streaming Details

**Q8:** The spec mentions 6 event types (start, config_start, evaluator_start, evaluator_end, config_end, end). Are these sufficient, or should we add:
- `field_start` / `field_end` - When a specific field evaluation begins/ends?
- `retention_cleanup` - When historical data cleanup runs?
- `comparison_ready` - When cross-config comparison completes?

What level of granularity is most useful without overwhelming users?

**Q9:** For progress callbacks, should they receive structured event objects or simple hashes?
```ruby
# Option A: Structured event object
on_progress do |event|
  puts "Status: #{event.status}"
  puts "Progress: #{event.progress_pct}%"
  puts "Current config: #{event.current_configuration}"
  puts "Field values: #{event.field_values}"
end

# Option B: Simple hash
on_progress do |event|
  puts "Status: #{event[:status]}"
  puts "Progress: #{event[:progress_pct]}%"
end
```

**Q10:** How frequently should progress events emit during long-running evaluations?
- Every evaluator completion (could be 100+ events for many configs)?
- Only at configuration boundaries?
- Time-based throttling (max 1 event per second)?

#### 4. Historical Storage & Retention

**Q11:** The spec mentions both time-based (30 days) and count-based (100 runs) retention. How should conflicts be resolved?
```ruby
history do
  auto_save true
  retention_days 30
  retention_count 100
end

# What if:
# - Run 101 happens on day 1 (under time limit, over count limit)?
# - Run 50 happens on day 31 (over time limit, under count limit)?
```

Should it be "keep if (within days) OR (within count)" vs "keep if (within days) AND (within count)"?

**Q12:** For historical queries, what filtering capabilities are needed?
```ruby
# Basic queries (specified)
evaluator.history.last(10)
evaluator.history.trend('usage.total_tokens')

# Advanced queries (should these exist?)
evaluator.history.query(
  date_range: 7.days.ago..Time.now,
  configuration: 'high_temp',
  passed: true
)

evaluator.history.where(field: 'tokens', operator: '<', value: 1000)
```

What query complexity is required for historical data?

**Q13:** Should historical storage support tagging or labeling runs?
```ruby
# Example: Tag runs for later comparison
result = evaluator.evaluate(span) do
  configuration :baseline, temperature: 0.7
  tag 'release-v1.0'  # <-- Should this exist?
end

# Later:
evaluator.history.tagged('release-v1.0')
```

This would enable comparisons like "how does current dev compare to last release baseline?"

#### 5. Edge Cases & Error Handling

**Q14:** How should missing fields be handled during evaluation?
```ruby
fields do
  select 'usage.total_tokens', as: :tokens
end

# What if span result doesn't have 'usage.total_tokens'?
# Option A: Raise error immediately at evaluation time
# Option B: Mark field as missing, skip evaluators, log warning
# Option C: Call evaluator with nil value, let it decide
```

Should there be a configuration option for missing field behavior?

**Q15:** What should happen when an evaluator raises an exception during execution?
```ruby
evaluate_field :output do
  use_evaluator :semantic_similarity, threshold: 0.85
  use_evaluator :coherence, min_score: 0.8  # This raises error
  combine_with :and
end

# Options:
# A: Fail entire evaluation immediately
# B: Mark evaluator as failed, continue others, fail combined result
# C: Retry evaluator N times before failing
# D: Skip failed evaluator, combine only successful results
```

**Q16:** How should schema validation errors be reported?
```ruby
# User defines invalid field path
fields do
  select 'invalid..path', as: :bad  # Double dots invalid
end

# Or invalid evaluator name
evaluate_field :output do
  use_evaluator :nonexistent_evaluator
end

# Should these:
# A: Raise error at definition time (when .define is called)?
# B: Raise error at evaluation time (when .evaluate is called)?
# C: Return validation result object with errors?
```

**Q17:** For parallel evaluator execution (mentioned in spec), how should concurrency limits work?
```ruby
# Example: 20 evaluators on same field
evaluate_field :output do
  20.times do |i|
    use_evaluator :semantic_similarity, threshold: 0.8 + (i * 0.01)
  end
  combine_with :and
end

# Should there be:
history do
  max_concurrent_evaluators 5  # Limit to 5 parallel
end

# Or automatic based on available CPU cores?
```

#### 6. Cross-Configuration Comparison

**Q18:** The spec shows `result.compare(:low_temp, :high_temp)`. What should the comparison return?
```ruby
comparison = result.compare(:low_temp, :high_temp)

# Option A: Structured comparison object
comparison.field_deltas  # Hash of field name => { low_temp: value, high_temp: value, delta: X }
comparison.winner(:tokens)  # Which config had lower tokens
comparison.summary  # Human-readable summary

# Option B: Simple hash
{
  low_temp: { tokens: 100, output: "..." },
  high_temp: { tokens: 120, output: "..." },
  deltas: { tokens: 20 }
}
```

**Q19:** For `result.rank_by('usage.total_tokens', :asc)`, should ranking support:
- Multi-field ranking with weights (`rank_by([['tokens', 0.7], ['latency', 0.3]])`)?
- Custom ranking functions (`rank_by { |config| config.tokens / config.quality }`)?
- Or just single-field ranking as specified?

**Q20:** Should comparison be limited to configurations within a single evaluation run, or support cross-run comparisons?
```ruby
# Same run comparison (specified)
result = evaluator.evaluate(span) do
  configuration :a, temperature: 0.3
  configuration :b, temperature: 0.7
end
result.compare(:a, :b)

# Cross-run comparison (should this exist?)
run1 = evaluator.evaluate(span1) { configuration :baseline }
run2 = evaluator.evaluate(span2) { configuration :new }
RAAF::Eval::Comparison.compare(run1, :baseline, run2, :new)
```

#### 7. Backward Compatibility & Migration

**Q21:** The spec states backward compatibility with existing RSpec helpers. Should there be:
- A deprecation path for old API (warnings but still functional)?
- Or indefinite parallel support (both APIs maintained forever)?
- Automatic migration tools (convert old API usage to DSL)?

**Q22:** For users with existing custom evaluators (not following the new interface), should the DSL provide an adapter?
```ruby
# Old-style custom evaluator (hypothetical)
class LegacyEvaluator
  def evaluate(value, baseline)
    { passed: value == baseline }
  end
end

# Adapter to new interface
RAAF::Eval::DSL.register_legacy_evaluator(LegacyEvaluator, :legacy_eval)
```

Or require users to update to new `FieldContext` interface?

### Existing Code to Reference

No similar existing code patterns identified for reuse. This is a new DSL API for RAAF Eval.

The RAAF Eval RSpec integration (Phase 2) provides foundation:
- RSpec helper methods: `evaluate_span`, `evaluate_latest_span`, `find_span`, etc.
- 40+ matchers across 7 categories (performance, quality, regression, statistical, safety, structural, LLM)
- SpanEvaluator class with method chaining

However, the DSL API is a higher-level declarative interface that will internally use these existing RSpec components.

### Visual Assets Request

Do you have any design mockups, wireframes, or screenshots that could help guide the DSL API development?

If yes, please place them in: `/Users/hajee/Enterprise Modules Dropbox/Bert Hajee/enterprisemodules/work/prospects_radar/vendor/local_gems/raaf/.agent-os/specs/2025-01-13-evaluator-dsl-api/planning/visuals/`

Use descriptive file names like:
- dsl-api-flow.png - Overall DSL usage flow diagram
- evaluator-definition-example.png - Example evaluator definition
- progress-streaming-diagram.png - Progress event flow
- comparison-output-example.png - Comparison result format

Please answer the questions above and let me know if you've added any visual files or can point to similar existing features.

## Additional Context Questions

Based on the RAAF Eval mission and roadmap, I have a few additional questions:

**Q23:** The product mission mentions "Interactive Prompt Editor" and "Unified Dashboard Integration" as key features. How should the DSL API integrate with the web UI?
- Should evaluator definitions be serializable (save/load from database)?
- Should the UI provide a visual DSL builder (drag-drop evaluators to fields)?
- Or is the DSL purely programmatic (RSpec tests only)?

**Q24:** Phase 6 roadmap includes "Continuous Evaluation" with automatic span evaluation. How should the DSL support this?
```ruby
# Example: Register evaluator for continuous evaluation
evaluator = RAAF::Eval.define do
  # ... definition
end

# Should there be:
RAAF::Eval.register_continuous(evaluator,
  span_filter: ->(span) { span.agent_name == "ProductionAgent" },
  sampling_rate: 0.1  # Evaluate 10% of spans
)
```

**Q25:** The mission mentions "Active Record Integration for Real Applications". How should the DSL support linking evaluations to AR models?
```ruby
# Example use case: Track evaluations per User
evaluator = RAAF::Eval.define do
  link_to User, via: ->(span) { span.metadata[:user_id] }
end

# Or simpler:
evaluator.evaluate(span, linked_to: @user)
```

Should model linking be part of the DSL, or handled separately?
