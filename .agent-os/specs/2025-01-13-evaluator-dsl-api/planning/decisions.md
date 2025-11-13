# Key Design Decisions for RAAF Eval DSL API

> Created: 2025-01-13
> Based on requirements clarification session

## API Design Decisions

### Field Selection
- **Use fluent method chaining** (Option A) for clean, composable API
- **Raise errors immediately** when fields are missing (fail fast approach)
- **No wildcard/glob patterns** for arrays (keep it simple)

### Evaluator Configuration
- **Support BOTH keyword arguments AND block syntax** for parameter configuration
  - `evaluate_with :name, param: value`
  - `evaluate_with :name { |config| config.param = value }`
- **Sequential execution** (no parallel execution to simplify implementation)
- **Mark evaluator as failed on exception, continue with others, fail combined result**

### Progress Streaming
- **Emit every evaluator completion** (no throttling)
- **Use structured event objects** (not simple hashes) with consistent schema
- Include 6 event types: start, config_start, evaluator_start, evaluator_end, config_end, end

### Historical Storage
- **OR logic for retention**: Keep if (within days) OR (within count)
- Delete only when BOTH time and count thresholds exceeded
- **Support tagging/labeling** runs with custom metadata
- **Basic queries** by evaluator name, configuration name, date range, tags

### Edge Cases
- **Raise error at definition time** for schema validation (when .define is called)
- **No concurrency limits** - removed parallel execution feature for simplicity

### Configuration Comparison
- **Return structured comparison object** with deltas, percentage changes, metadata
- **Single-field ranking only** in initial implementation
- **Limit to single-run comparisons** (not cross-run comparisons initially)

### Lambda Combination Logic
- **Pass named evaluator results** as hash: `lambda { |results| ... }`
- Lambda signature: `Hash<Symbol, EvaluatorResult>` → `EvaluatorResult`
- Enable complex logic: weighted averages, conditional requirements, bonus scoring

## Architecture Decisions

### RSpec Integration Strategy
- **Replace existing RSpec helpers** with evaluator type DSL interface
- **No backward compatibility** - clean break from old API
- Convert 40+ matchers to evaluator types (not RSpec matchers)
- Remove SpanEvaluator class and imperative method chaining API

### Rationale for Clean Break
1. **Simplicity**: No need to maintain dual interfaces (old + new)
2. **Clarity**: Single way to write evaluations (DSL only)
3. **Flexibility**: DSL provides more features than old RSpec helpers
4. **Migration**: Users explicitly opt into new API (no hidden behavior changes)

## Common Use Cases to Optimize

Based on user feedback, optimize for these patterns:

1. **Quality + Regression Testing**: "I want to verify my agent's output hasn't degraded when I switch from GPT-4 to Claude"
   - Quick access to semantic_similarity + coherence + regression evaluators
   - Built-in comparison between configurations

2. **Token Efficiency**: Monitor token usage across model changes
   - token_efficiency evaluator with automatic delta calculation
   - Easy ranking by token usage to find most efficient config

3. **Multi-Dimensional Quality**: Evaluate output across multiple quality axes
   - Combine multiple evaluators with flexible AND/OR/lambda logic
   - Clear per-evaluator and combined results

## Comparison with Typical Scenarios

### Typical Comparison: 2-3 Configurations
Most users compare 2-3 configurations (A/B or A/B/C testing):
- Example: `low_temp` vs `med_temp` vs `high_temp`
- Example: `gpt-4o` vs `claude-3-5-sonnet` vs `gemini-2.5-flash`

**Design Impact**: Optimize comparison UI for small number of configs (< 5)

### Field Discovery
- **No automatic field introspection** initially
- Users must know field names from span structure documentation
- Future: Could add `evaluator.available_fields` helper

## Open Questions for Future Consideration

1. **Multi-field ranking**: Should ranking support multiple fields with weights?
   - Decision: Single-field only for MVP, add multi-field in Phase 2 if needed

2. **Cross-run comparisons**: Should comparison support historical baseline?
   - Decision: Single-run only for MVP, add cross-run in Phase 2 if needed

3. **Field introspection**: Should DSL provide `available_fields` helper?
   - Decision: Defer to Phase 2, users refer to span structure docs for MVP

4. **Evaluator dependencies**: Should evaluators run in specific order?
   - Decision: Sequential execution order matches definition order, no dependency management

5. **Conditional evaluator execution**: Run evaluator based on previous results?
   - Decision: Out of scope, use lambda combination logic for conditional behavior

## Performance Targets

Based on spec requirements:

- **Field extraction**: < 5ms for 100 fields
- **Evaluator execution**: Sequential completion (no parallel overhead)
- **Progress events**: Real-time emission without blocking evaluation
- **Historical queries**: Fast queries with proper indexing (evaluator, config, timestamp, tags)

## Documentation Priorities

Based on user needs:

1. **Complete DSL API reference** with all methods and parameters
2. **Migration guide** from RSpec matchers to evaluator types
3. **Custom evaluator creation guide** with FieldContext API
4. **Lambda combination examples** for common patterns
5. **Catalog of 22 built-in evaluators** with parameters and use cases
