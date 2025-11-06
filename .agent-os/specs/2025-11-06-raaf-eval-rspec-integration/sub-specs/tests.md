# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-11-06-raaf-eval-rspec-integration/spec.md

> Created: 2025-11-06
> Version: 1.0.0

## Test Coverage

### Unit Tests

**RAAF::Eval::RSpec::Helpers**
- Includes evaluation DSL methods in RSpec examples
- Provides `evaluate_span` method
- Provides `with_configuration` method
- Provides `with_configurations` method
- Provides `run_evaluation` method
- Provides access to evaluation results
- Works with RSpec `let` and `subject` helpers
- Properly scopes variables within examples

**RAAF::Eval::RSpec::DSL**
- Parses block-based evaluation definitions
- Validates span selection (span_id, span object, or latest_span)
- Stores configuration definitions
- Supports named configurations
- Handles async execution flag
- Provides evaluation builder interface
- Raises clear errors for invalid syntax

**RAAF::Eval::RSpec::EvaluationRunner**
- Executes evaluation using Phase 1 engine
- Handles synchronous execution
- Handles asynchronous execution with result waiting
- Returns structured result object
- Caches results within same example
- Handles evaluation failures gracefully
- Integrates with RSpec progress reporting

### Matcher Unit Tests

**Quality Matchers:**

**maintain_quality matcher**
- Passes when semantic similarity above threshold
- Fails with clear message when quality drops
- Supports custom threshold: `maintain_quality.within(0.85)`
- Works across all configurations
- Compares against baseline by default

**have_similar_output_to matcher**
- Compares outputs using AI comparator
- Supports comparison to baseline: `have_similar_output_to(:baseline)`
- Supports comparison to other config: `have_similar_output_to(:gpt4)`
- Provides similarity score in failure message
- Handles missing comparison target gracefully

**have_coherent_output matcher**
- Checks coherence score from AI comparator
- Passes when coherence above threshold (default 0.8)
- Supports custom threshold: `have_coherent_output.above(0.9)`
- Provides coherence score in failure message

**not_hallucinate matcher**
- Checks hallucination detection from AI comparator
- Passes when no hallucination detected
- Fails with explanation when hallucination found
- Provides detected hallucinations in failure message

**Performance Matchers:**

**use_tokens matcher**
- Compares token usage with chained modifiers
- `use_tokens.within(10).percent_of(:baseline)` - Percentage comparison
- `use_tokens.less_than(1000)` - Absolute comparison
- `use_tokens.between(500, 1500)` - Range comparison
- Provides actual vs expected in failure message
- Shows percentage difference

**complete_within matcher**
- Checks latency against threshold
- `complete_within(2).seconds` - Duration check
- `complete_within(500).milliseconds` - Millisecond precision
- Provides actual latency in failure message
- Compares to baseline latency

**cost_less_than matcher**
- Checks cost against ceiling
- `cost_less_than(0.01)` - Dollar amount
- Calculates cost from token usage and model pricing
- Provides actual cost in failure message
- Shows cost comparison to baseline

**Regression Matchers:**

**not_have_regressions matcher**
- Checks baseline_comparison for regression flag
- Passes when no regressions detected
- Fails with list of detected regressions
- Supports severity filtering: `not_have_regressions.of_severity(:high)`
- Provides regression details in failure message

**perform_better_than matcher**
- Compares quality metrics against target
- `perform_better_than(:baseline)` - Baseline comparison
- `perform_better_than(:gpt4)` - Configuration comparison
- Checks multiple quality dimensions
- Provides improvement/degradation breakdown

**have_acceptable_variance matcher**
- Checks statistical variance from baseline
- `have_acceptable_variance.within(2).standard_deviations`
- Uses statistical analysis from Phase 1
- Provides variance statistics in failure message

**Safety Matchers:**

**not_have_bias matcher**
- Checks bias detection from AI comparator
- `not_have_bias` - All bias types
- `not_have_bias.for_gender` - Specific type
- `not_have_bias.for_race` - Specific type
- `not_have_bias.for_region` - Specific type
- Provides detected bias details in failure message

**be_safe matcher**
- Checks toxicity and safety metrics
- Passes when toxicity score below threshold
- Supports custom threshold: `be_safe.with_toxicity_below(0.1)`
- Provides safety score in failure message

**comply_with_policy matcher**
- Checks policy alignment from AI comparator
- `comply_with_policy` - General compliance
- `comply_with_policy.for(:data_privacy)` - Specific policy
- Provides policy violation details in failure message

**Statistical Matchers:**

**be_statistically_significant matcher**
- Checks p-value from statistical analysis
- `be_statistically_significant` - Default p < 0.05
- `be_statistically_significant.at_level(0.01)` - Custom threshold
- Provides p-value in failure message

**have_effect_size matcher**
- Checks Cohen's d from statistical analysis
- `have_effect_size.of(0.5)` - Medium effect
- `have_effect_size.above(0.8)` - Large effect minimum
- Provides actual effect size in failure message

**have_confidence_interval matcher**
- Checks confidence interval bounds
- `have_confidence_interval.within(-10, 10)` - Range check
- Provides actual CI in failure message

**LLM-Powered Matchers:**

**satisfy_llm_check matcher**
- Calls LLM judge with natural language prompt
- Passes when judge confirms assertion
- Fails with judge's reasoning
- Supports custom judge model: `satisfy_llm_check(prompt).using_model("o1-preview")`
- Supports confidence threshold: `satisfy_llm_check(prompt).with_confidence(0.9)`
- Caches judge results within test run
- Provides judge reasoning in failure message

**satisfy_llm_criteria matcher**
- Evaluates multiple criteria in single judge call
- Array format: `satisfy_llm_criteria(["criterion1", "criterion2"])`
- Hash format with weights: `satisfy_llm_criteria(accuracy: { weight: 2.0, description: "..." })`
- Passes when all criteria pass (or weighted threshold met)
- Fails with per-criterion results and reasoning
- Optimizes cost by batching criteria
- Provides detailed breakdown in failure message

**be_judged_as matcher**
- Most flexible matcher for qualitative judgments
- `be_judged_as("better than baseline")` - Subjective comparison
- `be_judged_as("appropriate for audience")` - Quality assessment
- `be_judged_as("more concise").than(:claude)` - Configuration comparison
- Provides judge reasoning in both pass and fail cases
- Useful for brand voice, tone, style checks

**Structural Matchers:**

**have_valid_format matcher**
- Checks structural metrics from Phase 1
- `have_valid_format` - Format validation passed
- `have_valid_format.as(:json)` - Specific format
- Provides format errors in failure message

**match_schema matcher**
- Validates output against JSON schema
- `match_schema(schema_hash)` - Schema validation
- Provides schema violation details in failure message

**have_length matcher**
- Checks output length
- `have_length.between(100, 500)` - Character range
- `have_length.less_than(1000)` - Maximum
- Provides actual length in failure message

### Integration Tests

**RSpec Configuration Integration**
- Include RAAF::Eval::RSpec in global RSpec config
- Auto-include for files in spec/evaluations/
- Tag evaluation tests with `:evaluation` metadata
- Run only evaluation tests with `--tag evaluation`
- Exclude evaluation tests with `--tag ~evaluation`

**End-to-End Evaluation Test**
- Define evaluation using block DSL
- Add multiple configurations
- Run evaluation synchronously
- Assert with multiple matchers
- All matchers pass or fail correctly
- RSpec reports results properly

**Async Evaluation Test**
- Define evaluation with async flag
- Configurations run in parallel
- Results aggregated correctly
- Matchers wait for completion
- Progress reported during execution

**Multi-Configuration Test**
- Define 5+ configurations
- Run evaluation
- Compare across all configurations
- Use `across_all_configurations` matcher
- Individual configuration assertions work
- Cross-configuration assertions work

**CI/CD Integration Test**
- Run evaluation test in non-interactive mode
- Exit codes correct (0 = pass, 1 = fail)
- JUnit XML output generated correctly
- JSON output generated correctly
- TAP output generated correctly

**Parallel Execution Test**
- Run multiple evaluation tests with `--parallel`
- Each test gets isolated evaluation engine
- Database connections handled correctly
- Results don't conflict between tests
- All tests complete successfully

**Factory Integration Test**
- Use FactoryBot to create test span
- Define evaluation with factory span
- Run evaluation
- Results stored correctly
- Matchers work with factory data

### Feature Tests

**Write Simple Evaluation Test**
- Given a production agent span
- When I write RSpec test with evaluation DSL
- And use matchers for quality and performance
- Then test runs and asserts correctly
- And I get clear pass/fail feedback

**Compare Multiple Models**
- Given a baseline span
- When I define configurations for 3 different models
- And run evaluation with async execution
- Then all models execute in parallel
- And I can assert on each model's results
- And compare models against each other

**Detect Quality Regression**
- Given a baseline with known good output
- When I modify agent prompt/parameters
- And run evaluation test
- Then test detects quality degradation
- And fails with clear regression details
- And provides suggestions for investigation

**CI/CD Pipeline Execution**
- Given evaluation tests in spec/evaluations/
- When CI pipeline runs `rspec --tag evaluation`
- Then all evaluations execute
- And results reported in CI-friendly format
- And pipeline fails if assertions fail
- And pipeline succeeds if assertions pass

**Use Custom Domain Metric**
- Given a custom metric from Phase 1
- When I write matcher for custom metric
- And use matcher in evaluation test
- Then custom metric calculated
- And matcher assertions work correctly

**Use LLM Judge for Natural Language Assertion**
- Given an evaluation result
- When I write test with `satisfy_llm_check("Response is professional")`
- And run evaluation test
- Then LLM judge evaluates the assertion
- And test passes/fails based on judge's verdict
- And judge's reasoning is displayed in output

**Multi-Criteria LLM Evaluation**
- Given an evaluation result
- When I use `satisfy_llm_criteria` with multiple criteria
- And run evaluation test
- Then all criteria evaluated in single judge call
- And per-criterion results reported
- And test passes only if all criteria pass

### Performance Tests

**DSL Parsing Performance**
- Parse 100 evaluation definitions
- Target: < 10ms total (< 0.1ms each)

**Matcher Execution Performance**
- Execute 100 matcher assertions
- Target: < 1000ms total (< 10ms each)

**Parallel Evaluation Performance**
- Run 10 configurations in parallel vs sequential
- Target: < 2x slowdown (ideally 1.5x for 10 configs)

**CI/CD Overhead**
- Measure RSpec startup and teardown overhead
- Target: < 500ms overhead for evaluation tests

## Test Data Factories

**Factory: evaluation_test_span**
```ruby
FactoryBot.define do
  factory :evaluation_test_span, class: 'RAAF::Eval::Models::EvaluationSpan' do
    span_id { SecureRandom.uuid }
    trace_id { SecureRandom.uuid }
    span_type { "agent" }
    source { "test" }
    span_data do
      {
        agent_name: "TestAgent",
        model: "gpt-4o",
        instructions: "Test instructions",
        input_messages: [
          { role: "user", content: "Test input" }
        ],
        output_messages: [
          { role: "assistant", content: "Test output" }
        ],
        metadata: {
          tokens: { total: 100, input: 50, output: 50 },
          latency_ms: 1000,
          cost: 0.002
        }
      }
    end
  end
end
```

**Factory: evaluation_test_result**
```ruby
FactoryBot.define do
  factory :evaluation_test_result do
    span { association :evaluation_test_span }

    token_metrics do
      { total: 100, input: 50, output: 50, cost: 0.002 }
    end

    latency_metrics do
      { total_ms: 1000, ttft_ms: 200 }
    end

    ai_comparison do
      {
        semantic_similarity: 0.90,
        coherence_score: 0.88,
        hallucination_detected: false,
        bias_detected: { gender: false, race: false }
      }
    end

    baseline_comparison do
      {
        token_delta: { absolute: 0, percentage: 0.0 },
        regression_detected: false
      }
    end
  end
end
```

## Mocking Requirements

**Phase 1 Evaluation Engine**
- Mock `RAAF::Eval::EvaluationEngine` for fast test execution
- Provide fixture evaluation results
- Support both success and failure scenarios
- Mock async execution with immediate completion

**RSpec Internals**
- Mock RSpec example context for matcher tests
- Provide fake example groups
- Mock RSpec configuration
- Mock RSpec reporter for progress tests

**Database**
- Use in-memory SQLite for fast tests
- Or use FactoryBot with DatabaseCleaner
- Provide realistic test data
- Isolate tests from each other

## Coverage Goals

- **Unit Test Coverage:** 95%+ for RSpec integration code
- **Matcher Coverage:** 100% for all custom matchers
- **Integration Coverage:** All user stories and DSL patterns
- **Feature Coverage:** All common evaluation patterns
- **Documentation Coverage:** Every matcher and DSL method with examples

## CI/CD Testing Strategy

- Run RSpec integration tests in GitHub Actions
- Test against RSpec 3.11, 3.12, 3.13
- Test against Ruby 3.2, 3.3, 3.4
- Test parallel execution in CI
- Test output formats (JUnit, JSON, TAP)
- Generate coverage reports
- Verify matcher documentation examples
