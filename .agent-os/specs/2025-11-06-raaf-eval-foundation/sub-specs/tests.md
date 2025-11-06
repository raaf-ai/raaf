# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-11-06-raaf-eval-foundation/spec.md

> Created: 2025-11-06
> Version: 1.0.0

## Test Coverage

### Unit Tests

**RAAF::Eval::SpanSerializer**
- Serializes agent span with all required fields
- Serializes tool call span with arguments and results
- Serializes handoff span with target agent and context
- Handles spans with errors gracefully
- Validates completeness of serialized data
- Deserializes span back to executable form
- Preserves data types during round-trip serialization

**RAAF::Eval::SpanDeserializer**
- Reconstructs agent from serialized data
- Reconstructs messages with proper role and content
- Reconstructs tool definitions
- Reconstructs context variables
- Handles missing optional fields with defaults
- Raises error for missing required fields

**RAAF::Eval::EvaluationEngine**
- Creates new evaluation run with baseline span
- Applies model change configuration
- Applies parameter change configuration
- Applies prompt/instruction change configuration
- Applies provider change configuration
- Executes agent with modified configuration
- Captures result span with full metadata
- Handles execution failures gracefully
- Supports multiple configurations in single run

**RAAF::Eval::Metrics::TokenMetrics**
- Calculates total token count
- Calculates input/output token breakdown
- Calculates reasoning tokens for o1 models
- Estimates cost based on model pricing
- Compares tokens against baseline
- Calculates percentage change

**RAAF::Eval::Metrics::LatencyMetrics**
- Measures total execution time
- Measures time to first token
- Measures time per token
- Extracts API latency from provider
- Compares latency against baseline

**RAAF::Eval::Metrics::AccuracyMetrics**
- Calculates exact match score
- Calculates fuzzy match score
- Calculates BLEU score (using rouge gem)
- Calculates F1 score (when ground truth provided)
- Handles missing ground truth gracefully

**RAAF::Eval::Metrics::StructuralMetrics**
- Validates output format (JSON, XML, plain text)
- Checks schema compliance
- Measures output length
- Detects format violations

**RAAF::Eval::Metrics::AIComparator**
- Compares semantic similarity between baseline and result
- Scores coherence of output
- Detects hallucinations
- Identifies bias (gender, race, region)
- Assesses tone consistency
- Verifies factuality
- Provides reasoning for comparison
- Handles comparison failures with fallback

**RAAF::Eval::Metrics::StatisticalAnalyzer**
- Calculates confidence intervals for metric differences
- Performs t-test for significance
- Calculates variance and standard deviation
- Computes effect size (Cohen's d)
- Handles small sample sizes appropriately

**RAAF::Eval::Models::EvaluationRun**
- Creates evaluation run with valid attributes
- Validates status transitions
- Associates with baseline span
- Tracks started_at and completed_at timestamps
- Stores metadata in JSONB

**RAAF::Eval::Models::EvaluationSpan**
- Stores serialized span data
- Validates JSONB structure
- Supports querying by span_id
- Links to evaluation run when appropriate
- Indexes JSONB for fast queries

**RAAF::Eval::Models::EvaluationConfiguration**
- Creates configuration with changes hash
- Validates configuration_type
- Associates with evaluation run
- Orders configurations by execution_order

**RAAF::Eval::Models::EvaluationResult**
- Stores all metric categories
- Associates with run and configuration
- Tracks AI comparator status separately
- Supports baseline comparison queries
- Handles error storage

### Integration Tests

**End-to-End Evaluation Flow**
- Select production span from raaf-tracing
- Serialize span to evaluation_spans table
- Create evaluation run with 3 configurations:
  1. Different model (GPT-4 → Claude)
  2. Modified temperature (0.7 → 0.9)
  3. Modified prompt
- Execute all configurations
- Calculate all metrics (quantitative + AI comparator)
- Store results with baseline comparison
- Query results and verify completeness

**Multi-Configuration Evaluation**
- Create evaluation with 5 different configurations
- Execute configurations in specified order
- Verify each result has unique result_span_id
- Verify all metrics calculated correctly
- Verify statistical analysis across configurations

**Provider Switching**
- Serialize span from OpenAI execution
- Create configuration switching to Anthropic
- Execute with Anthropic provider
- Verify parameter mapping (temperature, max_tokens)
- Verify result completeness

**Error Handling Flow**
- Serialize span with invalid model configuration
- Execute evaluation expecting failure
- Verify error captured in evaluation_result
- Verify partial metrics still calculated
- Verify evaluation marked as failed

**AI Comparator Integration**
- Execute evaluation with baseline and result
- Trigger AI comparator asynchronously
- Wait for comparator completion
- Verify comparison metrics stored
- Verify comparison reasoning provided
- Handle comparator failure gracefully

**Statistical Analysis**
- Execute evaluation with 10 configurations
- Calculate aggregate statistics
- Verify confidence intervals computed
- Verify significance tests performed
- Verify variance reported

### Feature Tests

**Span Serialization and Reproduction**
- Given a RAAF agent execution in production
- When I serialize the span
- Then I can reproduce the exact execution in test environment
- And the output matches original (within stochastic variance)

**Configuration Comparison Workflow**
- Given a serialized baseline span
- When I create evaluation with model A and model B
- Then both models execute with same inputs
- And I receive side-by-side metrics comparison
- And statistical significance is reported

**Regression Detection**
- Given a baseline evaluation result
- When I run new evaluation with code changes
- Then system detects if performance degraded
- And flags regressions in baseline_comparison
- And provides detailed regression report

**Bias Detection**
- Given an agent that processes user demographics
- When I run evaluation across multiple demographic groups
- Then bias metrics identify disparities
- And report bias scores for gender, race, region
- And flag potential compliance issues

**Custom Metrics**
- Given a domain-specific metric definition
- When I register the metric with evaluation engine
- Then metric is calculated for all evaluations
- And stored in custom_metrics JSONB
- And available for querying and reporting

### Mocking Requirements

**LLM Provider APIs**
- Mock OpenAI API responses for deterministic testing
- Mock Anthropic API responses with known outputs
- Mock Groq API responses for performance testing
- Use VCR cassettes for recording real API interactions
- Support both successful and error responses

**RAAF Tracing System**
- Mock `RAAF::Tracing::SpanTracer` for span queries
- Provide fixture spans for different scenarios:
  - Simple agent execution
  - Agent with multiple tool calls
  - Multi-turn conversation
  - Handoff between agents
  - Execution with errors
- Mock span processors and exporters

**Time and Randomness**
- Use `Timecop` for consistent timestamp testing
- Mock `SecureRandom` for predictable IDs
- Control stochastic model outputs for reproducibility

**Database**
- Use FactoryBot for test data generation
- Use DatabaseCleaner for test isolation
- Provide realistic fixture data for spans

## Performance Testing

**Span Serialization Performance**
- Benchmark serialization of 1000 spans
- Target: < 100ms per span average
- Measure memory usage during serialization

**Evaluation Execution Performance**
- Benchmark evaluation with 10 configurations
- Target: Baseline execution time + < 10% overhead per config
- Measure parallel vs sequential execution

**Metrics Calculation Performance**
- Benchmark all quantitative metrics on 100 results
- Target: < 500ms total for quantitative metrics
- Benchmark AI comparator on 10 results
- Target: < 5s per comparison

**Database Query Performance**
- Benchmark recent evaluations query (1000 runs)
- Target: < 100ms
- Benchmark JSONB filtering queries
- Target: < 1s for complex filters
- Verify GIN indexes are used (EXPLAIN ANALYZE)

## Test Data Factories

**Factory: evaluation_run**
```ruby
factory :evaluation_run, class: 'RAAF::Eval::Models::EvaluationRun' do
  name { "Test Evaluation #{SecureRandom.hex(4)}" }
  description { "Testing agent behavior changes" }
  status { "pending" }
  baseline_span_id { SecureRandom.uuid }
  initiated_by { "test_user" }
  metadata { { tags: ["test"], version: "1.0" } }
end
```

**Factory: evaluation_span**
```ruby
factory :evaluation_span, class: 'RAAF::Eval::Models::EvaluationSpan' do
  span_id { SecureRandom.uuid }
  trace_id { SecureRandom.uuid }
  span_type { "agent" }
  source { "production_trace" }
  span_data do
    {
      agent_name: "TestAgent",
      model: "gpt-4o",
      instructions: "You are a test assistant",
      input_messages: [{ role: "user", content: "Hello" }],
      output_messages: [{ role: "assistant", content: "Hi there!" }],
      metadata: { tokens: 50, latency_ms: 1000 }
    }
  end
end
```

**Factory: evaluation_configuration**
```ruby
factory :evaluation_configuration, class: 'RAAF::Eval::Models::EvaluationConfiguration' do
  association :evaluation_run
  name { "Model Change Test" }
  configuration_type { "model_change" }
  changes { { model: "claude-3-5-sonnet-20241022", provider: "anthropic" } }
  execution_order { 0 }
end
```

**Factory: evaluation_result**
```ruby
factory :evaluation_result, class: 'RAAF::Eval::Models::EvaluationResult' do
  association :evaluation_run
  association :evaluation_configuration
  result_span_id { SecureRandom.uuid }
  status { "completed" }
  token_metrics { { total: 100, input: 50, output: 50, cost: 0.002 } }
  latency_metrics { { total_ms: 1500, ttft_ms: 200 } }
  baseline_comparison { { token_delta: { absolute: 10, percentage: 10.0 } } }
end
```

## Coverage Goals

- **Unit Test Coverage:** 95%+ for core classes
- **Integration Test Coverage:** 90%+ for workflows
- **Feature Test Coverage:** All user stories from spec.md
- **Performance Tests:** All critical paths benchmarked
- **Mock Coverage:** All external dependencies mocked

## Continuous Integration

- Run full test suite on every commit
- Run performance benchmarks on main branch merges
- Report coverage to SimpleCov
- Fail build if coverage drops below threshold
- Run RuboCop linting alongside tests
