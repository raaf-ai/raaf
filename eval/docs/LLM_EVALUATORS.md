# LLM-Oriented Evaluators

## Overview

RAAF Eval provides DeepEval-inspired LLM evaluators with user-configurable quality thresholds. All evaluators use RAAF's standardized **good/average/bad** labeling pattern with three-tier threshold configuration.

## Quick Start

```ruby
# Basic usage with default thresholds
evaluator = RAAF::Eval::Evaluators::LLM::Hallucination.new
result = evaluator.evaluate(field_context, context: retrieval_context)

expect(result[:label]).to eq("good")           # good, average, or bad
expect(result[:score]).to be >= 0.90           # 0.0-1.0 score
expect(result).to be_factually_accurate        # RSpec matcher
```

## Core Evaluators (Phase 1)

### 1. Hallucination Detection

**Purpose:** Detect factually incorrect content by comparing output against provided context.

**Default Thresholds:**
- Good: ≥ 0.90 (minimal or no hallucination)
- Average: ≥ 0.70 (some factual inconsistencies)
- Bad: < 0.70 (significant hallucination)

**Usage:**
```ruby
# Basic usage
evaluator = RAAF::Eval::Evaluators::LLM::Hallucination.new
result = evaluator.evaluate(field_context, context: retrieval_context)

# Strict production settings
evaluator = RAAF::Eval::Evaluators::LLM::Hallucination.new(
  good_threshold: 0.98,
  average_threshold: 0.90
)

# Per-call override
result = evaluator.evaluate(field_context,
  context: retrieval_context,
  good_threshold: 0.95,
  average_threshold: 0.85
)

# RSpec matchers
expect(result).not_to have_hallucinations
expect(result).to be_factually_accurate(threshold: 0.95)
```

---

### 2. Answer Relevancy

**Purpose:** Evaluate if LLM output addresses the input query.

**Default Thresholds:**
- Good: ≥ 0.80 (highly relevant answer)
- Average: ≥ 0.60 (somewhat relevant)
- Bad: < 0.60 (mostly irrelevant)

**Usage:**
```ruby
evaluator = RAAF::Eval::Evaluators::LLM::AnswerRelevancy.new
result = evaluator.evaluate(field_context, query: user_query)

# RSpec matchers
expect(result).to have_answer_relevancy(threshold: 0.80)
expect(result).to be_relevant_to_query
```

---

### 3. Faithfulness (RAG-specific)

**Purpose:** Verify output is consistent with provided retrieval context.

**Default Thresholds:**
- Good: ≥ 0.90 (strictly adheres to context)
- Average: ≥ 0.75 (mostly faithful)
- Bad: < 0.75 (significant deviations)

**Usage:**
```ruby
evaluator = RAAF::Eval::Evaluators::LLM::Faithfulness.new
result = evaluator.evaluate(field_context, retrieval_context: docs)

# RSpec matcher
expect(result).to be_faithful_to_context(threshold: 0.90)
```

---

### 4. Bias Detection

**Purpose:** Detect gender, racial, political, age, religious, and socioeconomic bias.

**Default Thresholds:**
- Good: ≥ 0.90 (bias-free content)
- Average: ≥ 0.70 (minimal bias)
- Bad: < 0.70 (concerning bias)

**Usage:**
```ruby
# Check all bias types
evaluator = RAAF::Eval::Evaluators::LLM::Bias.new
result = evaluator.evaluate(field_context)

# Check specific bias types
result = evaluator.evaluate(field_context,
  bias_types: [:gender, :racial, :political]
)

# RSpec matchers
expect(result).not_to have_bias
expect(result).to be_unbiased(threshold: 0.95)
```

**Supported Bias Types:**
- `:gender` - Gender bias
- `:racial` - Racial/ethnic bias
- `:political` - Political bias
- `:age` - Age bias
- `:religious` - Religious bias
- `:socioeconomic` - Socioeconomic bias
- `:disability` - Disability bias
- `:sexual_orientation` - Sexual orientation bias

---

### 5. Toxicity Detection

**Purpose:** Detect toxic, harmful, or offensive content.

**Default Thresholds:**
- Good: ≥ 0.95 (completely safe)
- Average: ≥ 0.80 (minor concerns)
- Bad: < 0.80 (toxic content)

**Usage:**
```ruby
# Check all toxicity categories
evaluator = RAAF::Eval::Evaluators::LLM::Toxicity.new
result = evaluator.evaluate(field_context)

# Check specific categories
result = evaluator.evaluate(field_context,
  categories: [:hate_speech, :harassment, :violence]
)

# RSpec matchers
expect(result).not_to be_toxic
expect(result).to be_safe(threshold: 0.98)
```

**Supported Toxicity Categories:**
- `:profanity` - Curse words, vulgar language
- `:hate_speech` - Attacks on protected groups
- `:harassment` - Bullying, intimidation
- `:violence` - Threats, graphic violent content
- `:sexual` - Explicit sexual material
- `:threatening` - Intimidation, threats of harm
- `:identity_attack` - Attacks on personal characteristics
- `:insult` - Derogatory language
- `:severe_toxicity` - Extremely harmful content

---

## Threshold Configuration

### Three-Tier Configuration System

RAAF Eval supports three levels of threshold configuration with clear precedence:

**1. Class Defaults (Lowest Priority)**
```ruby
class Hallucination < BaseEvaluator
  DEFAULT_GOOD_THRESHOLD = 0.90      # Built-in default
  DEFAULT_AVERAGE_THRESHOLD = 0.70
end
```

**2. Instance Defaults (Medium Priority)**
```ruby
# Set thresholds when creating evaluator
evaluator = RAAF::Eval::Evaluators::LLM::Hallucination.new(
  good_threshold: 0.95,
  average_threshold: 0.80
)

# Reuse across multiple evaluations
result1 = evaluator.evaluate(field_context1, context: ctx1)
result2 = evaluator.evaluate(field_context2, context: ctx2)
```

**3. Call-Time Override (Highest Priority)**
```ruby
# Override for specific evaluation
result = evaluator.evaluate(field_context,
  context: retrieval_context,
  good_threshold: 0.98,      # Override for this call only
  average_threshold: 0.90
)
```

### Threshold Precedence Example

```ruby
# Class default: good=0.90, average=0.70
evaluator = Hallucination.new

# Instance override: good=0.95, average=0.80
evaluator = Hallucination.new(good_threshold: 0.95, average_threshold: 0.80)

# Call-time override wins
result = evaluator.evaluate(field_context,
  context: ctx,
  good_threshold: 0.98,       # Highest priority
  average_threshold: 0.90
)
# Uses: good=0.98, average=0.90
```

---

## Threshold Validation

All thresholds are validated to prevent configuration errors:

```ruby
# ❌ Error: good must be > average
evaluator = Hallucination.new(good_threshold: 0.70, average_threshold: 0.90)
# => ArgumentError: good_threshold (0.70) must be > average_threshold (0.90)

# ❌ Error: thresholds must be 0.0-1.0
evaluator = Hallucination.new(good_threshold: 1.5, average_threshold: 0.70)
# => ArgumentError: Thresholds must be between 0.0 and 1.0
```

---

## Result Structure

All evaluators return a standardized result hash:

```ruby
{
  label: "good",                    # "good", "average", or "bad"
  score: 0.92,                      # 0.0-1.0 score
  message: "[GOOD] Hallucination: 92%",
  details: {
    thresholds: {
      good: 0.90,                   # Threshold used
      average: 0.70,
      used: "good (≥0.90)"          # Which threshold was applied
    },
    evaluated_field: :answer,
    method: "llm_judge",
    # Evaluator-specific details...
  }
}
```

---

## RSpec Integration

### Basic Matchers

```ruby
# Label-based matchers (existing)
expect(result).to be_good
expect(result).to be_average
expect(result).to be_bad
expect(result).to be_at_least("average")

# Score-based matchers (new)
expect(result).to meet_quality_threshold(0.85)
```

### DeepEval-Inspired Matchers

```ruby
# Hallucination
expect(result).not_to have_hallucinations
expect(result).to be_factually_accurate(threshold: 0.95)

# Answer Relevancy
expect(result).to have_answer_relevancy(threshold: 0.80)
expect(result).to be_relevant_to_query

# Faithfulness
expect(result).to be_faithful_to_context(threshold: 0.90)

# Bias
expect(result).not_to have_bias
expect(result).to be_unbiased(threshold: 0.95)

# Toxicity
expect(result).not_to be_toxic
expect(result).to be_safe(threshold: 0.98)
```

### Composite Evaluation

```ruby
# Evaluate multiple aspects
results = {
  hallucination: hallucination_evaluator.evaluate(field_context, context: ctx),
  relevancy: relevancy_evaluator.evaluate(field_context, query: query),
  bias: bias_evaluator.evaluate(field_context),
  toxicity: toxicity_evaluator.evaluate(field_context)
}

# Check all passed
expect(results).to pass_all_evaluations
```

---

## Complete Examples

### Example 1: Production RAG Evaluation

```ruby
RSpec.describe "Customer Support RAG System" do
  let(:hallucination_eval) do
    RAAF::Eval::Evaluators::LLM::Hallucination.new(
      good_threshold: 0.95,    # Strict: customer support must be accurate
      average_threshold: 0.85
    )
  end

  let(:faithfulness_eval) do
    RAAF::Eval::Evaluators::LLM::Faithfulness.new(
      good_threshold: 0.95,    # Strict: must adhere to documentation
      average_threshold: 0.85
    )
  end

  it "provides accurate, faithful answers" do
    result_hallucination = hallucination_eval.evaluate(field_context,
      context: documentation
    )

    result_faithfulness = faithfulness_eval.evaluate(field_context,
      retrieval_context: retrieved_docs
    )

    expect(result_hallucination).to be_good
    expect(result_faithfulness).to be_good
    expect(result_hallucination).to be_factually_accurate(threshold: 0.95)
    expect(result_faithfulness).to be_faithful_to_context(threshold: 0.95)
  end
end
```

### Example 2: Content Safety Pipeline

```ruby
RSpec.describe "Content Safety Pipeline" do
  let(:bias_eval) { RAAF::Eval::Evaluators::LLM::Bias.new(good_threshold: 0.95) }
  let(:toxicity_eval) { RAAF::Eval::Evaluators::LLM::Toxicity.new(good_threshold: 0.98) }

  it "produces safe, unbiased content" do
    bias_result = bias_eval.evaluate(field_context)
    toxicity_result = toxicity_eval.evaluate(field_context)

    expect(bias_result).to be_good
    expect(toxicity_result).to be_good
    expect(bias_result).to be_unbiased
    expect(toxicity_result).to be_safe
  end
end
```

### Example 3: Development vs Production Thresholds

```ruby
RSpec.describe "Threshold Profiles" do
  context "development environment" do
    it "uses lenient thresholds" do
      evaluator = RAAF::Eval::Evaluators::LLM::AnswerRelevancy.new(
        good_threshold: 0.70,
        average_threshold: 0.50
      )

      result = evaluator.evaluate(field_context, query: user_query)
      expect(result).to be_at_least("average")  # Requires 50%+
    end
  end

  context "production environment" do
    it "uses strict thresholds" do
      evaluator = RAAF::Eval::Evaluators::LLM::AnswerRelevancy.new(
        good_threshold: 0.90,
        average_threshold: 0.75
      )

      result = evaluator.evaluate(field_context, query: user_query)
      expect(result).to be_good  # Requires 90%+
    end
  end
end
```

---

## Threshold Recommendations

### By Use Case

| Use Case | Hallucination | Relevancy | Faithfulness | Bias | Toxicity |
|----------|--------------|-----------|-------------|------|----------|
| **Customer Support** | 0.95 / 0.85 | 0.90 / 0.75 | 0.95 / 0.85 | 0.95 / 0.85 | 0.98 / 0.90 |
| **Internal Tools** | 0.85 / 0.70 | 0.80 / 0.60 | 0.85 / 0.70 | 0.90 / 0.70 | 0.95 / 0.80 |
| **Development** | 0.75 / 0.60 | 0.70 / 0.50 | 0.75 / 0.60 | 0.85 / 0.65 | 0.90 / 0.75 |
| **Research/Experimental** | 0.70 / 0.50 | 0.60 / 0.40 | 0.70 / 0.50 | 0.80 / 0.60 | 0.85 / 0.70 |

Format: `good_threshold / average_threshold`

### By Risk Tolerance

**Zero Tolerance (Safety-Critical)**
```ruby
good_threshold: 0.98
average_threshold: 0.95
# Example: Medical advice, legal content, financial guidance
```

**Strict (Production)**
```ruby
good_threshold: 0.90
average_threshold: 0.75
# Example: Customer-facing content, public APIs
```

**Standard (Default)**
```ruby
good_threshold: 0.80
average_threshold: 0.60
# Example: Internal tools, general use cases
```

**Lenient (Development)**
```ruby
good_threshold: 0.70
average_threshold: 0.50
# Example: Prototyping, experimentation
```

---

## Implementation Status

### ✅ Phase 1: Complete (5 Core Evaluators)
- Hallucination Detection
- Answer Relevancy
- Faithfulness (RAG)
- Bias Detection
- Toxicity Detection

### 🚧 Phase 2: Planned (G-Eval Framework)
- Custom criteria evaluation with chain-of-thought

### 🚧 Phase 3: Planned (RAG Evaluators)
- Contextual Relevancy
- Contextual Precision
- Contextual Recall

### 🚧 Phase 4: Planned (Agentic Evaluators)
- Task Completion
- Tool Correctness

---

## Comparison with DeepEval

| Feature | DeepEval | RAAF Eval |
|---------|----------|-----------|
| **Language** | Python | Ruby |
| **Testing Framework** | pytest | RSpec |
| **Labeling** | Pass/Fail | Good/Average/Bad |
| **Thresholds** | Single configurable | Three-tier configurable |
| **Core Evaluators** | 50+ | 5 (Phase 1), expanding |
| **RAG Support** | ✅ | ✅ |
| **LLM-as-Judge** | ✅ | ✅ |
| **Custom Criteria** | G-Eval | Planned (Phase 2) |
| **Rails Integration** | ❌ | ✅ |
| **Multi-Provider** | Limited | 10+ LLM providers |

---

## See Also

- [RAAF Eval RSpec Integration](RSPEC_INTEGRATION.md)
- [RAAF Eval API Reference](API.md)
- [Evaluator Quick Reference](EVALUATOR_QUICK_REFERENCE.md)
- [DeepEval Documentation](https://deepeval.com/docs)
