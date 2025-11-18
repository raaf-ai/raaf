# RAG (Retrieval-Augmented Generation) Evaluators

## Overview

RAAF Eval provides comprehensive RAG evaluation capabilities with three core metrics inspired by information retrieval and DeepEval. All evaluators use RAAF's standardized **good/average/bad** labeling pattern with three-tier threshold configuration.

RAG evaluation measures the quality of document retrieval and context usage in Retrieval-Augmented Generation systems across three fundamental dimensions:

- **Contextual Relevancy**: How relevant is the retrieved context to the query?
- **Contextual Precision**: What proportion of retrieved documents are relevant?
- **Contextual Recall**: What proportion of relevant documents were retrieved?

## Quick Start

```ruby
# Evaluate contextual relevancy
evaluator = RAAF::Eval::Evaluators::LLM::ContextualRelevancy.new
result = evaluator.evaluate(field_context, query: user_query, context: retrieved_docs)

expect(result[:label]).to eq("good")                    # good, average, or bad
expect(result[:score]).to be >= 0.75                    # 0.0-1.0 score
expect(result).to have_high_contextual_relevancy        # RSpec matcher

# Evaluate precision and recall together
precision_evaluator = RAAF::Eval::Evaluators::LLM::ContextualPrecision.new
recall_evaluator = RAAF::Eval::Evaluators::LLM::ContextualRecall.new

precision_result = precision_evaluator.evaluate(field_context,
  query: query,
  retrieved_context: retrieved_docs)

recall_result = recall_evaluator.evaluate(field_context,
  query: query,
  retrieved_context: retrieved_docs,
  available_context: all_docs)

# Analyze precision-recall balance
expect([precision_result, recall_result]).to have_high_f1_score
expect([precision_result, recall_result]).to have_balanced_retrieval
```

## Core RAG Evaluators (Phase 3)

### 1. Contextual Relevancy

**Purpose:** Evaluate whether retrieved context is relevant to the user's query. Measures if the retrieval system found contextually appropriate documents.

**Default Thresholds:**
- Good: ≥ 0.75 (highly relevant context)
- Average: ≥ 0.50 (somewhat relevant)
- Bad: < 0.50 (mostly irrelevant)

**Required Fields:**
- `query`: The user's input question or search query
- `context` or `retrieved_context`: Retrieved documents to evaluate

**Usage:**
```ruby
# Basic usage
evaluator = RAAF::Eval::Evaluators::LLM::ContextualRelevancy.new
result = evaluator.evaluate(field_context,
  query: "What is machine learning?",
  context: [
    "Machine learning is a subset of AI...",
    "ML algorithms improve automatically through experience..."
  ])

# Custom thresholds for strict evaluation
evaluator = RAAF::Eval::Evaluators::LLM::ContextualRelevancy.new(
  good_threshold: 0.85,
  average_threshold: 0.65
)

# Per-call threshold override
result = evaluator.evaluate(field_context,
  query: query,
  context: docs,
  good_threshold: 0.80)

# RSpec matchers
expect(result).to have_high_contextual_relevancy
expect(result).to have_high_contextual_relevancy(min_score: 0.80)
expect(result).to be_valid_rag_result
```

**Result Details:**
```ruby
{
  label: "good",
  score: 0.85,
  message: "[GOOD] Contextual Relevancy: 85%",
  details: {
    evaluated_field: :context,
    method: "contextual_relevancy",
    query: "What is machine learning?",
    context_preview: "Machine learning is a subset of AI that enables...",
    context_length: 245,
    relevancy_reasoning: "The retrieved context directly addresses machine learning...",
    thresholds: { good: 0.75, average: 0.50, used: "good (≥0.75)" }
  }
}
```

---

### 2. Contextual Precision

**Purpose:** Measure the proportion of retrieved documents that are actually relevant. High precision means few irrelevant documents were retrieved.

**Formula:** `precision = relevant_retrieved / total_retrieved`

**Default Thresholds:**
- Good: ≥ 0.75 (most retrieved docs are relevant)
- Average: ≥ 0.50 (about half are relevant)
- Bad: < 0.50 (many irrelevant docs retrieved)

**Required Fields:**
- `query`: The user's input question
- `retrieved_context`: Documents that were retrieved
- `context` or `retrieval_context`: Alternative field names for retrieved documents

**Usage:**
```ruby
# Basic usage
evaluator = RAAF::Eval::Evaluators::LLM::ContextualPrecision.new
result = evaluator.evaluate(field_context,
  query: "What is machine learning?",
  retrieved_context: [
    "Machine learning is a subset of AI...",        # Relevant
    "ML algorithms improve through experience...",  # Relevant
    "The weather today is sunny..."                 # Irrelevant
  ])

# Analyze document relevance
result[:details][:document_count]       # => 3
result[:details][:relevant_count]       # => 2
result[:details][:irrelevant_count]     # => 1
result[:score]                          # => 0.67 (2/3)

# Per-document relevance analysis
result[:details][:document_relevance].each do |doc|
  puts "Doc #{doc[:index]}: #{doc[:relevant] ? 'Relevant' : 'Irrelevant'}"
  puts "Score: #{doc[:relevance_score]}"
  puts "Preview: #{doc[:content]}"
end

# Custom relevance threshold (how strict to judge relevance)
result = evaluator.evaluate(field_context,
  query: query,
  retrieved_context: docs,
  relevance_threshold: 0.70)  # Stricter relevance judgment

# RSpec matchers
expect(result).to have_high_precision
expect(result).to have_high_precision(min_score: 0.80)
expect(result).to have_minimal_irrelevant_documents
expect(result).to have_minimal_irrelevant_documents(max_count: 1)
expect(result).to be_valid_rag_result
```

**Result Details:**
```ruby
{
  label: "good",
  score: 0.80,
  message: "[GOOD] Contextual Precision: 80%",
  details: {
    evaluated_field: :retrieved_context,
    method: "contextual_precision",
    query: "What is machine learning?",
    document_count: 5,
    relevant_count: 4,
    irrelevant_count: 1,
    document_relevance: [
      {
        index: 0,
        content: "Machine learning is a subset of AI...",
        relevance_score: 0.92,
        relevant: true
      },
      # ... more documents
    ],
    precision_reasoning: "4 out of 5 retrieved documents are highly relevant...",
    relevance_threshold: 0.60,
    thresholds: { good: 0.75, average: 0.50, used: "good (≥0.75)" }
  }
}
```

---

### 3. Contextual Recall

**Purpose:** Measure the proportion of relevant documents that were successfully retrieved. High recall means we didn't miss important relevant documents.

**Formula:** `recall = relevant_retrieved / total_relevant_available`

**Default Thresholds:**
- Good: ≥ 0.75 (captured most relevant docs)
- Average: ≥ 0.50 (captured about half)
- Bad: < 0.50 (missed many relevant docs)

**Required Fields:**
- `query`: The user's input question
- `retrieved_context`: Documents that were retrieved
- `available_context` or `ground_truth`: All available documents (including those not retrieved)

**Usage:**
```ruby
# Basic usage
evaluator = RAAF::Eval::Evaluators::LLM::ContextualRecall.new
result = evaluator.evaluate(field_context,
  query: "What is machine learning?",
  retrieved_context: [
    "Machine learning is a subset of AI...",
    "ML algorithms improve through experience..."
  ],
  available_context: [
    "Machine learning is a subset of AI...",        # Retrieved + Relevant
    "ML algorithms improve through experience...",  # Retrieved + Relevant
    "ML is used in recommendation systems...",      # NOT retrieved, but Relevant (missed!)
    "The weather today is sunny..."                 # NOT retrieved, Irrelevant (correctly ignored)
  ])

# Analyze recall metrics
result[:details][:retrieved_count]          # => 2 (what we got)
result[:details][:available_count]          # => 4 (total available)
result[:details][:relevant_count]           # => 3 (total relevant in available set)
result[:details][:retrieved_relevant_count] # => 2 (relevant docs we got)
result[:details][:missed_relevant_count]    # => 1 (relevant docs we missed)
result[:score]                              # => 0.67 (2/3)

# Document status analysis
result[:details][:document_analysis].each do |doc|
  case doc[:status]
  when "retrieved_relevant"
    puts "✓ RETRIEVED & RELEVANT"
  when "missed_relevant"
    puts "✗ MISSED & RELEVANT (should have retrieved!)"
  when "retrieved_irrelevant"
    puts "⚠ RETRIEVED & IRRELEVANT (noise)"
  when "not_retrieved_irrelevant"
    puts "- NOT RETRIEVED & IRRELEVANT (correctly ignored)"
  end
end

# Custom relevance threshold
result = evaluator.evaluate(field_context,
  query: query,
  retrieved_context: retrieved,
  available_context: all_docs,
  relevance_threshold: 0.70)

# RSpec matchers
expect(result).to have_high_recall
expect(result).to have_high_recall(min_score: 0.80)
expect(result).to have_minimal_missed_documents
expect(result).to have_minimal_missed_documents(max_count: 2)
expect(result).to be_valid_rag_result
```

**Result Details:**
```ruby
{
  label: "good",
  score: 0.85,
  message: "[GOOD] Contextual Recall: 85%",
  details: {
    evaluated_field: :retrieved_context,
    method: "contextual_recall",
    query: "What is machine learning?",
    retrieved_count: 5,
    available_count: 8,
    relevant_count: 6,
    retrieved_relevant_count: 5,
    missed_relevant_count: 1,
    document_analysis: [
      {
        index: 0,
        content: "Machine learning is a subset of AI...",
        relevance_score: 0.92,
        relevant: true,
        retrieved: true,
        status: "retrieved_relevant"
      },
      {
        index: 5,
        content: "Deep learning is a subfield of ML...",
        relevance_score: 0.85,
        relevant: true,
        retrieved: false,
        status: "missed_relevant"  # This one was missed!
      },
      # ... more documents
    ],
    recall_reasoning: "5 out of 6 relevant documents were successfully retrieved...",
    relevance_threshold: 0.60,
    thresholds: { good: 0.75, average: 0.50, used: "good (≥0.75)" }
  }
}
```

---

## Result Structure

All RAG evaluators return results following the standard RAAF Eval format:

```ruby
{
  label: "good",                    # "good", "average", or "bad"
  score: 0.85,                      # 0.0-1.0 score
  message: "[GOOD] Contextual Relevancy: 85%",
  details: {
    thresholds: {
      good: 0.75,                   # Threshold used
      average: 0.50,
      used: "good (≥0.75)"          # Which threshold was applied
    },
    evaluated_field: :context,
    method: "contextual_relevancy", # or "contextual_precision", "contextual_recall"
    query: "What is machine learning?",
    # Evaluator-specific details...
  }
}
```

---

## RSpec Integration

### Basic RAG Matchers

```ruby
# Contextual Relevancy
expect(result).to have_high_contextual_relevancy
expect(result).to have_high_contextual_relevancy(min_score: 0.80)

# Contextual Precision
expect(result).to have_high_precision
expect(result).to have_high_precision(min_score: 0.85)
expect(result).to have_minimal_irrelevant_documents
expect(result).to have_minimal_irrelevant_documents(max_count: 1)

# Contextual Recall
expect(result).to have_high_recall
expect(result).to have_high_recall(min_score: 0.80)
expect(result).to have_minimal_missed_documents
expect(result).to have_minimal_missed_documents(max_count: 2)

# Result validation
expect(result).to be_valid_rag_result
```

### Advanced RAG Matchers

```ruby
# F1 Score (harmonic mean of precision and recall)
precision_result = precision_evaluator.evaluate(field_context, ...)
recall_result = recall_evaluator.evaluate(field_context, ...)

expect([precision_result, recall_result]).to have_high_f1_score
expect([precision_result, recall_result]).to have_high_f1_score(min_f1: 0.80)

# Balanced retrieval (precision vs recall trade-off)
expect([precision_result, recall_result]).to have_balanced_retrieval
expect([precision_result, recall_result]).to have_balanced_retrieval(tolerance: 0.10)

# All metrics together
results = {
  relevancy: relevancy_result,
  precision: precision_result,
  recall: recall_result
}

expect(results).to meet_all_rag_thresholds
expect(results).to meet_all_rag_thresholds(
  relevancy: 0.80,
  precision: 0.75,
  recall: 0.75
)
```

---

## Common RAG Evaluation Patterns

### Pattern 1: Full RAG Pipeline Evaluation

```ruby
# Evaluate complete RAG pipeline with all three metrics
describe "RAG pipeline evaluation" do
  let(:query) { "What is quantum computing?" }
  let(:retrieved_docs) { retrieval_system.search(query) }
  let(:all_docs) { document_store.all }

  let(:relevancy_evaluator) { RAAF::Eval::Evaluators::LLM::ContextualRelevancy.new }
  let(:precision_evaluator) { RAAF::Eval::Evaluators::LLM::ContextualPrecision.new }
  let(:recall_evaluator) { RAAF::Eval::Evaluators::LLM::ContextualRecall.new }

  it "retrieves highly relevant context" do
    result = relevancy_evaluator.evaluate(field_context,
      query: query,
      context: retrieved_docs)

    expect(result).to have_high_contextual_relevancy(min_score: 0.75)
  end

  it "maintains high precision (few irrelevant docs)" do
    result = precision_evaluator.evaluate(field_context,
      query: query,
      retrieved_context: retrieved_docs)

    expect(result).to have_high_precision(min_score: 0.75)
    expect(result).to have_minimal_irrelevant_documents(max_count: 2)
  end

  it "achieves high recall (captures most relevant docs)" do
    result = recall_evaluator.evaluate(field_context,
      query: query,
      retrieved_context: retrieved_docs,
      available_context: all_docs)

    expect(result).to have_high_recall(min_score: 0.75)
    expect(result).to have_minimal_missed_documents(max_count: 1)
  end

  it "maintains balanced precision-recall trade-off" do
    precision = precision_evaluator.evaluate(field_context,
      query: query, retrieved_context: retrieved_docs)

    recall = recall_evaluator.evaluate(field_context,
      query: query, retrieved_context: retrieved_docs, available_context: all_docs)

    expect([precision, recall]).to have_high_f1_score(min_f1: 0.75)
    expect([precision, recall]).to have_balanced_retrieval(tolerance: 0.15)
  end
end
```

### Pattern 2: Retrieval System Comparison

```ruby
# Compare two retrieval systems
describe "retrieval system comparison" do
  it "vector search outperforms keyword search" do
    vector_docs = vector_search.retrieve(query, top_k: 10)
    keyword_docs = keyword_search.retrieve(query, top_k: 10)

    vector_precision = precision_evaluator.evaluate(field_context,
      query: query, retrieved_context: vector_docs)

    keyword_precision = precision_evaluator.evaluate(field_context,
      query: query, retrieved_context: keyword_docs)

    expect(vector_precision[:score]).to be > keyword_precision[:score]
    expect(vector_precision).to have_high_precision(min_score: 0.80)
  end
end
```

### Pattern 3: Relevance Threshold Tuning

```ruby
# Find optimal relevance threshold for document classification
describe "relevance threshold tuning" do
  it "evaluates recall at different relevance thresholds" do
    thresholds = [0.40, 0.50, 0.60, 0.70, 0.80]
    results = {}

    thresholds.each do |threshold|
      result = recall_evaluator.evaluate(field_context,
        query: query,
        retrieved_context: retrieved_docs,
        available_context: all_docs,
        relevance_threshold: threshold)

      results[threshold] = {
        recall: result[:score],
        relevant_count: result[:details][:relevant_count],
        missed_count: result[:details][:missed_relevant_count]
      }
    end

    # Lower threshold = more docs classified as relevant = potentially lower recall
    expect(results[0.40][:relevant_count]).to be > results[0.80][:relevant_count]
  end
end
```

### Pattern 4: Retrieval Quality Monitoring

```ruby
# Monitor retrieval quality over time
describe "retrieval quality monitoring" do
  it "maintains consistent retrieval quality across queries" do
    queries = [
      "What is machine learning?",
      "Explain neural networks",
      "How does backpropagation work?"
    ]

    all_results = queries.map do |q|
      docs = retrieval_system.search(q)
      precision_evaluator.evaluate(field_context,
        query: q, retrieved_context: docs)
    end

    # All queries should meet minimum precision
    all_results.each do |result|
      expect(result).to have_high_precision(min_score: 0.70)
    end

    # Check variance in precision scores
    scores = all_results.map { |r| r[:score] }
    variance = scores.map { |s| (s - scores.sum / scores.size) ** 2 }.sum / scores.size

    expect(variance).to be < 0.05  # Low variance = consistent quality
  end
end
```

### Pattern 5: Precision-Recall Trade-off Analysis

```ruby
# Analyze precision-recall trade-off at different retrieval counts
describe "precision-recall trade-off" do
  it "evaluates trade-off at different top_k values" do
    top_k_values = [5, 10, 20, 30]
    trade_off_results = {}

    top_k_values.each do |k|
      docs = retrieval_system.search(query, top_k: k)

      precision = precision_evaluator.evaluate(field_context,
        query: query, retrieved_context: docs)

      recall = recall_evaluator.evaluate(field_context,
        query: query, retrieved_context: docs, available_context: all_docs)

      trade_off_results[k] = {
        precision: precision[:score],
        recall: recall[:score],
        f1: 2.0 * (precision[:score] * recall[:score]) / (precision[:score] + recall[:score])
      }
    end

    # Typically: higher k = higher recall, lower precision
    expect(trade_off_results[5][:precision]).to be > trade_off_results[30][:precision]
    expect(trade_off_results[30][:recall]).to be > trade_off_results[5][:recall]

    # Find k with best F1 score
    best_k = trade_off_results.max_by { |k, metrics| metrics[:f1] }.first
    puts "Optimal top_k: #{best_k} (F1: #{trade_off_results[best_k][:f1].round(2)})"
  end
end
```

---

## Threshold Configuration Best Practices

### Production Settings (Strict)

```ruby
# Strict thresholds for production RAG systems
good_threshold: 0.85
average_threshold: 0.70
# High bar for quality, detect issues early
```

### Development Settings (Balanced)

```ruby
# Balanced thresholds for development
good_threshold: 0.75  # Default
average_threshold: 0.50  # Default
# Standard thresholds for most use cases
```

### Experimentation Settings (Lenient)

```ruby
# Lenient thresholds for experimentation
good_threshold: 0.60
average_threshold: 0.40
# Allow lower quality during prototyping
```

---

## Understanding RAG Metrics

### When to Use Each Metric

| Metric | Use When | Measures |
|--------|----------|----------|
| **Contextual Relevancy** | Evaluating if retrieved context matches query intent | Context-query alignment |
| **Contextual Precision** | Reducing noise in retrieval results | Proportion of relevant docs in results |
| **Contextual Recall** | Ensuring comprehensive retrieval | Proportion of relevant docs retrieved |
| **F1 Score** | Balancing precision and recall | Harmonic mean of precision-recall |
| **Balanced Retrieval** | Avoiding extreme precision or recall | Precision-recall difference |

### Interpreting Scores

**Contextual Relevancy:**
- **0.90-1.00**: Excellent - context directly addresses query
- **0.75-0.89**: Good - context is highly relevant
- **0.50-0.74**: Average - context is somewhat relevant
- **0.00-0.49**: Poor - context is mostly irrelevant

**Contextual Precision:**
- **0.90-1.00**: Excellent - almost all retrieved docs are relevant
- **0.75-0.89**: Good - most retrieved docs are relevant
- **0.50-0.74**: Average - about half are relevant
- **0.00-0.49**: Poor - many irrelevant docs retrieved

**Contextual Recall:**
- **0.90-1.00**: Excellent - captured nearly all relevant docs
- **0.75-0.89**: Good - captured most relevant docs
- **0.50-0.74**: Average - captured about half
- **0.00-0.49**: Poor - missed many relevant docs

**F1 Score:**
- **0.80-1.00**: Excellent balance
- **0.70-0.79**: Good balance
- **0.60-0.69**: Acceptable
- **0.00-0.59**: Imbalanced or poor overall

### Precision vs Recall Trade-off

RAG systems must balance precision (fewer irrelevant docs) with recall (don't miss relevant docs):

- **High Precision, Low Recall**: Conservative retrieval, may miss relevant docs
- **Low Precision, High Recall**: Aggressive retrieval, includes noise
- **Balanced (High F1)**: Optimal balance for most use cases

**Example Scenarios:**

| Scenario | Precision | Recall | F1 | Interpretation |
|----------|-----------|--------|-----|----------------|
| Conservative Search | 0.90 | 0.60 | 0.72 | Few irrelevant docs, but missing relevant ones |
| Aggressive Search | 0.60 | 0.90 | 0.72 | Captures most relevant, but includes noise |
| Optimal Search | 0.80 | 0.80 | 0.80 | Good balance |
| Poor Search | 0.40 | 0.40 | 0.40 | Low quality overall |

---

## Implementation Status

### ✅ Phase 3: Complete (RAG Evaluators)
- Contextual Relevancy Evaluator
- Contextual Precision Evaluator
- Contextual Recall Evaluator
- 9 RAG-specific RSpec matchers
- Comprehensive test coverage (64+ test cases)

### 🚧 Phase 4: Planned (Agentic Evaluators)
- Task Completion Evaluator
- Tool Correctness Evaluator

---

## Comparison with DeepEval RAG Metrics

| Feature | DeepEval | RAAF Eval |
|---------|----------|-----------|
| **Contextual Relevancy** | ✅ | ✅ |
| **Contextual Precision** | ✅ | ✅ |
| **Contextual Recall** | ✅ | ✅ |
| **Answer Relevancy** | ✅ | ✅ (LLM Evaluators) |
| **Faithfulness** | ✅ | ✅ (LLM Evaluators) |
| **Testing Framework** | pytest | RSpec |
| **Labeling** | Pass/Fail | Good/Average/Bad |
| **Thresholds** | Single | Three-tier configurable |
| **Document Analysis** | Limited | Detailed per-document analysis |
| **F1 Score Matcher** | ❌ | ✅ |
| **Balance Matcher** | ❌ | ✅ |
| **Rails Integration** | ❌ | ✅ |

---

## See Also

- [LLM-Oriented Evaluators](LLM_EVALUATORS.md) - Hallucination, Answer Relevancy, Faithfulness
- [G-Eval Framework](G_EVAL.md) - Custom criteria evaluation
- [RAAF Eval RSpec Integration](RSPEC_INTEGRATION.md) - Complete matcher reference
- [DeepEval RAG Metrics](https://deepeval.com/docs/metrics-contextual-relevancy) - Original inspiration

---

## Footnotes

**RAG Evaluation Best Practices:**

1. **Always evaluate all three metrics together** - They provide complementary insights
2. **Use ground truth data when available** - Provides more accurate recall measurement
3. **Tune relevance thresholds** - Adjust based on your domain and use case
4. **Monitor F1 score** - Ensures balanced precision-recall trade-off
5. **Track metrics over time** - Detect retrieval quality degradation
6. **Test across diverse queries** - Ensure consistent performance
7. **Validate document analysis** - Review per-document relevance judgments
8. **Consider user feedback** - LLM judgments should align with user perception
