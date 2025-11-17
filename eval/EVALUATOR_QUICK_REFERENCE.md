# RAAF Eval Evaluator Quick Reference

**40+ RSpec Matchers Across 7 Categories**

## 🎯 3-Tier Labeling System

RAAF Eval uses a three-tier labeling system for evaluation results:

- **good** - High quality, exceeds expectations (score ≥ good_threshold)
- **average** - Acceptable quality, room for improvement (score ≥ average_threshold)
- **bad** - Poor quality, requires attention (score < average_threshold)

**Basic Matchers:**
```ruby
expect(result).to be_good                    # Label is "good"
expect(result).to be_average                 # Label is "average"
expect(result).to be_bad                     # Label is "bad"
expect(result).to be_at_least("average")     # Label is "average" or "good"
expect(result[:label]).to eq("good")         # Direct field access
```

## 1️⃣ QUALITY MATCHERS (4)

```ruby
expect(result).to maintain_quality.within(20).percent
expect(result).to have_similar_output_to(:baseline).within(20).percent
expect(result).to have_coherent_output.with_threshold(0.75)
expect(result).to not_hallucinate
```

## 2️⃣ PERFORMANCE MATCHERS (3)

```ruby
expect(result).to use_tokens.less_than(5000)
expect(result).to use_tokens.between(100, 1000)
expect(result).to use_tokens.percent_of(:baseline).within(10)

expect(result).to complete_within(5).seconds
expect(result).to complete_within(500).milliseconds

expect(result).to cost_less_than(0.50).for_model("gpt-4o")
```

## 3️⃣ REGRESSION MATCHERS (3)

```ruby
expect(result).to not_have_regressions
expect(result).to not_have_regressions.of_severity(:high)

expect(result).to perform_better_than(:baseline)
expect(result).to perform_better_than(:baseline).on_metrics(:quality, :latency, :tokens)

expect(result).to have_acceptable_variance
  .within(2.0)
  .standard_deviations
  .for_metric(:output_length)
```

## 4️⃣ SAFETY MATCHERS (3)

```ruby
expect(result).to not_have_bias
expect(result).to not_have_bias.for_gender
expect(result).to not_have_bias.for_race

expect(result).to be_safe
expect(result).to be_safe.with_toxicity_below(0.3)

expect(result).to comply_with_policy.for("no_medical_advice")
expect(result).to comply_with_policy.for("no_financial_advice")
expect(result).to comply_with_policy.for("no_personal_data")
```

## 5️⃣ STATISTICAL MATCHERS (3)

```ruby
expect(result).to be_statistically_significant
expect(result).to be_statistically_significant.at_level(0.01)

expect(result).to have_effect_size.above(0.5)
expect(result).to have_effect_size.of(0.2)

expect(result).to have_confidence_interval
  .within(100, 200)
  .at_confidence(0.95)
```

## 6️⃣ STRUCTURAL MATCHERS (3)

```ruby
expect(result).to have_valid_format.as(:json)
expect(result).to have_valid_format.as(:xml)
expect(result).to have_valid_format.as(:html)

expect(result).to match_schema({
  name: String,
  age: Integer,
  email: String
})

expect(result).to have_length.between(100, 1000)
expect(result).to have_length.greater_than(50)
expect(result).to have_length.less_than(5000)
```

## 7️⃣ LLM-POWERED MATCHERS (3)

```ruby
expect(result).to satisfy_llm_check("Is the response professional?")
expect(result).to satisfy_llm_check("Does it answer the question?")
  .using_model("claude-3-5-sonnet")
  .with_confidence(0.8)

expect(result).to satisfy_llm_criteria([
  "Accurate information",
  "Clear explanation",
  "Professional tone"
])

expect(result).to be_judged_as("more helpful")
expect(result).to be_judged_as("better quality")
  .than(:baseline)
  .using_model("gpt-4o")
```

---

## Custom Matcher Template

```ruby
module RAAF::Eval::RSpec::Matchers
  module CustomMatchers
    module MyCustom
      include Base
      
      def initialize(*args)
        super
        @config = nil
      end
      
      def configure(value)
        @config = value
        self
      end
      
      def matches?(evaluation_result)
        @evaluation_result = evaluation_result
        output = extract_output(evaluation_result)
        # Your logic here
        true
      end
      
      def failure_message
        "Expected X, but got Y"
      end
    end
  end
end

# Register in matchers.rb:
::RSpec::Matchers.define :my_custom do
  include CustomMatchers::MyCustom
end
```

---

## Key Data Extraction Helpers

```ruby
output = extract_output(result)      # Get AI output text
usage = extract_usage(result)        # Get {input_tokens, output_tokens, ...}
latency_ms = extract_latency(result) # Get execution time in ms

# Format helpers
format_percent(0.925)  # "92.50%"
format_number(1234567) # "1,234,567"
```

---

## Base Matcher Interface

Every matcher includes `Base` module with:

```ruby
def initialize(*args)              # Configuration
def matches?(evaluation_result)    # Main assertion (returns true/false)
def failure_message                # Explain failure
def failure_message_when_negated   # Explain negation failure
```

---

## Common Patterns

**Polymorphic Input Handling:**
```ruby
result1 = EvaluationResult.new        # RAAF object ✅
result2 = { output: "...", ... }      # Hash ✅
result3 = "output string"             # String ✅
```

**Chainable Configuration:**
```ruby
matcher.within(percent).percent.across_all_configurations
```

**Multiple Comparison Targets:**
```ruby
have_similar_output_to(:baseline)      # Symbol reference
have_similar_output_to(other_result)   # Variable reference
have_similar_output_to("exact text")   # String literal
have_similar_output_to(hash_result)    # Hash/object
```

---

## High-Priority Extension Areas

❌ Domain-specific evaluation (RAG, math, code execution)
❌ Agent-specific metrics (tool calls, handoffs, decision paths)
⚠️ Advanced A/B testing (multiple comparisons, power analysis)
⚠️ Semantic validation (fact verification, entailment)
⚠️ Consistency checks (determinism, input perturbation)

See `EVALUATOR_ECOSYSTEM_RESEARCH.md` for detailed gap analysis.

