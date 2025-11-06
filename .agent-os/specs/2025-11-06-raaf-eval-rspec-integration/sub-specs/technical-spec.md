# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-11-06-raaf-eval-rspec-integration/spec.md

> Created: 2025-11-06
> Version: 1.0.0

## Technical Requirements

### RSpec Integration Requirements

- Provide `RAAF::Eval::RSpec` module that can be included in RSpec configuration
- Auto-include module in `spec/evaluations/**/*_spec.rb` files
- Provide `spec_helper` configuration example
- Support RSpec 3.x metadata for tagging evaluation tests (`:evaluation` tag)
- Enable running only evaluation tests: `rspec --tag evaluation`
- Compatible with RSpec's `let`, `before`, `after`, `subject` helpers

### Evaluation DSL Requirements

**Core DSL Methods:**

```ruby
# Select span for evaluation
evaluate_span("span_id_123")
evaluate_span(span: span_object)
evaluate_latest_span(agent: "MyAgent")

# Define configuration variants
with_configuration(name: "GPT-4 High Temp", model: "gpt-4o", temperature: 0.9)
with_configurations([
  { name: "GPT-4", model: "gpt-4o" },
  { name: "Claude", model: "claude-3-5-sonnet-20241022", provider: "anthropic" }
])

# Execute evaluation
run_evaluation
run_evaluation(async: true)  # For CI parallelization

# Access results
evaluation_result           # Current evaluation result
baseline_result            # Original span result
configuration_results      # Hash of results by configuration name
```

**Declarative DSL Example:**

```ruby
RSpec.describe "MyAgent Evaluation" do
  let(:baseline_span) { RAAF::Eval.find_span("span_123") }

  evaluation do
    span baseline_span

    configuration :gpt4, model: "gpt-4o", temperature: 0.7
    configuration :claude, model: "claude-3-5-sonnet-20241022", provider: "anthropic"
    configuration :high_temp, model: "gpt-4o", temperature: 0.9

    run_async true  # Parallel execution
  end

  it "maintains quality across models" do
    expect(evaluation).to maintain_quality
    expect(evaluation[:gpt4]).to have_similar_output_to(:baseline)
    expect(evaluation[:claude]).to have_similar_output_to(:baseline)
  end
end
```

### Custom Matchers Requirements

All matchers should:
- Provide clear failure messages with actual vs expected values
- Support chaining (e.g., `within(10).percent`)
- Work with both singular results and configuration comparisons
- Include detailed explanations in failure output

**Required Matchers:**

1. **Quality Matchers:**
   - `maintain_quality` - Semantic similarity within threshold
   - `have_similar_output_to(target)` - Compare outputs
   - `have_coherent_output` - Coherence score above threshold
   - `not_hallucinate` - No hallucination detected

2. **Performance Matchers:**
   - `use_tokens.within(N).percent_of(target)` - Token usage comparison
   - `complete_within(N).seconds` - Latency threshold
   - `cost_less_than(amount)` - Cost ceiling

3. **Regression Matchers:**
   - `not_have_regressions` - No baseline degradation
   - `perform_better_than(:baseline)` - Quality improvement
   - `have_acceptable_variance` - Within statistical bounds

4. **Safety Matchers:**
   - `not_have_bias` - No demographic bias detected
   - `be_safe` - Toxicity/safety checks pass
   - `comply_with_policy` - Policy alignment validated

5. **Statistical Matchers:**
   - `be_statistically_significant` - P-value below threshold
   - `have_effect_size.of(N)` - Cohen's d threshold
   - `have_confidence_interval.within(min, max)` - CI bounds

6. **Structural Matchers:**
   - `have_valid_format` - Output format compliance
   - `match_schema(schema)` - JSON/structure validation
   - `have_length.between(min, max)` - Output length bounds

7. **LLM-Powered Matchers:**
   - `satisfy_llm_check(prompt)` - Natural language assertion using LLM judge
   - `satisfy_llm_criteria(criteria)` - Multi-criteria LLM evaluation
   - `be_judged_as(description)` - Flexible LLM-based quality check

### LLM-Powered Matcher Requirements

The LLM-powered matchers use an AI judge to evaluate outputs based on natural language criteria. This provides maximum flexibility for assertions that are hard to code precisely.

**Core Implementation:**
- Use dedicated "Judge" agent from Phase 1 AI comparator infrastructure
- Accept natural language assertion descriptions
- Return pass/fail with detailed reasoning
- Support configuration of judge model (default: gpt-4o for accuracy)
- Cache judge results to avoid redundant API calls

**satisfy_llm_check(prompt) Matcher:**

```ruby
# Simple natural language assertion
expect(result).to satisfy_llm_check("The response is polite and professional")
expect(result).to satisfy_llm_check("No medical advice is provided")
expect(result).to satisfy_llm_check("The answer stays on topic and doesn't ramble")

# With custom judge model
expect(result).to satisfy_llm_check("Complex reasoning is sound").using_model("o1-preview")

# With custom threshold for confidence
expect(result).to satisfy_llm_check("Response is helpful").with_confidence(0.9)
```

**Implementation Details:**
- Sends baseline output and result output to judge agent
- Judge evaluates: "Does the output satisfy: [PROMPT]?"
- Returns: pass/fail, confidence score (0.0-1.0), reasoning
- Failure message includes judge's reasoning for debugging

**satisfy_llm_criteria(criteria) Matcher:**

```ruby
# Multi-criteria evaluation
expect(result).to satisfy_llm_criteria([
  "Response is accurate and factual",
  "Tone is appropriate for the audience",
  "No unnecessary jargon is used",
  "Examples are clear and relevant"
])

# With custom weights
expect(result).to satisfy_llm_criteria(
  accuracy: { weight: 2.0, description: "Response is factually correct" },
  clarity: { weight: 1.5, description: "Explanation is clear" },
  conciseness: { weight: 1.0, description: "Response is concise" }
)
```

**Implementation Details:**
- Evaluates multiple criteria in single judge call (cost optimization)
- Each criterion gets pass/fail + reasoning
- Overall pass requires all criteria to pass (or weighted threshold)
- Failure message lists which criteria failed with reasons

**be_judged_as(description) Matcher:**

```ruby
# Flexible quality assessment
expect(result).to be_judged_as("better than the baseline")
expect(result).to be_judged_as("appropriate for a technical audience")
expect(result).to be_judged_as("consistent with brand voice guidelines")

# Comparing two configurations
expect(evaluation[:gpt4]).to be_judged_as("more concise").than(:claude)
```

**Implementation Details:**
- Most flexible matcher for subjective quality judgments
- Can compare against baseline or other configurations
- Judge provides qualitative assessment with reasoning
- Useful for aspects that are hard to quantify

**Configuration Options:**

```ruby
# Global configuration in spec_helper.rb
RAAF::Eval::RSpec.configure do |config|
  config.llm_judge_model = "gpt-4o"  # Default judge model
  config.llm_judge_temperature = 0.3  # Lower for consistency
  config.llm_judge_cache = true      # Cache judge results
  config.llm_judge_timeout = 30      # Seconds
end

# Per-test configuration
RSpec.describe "MyTest", :evaluation do
  around(:each) do |example|
    RAAF::Eval::RSpec.with_judge_config(model: "o1-preview") do
      example.run
    end
  end
end
```

**Cost Optimization:**
- Cache judge results within same test run
- Batch multiple criteria into single judge call
- Use cheaper models for simple checks (gpt-4o-mini)
- Provide cost estimates in test output

**Error Handling:**
- Retry judge calls once on failure
- Gracefully degrade if judge unavailable (mark test as pending with warning)
- Log all judge reasoning for debugging
- Provide clear error messages if judge contradicts itself

### Parallel Execution Requirements

- Support RSpec's `--parallel` flag for concurrent test execution
- Use thread-safe evaluation engine from Phase 1
- Distribute configuration evaluations across threads/processes
- Aggregate results correctly from parallel workers
- Handle database connection pooling for parallel tests
- Report progress in parallel mode

### CI/CD Integration Requirements

- Exit with proper status codes (0 = pass, 1 = fail)
- Support JUnit XML output format: `--format RspecJunitFormatter`
- Support JSON output format: `--format json`
- Support TAP (Test Anything Protocol) format
- Work with GitHub Actions, GitLab CI, Jenkins, CircleCI
- Provide CI-specific configuration examples
- Handle timeout configuration for long-running evaluations
- Support fail-fast mode for quick feedback

## Approach Options

### Option A: Monkey-patch RSpec Core (Not Selected)

Extend RSpec's core classes to add evaluation methods.

**Pros:**
- Deep integration with RSpec
- Can hook into RSpec lifecycle everywhere

**Cons:**
- Fragile, breaks with RSpec updates
- Hard to maintain
- Violates encapsulation
- Could conflict with other extensions

### Option B: Custom Module with Explicit Include (Selected)

Provide module that must be explicitly included in spec files or globally configured.

**Pros:**
- Clean, explicit integration
- No monkey-patching
- Easy to maintain and test
- Works with RSpec conventions
- Compatible with future RSpec versions

**Cons:**
- Requires user configuration
- Slightly more setup than automatic

**Rationale:** Explicit module inclusion follows Ruby and RSpec best practices, provides maintainability, and avoids fragile monkey-patching. The minor setup cost is worth the stability and clarity.

### Option C: RSpec Custom Formatter (Not Selected)

Implement as RSpec formatter that runs alongside tests.

**Pros:**
- Non-invasive
- Easy to enable/disable

**Cons:**
- Limited access to test context
- Can't provide DSL methods
- Awkward for defining evaluations
- Doesn't fit the use case

**Rationale:** Formatters are for output formatting, not for defining test behavior. This approach would be fighting RSpec's architecture.

## DSL Design Patterns

### Pattern 1: Block-Based DSL (Selected)

```ruby
evaluation do
  span baseline_span
  configuration :gpt4, model: "gpt-4o"
  configuration :claude, model: "claude-3-5-sonnet"
end
```

**Pros:**
- Clean, declarative syntax
- Familiar Ruby idiom
- Easy to read and maintain
- Supports validation

**Cons:**
- Slightly more verbose
- Block scope considerations

### Pattern 2: Method Chaining

```ruby
evaluate_span(span).
  with_config(:gpt4, model: "gpt-4o").
  with_config(:claude, model: "claude-3-5-sonnet").
  run
```

**Pros:**
- Compact
- Fluent interface

**Cons:**
- Harder to read with many options
- Less declarative
- Awkward error handling

**Rationale:** Block-based DSL is more readable for complex evaluations and follows Ruby DSL conventions (like RSpec itself).

## External Dependencies

### New Dependencies

**rspec-expectations (~> 3.0)**
- Purpose: Base for custom matchers
- Justification: Already a transitive dependency, provides matcher DSL
- License: MIT (compatible)

**parallel_tests (~> 4.0)** (optional)
- Purpose: Parallel RSpec execution
- Justification: Industry standard for parallel RSpec, well-maintained
- License: MIT (compatible)
- Note: Optional - provides enhanced parallel support beyond RSpec's built-in

**rspec-junit-formatter (~> 0.6)** (optional, dev dependency)
- Purpose: JUnit XML output for CI/CD
- Justification: Standard for CI integration, widely used
- License: MIT (compatible)
- Note: Optional - for users who want JUnit output

### Integration Dependencies

**raaf-eval (Phase 1)**
- Purpose: Core evaluation engine, metrics, and storage
- Justification: Phase 2 builds directly on Phase 1 foundation
- Required: Yes

**factory_bot_rails (~> 6.0)** (optional, dev dependency)
- Purpose: Test data generation for evaluation tests
- Justification: Standard Rails testing tool, familiar to users
- License: MIT (compatible)
- Note: Optional - provides test helpers

## Performance Considerations

### Parallel Execution Strategy

- Use RSpec's built-in `--parallel` support as baseline
- Enhance with `parallel_tests` gem for advanced scenarios
- Distribute configuration evaluations across workers
- Share database connections via connection pool
- Use Redis/Memcached for cross-process result sharing (if needed)
- Target: N configurations in ~1.2x single configuration time (with N workers)

### Matcher Performance

- Lazy-load evaluation results (don't run until matcher executes)
- Cache metric calculations within same example
- Avoid redundant baseline comparisons
- Target: < 10ms overhead per matcher execution

### CI/CD Optimization

- Provide `--fail-fast` integration to stop on first failure
- Support incremental evaluation (run only changed agents)
- Enable result caching for unchanged configurations
- Provide `--only-failed` support for re-running failures

## Error Handling

### Evaluation Failures

- Distinguish between test failures and evaluation errors
- Test failure: Matcher expectation not met (normal test failure)
- Evaluation error: Span serialization failed, execution crashed, etc.
- Report evaluation errors clearly with debugging context

### Matcher Failures

- Provide detailed failure messages with:
  - Expected value/behavior
  - Actual value/behavior
  - Difference/delta
  - Debugging tips
- Example: "Expected token usage within 10% of baseline (500 tokens), but got 650 tokens (30% increase). Check if prompt changes added unnecessary verbosity."

### CI/CD Error Handling

- Timeout handling for long-running evaluations
- Graceful degradation if metrics unavailable
- Retry logic for transient API failures
- Clear error messages in CI logs

## Security Considerations

- Inherit PII redaction from raaf-eval Phase 1
- Sanitize span data in test output
- Don't expose API keys in test logs or failures
- Validate configuration inputs to prevent injection

## Example Usage Patterns

### Simple Evaluation Test

```ruby
RSpec.describe "SearchAgent Evaluation", :evaluation do
  let(:baseline_span) { RAAF::Eval.latest_span(agent: "SearchAgent") }

  it "maintains quality with higher temperature" do
    result = evaluate_span(baseline_span)
      .with_configuration(temperature: 0.9)
      .run

    expect(result).to maintain_quality
    expect(result).to use_tokens.within(20).percent_of(:baseline)
  end
end
```

### Multi-Configuration Comparison

```ruby
RSpec.describe "ResearchAgent Model Comparison", :evaluation do
  evaluation do
    span latest_span_for("ResearchAgent")

    configuration :gpt4, model: "gpt-4o"
    configuration :claude, model: "claude-3-5-sonnet-20241022"
    configuration :gemini, model: "gemini-pro", provider: "gemini"

    run_async true
  end

  it "all models maintain quality" do
    expect(evaluation).to maintain_quality.across_all_configurations
  end

  it "Claude is fastest" do
    expect(evaluation[:claude]).to complete_faster_than(:gpt4)
    expect(evaluation[:claude]).to complete_faster_than(:gemini)
  end

  it "GPT-4 uses fewer tokens" do
    expect(evaluation[:gpt4]).to use_fewer_tokens_than(:claude)
  end
end
```

### Regression Detection

```ruby
RSpec.describe "AgentBehaviorRegression", :evaluation do
  let(:baseline) { RAAF::Eval.find_span("production_span_abc123") }

  context "after prompt changes" do
    let(:new_instructions) { "Updated prompt with additional context..." }

    it "doesn't regress on quality" do
      result = evaluate_span(baseline)
        .with_configuration(instructions: new_instructions)
        .run

      expect(result).not_to have_regressions
      expect(result).to maintain_quality
      expect(result).to have_similar_output_to(:baseline)
    end
  end
end
```

### CI/CD Integration Example

```yaml
# .github/workflows/evaluations.yml
name: Agent Evaluations

on: [push, pull_request]

jobs:
  evaluations:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
      - name: Install dependencies
        run: bundle install
      - name: Run evaluations
        run: bundle exec rspec spec/evaluations/ --tag evaluation --format RspecJunitFormatter --out evaluations.xml
      - name: Publish results
        uses: mikepenz/action-junit-report@v3
        with:
          report_paths: 'evaluations.xml'
```
