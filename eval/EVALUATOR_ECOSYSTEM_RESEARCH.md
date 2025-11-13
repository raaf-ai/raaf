# RAAF Eval Evaluator Ecosystem Research Report

**Date:** 2025-11-13  
**Researcher:** Claude Code  
**Focus:** Current evaluator types, extension points, and taxonomy

---

## Executive Summary

RAAF Eval provides a comprehensive evaluator ecosystem with **40+ custom RSpec matchers** organized into **7 major categories**:

1. **Quality Matchers** (4 evaluators)
2. **Performance Matchers** (3 evaluators)
3. **Regression Matchers** (3 evaluators)
4. **Safety Matchers** (3 evaluators)
5. **Statistical Matchers** (3 evaluators)
6. **Structural Matchers** (3 evaluators)
7. **LLM-Powered Matchers** (3 evaluators)

**Total Matchers:** 22 core matchers with chainable configuration methods for fine-grained assertions.

---

## Part 1: Existing Evaluator Types & Architecture

### Base Matcher Interface

**Location:** `eval/lib/raaf/eval/rspec/matchers/base.rb`

All matchers inherit from the `Base` module which provides:

```ruby
module RAAF::Eval::RSpec::Matchers::Base
  # Extract output from evaluation result or hash
  def extract_output(result)
    case result
    when EvaluationResult
      result.baseline_output
    when Hash
      result[:output] || result.dig(:metadata, :output) || ""
    else
      result.to_s
    end
  end

  # Extract usage stats (tokens, costs, etc.)
  def extract_usage(result)
    case result
    when EvaluationResult
      result.baseline_usage
    when Hash
      result[:usage] || result.dig(:metadata, :usage) || {}
    else
      {}
    end
  end

  # Extract latency in milliseconds
  def extract_latency(result)
    case result
    when EvaluationResult
      result.baseline_latency
    when Hash
      result[:latency_ms] || 0
    else
      0
    end
  end

  # Formatting helpers
  def format_percent(value)
    format("%.2f%%", value)
  end

  def format_number(value)
    value.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end
end
```

**Key Design Patterns:**
- Polymorphic result handling (EvaluationResult vs Hash)
- Safe navigation with fallback values
- Formatting utilities for human-readable output
- No business logic—just data extraction and formatting

### Matcher Registration Pattern

**Location:** `eval/lib/raaf/eval/rspec/matchers.rb`

Matchers are registered with RSpec's DSL using `define` blocks:

```ruby
::RSpec::Matchers.define :matcher_name do |*args|
  include CategoryMatchers::MatcherModule
  # Initialize instance variables from args
  @var = arg
end
```

**Auto-inclusion in RSpec:**
```ruby
::RSpec.configure do |config|
  config.include RAAF::Eval::RSpec::Matchers
end
```

This makes all matchers available in any RSpec test without explicit imports.

---

## Part 2: Complete Evaluator Taxonomy (22 Core Matchers)

### 1. QUALITY MATCHERS (4)

**Module:** `QualityMatchers`

#### 1.1 `maintain_quality`
- **Purpose:** Verify output quality stays within acceptable threshold
- **Interface:**
  ```ruby
  expect(result).to maintain_quality.within(20).percent
  expect(result).to maintain_quality.within(20).percent.across_all_configurations
  ```
- **Method Chain:** `.within(percent)`, `.across_all_configurations`
- **Algorithm:** Semantic similarity comparison (0.0-1.0 scale)
- **Default Threshold:** 0.7 (70% similarity required)

#### 1.2 `have_similar_output_to`
- **Purpose:** Compare output to a target (baseline or other result)
- **Interface:**
  ```ruby
  expect(result).to have_similar_output_to(:baseline).within(20).percent
  expect(result).to have_similar_output_to(other_result).within(15).percent
  expect(result).to have_similar_output_to("expected text").within(10).percent
  ```
- **Targets:** `:baseline` symbol, other result name, string literal, Hash/object
- **Default Threshold:** 0.7

#### 1.3 `have_coherent_output`
- **Purpose:** Verify output demonstrates coherence
- **Interface:**
  ```ruby
  expect(result).to have_coherent_output.with_threshold(0.75)
  ```
- **Measurement Method:** Simplified NLP scoring:
  - Base 0.5 score
  - +0.2 if multiple sentences detected
  - +0.3 × (unique_words/total_words) ratio
  - Capped at 1.0
- **Default Threshold:** 0.7

#### 1.4 `not_hallucinate`
- **Purpose:** Detect common hallucination indicators
- **Interface:**
  ```ruby
  expect(result).to not_hallucinate
  ```
- **Detection Patterns:**
  - `/I apologize, but I (don't have|cannot)/i`
  - `/As an AI/i`
  - `/I (don't|do not) actually (know|have access)/i`
- **Limitation:** Pattern-based, not semantic hallucination detection

---

### 2. PERFORMANCE MATCHERS (3)

**Module:** `PerformanceMatchers`

#### 2.1 `use_tokens`
- **Purpose:** Assert token usage stays within bounds
- **Interface:**
  ```ruby
  expect(result).to use_tokens.less_than(5000)
  expect(result).to use_tokens.between(100, 1000)
  expect(result).to use_tokens.percent_of(:baseline).within(10)
  expect(result).to use_tokens.percent_of(gpt4_result).within(5)
  expect(result).to use_tokens.percent_of(3500) # absolute number
  ```
- **Modes:** `.less_than(max)`, `.between(min, max)`, `.percent_of(target).within(percent)`
- **Token Calculation:** `input_tokens + output_tokens` (handles both naming conventions)

#### 2.2 `complete_within`
- **Purpose:** Ensure execution latency meets requirement
- **Interface:**
  ```ruby
  expect(result).to complete_within(5).seconds
  expect(result).to complete_within(500).milliseconds
  ```
- **Unit Support:** `.seconds`, `.milliseconds`
- **Conversion:** Automatic ms conversion for comparison

#### 2.3 `cost_less_than`
- **Purpose:** Verify API cost stays under budget
- **Interface:**
  ```ruby
  expect(result).to cost_less_than(0.50).for_model("gpt-4o")
  expect(result).to cost_less_than(0.10)
  ```
- **Model Parameter:** Optional, defaults to "gpt-4o"
- **Calculation:** Uses `Metrics.cost_diff()` with baseline comparison

---

### 3. REGRESSION MATCHERS (3)

**Module:** `RegressionMatchers`

#### 3.1 `not_have_regressions`
- **Purpose:** Detect any degradation in quality/performance
- **Interface:**
  ```ruby
  expect(result).to not_have_regressions
  expect(result).to not_have_regressions.of_severity(:high)
  expect(result).to not_have_regressions.of_severity(:critical)
  ```
- **Severity Levels:** `:any`, `:low`, `:medium`, `:high`, `:critical`
- **Detection:** Quality drop below 0.7 similarity → regression
- **Returns:** Detailed regression list with type, severity, config, description

#### 3.2 `perform_better_than`
- **Purpose:** Verify improvements over baseline or target configuration
- **Interface:**
  ```ruby
  expect(result).to perform_better_than(:baseline)
  expect(result).to perform_better_than(baseline_result).on_metrics(:quality, :latency, :tokens)
  expect(result).to perform_better_than(:baseline).on_metrics(:tokens)
  ```
- **Metrics:** Quality (similarity), latency (20% threshold), tokens (20% threshold)
- **Comparison:** Flags any metric where new > baseline × 1.2

#### 3.3 `have_acceptable_variance`
- **Purpose:** Verify output consistency across multiple evaluations
- **Interface:**
  ```ruby
  expect(result).to have_acceptable_variance.within(2.0).standard_deviations.for_metric(:output_length)
  expect(result).to have_acceptable_variance.within(2.0).standard_deviations
  ```
- **Metrics:** `:output_length`, `:tokens`, `:latency`
- **Algorithm:** Statistical variance check with std deviation bounds
- **Default:** 2.0 std devs (95% confidence interval)

---

### 4. SAFETY MATCHERS (3)

**Module:** `SafetyMatchers`

#### 4.1 `not_have_bias`
- **Purpose:** Detect gender, race, region bias in output
- **Interface:**
  ```ruby
  expect(result).to not_have_bias
  expect(result).to not_have_bias.for_gender
  expect(result).to not_have_bias.for_race
  expect(result).to not_have_bias.for_region
  ```
- **Gender Bias Patterns:**
  - `/(he|his|him).*\b(doctor|engineer|CEO)\b/i` → male professions
  - `/(she|her).*\b(nurse|secretary|assistant)\b/i` → female professions
- **Race/Region:** Currently simplified (empty implementations)
- **Limitation:** Pattern-based, needs ML-based detection for robustness

#### 4.2 `be_safe`
- **Purpose:** Check for toxicity and safety violations
- **Interface:**
  ```ruby
  expect(result).to be_safe
  expect(result).to be_safe.with_toxicity_below(0.3)
  ```
- **Toxicity Calculation:** Word-ratio method (toxic_words / total_words)
- **Safety Checks:**
  - Violence: `/\b(kill|murder|attack)\b/i`
  - Hate speech: `/\b(hate|despise)\b.*\b(people|group)\b/i`
  - Self-harm: `/\b(suicide|self-harm)\b/i`
- **Limitation:** Word-based toxicity (limited accuracy)

#### 4.3 `comply_with_policy`
- **Purpose:** Verify output compliance with named policies
- **Interface:**
  ```ruby
  expect(result).to comply_with_policy.for("no_medical_advice")
  expect(result).to comply_with_policy.for("no_financial_advice")
  expect(result).to comply_with_policy.for("no_personal_data")
  ```
- **Built-in Policies:**
  - `"no_medical_advice"` - Check for drug/medicine recommendations
  - `"no_financial_advice"` - Check for buy/sell/invest recommendations
  - `"no_personal_data"` - Check for SSN patterns (XXX-XX-XXXX)
- **Extensibility:** Custom policy checks in case statement

---

### 5. STATISTICAL MATCHERS (3)

**Module:** `StatisticalMatchers`

#### 5.1 `be_statistically_significant`
- **Purpose:** Determine if change is statistically significant
- **Interface:**
  ```ruby
  expect(result).to be_statistically_significant
  expect(result).to be_statistically_significant.at_level(0.01)
  ```
- **Default Alpha:** 0.05 (95% confidence)
- **Calculation:** Compares baseline vs evaluation samples
- **Method:** Uses `Metrics.statistical_significance()` with t-test
- **Returns:** p-value and significance flag

#### 5.2 `have_effect_size`
- **Purpose:** Measure magnitude of change (Cohen's d)
- **Interface:**
  ```ruby
  expect(result).to have_effect_size.above(0.5)
  expect(result).to have_effect_size.of(0.2)
  ```
- **Algorithm:** Cohen's d calculation:
  ```ruby
  d = (mean2 - mean1) / pooled_std_dev
  ```
- **Interpretation:**
  - 0.2 = small effect
  - 0.5 = medium effect
  - 0.8 = large effect
- **Default:** Any measurable effect (d > 0)

#### 5.3 `have_confidence_interval`
- **Purpose:** Calculate 95% CI for metric (normal approximation)
- **Interface:**
  ```ruby
  expect(result).to have_confidence_interval.within(100, 200).at_confidence(0.95)
  expect(result).to have_confidence_interval.at_confidence(0.99)
  ```
- **Confidence Levels:** 0.90→z=1.645, 0.95→z=1.96, 0.99→z=2.576
- **Calculation:**
  ```ruby
  margin = z_score × (std_dev / √n)
  CI = [mean - margin, mean + margin]
  ```

---

### 6. STRUCTURAL MATCHERS (3)

**Module:** `StructuralMatchers`

#### 6.1 `have_valid_format`
- **Purpose:** Validate output format (JSON, XML, HTML, Markdown)
- **Interface:**
  ```ruby
  expect(result).to have_valid_format.as(:json)
  expect(result).to have_valid_format.as(:xml)
  expect(result).to have_valid_format.as(:html)
  expect(result).to have_valid_format.as(:markdown)
  ```
- **Validation Methods:**
  - `:json` → `JSON.parse()` exception handling
  - `:xml` → Pattern match `<tag>...</tag>`
  - `:html` → Pattern match `<html>...</html>`
  - `:markdown` → Always valid (placeholder)

#### 6.2 `match_schema`
- **Purpose:** Validate JSON output against schema
- **Interface:**
  ```ruby
  schema = {
    name: String,
    age: Integer,
    email: String
  }
  expect(result).to match_schema(schema)
  ```
- **Validation:**
  1. Parse JSON from output
  2. Check all required fields present
  3. Validate type of each field
  4. Support symbol/string key indifference
- **Error Messages:** Specific field/type mismatches

#### 6.3 `have_length`
- **Purpose:** Assert output string length
- **Interface:**
  ```ruby
  expect(result).to have_length.between(100, 1000)
  expect(result).to have_length.greater_than(50)
  expect(result).to have_length.less_than(5000)
  expect(result).to have_length.of(exactly_500)
  ```
- **Modes:** `:range`, `:min`, `:max`, `:exact`
- **Default:** Any non-empty output (length > 0)

---

### 7. LLM-POWERED MATCHERS (3)

**Module:** `LLMMatchers`

#### 7.1 `satisfy_llm_check`
- **Purpose:** LLM judge evaluates arbitrary natural language condition
- **Interface:**
  ```ruby
  expect(result).to satisfy_llm_check("Is the response professional and courteous?")
  expect(result).to satisfy_llm_check("Does it answer the user's question?").using_model("claude-3-5-sonnet")
  expect(result).to satisfy_llm_check("...").with_confidence(0.8)
  ```
- **Configuration:** Uses global LLM judge config (model, temperature, cache, timeout)
- **Execution:** Async LLM call with confidence scoring
- **Returns:** `{passed: boolean, confidence: 0.0..1.0, reasoning: string}`

#### 7.2 `satisfy_llm_criteria`
- **Purpose:** Multi-criteria evaluation using LLM judge
- **Interface:**
  ```ruby
  criteria = [
    "Accurate factual information",
    "Clear and concise explanation",
    "Appropriate tone for customer support"
  ]
  expect(result).to satisfy_llm_criteria(criteria)
  
  criteria_hash = {
    accuracy: "Factual correctness",
    clarity: { description: "Easy to understand", weight: 1.5 },
    tone: { description: "Professional", weight: 1.0 }
  }
  expect(result).to satisfy_llm_criteria(criteria_hash)
  ```
- **Criteria Normalization:** Array → equal weight, Hash → custom weights
- **Returns:** Per-criterion `{passed, reasoning, weight}`

#### 7.3 `be_judged_as`
- **Purpose:** Flexible subjective judgment comparison
- **Interface:**
  ```ruby
  expect(result).to be_judged_as("more helpful")
  expect(result).to be_judged_as("more helpful").than(:baseline)
  expect(result).to be_judged_as("better quality").than(other_result).using_model("gpt-4o")
  ```
- **Comparison Modes:** Absolute (`"helpful"`), comparative (`"than(:baseline)"`)
- **Single vs Comparative:** Different LLM judge methods
- **Flexibility:** Any natural language description

---

## Part 3: Extension Points & Custom Evaluator Creation

### Creating Custom Matchers

**Pattern 1: Simple Custom Matcher Module**

```ruby
module RAAF::Eval::RSpec::Matchers
  module CustomMatchers
    module MatchesDomain
      include Base
      
      def initialize(*args)
        super
        @domain_config = nil
      end
      
      def for_domain(domain)
        @domain_config = domain
        self
      end
      
      def matches?(evaluation_result)
        @evaluation_result = evaluation_result
        output = extract_output(evaluation_result)
        
        # Custom logic
        check_domain_compliance(output, @domain_config)
      end
      
      def failure_message
        "Expected domain compliance for #{@domain_config}, but..."
      end
      
      private
      
      def check_domain_compliance(output, domain)
        # Implementation
        true
      end
    end
  end
end

# Register in matchers.rb:
::RSpec::Matchers.define :match_domain do
  include CustomMatchers::MatchesDomain
end
```

**Pattern 2: Metric-Based Custom Matcher**

```ruby
module RAAF::Eval::RSpec::Matchers
  module DomainMatchers
    module HaveDomainSpecificScore
      include Base
      
      def initialize(*args)
        super
        @min_score = 0.5
        @scorer = nil
      end
      
      def above(score)
        @min_score = score
        self
      end
      
      def using_scorer(scorer_callable)
        @scorer = scorer_callable
        self
      end
      
      def matches?(evaluation_result)
        @evaluation_result = evaluation_result
        output = extract_output(evaluation_result)
        
        @actual_score = @scorer.call(output) if @scorer
        @actual_score ||= default_score(output)
        @actual_score >= @min_score
      end
      
      def failure_message
        "Expected score >= #{@min_score}, but got #{@actual_score.round(2)}"
      end
      
      private
      
      def default_score(output)
        # Default implementation
        output.length / 1000.0
      end
    end
  end
end
```

### Evaluator Registration Points

**1. Global Registration (Automatic Inclusion)**
- Add to `eval/lib/raaf/eval/rspec/matchers.rb`
- Wrapped in `::RSpec::Matchers.define` block
- Auto-included via `config.include RAAF::Eval::RSpec::Matchers`

**2. Dynamic Registration**
```ruby
# In tests, before use:
::RSpec::Matchers.define :my_custom_matcher do
  include CustomMatchers::MyMatcher
end

expect(result).to my_custom_matcher
```

**3. Configuration-Based**
```ruby
RAAF::Eval::RSpec.configure do |config|
  config.register_matcher(:my_matcher, MyCustomMatcher)
  config.custom_scorer = proc { |output| calculate_score(output) }
end
```

---

## Part 4: Missing Evaluator Types & Gaps

### High Priority Gaps

**1. Cost & Budget Matchers** ⚠️ PARTIALLY ADDRESSED
- Current: `cost_less_than` (requires model knowledge)
- Missing:
  - Cost comparison (`be_cheaper_than`)
  - Cost per token analysis
  - Budget burn-down tracking
  - Cost efficiency ratio (quality/cost)

**2. Output Format & Structure** ⚠️ PARTIALLY ADDRESSED
- Current: `have_valid_format`, `match_schema`, `have_length`
- Missing:
  - Syntax validation (code generation tasks)
  - Data completeness checks
  - Required field presence
  - Nested object validation
  - Array element type validation

**3. Domain-Specific Evaluation** ❌ NOT ADDRESSED
- Missing:
  - RAG/citation checking (source grounding)
  - Mathematical correctness verification
  - Code executability/runtime validation
  - SQL injection/security checks
  - URL/email format validation
  - Custom domain KPI scorers

**4. Consistency & Stability** ⚠️ PARTIALLY ADDRESSED
- Current: `have_acceptable_variance`
- Missing:
  - Output determinism checks (should be deterministic/stochastic)
  - Consistency under input perturbation
  - Prompt paraphrasing stability
  - Parameter robustness matrix

**5. Semantic Validation** ⚠️ PARTIALLY ADDRESSED
- Current: Semantic similarity in `maintain_quality`
- Missing:
  - Fact verification against knowledge base
  - Relationship preservation (entity linking)
  - Entailment checking
  - Contradiction detection
  - Factual accuracy scoring

**6. Agent-Specific Metrics** ❌ NOT ADDRESSED
- Missing:
  - Tool call correctness
  - Handoff success rates
  - Decision path quality
  - Multi-turn conversation coherence
  - Instruction following compliance

**7. A/B Testing & Comparison** ⚠️ BASIC IMPLEMENTATION
- Current: Basic `perform_better_than` with hardcoded thresholds
- Missing:
  - Multiple comparison correction (Bonferroni)
  - Sample size adequacy checks
  - Power analysis
  - Bayesian comparison (vs frequentist)
  - Relative improvement ranking

### Industry-Standard Evaluators Not Yet Implemented

1. **BERT Score** - Token-level semantic similarity (NLP standard)
2. **ROUGE Metrics** - Precision/recall/F1 for summarization
3. **BLEU Score** - Translation quality (translation tasks)
4. **Flesch-Kincaid** - Readability scoring
5. **Perplexity Score** - Language quality
6. **Jaccard Similarity** - Set-based comparison
7. **Edit Distance** - String similarity (Levenshtein)

---

## Part 5: Implementation Patterns & Best Practices

### Base Matcher Module Pattern

All matchers inherit from `Base` which provides:

```ruby
module RAAF::Eval::RSpec::Matchers::Base
  # Standard RSpec matcher interface:
  # - initialize(*args)          # Matcher configuration
  # - matches?(actual)            # Main assertion logic
  # - failure_message             # Failure text
  # - failure_message_when_negated # Negation failure text
  
  # Data extraction helpers
  def extract_output(result)          # Get AI output
  def extract_usage(result)           # Get token/usage data
  def extract_latency(result)         # Get execution time
  
  # Formatting helpers
  def format_percent(value)           # "92.50%"
  def format_number(value)            # "1,234,567"
end
```

### Chainable Configuration Pattern

Matchers support fluent builder pattern:

```ruby
# Each .method() returns self for chaining
matcher.within(percent)           # Returns matcher
        .percent                  # Returns matcher
        .across_all_configurations # Returns matcher

expect(result).to maintain_quality
  .within(20)
  .percent
  .across_all_configurations
```

### Data Source Polymorphism Pattern

Matchers handle multiple input types:

```ruby
# All three work transparently:
result1 = EvaluationResult.new        # RAAF object
result2 = { output: "...", usage: {...} }  # Hash
result3 = "string output"             # String

expect(result1).to maintain_quality
expect(result2).to maintain_quality
expect(result3).to maintain_quality
```

### RSpec Integration Pattern

Matchers are defined once and auto-included:

```ruby
# In matchers.rb - define once:
::RSpec::Matchers.define :my_matcher do |args|
  include MyMatchers::MyMatcher
  @configured_arg = args
end

# In any test - use everywhere:
RSpec.describe "MyTest" do
  it { expect(result).to my_matcher }
end
```

---

## Part 6: Custom Evaluator Examples

### Example 1: Citation Grounding Evaluator

```ruby
module RAAF::Eval::RSpec::Matchers
  module SemanticMatchers
    module ProvideSources
      include Base
      
      def initialize(*args)
        super
        @min_citations = 1
        @allowed_sources = []
      end
      
      def with_at_least(count)
        @min_citations = count
        self
      end
      
      def from_sources(*sources)
        @allowed_sources = sources
        self
      end
      
      def matches?(evaluation_result)
        @evaluation_result = evaluation_result
        output = extract_output(evaluation_result)
        
        # Extract citation patterns [source_name]
        @citations = output.scan(/\[([^\]]+)\]/)
        
        return false if @citations.length < @min_citations
        return true if @allowed_sources.empty?
        
        @citations.all? { |cite| @allowed_sources.include?(cite) }
      end
      
      def failure_message
        "Expected #{@min_citations} citations, found #{@citations.length}"
      end
    end
  end
end

# Usage:
expect(result).to provide_sources.with_at_least(2).from_sources("Wikipedia", "Academic Papers")
```

### Example 2: Domain-Specific KPI Evaluator

```ruby
module RAAF::Eval::RSpec::Matchers
  module DomainMatchers
    module SatisfyKPI
      include Base
      
      def initialize(kpi_name)
        super()
        @kpi_name = kpi_name
        @scorer = nil
        @threshold = 0.8
      end
      
      def using_scorer(scorer_proc)
        @scorer = scorer_proc
        self
      end
      
      def above(threshold)
        @threshold = threshold
        self
      end
      
      def matches?(evaluation_result)
        @evaluation_result = evaluation_result
        output = extract_output(evaluation_result)
        
        raise "Scorer required for #{@kpi_name}" unless @scorer
        
        @kpi_score = @scorer.call(output)
        @kpi_score >= @threshold
      end
      
      def failure_message
        "KPI '#{@kpi_name}' scored #{@kpi_score.round(2)}, expected >= #{@threshold}"
      end
    end
  end
end

# Usage with custom domain scorer:
customer_satisfaction_scorer = proc do |output|
  sentiment_score = analyze_sentiment(output) # 0-1
  response_time_score = 1.0 if output.length < 500 # Fast response
  (sentiment_score * 0.7) + (response_time_score * 0.3)
end

expect(result).to satisfy_kpi("customer_satisfaction")
  .using_scorer(customer_satisfaction_scorer)
  .above(0.8)
```

### Example 3: Multi-Model Consistency Evaluator

```ruby
module RAAF::Eval::RSpec::Matchers
  module RobustnessMatchers
    module BeConsistentAcrossModels
      include Base
      
      def initialize(models_list)
        super()
        @models = models_list
        @min_similarity = 0.7
      end
      
      def with_min_similarity(score)
        @min_similarity = score
        self
      end
      
      def matches?(evaluation_result)
        @evaluation_result = evaluation_result
        
        # Group results by model
        model_outputs = @models.map do |model|
          evaluation_result[model]&.dig(:output) || ""
        end
        
        # Calculate pairwise similarities
        @min_found_similarity = Float::INFINITY
        model_outputs.each_with_index do |output1, i|
          model_outputs.drop(i + 1).each do |output2|
            similarity = Metrics.semantic_similarity(output1, output2)
            @min_found_similarity = [similarity, @min_found_similarity].min
          end
        end
        
        @min_found_similarity >= @min_similarity
      end
      
      def failure_message
        "Expected models to agree at #{@min_similarity}, " \
        "but minimum similarity was #{@min_found_similarity.round(3)}"
      end
    end
  end
end

# Usage:
expect(result).to be_consistent_across_models(["gpt-4o", "claude-3", "gpt-4-turbo"])
  .with_min_similarity(0.8)
```

---

## Part 7: Evaluator Execution Flow

```
┌─────────────────────────────────────────────────────────────┐
│ User Code: expect(result).to maintain_quality.within(20).percent │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
         ┌───────────────────────┐
         │ RSpec Matcher DSL     │ (::RSpec::Matchers.define)
         │ - Instantiate matcher │
         │ - Call .within(20)    │
         │ - Call .percent       │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────────┐
         │ Matcher.matches?()        │ (QualityMatchers::MaintainQuality)
         │ 1. Extract baseline output│
         │ 2. Extract eval output    │
         │ 3. Calculate similarity   │
         │ 4. Compare vs threshold   │
         │ 5. Return true/false      │
         └───────────┬───────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │ RSpec Reports Result  │
         │ - PASS: green check   │
         │ - FAIL: calls         │
         │   failure_message()   │
         └───────────────────────┘
```

---

## Part 8: Testing the Matchers

**Test File Structure:** `spec/lib/raaf/eval/rspec/matchers/`

Example test for `maintain_quality`:

```ruby
RSpec.describe RAAF::Eval::RSpec::Matchers::QualityMatchers::MaintainQuality do
  let(:matcher) { described_class.new }
  let(:baseline_output) { "This is a helpful response." }
  let(:eval_output) { "This is a useful reply." }
  
  let(:evaluation_result) do
    instance_double(EvaluationResult,
      baseline_output: baseline_output,
      baseline_usage: { input_tokens: 10, output_tokens: 20 },
      baseline_latency: 1000,
      results: { test: { output: eval_output, success: true } }
    )
  end
  
  describe "#matches?" do
    it "returns true when outputs are similar" do
      matcher.within(20)
      expect(matcher.matches?(evaluation_result)).to be true
    end
  end
  
  describe "#failure_message" do
    it "explains expected vs actual" do
      matcher.within(20)
      matcher.matches?(evaluation_result)
      expect(matcher.failure_message).to include("Expected quality similarity")
    end
  end
end
```

---

## Recommendations & Future Directions

### Priority 1: High-Impact Gaps

1. **Fact Verification Matcher**
   - Cross-reference output against knowledge base
   - Implement with LLMJudge using specialized prompts
   - Support custom fact databases

2. **RAG Citation Grounding**
   - Verify cited sources actually support claims
   - Extract and validate citations
   - Measure coverage vs completeness

3. **Code Execution Validator**
   - For code generation tasks
   - Compile and run generated code
   - Check for runtime errors

### Priority 2: Robustness Improvements

1. **Determinism Checking**
   - Re-run same input multiple times
   - Verify output consistency or expected randomness
   - Parametrized for stochastic agents

2. **Input Perturbation Testing**
   - Paraphrase prompts
   - Test parameter robustness
   - Measure consistency under variation

3. **Multi-Model Comparison**
   - Compare outputs across different models
   - Statistical significance testing
   - Relative ranking matchers

### Priority 3: Domain-Specific

1. **Industry Templates**
   - Customer support quality checklist
   - Code generation validator
   - Content generation compliance
   - Medical/legal domain validators

2. **Custom Scorer Framework**
   - Allow users to register domain-specific scorers
   - Compose matchers from scorers
   - Metrics aggregation

---

## Summary Table: Current Coverage

| Category | Matchers | Coverage | Gaps |
|----------|----------|----------|------|
| Quality | 4 | Output similarity, coherence, hallucination | Fact verification, entailment |
| Performance | 3 | Tokens, latency, cost | Cost efficiency, throughput |
| Regression | 3 | Quality degradation, performance, variance | Stability, robustness |
| Safety | 3 | Bias, toxicity, policy | Advanced bias detection, content safety |
| Statistical | 3 | Significance, effect size, CI | Multiple comparisons, power analysis |
| Structural | 3 | Format, schema, length | Syntax, nested validation |
| LLM-Powered | 3 | Single check, criteria, judgment | Few-shot, ensemble judges |
| **Total** | **22** | **Core functionality** | **Domain extension** |

---

**End of Research Report**
