# G-Eval: General Evaluation Framework

## Overview

G-Eval (General Evaluation) is a flexible, custom criteria evaluation framework that uses chain-of-thought reasoning with LLM-as-judge. Unlike pre-defined evaluators (Hallucination, Bias, Toxicity), G-Eval allows you to define **your own evaluation criteria** in natural language and have the LLM evaluate outputs against those criteria with detailed reasoning.

**Key Features:**
- **Custom Criteria**: Define evaluation criteria in plain English (e.g., "Output is professional and polite")
- **Chain-of-Thought Reasoning**: Get step-by-step explanations for evaluation decisions
- **Weighted Criteria**: Assign different importance weights to different criteria
- **Flexible Configuration**: Three-tier threshold system (call-time > instance > class defaults)
- **Standardized Output**: Compatible with all existing RAAF Eval RSpec matchers

## When to Use G-Eval

**Use G-Eval when:**
- ✅ You have **domain-specific quality criteria** (e.g., "Follows medical terminology guidelines")
- ✅ You need **subjective quality assessments** (e.g., "Tone is empathetic and supportive")
- ✅ Standard evaluators don't match your use case (e.g., evaluating code quality, legal compliance)
- ✅ You want **explainable evaluation** with reasoning for each criterion

**Don't use G-Eval when:**
- ❌ Standard evaluators already cover your needs (use Hallucination, Bias, Toxicity instead)
- ❌ You need purely objective metrics (use Structural evaluators for format validation)
- ❌ You have simple threshold-based rules (use custom rule-based evaluators instead)

## Quick Start

### Basic Example (Single Criterion)

```ruby
require 'raaf/eval'

# Create evaluator with single criterion
evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(
  criteria: ["Output is factually accurate"]
)

# Evaluate output
field_context = RAAF::Eval::DSL::FieldContext.new(
  :output,
  { output: "Paris is the capital of France." }
)

result = evaluator.evaluate(field_context)

puts result[:label]     # => "good"
puts result[:score]     # => 0.95
puts result[:message]   # => "[GOOD] GEval: 95%"

# Check chain-of-thought reasoning
puts result[:details][:chain_of_thought]
# => "Evaluation Summary:
#     Analyzed output: 'Paris is the capital of France.'
#
#     Criterion 1 (Output is factually accurate): Score 95% - The output strongly
#     satisfies the criterion 'Output is factually accurate'. It demonstrates clear
#     alignment with the evaluation standard."
```

### Multiple Criteria (Equal Weight)

```ruby
evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(
  criteria: [
    "Output is factually accurate",
    "Output is grammatically correct",
    "Output is clear and concise"
  ]
)

result = evaluator.evaluate(field_context)

# Overall score is average of all criteria scores
puts result[:score]  # => 0.83 (average of 0.95, 0.80, 0.75)

# Check individual criterion results
result[:details][:criteria_evaluation].each do |criterion|
  puts "#{criterion[:criterion]}: #{criterion[:score]}"
  puts "  Reasoning: #{criterion[:reasoning]}"
end
# => accuracy: 0.95
#    Reasoning: The output strongly satisfies the criterion...
# => grammar: 0.80
#    Reasoning: The output adequately meets the criterion...
# => clarity: 0.75
#    Reasoning: The output adequately meets the criterion...
```

### Weighted Criteria (Different Importance)

```ruby
evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(
  criteria: {
    accuracy: { description: "Output is factually accurate", weight: 2.0 },
    grammar: { description: "Output is grammatically correct", weight: 1.0 },
    clarity: { description: "Output is clear and concise", weight: 1.0 }
  }
)

result = evaluator.evaluate(field_context)

# Overall score is weighted average
# (0.95 * 2.0 + 0.80 * 1.0 + 0.75 * 1.0) / (2.0 + 1.0 + 1.0) = 0.8625
puts result[:score]  # => 0.8625

# Weights are included in criteria evaluation
result[:details][:criteria_evaluation].each do |criterion|
  puts "#{criterion[:criterion]}: score=#{criterion[:score]}, weight=#{criterion[:weight]}"
end
```

### Custom Thresholds

```ruby
# Instance-level thresholds (override class defaults)
evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(
  criteria: ["Output is professional"],
  good_threshold: 0.90,      # Require 90% for "good" label
  average_threshold: 0.75    # Require 75% for "average" label
)

result = evaluator.evaluate(field_context)  # Uses 0.90/0.75 thresholds

# Call-time threshold override (highest priority)
result = evaluator.evaluate(
  field_context,
  good_threshold: 0.95,      # Stricter requirement for this evaluation
  average_threshold: 0.85
)
```

## Criteria Formats

### Array Format (Simple, Equal Weight)

Most common format for equal-weight criteria:

```ruby
criteria = [
  "Output is factually accurate",
  "Output is grammatically correct",
  "Output is concise"
]

evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(criteria: criteria)
# All criteria have weight: 1.0
# Overall score = (score1 + score2 + score3) / 3
```

### Hash Format (Named, Weighted)

Use when criteria have different importance:

```ruby
criteria = {
  accuracy: { description: "Output is factually accurate", weight: 3.0 },
  grammar: { description: "Output is grammatically correct", weight: 1.0 },
  style: { description: "Output follows style guide", weight: 1.0 }
}

evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(criteria: criteria)
# Accuracy is 3x more important than grammar or style
# Overall score = (score1*3 + score2*1 + score3*1) / 5
```

### Hash Format (Simple)

Shorthand when you want names but equal weight:

```ruby
criteria = {
  accuracy: "Output is factually accurate",
  grammar: "Output is grammatically correct"
}

evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(criteria: criteria)
# Automatically assigns weight: 1.0 to both
```

## RSpec Integration

G-Eval has comprehensive RSpec matcher support with 6 specialized matchers:

### 1. `meet_all_criteria` - Check All Criteria Pass

```ruby
RSpec.describe "Customer Support Response" do
  let(:evaluator) do
    RAAF::Eval::Evaluators::LLM::GEval.new(
      criteria: ["Professional tone", "Empathetic language", "Clear solution"]
    )
  end

  it "meets all quality criteria" do
    result = evaluator.evaluate(field_context)

    expect(result).to meet_all_criteria(min_score: 0.70)
  end
end
```

### 2. `meet_criterion` - Check Specific Criterion

```ruby
it "has excellent accuracy" do
  result = evaluator.evaluate(field_context)

  # Check by criterion name
  expect(result).to meet_criterion(:accuracy, min_score: 0.90)

  # Or check by index
  expect(result).to meet_criterion(0, min_score: 0.90)
end
```

### 3. `have_chain_of_thought` - Verify Reasoning Exists

```ruby
it "provides detailed reasoning" do
  result = evaluator.evaluate(field_context)

  expect(result).to have_chain_of_thought(min_length: 100)
end
```

### 4. `respect_criteria_weights` - Validate Weighted Scoring

```ruby
it "calculates weighted average correctly" do
  result = evaluator.evaluate(field_context)

  expect(result).to respect_criteria_weights
end
```

### 5. `evaluate_criteria_count` - Verify Criteria Count

```ruby
it "evaluates all expected criteria" do
  result = evaluator.evaluate(field_context)

  expect(result).to evaluate_criteria_count(3)
end
```

### 6. `be_valid_g_eval_result` - Complete Structure Validation

```ruby
it "returns valid G-Eval result structure" do
  result = evaluator.evaluate(field_context)

  expect(result).to be_valid_g_eval_result
end
```

### Matcher Chaining

Combine multiple matchers for comprehensive validation:

```ruby
it "meets all G-Eval quality requirements" do
  result = evaluator.evaluate(field_context)

  expect(result).to be_valid_g_eval_result
    .and meet_all_criteria(min_score: 0.70)
    .and have_chain_of_thought
    .and respect_criteria_weights
    .and evaluate_criteria_count(3)
end
```

## Result Structure

G-Eval returns a standardized result hash with G-Eval-specific details:

```ruby
{
  # Standard fields (all evaluators)
  label: "good",                          # Quality label: "good", "average", or "bad"
  score: 0.8625,                          # Overall weighted score (0.0-1.0)
  message: "[GOOD] GEval: 86%",           # Human-readable message

  # G-Eval specific details
  details: {
    evaluated_field: :output,             # Field that was evaluated
    method: "g_eval",                     # Evaluator identifier
    criteria_count: 3,                    # Number of criteria

    # Chain-of-thought reasoning
    chain_of_thought: "Evaluation Summary:\n...",

    # Individual criterion results
    criteria_evaluation: [
      {
        criterion: :accuracy,             # Criterion name/identifier
        description: "Output is factually accurate",
        weight: 2.0,                      # Criterion weight
        score: 0.95,                      # Individual score (0.0-1.0)
        reasoning: "The output strongly satisfies..."
      },
      # ... more criteria
    ],

    # Threshold metadata
    thresholds: {
      good: 0.80,                         # "Good" threshold used
      average: 0.60,                      # "Average" threshold used
      used: "good (≥0.8)"                # Which threshold matched
    },

    # Evaluation note
    evaluation_note: "Meets 3/3 criteria well (86%)"
  }
}
```

## Threshold System

G-Eval uses a three-tier threshold configuration system:

### Tier 1: Class Defaults (Lowest Priority)

```ruby
# Built into GEval class
DEFAULT_GOOD_THRESHOLD = 0.80     # ≥80% = "good"
DEFAULT_AVERAGE_THRESHOLD = 0.60  # ≥60% = "average", <60% = "bad"
```

### Tier 2: Instance Defaults (Override Class)

```ruby
evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(
  criteria: ["Professional tone"],
  good_threshold: 0.90,
  average_threshold: 0.75
)

# All evaluations use 0.90/0.75 unless overridden at call-time
```

### Tier 3: Call-Time Options (Highest Priority)

```ruby
# Override on specific evaluation call
result = evaluator.evaluate(
  field_context,
  good_threshold: 0.95,
  average_threshold: 0.85
)

# This evaluation uses 0.95/0.85, but instance defaults remain 0.90/0.75
```

## Writing Good Criteria

### ✅ Good Criteria Examples

**Specific and Measurable:**
```ruby
"Output contains at least 3 concrete examples"
"Response addresses all questions in the input"
"Code follows PEP 8 style guidelines"
```

**Clear Quality Standards:**
```ruby
"Tone is professional and respectful"
"Language is accessible to a general audience"
"Explanation is thorough and well-organized"
```

**Domain-Specific:**
```ruby
"Medical terminology is used accurately"
"Legal citations follow Bluebook format"
"Financial calculations are correct"
```

### ❌ Poor Criteria Examples

**Too Vague:**
```ruby
"Output is good"          # What makes it "good"?
"Response is appropriate" # Appropriate for what context?
```

**Contradictory:**
```ruby
"Output is extremely detailed and also concise"  # Can't be both!
```

**Subjective Without Context:**
```ruby
"Output is beautiful"  # Beauty is too subjective without definition
```

## Domain-Specific Examples

### Medical Content Evaluation

```ruby
evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(
  criteria: {
    accuracy: {
      description: "Medical information is factually accurate and evidence-based",
      weight: 3.0
    },
    terminology: {
      description: "Medical terminology is used correctly",
      weight: 2.0
    },
    accessibility: {
      description: "Explanation is understandable to patients (non-medical audience)",
      weight: 2.0
    },
    empathy: {
      description: "Tone is empathetic and supportive",
      weight: 1.0
    }
  },
  good_threshold: 0.90,     # Medical content requires high accuracy
  average_threshold: 0.75
)
```

### Code Quality Evaluation

```ruby
evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(
  criteria: {
    correctness: {
      description: "Code produces correct output for given inputs",
      weight: 3.0
    },
    style: {
      description: "Code follows language style guide and best practices",
      weight: 1.0
    },
    efficiency: {
      description: "Algorithm is reasonably efficient (no obvious inefficiencies)",
      weight: 1.0
    },
    readability: {
      description: "Code is well-organized and easy to understand",
      weight: 1.0
    }
  }
)
```

### Legal Document Evaluation

```ruby
evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(
  criteria: {
    accuracy: {
      description: "Legal information is accurate and up-to-date",
      weight: 4.0
    },
    completeness: {
      description: "All relevant legal points are addressed",
      weight: 2.0
    },
    citations: {
      description: "Legal citations are properly formatted and relevant",
      weight: 2.0
    },
    clarity: {
      description: "Language is clear and professional",
      weight: 1.0
    }
  },
  good_threshold: 0.95,     # Legal content requires very high accuracy
  average_threshold: 0.85
)
```

## Best Practices

### 1. Use 3-7 Criteria

Too few criteria (1-2) don't provide enough signal. Too many criteria (8+) make evaluation expensive and results harder to interpret.

**Good:**
```ruby
criteria: [
  "Factually accurate",
  "Grammatically correct",
  "Clear and concise",
  "Professional tone"
]
# 4 criteria - comprehensive but focused
```

### 2. Weight by Importance

Use weights to reflect real-world priorities:

```ruby
criteria: {
  accuracy: { description: "Factually correct", weight: 3.0 },      # Most important
  safety: { description: "No harmful content", weight: 2.0 },       # Important
  grammar: { description: "Grammatically correct", weight: 1.0 }    # Less critical
}
# Accuracy errors are 3x more important than grammar errors
```

### 3. Provide Context in Criteria

Include enough context for the LLM to evaluate correctly:

```ruby
# ❌ Too vague
"Output is professional"

# ✅ Clear context
"Output uses professional business language appropriate for executive communication"
```

### 4. Test Your Criteria

Validate criteria against known good/bad examples:

```ruby
RSpec.describe "Criteria Validation" do
  let(:evaluator) { RAAF::Eval::Evaluators::LLM::GEval.new(criteria: criteria) }

  context "with known good example" do
    let(:field_context) { FieldContext.new(:output, { output: good_example }) }

    it "scores high" do
      result = evaluator.evaluate(field_context)
      expect(result[:score]).to be >= 0.80
    end
  end

  context "with known bad example" do
    let(:field_context) { FieldContext.new(:output, { output: bad_example }) }

    it "scores low" do
      result = evaluator.evaluate(field_context)
      expect(result[:score]).to be < 0.60
    end
  end
end
```

### 5. Cache Evaluator Instances

Create evaluators once and reuse them:

```ruby
# ✅ Good: Create once, use many times
class MyEvaluatorSuite
  def self.content_quality
    @content_quality ||= RAAF::Eval::Evaluators::LLM::GEval.new(
      criteria: { accuracy: "...", clarity: "..." }
    )
  end
end

# ❌ Bad: Creating new evaluator for each evaluation
def evaluate_content(output)
  evaluator = RAAF::Eval::Evaluators::LLM::GEval.new(...)  # Wasteful
  evaluator.evaluate(output)
end
```

## Comparison with Other Evaluators

| Feature | G-Eval | DeepEval Evaluators | Custom Rule-Based |
|---------|--------|---------------------|-------------------|
| **Criteria** | Custom, user-defined | Pre-defined (hallucination, bias, etc.) | Custom rules |
| **Reasoning** | Chain-of-thought LLM | LLM-based | Rule logic |
| **Flexibility** | Very high | Medium (parameters only) | Very high |
| **Cost** | High (LLM per evaluation) | High (LLM per evaluation) | Low (no LLM) |
| **Setup Effort** | Low (just define criteria) | Very low (use as-is) | High (write rules) |
| **Use Case** | Domain-specific quality | General AI safety | Objective validation |

**When to use which:**
- **G-Eval**: Domain-specific quality criteria (medical accuracy, code quality, legal compliance)
- **DeepEval**: General AI safety and quality (hallucination, bias, toxicity, relevancy)
- **Rule-Based**: Objective validation (format checking, length limits, keyword presence)

## Current Limitations

### Mock Implementation

**Status**: The current implementation uses **mock scoring** based on heuristics, NOT actual LLM calls.

```ruby
# Current mock behavior (lib/raaf/eval/evaluators/llm/g_eval.rb:237)
def mock_criteria_evaluation(output, criteria)
  # Simple heuristic-based mock evaluation
  output_lower = output.downcase
  output_length = output.split.size

  # Mock scoring based on output characteristics
  # TODO: Replace with actual LLM integration
end
```

**Impact:**
- ✅ **Tests work correctly** - All 53 tests pass with mock implementation
- ✅ **Result structure is correct** - Full integration with RSpec matchers
- ✅ **Prompt template is ready** - `build_g_eval_prompt` creates proper LLM prompts
- ⚠️ **Evaluation quality is limited** - Mock scores are heuristic-based, not AI-powered

**Migration Path:**

When integrating with actual LLM:

1. Replace `mock_criteria_evaluation` with real LLM call:
```ruby
def llm_judge_criteria(output:, criteria:, model: nil)
  prompt = build_g_eval_prompt(output, criteria)

  # Call RAAF LLM integration (TODO)
  llm_response = RAAF::LLM.call(prompt, model: model || "gpt-4o")

  # Parse JSON response
  parsed = JSON.parse(llm_response, symbolize_names: true)

  [parsed[:criteria], parsed[:overall_chain_of_thought]]
end
```

2. Update tests to use VCR or similar for LLM mocking
3. Add model selection options (currently placeholder in `evaluate` method)

## FAQ

### Q: How many criteria should I use?

**A**: 3-7 criteria is optimal. Too few (1-2) don't provide enough signal, too many (8+) make evaluation expensive and harder to interpret.

### Q: Should I use weighted or equal-weight criteria?

**A**: Use weighted criteria when some aspects are clearly more important than others (e.g., accuracy > grammar in medical content). Use equal weight when all criteria are equally important.

### Q: Can I use G-Eval for code evaluation?

**A**: Yes! G-Eval works well for code quality, correctness, style adherence, and efficiency evaluation. See the "Code Quality Evaluation" example above.

### Q: How do I choose good/average thresholds?

**A**: Start with defaults (0.80/0.60), then adjust based on your use case:
- **Safety-critical** (medical, legal): 0.95/0.85 (very strict)
- **Quality content** (documentation, support): 0.85/0.70 (strict)
- **General content** (drafts, internal docs): 0.80/0.60 (default)
- **Experimental** (brainstorming, ideas): 0.70/0.50 (lenient)

### Q: Can I combine G-Eval with other evaluators?

**A**: Yes! G-Eval works alongside DeepEval evaluators:

```ruby
RSpec.describe "Complete Quality Check" do
  let(:hallucination_check) { RAAF::Eval::Evaluators::LLM::Hallucination.new }
  let(:custom_quality) { RAAF::Eval::Evaluators::LLM::GEval.new(criteria: [...]) }

  it "passes all quality checks" do
    # Check for hallucinations first
    expect(hallucination_check.evaluate(field_context)).to be_factually_accurate

    # Then check custom criteria
    expect(custom_quality.evaluate(field_context)).to meet_all_criteria
  end
end
```

### Q: How expensive is G-Eval?

**A**: Each G-Eval call will use ~500-1000 tokens (depending on output length and criteria count). With GPT-4o:
- **Input**: ~$0.0025 per evaluation
- **Output**: ~$0.01 per evaluation
- **Total**: ~$0.0125 per evaluation (~$12.50 per 1000 evaluations)

Use caching and batch evaluation to reduce costs.

## See Also

- **[LLM Evaluators Documentation](LLM_EVALUATORS.md)** - DeepEval-inspired evaluators (Hallucination, Bias, etc.)
- **[RSpec Integration Guide](RSPEC_INTEGRATION.md)** - Complete RSpec matcher reference
- **[Evaluation Best Practices](../README.md#best-practices)** - General evaluation guidelines
