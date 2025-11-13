# Specification: RAAF Eval DSL API

> Created: 2025-01-13
> Status: Planning

## Overview

Create a comprehensive Domain-Specific Language (DSL) for the RAAF Eval framework that transforms the evaluation workflow from imperative method chaining to declarative configuration. The DSL will enable developers to define evaluators that specify field selections, attach multiple evaluator types per field with flexible logic, stream real-time progress with full metrics, automatically store historical results, and compare runs across configurations.

This enhancement addresses the current limitation where users must manually chain methods and combine RSpec matchers without a unified way to configure evaluations, track progress, or compare historical results systematically.

## Complete DSL API Example

```ruby
# Define evaluator with fluent method chaining
evaluator = RAAF::Eval.define do
  # Select fields to evaluate
  select 'output', as: :output
  select 'usage.total_tokens', as: :tokens
  select 'latency_ms', as: :latency

  # Evaluate output field with multiple evaluators
  evaluate_field :output do
    # Quality evaluators
    evaluate_with :semantic_similarity, threshold: 0.85
    evaluate_with :coherence, min_score: 0.8
    evaluate_with :hallucination_detection

    # All must pass
    combine_with :and
  end

  # Evaluate token usage
  evaluate_field :tokens do
    evaluate_with :token_efficiency, max_increase_pct: 10
  end

  # Evaluate latency
  evaluate_field :latency do
    evaluate_with :latency_regression, max_ms: 200
  end

  # Custom evaluator
  evaluate_field :output do
    evaluate_with :citation_grounding, knowledge_base: kb_path
  end

  # Progress streaming
  on_progress do |event|
    puts "#{event.status}: #{event.progress}% - #{event.current_field}"
    puts "  Values: #{event.field_values}"
    puts "  Deltas: #{event.deltas}" if event.deltas
  end

  # Historical storage
  history do
    auto_save true
    retention_days 30
    retention_count 100
    tags environment: 'production', feature: 'chat'
  end
end

# Execute evaluation with multiple configurations
result = evaluator.evaluate(span) do
  configuration :low_temp, temperature: 0.3
  configuration :med_temp, temperature: 0.7
  configuration :high_temp, temperature: 1.0
end

# Check results
puts result.passed?  # Overall pass/fail
puts result.field_results[:output]  # Field-specific results

# Compare configurations
comparison = result.compare(:low_temp, :high_temp)
puts comparison.deltas  # { tokens: { absolute: -50, percentage: -10 } }

# Rank configurations
ranking = result.rank_by(:tokens, :asc)
puts ranking.best  # :low_temp
puts ranking.worst # :high_temp

# Query historical results
history = evaluator.history.query(
  configuration: :low_temp,
  date_range: 30.days.ago..Time.now,
  tags: { environment: 'production' }
)

# Trend analysis
trend = evaluator.history.trend(:tokens, configurations: [:low_temp])
puts trend.data  # [{ date: '2025-01-01', value: 500 }, ...]
```

## User Stories

### Story 1: Define Multi-Field Evaluator with Nested Paths

As a RAAF developer, I want to select specific fields from span results using nested dot notation (e.g., `usage.total_tokens`, `baseline_comparison.quality_change`) so that I can evaluate only the metrics that matter for my use case without manual hash traversal.

**Workflow:**
1. Developer creates an evaluator definition using `RAAF::Eval.define` block
2. Within the `fields` block, developer calls `select 'usage.total_tokens', as: :tokens` for each field
3. System parses nested paths and creates field accessors
4. When evaluation runs, system extracts values using dot notation automatically

**Problem Solved:** Eliminates manual hash digging like `result.dig(:usage, :total_tokens)` throughout test code

### Story 2: Attach Multiple Evaluators to Single Field with Logic

As a RAAF tester, I want to attach multiple evaluators (semantic similarity, coherence, hallucination detection) to a single field like `output` and specify AND/OR/custom logic so that I can validate multiple quality dimensions simultaneously with flexible pass/fail criteria.

**Workflow:**
1. Developer defines field evaluators within `evaluate_field :output` block
2. Calls `evaluate_with :semantic_similarity, threshold: 0.85`
3. Calls `evaluate_with :coherence, min_score: 0.8`
4. Specifies `combine_with :and` to require all evaluators pass
5. System executes all evaluators in parallel and combines results

**Problem Solved:** Simplifies complex validation logic that currently requires multiple RSpec matchers and manual result combination

### Story 3: Stream Real-Time Progress with Full Metrics

As a RAAF operator, I want to receive real-time progress updates during evaluation runs that include status, current values, deltas from baseline, and quality metrics so that I can monitor long-running evaluations and identify issues early.

**Workflow:**
1. Developer defines `on_progress` callback in evaluator definition
2. System emits progress events during evaluation execution
3. Callback receives event with `status`, `progress`, `current_values`, `deltas`, `quality_metrics`
4. Developer displays or logs progress information as needed

**Problem Solved:** Eliminates polling and manual metric calculation for tracking evaluation progress

### Story 4: Automatic Historical Storage with Retention

As a RAAF engineer, I want evaluation results automatically saved to database with configurable retention policies (time-based and count-based) so that I can track agent performance over time without manual result persistence.

**Workflow:**
1. Developer enables `auto_save true` in `history` configuration block
2. Specifies `retention_days 30` and `retention_count 100`
3. System automatically persists results after each evaluation run
4. System automatically purges results older than 30 days or beyond top 100
5. Developer queries historical results via `evaluator.history` API

**Problem Solved:** Removes burden of manual result persistence and cleanup

### Story 5: Compare Configurations and Rank Results

As a RAAF developer, I want to compare evaluation results across multiple configurations (different temperatures, models, prompts) and rank them by specific fields (e.g., lowest token usage, best quality) so that I can identify optimal agent configurations.

**Workflow:**
1. Developer executes evaluator with multiple configurations via block
2. Calls `configuration :low_temp, temperature: 0.3` for each config
3. After run completes, calls `result.compare(:low_temp, :high_temp)`
4. Or calls `result.rank_by('usage.total_tokens', :asc)` to rank all configs
5. System generates comparison tables or rankings

**Problem Solved:** Eliminates manual result comparison logic scattered across test files

## Specific Requirements

### Field Selection System
- Parse nested field paths using dot notation (e.g., `usage.total_tokens`)
- Support field aliasing with `as:` parameter for shorter references
- Validate field paths against span structure at definition time
- Extract field values automatically during evaluation execution
- Support both string and symbol field names interchangeably
- **Raise error immediately** when selected field is missing during evaluation
- Cache parsed field paths for performance

### Multi-Evaluator Field System
- Attach multiple evaluator types (semantic, performance, structural) to single field
- Support three combination modes: `:and` (all pass), `:or` (any pass), lambda (custom logic)
- **Execute evaluators sequentially** (no parallel execution)
- Collect results from all evaluators before applying combination logic
- Support evaluator-specific configuration parameters via `evaluate_with(name, **params)`
- Map evaluator names to existing RSpec matchers (semantic_similarity → maintain_semantic_similarity)
- Provide clear pass/fail results per evaluator and combined result
- **Mark evaluator as failed on exception, continue with other evaluators, fail combined result**
- Pass FieldContext object to all evaluators with field-specific value and full result access
- Create FieldContext with field_name, value, baseline_value, delta, and convenience accessors

### Evaluator Type System

**Built-in Evaluator Types (22 matchers across 7 categories):**

1. **Quality Evaluators** (4 matchers)
   - `:semantic_similarity` - Maintain semantic meaning (threshold: 0.8)
   - `:coherence` - Text coherence and flow (min_score: 0.8)
   - `:hallucination_detection` - No hallucinations or false claims
   - `:relevance` - Response relevance to prompt (threshold: 0.7)

2. **Performance Evaluators** (3 matchers)
   - `:token_efficiency` - Minimize token usage vs baseline
   - `:latency` - Response time thresholds (max_ms: 2000)
   - `:throughput` - Tokens per second (min_tps: 10)

3. **Regression Evaluators** (3 matchers)
   - `:no_regression` - No degradation from baseline
   - `:token_regression` - Token usage doesn't increase (max_pct: 10)
   - `:latency_regression` - Latency doesn't increase (max_ms: 200)

4. **Safety Evaluators** (3 matchers)
   - `:bias_detection` - No gender, race, or cultural bias
   - `:toxicity_detection` - No offensive or harmful content
   - `:compliance` - Adheres to content policies

5. **Statistical Evaluators** (3 matchers)
   - `:consistency` - Consistent results across runs (std_dev: 0.1)
   - `:statistical_significance` - Results are statistically significant (p_value: 0.05)
   - `:effect_size` - Practical significance (cohen_d: 0.5)

6. **Structural Evaluators** (3 matchers)
   - `:json_validity` - Valid JSON format
   - `:schema_match` - Matches JSON schema
   - `:format_compliance` - Output matches expected format

7. **LLM-Powered Evaluators** (3 matchers)
   - `:llm_judge` - Custom LLM evaluation with criteria
   - `:quality_score` - Overall quality assessment (min_score: 0.7)
   - `:rubric_evaluation` - Rubric-based grading

**Custom Evaluator Support:**

Users can create custom evaluator classes that implement the evaluator interface:

```ruby
# Custom evaluator class
class CitationGroundingEvaluator
  include RAAF::Eval::DSL::Evaluator

  # Required: evaluator name for DSL reference
  evaluator_name :citation_grounding

  # Required: evaluate method receives FieldContext object
  def evaluate(field_context, **options)
    # Get the field value being evaluated
    text = field_context.value

    # Access configuration
    knowledge_base = options[:knowledge_base]

    # Can access other fields for context
    model = field_context[:configuration][:model]
    tokens = field_context[:usage][:total_tokens]

    # Extract and verify citations
    citations = extract_citations(text)
    grounded = verify_citations(citations, knowledge_base)

    {
      passed: grounded[:unverified].empty?,
      score: grounded[:verified_ratio],
      details: {
        field_evaluated: field_context.field_name,
        total_citations: citations.count,
        verified: grounded[:verified].count,
        unverified: grounded[:unverified],
        ratio: grounded[:verified_ratio],
        context: {
          model: model,
          tokens: tokens
        }
      },
      message: "#{grounded[:verified].count}/#{citations.count} citations grounded in #{field_context.field_name}"
    }
  end

  private

  def extract_citations(text)
    return [] unless text.is_a?(String)
    text.scan(/\[(\d+)\]/).flatten.map(&:to_i)
  end

  def verify_citations(citations, kb)
    verified = citations.select { |c| kb.include?(c.to_s) }
    {
      verified: verified,
      unverified: citations - verified,
      verified_ratio: verified.count.to_f / citations.count
    }
  end
end

# Register custom evaluator
RAAF::Eval::DSL.register_evaluator(CitationGroundingEvaluator)

# Use in DSL
evaluator = RAAF::Eval.define do
  evaluate_field :output do
    use_evaluator :citation_grounding, knowledge_base: kb_path
    combine_with :and
  end
end
```

**Evaluator Interface Requirements:**

All custom evaluators must implement:
- `evaluator_name` class method - Returns symbol for DSL reference
- `evaluate(field_context, **options)` instance method - Receives FieldContext object and returns hash with:
  - `:passed` (Boolean) - Whether evaluation passed
  - `:score` (Float, optional) - Numeric score 0.0-1.0
  - `:details` (Hash, optional) - Detailed results for debugging
  - `:message` (String, optional) - Human-readable explanation

**FieldContext API:**

The `field_context` parameter provides rich access to evaluation data:

```ruby
def evaluate(field_context, **options)
  # Primary field being evaluated
  value = field_context.value                    # The specific field value
  baseline = field_context.baseline_value        # Baseline value for comparison
  delta = field_context.delta                    # Automatic delta calculation (numeric fields)
  field_name = field_context.field_name          # Name of field being evaluated

  # Access other fields from full result
  tokens = field_context[:usage][:total_tokens]
  latency = field_context[:latency_ms]
  model = field_context[:configuration][:model]

  # Convenience accessors
  output = field_context.output                  # result[:output]
  baseline_output = field_context.baseline_output # result[:baseline_output]
  usage = field_context.usage                    # result[:usage]
  baseline_usage = field_context.baseline_usage  # result[:baseline_usage]
  configuration = field_context.configuration    # result[:configuration]

  # Full result access (when needed)
  full_result = field_context.full_result        # Complete result hash
end
```

**FieldContext Methods:**
- `value` - Primary field value being evaluated
- `baseline_value` - Baseline value for the field (auto-detects baseline_* fields)
- `delta` - Hash with `:absolute` and `:percentage` for numeric fields
- `field_name` - Symbol/String name of field being evaluated
- `[field_name]` - Access any field from result (supports nested paths like `usage.total_tokens`)
- `output`, `baseline_output` - Convenience accessors for output fields
- `usage`, `baseline_usage` - Convenience accessors for token usage
- `latency_ms` - Convenience accessor for latency
- `configuration` - Convenience accessor for configuration
- `full_result` - Complete result hash for complex evaluations
- `field_exists?(field_name)` - Check if field exists in result

**Example: Token Efficiency Evaluator Using Delta:**

```ruby
class TokenEfficiencyEvaluator
  include RAAF::Eval::DSL::Evaluator

  evaluator_name :token_efficiency

  def evaluate(field_context, **options)
    # Get token count (the field being evaluated)
    current_tokens = field_context.value
    baseline_tokens = field_context.baseline_value

    # Configuration
    max_increase_pct = options[:max_increase_pct] || 10

    # Automatic delta calculation
    delta = field_context.delta

    return {
      passed: true,
      message: "No baseline to compare"
    } unless delta

    passed = delta[:percentage] <= max_increase_pct

    {
      passed: passed,
      score: passed ? 1.0 : [1.0 - (delta[:percentage] / 100), 0].max,
      details: {
        field: field_context.field_name,
        current_tokens: current_tokens,
        baseline_tokens: baseline_tokens,
        delta: delta,
        threshold: max_increase_pct
      },
      message: "Token usage: #{delta[:percentage]}% change (threshold: #{max_increase_pct}%)"
    }
  end
end

# Usage
evaluate_field :tokens do
  use_evaluator :token_efficiency, max_increase_pct: 10
end
```

**Example: Cross-Field Context-Aware Evaluator:**

```ruby
class SmartQualityEvaluator
  include RAAF::Eval::DSL::Evaluator

  evaluator_name :smart_quality

  def evaluate(field_context, **options)
    # Primary field
    output = field_context.value

    # Access full context for intelligent evaluation
    tokens = field_context[:usage][:total_tokens]
    latency = field_context[:latency_ms]
    model = field_context[:configuration][:model]

    # Base quality score
    base_score = calculate_quality(output)

    # Adjust expectations based on model
    adjusted_score = case model
    when "gpt-4o"
      base_score * 1.0  # Expect high quality
    when "gpt-3.5-turbo"
      base_score * 1.1  # More lenient
    else
      base_score
    end

    # Penalize inefficiency
    efficiency_penalty = if tokens > 1000 && output.length < 200
      0.1  # Used many tokens for short output
    else
      0.0
    end

    final_score = [adjusted_score - efficiency_penalty, 0].max

    {
      passed: final_score >= 0.7,
      score: final_score,
      details: {
        evaluated_field: field_context.field_name,
        base_quality: base_score,
        efficiency_penalty: efficiency_penalty,
        context: {
          model: model,
          tokens: tokens,
          latency: latency
        }
      },
      message: "Quality: #{(final_score * 100).round}% (model: #{model}, tokens: #{tokens})"
    }
  end

  private

  def calculate_quality(text)
    # Quality evaluation logic
    0.85
  end
end
```

**Evaluator Registration:**

Custom evaluators can be registered globally:
```ruby
RAAF::Eval::DSL.register_evaluator(MyCustomEvaluator)
```

Or passed directly to evaluator definition:
```ruby
evaluator = RAAF::Eval.define do
  register_evaluator MyCustomEvaluator

  evaluate_field :output do
    use_evaluator :my_custom, param: value
  end
end
```

**Lambda Combination Logic:**

For advanced combination logic beyond AND/OR, use a lambda that receives named evaluator results:

```ruby
evaluate_field :output do
  evaluate_with :semantic_similarity, threshold: 0.85
  evaluate_with :coherence, min_score: 0.8
  evaluate_with :hallucination_detection

  # Lambda receives hash with evaluator names as keys
  combine_with lambda { |results|
    # Custom logic: require similarity and coherence, hallucination is optional
    required_passed = results[:semantic_similarity][:passed] &&
                     results[:coherence][:passed]

    # Bonus points if no hallucinations
    bonus = results[:hallucination_detection][:passed] ? 0.1 : 0.0

    # Calculate combined score
    avg_score = (results[:semantic_similarity][:score] +
                results[:coherence][:score]) / 2.0

    {
      passed: required_passed,
      score: [avg_score + bonus, 1.0].min,
      details: {
        required_passed: required_passed,
        bonus_applied: bonus > 0,
        individual_results: results
      },
      message: "Combined evaluation: #{required_passed ? 'PASS' : 'FAIL'}"
    }
  }
end
```

**Lambda Signature:**
- Input: `Hash` with evaluator names as keys, each containing `{ passed:, score:, details:, message: }`
- Output: `Hash` with `{ passed:, score:, details:, message: }` following evaluator result contract

### Real-Time Progress Streaming
- Emit progress events at key execution milestones (start, config_start, evaluator_start, evaluator_end, config_end, end)
- Include status string (pending, running, evaluating, completed, failed) in events
- Calculate and include percentage progress based on total configurations and evaluators
- Include current field values for all selected fields
- Calculate deltas from baseline for numeric fields
- Include quality metrics from quality evaluators (coherence, relevance, etc.)
- Support multiple progress callbacks registered on single evaluator
- **Emit progress events every evaluator completion** (no throttling)
- **Use structured event objects** (not simple hashes) with consistent schema
- Provide timestamp for each progress event
- Support optional event filtering by status or configuration

### Automatic Historical Storage
- Persist evaluation results to database after each run completion
- Store configuration details, field values, evaluator results, and metadata
- Implement time-based retention (delete runs older than N days)
- Implement count-based retention (keep only last N runs per evaluator)
- **Use OR logic for retention**: Keep if (within days) OR (within count), delete only when BOTH exceeded
- Execute retention policies automatically on background schedule
- Support manual retention policy execution
- **Support basic historical queries**: by evaluator name, configuration name, date range
- **Support tagging/labeling runs** with custom metadata for organization
- Index results by evaluator name, configuration name, timestamp, tags for fast queries
- Compress historical data for storage efficiency

### FieldContext Implementation
- Create FieldContext class that wraps evaluation result with field-aware API
- Store field_name and full result hash in FieldContext instance
- Implement `value` method to extract field value from result using field_name
- Implement `baseline_value` method to auto-detect and extract baseline field (e.g., baseline_output for :output)
- Implement `delta` method to calculate absolute and percentage deltas for numeric fields
- Implement `[]` method to access any field from result (supports nested paths like 'usage.total_tokens')
- Implement convenience accessors: `output`, `baseline_output`, `usage`, `baseline_usage`, `latency_ms`, `configuration`
- Implement `full_result` method to return complete result hash when needed
- Implement `field_exists?` method to check field existence
- Handle nested field paths in field extraction (e.g., 'usage.total_tokens' → result.dig(:usage, :total_tokens))
- Support both symbol and string field names interchangeably
- Provide clear error messages when field doesn't exist

### Cross-Configuration Comparison
- Compare field values between two specific configurations within single evaluation run
- **Return structured comparison object** with deltas, percentage changes, and metadata
- Support comparison of quality metrics (e.g., semantic similarity scores)
- Rank all configurations by selected field (ascending or descending)
- **Single-field ranking only** in initial implementation
- Identify best and worst performing configurations automatically
- Generate visualization-ready data structures (arrays, hashes)
- **Limit comparison to configurations within single run** (not cross-run initially)

### DSL API Surface
- Top-level `RAAF::Eval.define` method returns EvaluatorDefinition instance
- **Fluent method chaining** for evaluator configuration
- `evaluate_field` block for attaching evaluators to specific fields
- `on_progress` block for progress callback registration
- `history` block for historical storage configuration
- `evaluate(span)` method executes evaluation with configurations block
- `configuration(name, **options)` method within evaluate block
- **Pass evaluator parameters via keyword arguments** AND via block: `evaluate_with :name, param: value` AND `evaluate_with :name { |config| config.param = value }`
- Result object with `passed?`, `field_results`, `compare`, `rank_by` methods
- History object with `last(n)`, `trend(field)`, `query(**filters)` methods
- **Raise schema validation errors at definition time** (when .define is called)

### RSpec Integration Strategy
- **Replace existing RSpec helpers with evaluator type DSL interface**
- Maintain existing 40+ matchers as evaluator types (not RSpec matchers)
- **No backward compatibility** - clean break from old API
- Update documentation and migration guide to show evaluator type usage
- Remove SpanEvaluator class and imperative method chaining API

## Out of Scope

- **Automatic evaluator discovery** - Users must explicitly specify evaluators, no AI-based evaluator suggestion
- **Visual dashboard integration** - DSL focuses on programmatic API, not UI components
- **Real-time evaluation monitoring UI** - Progress streaming is programmatic only, no web interface
- **Distributed evaluation execution** - All evaluation runs execute locally, no multi-node distribution
- **Historical data migration tools** - No tools for migrating pre-DSL evaluation data to new format
- **Historical data export formats** - No CSV/JSON export of historical evaluation results
- **Evaluator performance profiling** - No built-in profiling of evaluator execution time
- **Evaluator dependency management** - No dependency resolution between evaluators (e.g., run X before Y)
- **Conditional evaluator execution** - No support for running evaluators based on previous results
- **Multi-tenant historical storage** - No support for isolating historical data by user/team
- **Historical data replication** - No support for backing up or syncing historical data across systems
- **Pre-built advanced evaluators** - Only core 22 evaluators included; advanced evaluators (RAG grounding, code execution, fact verification) are examples but not implemented in this phase

## Expected Deliverable

Upon completion, the RAAF Eval DSL API will provide the following testable outcomes:

### Functional Deliverables

1. **Field Selection DSL** - Users can select nested fields using dot notation and field aliases work correctly (test: select `usage.total_tokens` as `:tokens` and verify alias works)

2. **Multi-Evaluator System** - Users can attach multiple evaluators to single field with AND/OR/custom logic and all evaluators execute correctly (test: attach semantic_similarity + coherence with AND logic, verify both run and combined result is correct)

3. **Progress Streaming** - Users can register progress callbacks that receive events with status, progress percentage, current values, deltas, and quality metrics (test: register callback, run evaluation, verify callback receives all expected event types and data)

4. **Historical Storage** - Evaluation results automatically persist to database with configurable retention policies that execute correctly (test: run 150 evaluations with 100 count retention, verify only last 100 remain; set 30 day retention, verify older runs deleted)

5. **Configuration Comparison** - Users can compare results between configurations and rank all configurations by field values (test: run 3 configs, compare first two and verify delta calculation, rank by tokens and verify ordering)

6. **DSL API Surface** - All DSL methods (define, fields, evaluate_field, on_progress, history, evaluate, configuration) work as documented (test: execute complete DSL example from docs, verify no errors and correct results)

7. **Backward Compatibility** - Existing RSpec helpers and SpanEvaluator API continue to work unchanged alongside DSL (test: run existing tests with new DSL present, verify all pass)

8. **Custom Evaluator System** - Users can create custom evaluator classes that implement the evaluator interface, register them globally or per-definition, and use them in DSL with full parameter support (test: create custom citation grounding evaluator, register it, use in DSL with knowledge_base parameter, verify evaluation executes and returns correct result structure)

### Non-Functional Deliverables

9. **Performance** - Field extraction overhead < 5ms for 100 fields, evaluator execution in parallel completes in < 2x slowest individual evaluator time

10. **Documentation** - Complete API documentation with 10+ examples covering all DSL features, custom evaluator creation guide, migration guide from old API to DSL, catalog of all 22 built-in evaluators with parameters and examples

11. **Test Coverage** - >90% test coverage for all DSL components, including unit tests, integration tests, custom evaluator examples, and performance benchmarks
