# RAAF Eval Architecture

> Version: 1.0.0
> Last Updated: 2025-11-07
> Phase 1: Foundation & Core Infrastructure

## System Overview

RAAF Eval is an integrated AI evaluation framework that enables systematic testing and validation of agent behavior across different LLM configurations, parameters, and prompts. The architecture is designed for:

- **Performance**: < 10% overhead on agent execution
- **Scalability**: Handle 1000+ evaluations per day
- **Flexibility**: Support any RAAF agent configuration
- **Extensibility**: Custom metrics and domain-specific evaluation

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         RAAF Eval System                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────┐      ┌────────────────┐                    │
│  │  Span Source   │      │  Evaluation    │                    │
│  │                │      │  Configuration │                    │
│  │  - Production  │──┐   │                │                    │
│  │  - Test        │  │   │  - Model       │                    │
│  │  - Manual      │  │   │  - Parameters  │                    │
│  └────────────────┘  │   │  - Prompts     │                    │
│                      │   └────────────────┘                    │
│                      │            │                             │
│                      ▼            ▼                             │
│              ┌──────────────────────┐                          │
│              │  Evaluation Engine   │                          │
│              │                      │                          │
│              │  1. Deserialize span │                          │
│              │  2. Apply config     │                          │
│              │  3. Execute agent    │                          │
│              │  4. Capture result   │                          │
│              └──────────────────────┘                          │
│                       │                                         │
│                       ▼                                         │
│              ┌──────────────────────┐                          │
│              │   Metrics System     │                          │
│              │                      │                          │
│              │  ┌────────────────┐  │                          │
│              │  │ Quantitative   │  │                          │
│              │  │ - Tokens       │  │                          │
│              │  │ - Latency      │  │                          │
│              │  │ - Accuracy     │  │                          │
│              │  │ - Structural   │  │                          │
│              │  └────────────────┘  │                          │
│              │                      │                          │
│              │  ┌────────────────┐  │                          │
│              │  │ Qualitative    │  │                          │
│              │  │ - AI Comparator│  │◄─── (Async)             │
│              │  │ - Semantic     │  │                          │
│              │  │ - Bias Check   │  │                          │
│              │  └────────────────┘  │                          │
│              │                      │                          │
│              │  ┌────────────────┐  │                          │
│              │  │ Statistical    │  │                          │
│              │  │ - Significance │  │                          │
│              │  │ - Confidence   │  │                          │
│              │  └────────────────┘  │                          │
│              │                      │                          │
│              │  ┌────────────────┐  │                          │
│              │  │ Custom Metrics │  │                          │
│              │  │ - Domain KPIs  │  │                          │
│              │  └────────────────┘  │                          │
│              └──────────────────────┘                          │
│                       │                                         │
│                       ▼                                         │
│              ┌──────────────────────┐                          │
│              │   Result Storage     │                          │
│              │   (PostgreSQL)       │                          │
│              │                      │                          │
│              │  - Evaluation runs   │                          │
│              │  - Span snapshots    │                          │
│              │  - Configurations    │                          │
│              │  - Results + metrics │                          │
│              └──────────────────────┘                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Component Architecture

### 1. Span Management Layer

#### SpanSerializer

**Responsibility**: Serialize complete span data for reproducible evaluation

**Key Operations**:
```ruby
# Serialize a span to JSONB
serialized = SpanSerializer.serialize(span)

# Fields captured:
# - Span metadata (ID, trace ID, timestamps)
# - Agent configuration (model, instructions, parameters)
# - Message history (all turns)
# - Tool calls and results
# - Handoff information
# - Provider details
# - Usage metrics
```

**Performance**: < 100ms for typical spans

#### SpanDeserializer

**Responsibility**: Reconstruct executable agent from serialized span

**Key Operations**:
```ruby
# Deserialize span to executable configuration
config = SpanDeserializer.deserialize(serialized_span)

# Output:
# {
#   agent: RAAF::Agent,
#   messages: [...],
#   context: {...}
# }
```

**Performance**: < 50ms for typical spans

#### SpanAccessor

**Responsibility**: Query and retrieve spans from tracing system

**Key Operations**:
```ruby
# Find span by ID
span = SpanAccessor.find("span_123")

# Query with filters
spans = SpanAccessor.query(
  agent_name: "CustomerSupport",
  model: "gpt-4o",
  start_date: 7.days.ago,
  status: "success"
)
```

**Performance**: < 100ms with proper indexes

### 2. Evaluation Engine

#### Engine Core

**Responsibility**: Execute agent with modified configuration

**Architecture**:
```
Input: Baseline Span + Configuration Overrides
  │
  ├─► Extract agent config from span
  │
  ├─► Merge with overrides
  │
  ├─► Create agent instance
  │
  ├─► Extract messages from span
  │
  ├─► Execute agent via RAAF::Runner
  │
  └─► Capture result span
```

**Key Features**:
- Configuration validation
- Provider-specific parameter mapping
- Error handling with detailed context
- Minimal execution overhead (< 10%)

**Example**:
```ruby
engine = RAAF::Eval::Engine.new(
  span: baseline_span,
  configuration_overrides: {
    model: "claude-3-5-sonnet-20241022",
    temperature: 0.7,
    max_tokens: 1000
  }
)

result = engine.execute
# Returns: { success:, output:, messages:, usage:, baseline_comparison: }
```

### 3. Metrics System

#### Metrics Architecture

**Design Pattern**: Strategy Pattern for pluggable metrics

```
MetricBase (Abstract)
  │
  ├─► TokenMetrics
  ├─► LatencyMetrics
  ├─► AccuracyMetrics
  ├─► StructuralMetrics
  ├─► AIComparator
  ├─► StatisticalAnalyzer
  └─► CustomMetric (User-defined)
```

**Execution Flow**:
```
1. Quantitative Metrics (Fast, Sync)
   ├─► TokenMetrics: ~1ms
   ├─► LatencyMetrics: ~1ms
   ├─► AccuracyMetrics: ~30ms
   └─► StructuralMetrics: ~1ms

2. Statistical Analysis (Sync, requires samples)
   └─► StatisticalAnalyzer: ~50ms

3. AI Comparator (Slow, Async recommended)
   └─► AIComparator: 1-5s
```

**Metric Interface**:
```ruby
class MetricBase
  def calculate(baseline_span, result_span)
    # Returns hash of metric data
  end
end
```

#### Custom Metrics Registry

**Pattern**: Registry Pattern for metric discovery

```ruby
# Register
CustomMetric::Registry.register(MyMetric.new)

# Retrieve
metric = CustomMetric::Registry.get("my_metric")

# List all
all_metrics = CustomMetric::Registry.all
```

### 4. Data Layer

#### Database Schema

**Tables**:
1. **evaluation_runs** - Top-level evaluation record
2. **evaluation_spans** - Serialized span snapshots
3. **evaluation_configurations** - Configuration variants
4. **evaluation_results** - Results with all metrics

**Indexing Strategy**:
- B-tree indexes: IDs, timestamps, foreign keys
- GIN indexes: JSONB columns (span_data, metrics)
- Composite indexes: Common query patterns

**Query Patterns**:
```sql
-- Recent evaluations (< 20ms)
SELECT * FROM evaluation_runs
WHERE created_at > NOW() - INTERVAL '7 days'
ORDER BY created_at DESC;

-- Find spans by model (< 50ms with GIN index)
SELECT * FROM evaluation_spans
WHERE span_data @> '{"metadata": {"model": "gpt-4o"}}'::jsonb;

-- Regression detection (< 100ms with GIN index)
SELECT * FROM evaluation_results
WHERE baseline_comparison @> '{"regression_detected": true}'::jsonb;
```

See [DATABASE_SCHEMA.md](.agent-os/specs/2025-11-06-raaf-eval-foundation/sub-specs/database-schema.md) for complete schema.

### 5. Integration Points

#### RAAF Core Integration

```
RAAF Eval
  │
  ├─► RAAF::Agent (agent creation)
  ├─► RAAF::Runner (agent execution)
  ├─► RAAF::Tool (tool handling)
  └─► RAAF::Models::*Provider (provider support)
```

#### RAAF Tracing Integration

```
RAAF Eval
  │
  └─► RAAF::Tracing::SpanTracer (span access)
      └─► Span data structures
```

## Data Flow

### Evaluation Execution Flow

```
1. User initiates evaluation
   ↓
2. Load baseline span
   ↓
3. Create evaluation run record
   ↓
4. For each configuration:
   │
   ├─► Create configuration record
   │
   ├─► Apply configuration to agent
   │
   ├─► Execute agent via Engine
   │
   ├─► Capture result span
   │
   ├─► Calculate quantitative metrics (sync)
   │
   ├─► Queue AI comparator (async)
   │
   ├─► Store result record
   │
   └─► Update run status
   ↓
5. Return results to user
   ↓
6. (Later) AI comparator completes
   ↓
7. Update result with AI metrics
```

### Metrics Calculation Flow

```
Baseline Span + Result Span
   │
   ├─► TokenMetrics.calculate()
   │    └─► Extract token counts
   │         └─► Calculate deltas and costs
   │
   ├─► LatencyMetrics.calculate()
   │    └─► Extract timestamps
   │         └─► Calculate durations and deltas
   │
   ├─► AccuracyMetrics.calculate()
   │    └─► Extract outputs
   │         └─► Calculate similarity scores
   │
   ├─► StructuralMetrics.calculate()
   │    └─► Parse output structure
   │         └─► Validate format
   │
   ├─► StatisticalAnalyzer.analyze() (if samples provided)
   │    └─► Calculate statistics
   │         └─► Significance testing
   │
   └─► AIComparator.calculate() (async)
        └─► Send to AI provider
             └─► Parse and return results
```

## Scalability Considerations

### Horizontal Scaling

**Stateless Components**:
- Evaluation Engine: No shared state
- Metrics Calculators: Pure functions
- AI Comparator: Can run on separate workers

**Scaling Strategy**:
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Engine    │     │   Engine    │     │   Engine    │
│  Instance 1 │     │  Instance 2 │     │  Instance 3 │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │
       └───────────────────┴───────────────────┘
                          │
                          ▼
                ┌──────────────────┐
                │   PostgreSQL     │
                │  (Shared State)  │
                └──────────────────┘
```

### Vertical Scaling

**Resource Allocation**:
- **CPU**: Metrics calculation (especially accuracy metrics)
- **Memory**: Batch processing of evaluations
- **I/O**: Database queries and AI API calls

**Recommendations**:
- Small: 2 CPU, 4GB RAM, 20GB storage
- Medium: 4 CPU, 8GB RAM, 100GB storage
- Large: 8 CPU, 16GB RAM, 500GB storage

### Database Scaling

**For Large Deployments (> 100K evaluations)**:
1. Table partitioning by created_at
2. Read replicas for queries
3. Connection pooling (PgBouncer)
4. Archive old data (> 90 days)

## Security Architecture

### Data Protection

**PII Handling**:
- Leverage RAAF's PII detection
- Redact sensitive data before serialization
- Audit log all evaluation executions

**Access Control**:
- (Future) Role-based access to evaluations
- (Future) Evaluation result encryption at rest

### Input Validation

**Configuration Validation**:
```ruby
# Validate before execution
validate_configuration(overrides)
  - Check model name format
  - Verify parameter ranges
  - Sanitize instruction text
  - Validate tool names
```

## Error Handling Strategy

### Error Categories

1. **Serialization Errors**: Log warning, store partial span
2. **Execution Errors**: Store error details, mark evaluation failed
3. **Metrics Errors**: Store available metrics, mark failed metrics
4. **AI Comparator Errors**: Retry once, then continue with quantitative metrics
5. **Database Errors**: Raise exception, don't silently fail

### Error Flow

```
Try: Execute evaluation
  │
  ├─► Success: Store result
  │
  └─► Error:
      ├─► Log error with context
      ├─► Store error in result record
      ├─► Update run status to 'failed'
      └─► Return error to user
```

## Future Architecture (Post-Phase 1)

### Phase 2: RSpec Integration

```
RAAF Eval
  │
  └─► RSpec Integration
      ├─► Custom matchers
      ├─► Evaluation DSL
      └─► Test helpers
```

### Phase 3: Web UI

```
RAAF Eval
  │
  └─► Rails Engine
      ├─► Span browser
      ├─► Evaluation interface
      ├─► Results viewer
      └─► Metrics dashboard
```

### Phase 4: Advanced Features

```
RAAF Eval
  │
  ├─► Active Record Integration
  │   └─► Polymorphic associations
  │
  ├─► Metrics Dashboard
  │   ├─► Aggregate views
  │   └─► Trend analysis
  │
  └─► Historical Tracking
      └─► Performance over time
```

### Phase 5: Collaboration

```
RAAF Eval
  │
  ├─► Evaluation Sessions
  │   ├─► Shareable links
  │   └─► Session persistence
  │
  ├─► Data Export
  │   ├─► CSV export
  │   └─► JSON export
  │
  └─► API
      └─► RESTful endpoints
```

## Design Principles

1. **Minimal Overhead**: Keep evaluation overhead < 10%
2. **JSONB-First**: Use database-native JSONB for flexibility
3. **Async AI**: Run expensive AI operations asynchronously
4. **Fail Gracefully**: Continue with partial results on errors
5. **Database-Backed**: All state in database, engines stateless
6. **Extensible**: Support custom metrics and configurations
7. **Observable**: Comprehensive logging and metrics

## Performance Characteristics

See [PERFORMANCE.md](PERFORMANCE.md) for detailed benchmarks.

**Summary**:
- Span serialization: < 100ms
- Engine initialization: < 10ms
- Quantitative metrics: < 500ms
- Database queries: < 100ms (with indexes)
- AI comparator: < 5s (async recommended)

## References

- [Technical Specification](.agent-os/specs/2025-11-06-raaf-eval-foundation/sub-specs/technical-spec.md)
- [Database Schema](.agent-os/specs/2025-11-06-raaf-eval-foundation/sub-specs/database-schema.md)
- [Usage Guide](USAGE_GUIDE.md)
- [Metrics Guide](METRICS.md)
- [Performance Guide](PERFORMANCE.md)
