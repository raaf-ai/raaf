# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-11-06-raaf-eval-foundation/spec.md

> Created: 2025-11-06
> Version: 1.0.0

## Technical Requirements

### Gem Structure

- Create `raaf-eval` directory at RAAF mono-repo root level
- Follow RAAF gem conventions: `lib/raaf/eval/`, `spec/`, `raaf-eval.gemspec`
- Depend on `raaf-core` (>= current version) for agent and runner access
- Depend on `raaf-tracing` (>= current version) for span access
- Support Ruby 3.3+ with proper version constraints
- Include RSpec for testing framework
- Include ActiveRecord for database ORM

### Span Serialization Requirements

- Serialize complete span data including:
  - Span ID, parent ID, trace ID, timestamps
  - Agent name, model, instructions, parameters
  - Input messages (all turns in conversation)
  - Output messages (assistant responses, tool calls)
  - Tool execution details (tool name, arguments, results)
  - Handoff information (target agent, context passed)
  - Provider details (API version, request/response headers)
  - Token usage, latency, cost metadata
  - Context variables passed to agent
  - Any error information
- Store as JSONB in PostgreSQL for efficient querying
- Support deserialization back to executable form
- Validate serialized data completeness before storage

### Evaluation Engine Requirements

- Accept serialized span as baseline input
- Support configuration modifications:
  - Model changes (gpt-4o → claude-3-5-sonnet, etc.)
  - Provider switches (OpenAI → Anthropic → Groq, etc.)
  - Parameter changes (temperature, max_tokens, top_p, etc.)
  - Instruction/prompt modifications
  - Tool availability changes
- Re-execute agent using RAAF::Runner with modified configuration
- Capture new span data in same format as baseline
- Handle provider-specific parameter mappings
- Gracefully handle execution failures with detailed error context

### Metrics System Requirements

#### Quantitative Metrics
- **Token Metrics**: Total tokens, input tokens, output tokens, reasoning tokens, cost per token, total cost
- **Latency Metrics**: Total execution time, time to first token, time per token, provider API latency
- **Accuracy Metrics**: Exact match, fuzzy match, BLEU score, F1 score (when ground truth available)
- **Structural Metrics**: Output length, format compliance, schema validation

#### Qualitative AI-Powered Metrics
- **AI Comparator Agent**: Dedicated RAAF agent that compares baseline vs new outputs
  - Semantic similarity assessment
  - Coherence and relevance scoring
  - Hallucination detection
  - Bias identification (gender, race, region)
  - Tone and style consistency
  - Factuality verification (when applicable)
- **Safety & Compliance**: Toxicity detection, policy alignment, PII handling compliance

#### Statistical Analysis
- Confidence intervals for numeric metrics
- Statistical significance testing (t-test, chi-square)
- Variance and standard deviation reporting
- Effect size calculation (Cohen's d)

#### Custom Metrics
- Pluggable metric interface for domain-specific KPIs
- Support for synchronous and asynchronous metric calculation
- Metric aggregation across multiple evaluation runs

### Data Quality Requirements

- **Data Leakage Detection**: Compare training data fingerprints against test inputs
- **Diversity Testing**: Track coverage across languages, domains, input types
- **Robustness Testing**: Support adversarial and noisy input variants
- **Edge Case Coverage**: Identify and flag boundary conditions

### Performance Requirements

- Span serialization: < 100ms for typical span
- Span deserialization: < 50ms
- Evaluation execution: Same as baseline agent execution + overhead < 10%
- Metrics calculation: < 500ms for standard metrics, < 5s for AI comparator
- Database queries: < 100ms for recent evaluations, < 1s for complex aggregations

## Approach Options

### Option A: In-Memory Span Objects (Not Selected)

Store spans as Ruby objects in memory, serialize to database only for persistence.

**Pros:**
- Familiar Ruby object interface
- Easy to work with in code
- Type safety with Ruby classes

**Cons:**
- Memory intensive for large evaluation batches
- Difficult to query across evaluations
- Serialization format tightly coupled to Ruby implementation
- Hard to share with non-Ruby tools

### Option B: JSONB-First with Accessor Methods (Selected)

Store spans as JSONB in database, provide Ruby accessor methods for convenience.

**Pros:**
- Database-native querying and filtering
- Efficient storage and retrieval
- Language-agnostic format
- Supports partial updates
- PostgreSQL JSONB indexing for fast queries

**Cons:**
- Requires accessor method layer
- Less type-safe than pure Ruby objects
- Need validation for JSONB structure

**Rationale:** JSONB-first approach provides flexibility, efficient querying, and future-proofs the system for non-Ruby integrations (e.g., Python clients). The slight overhead of accessor methods is outweighed by database query performance and storage efficiency.

### Option C: Two-Phase Metrics (Selected)

Calculate fast quantitative metrics synchronously, run AI comparator asynchronously.

**Pros:**
- Fast feedback for basic metrics
- AI comparator doesn't block results
- Can batch AI comparisons for cost optimization
- Supports progressive result enhancement

**Cons:**
- More complex result state management
- Need to handle async metric failures
- UI must handle partial results

**Rationale:** This hybrid approach provides immediate value (fast metrics) while enabling sophisticated analysis (AI comparator) without blocking the evaluation workflow. It also allows cost optimization by batching AI comparisons.

## External Dependencies

### New Dependencies

**rouge (~> 4.0)**
- Purpose: Calculate BLEU scores and other NLP metrics
- Justification: Industry-standard Ruby gem for NLP evaluation metrics, actively maintained
- License: MIT (compatible)

**ruby-statistics (~> 3.0)**
- Purpose: Statistical significance testing, confidence intervals, variance calculations
- Justification: Comprehensive statistical analysis without requiring R integration
- License: MIT (compatible)

**matrix (~> 0.4)**
- Purpose: Matrix operations for similarity calculations
- Justification: Standard library gem, efficient matrix math for embeddings
- License: Ruby license (compatible)

### Optional Dependencies

**tiktoken_ruby (~> 0.0.5)**
- Purpose: Accurate token counting for OpenAI models
- Justification: More accurate than regex-based counting, matches OpenAI's tokenizer
- License: MIT (compatible)
- Note: Optional - fallback to approximate counting if not installed

## Integration Points

### raaf-core Integration
- Access `RAAF::Agent` class for creating agent instances
- Use `RAAF::Runner` for executing agents
- Leverage `RAAF::Tool` interface for tool handling
- Reuse provider implementations from `RAAF::Models::*Provider`

### raaf-tracing Integration
- Query spans using `RAAF::Tracing::SpanTracer`
- Access span processors for filtering
- Reuse span data structures and serialization

### Database Integration
- Use ActiveRecord for schema management
- Store in existing RAAF database (not separate database)
- Use standard Rails migrations
- Leverage PostgreSQL JSONB for span storage

## Error Handling Strategy

- **Serialization Errors**: Log warning, store partial span with error flag
- **Execution Errors**: Store error details in result, mark evaluation as failed
- **Metrics Errors**: Store available metrics, mark failed metrics as unavailable
- **AI Comparator Errors**: Retry once, then store error and continue with quantitative metrics
- **Database Errors**: Raise exception, do not silently fail data persistence

## Security Considerations

- Leverage RAAF's PII detection for span data
- Redact sensitive information before serialization
- Validate all configuration inputs
- Sanitize prompts before AI comparator execution
- Audit log all evaluation executions
