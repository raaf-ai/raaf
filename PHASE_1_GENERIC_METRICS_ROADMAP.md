# RAAF Phase 1: Generic Metrics Roadmap

> **Architecture Decision:** RAAF tracks ONLY generic agent execution data. Applications inject domain-specific data via hooks.
>
> **Status:** Planning
> **Updated:** 2025-10-24
> **Scope:** Generic framework metrics only (tokens, costs, latency, tool execution, error recovery)

---

## 🎯 Scope Clarification: Generic vs Application-Specific

### ✅ RAAF Responsibility (Generic Agent Framework)

These metrics apply to **ANY agent in ANY application**:

1. **Token Usage & Costs**
   - Input/output tokens (provider-agnostic)
   - Cache metrics (read tokens, savings)
   - Cost calculations per execution
   - ✅ Generic: Every agent uses tokens

2. **Latency & Performance**
   - Total execution time
   - LLM response time
   - Tool execution time
   - Pipeline duration (if using pipelines)
   - ✅ Generic: Every execution has timing

3. **Tool Execution Data**
   - Tool name (generic identifier)
   - Execution duration
   - Success/failure status
   - Retry counts and backoff timing
   - Basic error information
   - ✅ Generic: Every tool execution is the same pattern

4. **Error Recovery Tracking**
   - Retry attempts with reasons
   - Backoff timing
   - Final recovery status
   - Stack trace for debugging
   - ✅ Generic: All applications need error tracking

5. **Agent Configuration**
   - Model settings (temperature, max_tokens, top_p, penalties)
   - Tool availability (count only)
   - Response format type
   - Provider information
   - ✅ Generic: Standard agent configuration

6. **Execution Status**
   - Agent start/end timestamps
   - Overall success/failure
   - Provider used
   - Model version
   - ✅ Generic: All agents have lifecycle

### ❌ NOT RAAF Responsibility (Use Hooks Instead)

These metrics are **domain-specific** and belong in APPLICATION hooks:

- **ProspectsRadar Examples:**
  - Prospect quality scores and reasoning
  - Search query analysis (what was searched, why)
  - Company fit analysis results
  - DMU hierarchy scoring
  - Cost per prospect discovered
  - Confidence scores for lead data
  - Market discovery dimensions
  - Stakeholder classification reasoning
  - Buying signal detection patterns

- **Generic Pattern:**
  - Any metric specific to your business domain
  - Any scoring/classification unique to your application
  - Any cost tracking specific to your workflows
  - Any application-level decision trees

**These belong in application-level hooks, NOT in RAAF core.**

---

## 📊 Phase 1: Immediate Implementation (Generic Metrics)

**Effort:** ~20 hours
**Impact:** 💰 Cost visibility, ⚡ Performance insights, 🐛 Debugging capability
**Status:** Ready to implement

### 1. Token Usage & Costs ⭐⭐⭐

**What to capture:**
```
span.set_attribute("llm.tokens.input", 1250)
span.set_attribute("llm.tokens.output", 342)
span.set_attribute("llm.tokens.cache_read", 500)
span.set_attribute("llm.tokens.cache_creation", 100)
span.set_attribute("llm.cost.total_cents", 12)     # $0.12
span.set_attribute("llm.cost.input_cents", 6)      # $0.06
span.set_attribute("llm.cost.output_cents", 5)     # $0.05
span.set_attribute("llm.cost.cached_cents", 1)     # $0.01 savings
```

**Why generic:**
- Every LLM execution produces tokens
- Cost calculation applies to all models
- Financial tracking is framework-level concern

**Implementation location:**
- `raaf/tracing/lib/raaf/tracing/span_collectors/llm_collector.rb`
- Extract from response.usage (OpenAI, Anthropic, etc.)
- Provider-agnostic calculation

---

### 2. Latency Metrics ⭐⭐⭐

**What to capture:**
```
span.set_attribute("llm.latency.total_ms", 2450)
span.set_attribute("llm.latency.first_token_ms", 1200)
span.set_attribute("llm.latency.ttft_percentile", "p95")
span.set_attribute("agent.duration_ms", 5230)
span.set_attribute("tool.duration_ms", 2341)
```

**Why generic:**
- All agents care about execution speed
- Performance optimization is framework concern
- Helps identify slow operations

**Implementation location:**
- `raaf/tracing/lib/raaf/tracing/span_collectors/agent_collector.rb`
- `raaf/tracing/lib/raaf/tracing/span_collectors/llm_collector.rb`
- `raaf/tracing/lib/raaf/tracing/span_collectors/tool_collector.rb`

---

### 3. Tool Execution Data ⭐⭐⭐

**What to capture:**
```
tool_span.set_attribute("tool.name", "web_search")
tool_span.set_attribute("tool.duration_ms", 1234)
tool_span.set_attribute("tool.status", "success")
tool_span.set_attribute("tool.retry_count", 0)
tool_span.set_attribute("tool.error_type", nil)

# Also as events for sequential tracking
span.add_event("tool.execution", attributes: {
  tool_name: "web_search",
  duration_ms: 1234,
  status: "success",
  attempt: 1
})
```

**Why generic:**
- Every tool execution has same pattern
- Generic tool identification (name only)
- Success/failure is framework-level
- Retry tracking helps all applications debug

**Implementation location:**
- `raaf/tracing/lib/raaf/tracing/span_collectors/tool_collector.rb`

---

### 4. Error Recovery Tracking ⭐⭐⭐

**What to capture:**
```
span.add_event("error.retry", attributes: {
  attempt: 1,
  error_type: "RateLimitError",
  error_message: "Rate limit exceeded",
  backoff_ms: 1000,
  timestamp: "2025-10-24T12:30:45Z"
})

span.add_event("error.recovery", attributes: {
  final_status: "recovered",
  total_attempts: 3,
  total_delay_ms: 3000,
  success_on_attempt: 3
})
```

**Why generic:**
- All agents might hit transient errors
- Retry patterns are framework concern
- Recovery tracking helps debugging

**Implementation location:**
- `raaf/tracing/lib/raaf/tracing/span_collectors/error_collector.rb` (new)

---

### 5. Agent Configuration ⭐⭐

**Already Implemented** (October 24, 2025):
```
agent.temperature: 0.7
agent.max_tokens: 2000
agent.top_p: 0.95
agent.frequency_penalty: 0.1
agent.presence_penalty: 0.05
agent.tool_choice: "auto"
agent.parallel_tool_calls: true
agent.response_format: {"type": "json_schema"}
agent.model: "gpt-4o"
```

**Why generic:**
- Standard agent configuration applies to all agents
- Helps understand execution context
- Aids debugging configuration issues

**Implementation location:**
- ✅ `raaf/tracing/lib/raaf/tracing/span_collectors/agent_collector.rb` (lines 60-132)
- ✅ `raaf/rails/app/components/raaf/rails/tracing/agent_span_component.rb` (lines 217-301)

---

### 6. Provider & Model Information ⭐

**What to capture:**
```
span.set_attribute("llm.provider", "openai")
span.set_attribute("llm.model", "gpt-4o")
span.set_attribute("llm.provider_version", "2024-08-06")
span.set_attribute("llm.rate_limit.requests_per_minute", 5000)
span.set_attribute("llm.rate_limit.tokens_per_minute", 2000000)
```

**Why generic:**
- Every LLM call uses a specific provider/model
- Rate limit tracking helps all applications
- Provider info essential for debugging

**Implementation location:**
- `raaf/tracing/lib/raaf/tracing/span_collectors/llm_collector.rb`

---

## 🔧 Implementation Tasks

### Task 1: LLM Collector Enhancement
- [ ] 1.1 Write tests for token tracking
- [ ] 1.2 Add token capture to LLMCollector
- [ ] 1.3 Implement cost calculation helpers
- [ ] 1.4 Add first-token-time tracking
- [ ] 1.5 Verify all tests pass

### Task 2: Tool Collector Implementation
- [ ] 2.1 Write tests for tool tracking
- [ ] 2.2 Create ToolCollector class
- [ ] 2.3 Capture tool name, duration, status
- [ ] 2.4 Track retry information
- [ ] 2.5 Verify all tests pass

### Task 3: Error Tracking
- [ ] 3.1 Write tests for error events
- [ ] 3.2 Create ErrorCollector for retry tracking
- [ ] 3.3 Capture error type and recovery status
- [ ] 3.4 Track backoff timing
- [ ] 3.5 Verify all tests pass

### Task 4: Rails UI Enhancements
- [ ] 4.1 Update LLMSpanComponent to display token/cost data
- [ ] 4.2 Update ToolSpanComponent to display execution metrics
- [ ] 4.3 Add error recovery timeline visualization
- [ ] 4.4 Update dashboard with Phase 1 metrics
- [ ] 4.5 Verify UI displays all data correctly

### Task 5: Documentation & Testing
- [ ] 5.1 Document all Phase 1 data points
- [ ] 5.2 Create example traces with Phase 1 data
- [ ] 5.3 Run full test suite
- [ ] 5.4 Document Phase 1 completion
- [ ] 5.5 Prepare for Phase 2 planning

---

## 🎣 Application Hooks: Where to Add Domain-Specific Data

**Design Pattern:** Applications implement hooks to inject custom span data without modifying RAAF core.

### Hook Mechanism (Design Phase)

```ruby
# In RAAF: Provide hook points for applications
class RAAF::Tracing::SpanCollector
  # After span creation, before storage
  def after_span_created(span, context)
    # Allow applications to register callbacks
    RAAF.configuration.span_hooks.each do |hook|
      hook.call(span, context)
    end
  end
end

# In Application: Register domain-specific hooks
# config/initializers/raaf_hooks.rb
RAAF.configure do |config|
  config.register_span_hook do |span, context|
    # Add application-specific attributes
    if context.component.is_a?(ProspectScoringAgent)
      span.set_attribute("prospect.quality_score", calculate_quality)
      span.set_attribute("prospect.confidence", calculate_confidence)
      span.set_attribute("prospect.decision_reasoning", collect_reasoning)
    end
  end

  config.register_span_hook do |span, context|
    # Example 2: Cost per prospect tracking
    if context.component.is_a?(ProspectDiscoveryExecutor)
      span.set_attribute("app.prospect.cost_cents", calculate_cost)
      span.set_attribute("app.prospect.source_quality", assess_source)
    end
  end
end
```

### Benefits of Hook Approach

✅ **Clean Separation**: RAAF = framework, Applications = domain logic
✅ **No RAAF Modifications**: Applications don't need to fork RAAF
✅ **Reusable**: Same hooks work across different RAAF applications
✅ **Flexible**: Applications add exactly what they need
✅ **Testable**: Mock hooks in tests without affecting RAAF core

### What Goes in Hooks (Examples)

**ProspectsRadar Application Hooks:**
```ruby
# Hook 1: Prospect Quality Scoring
config.register_span_hook(:prospect_quality) do |span, context|
  if context.agent_name == "ProspectScoringAgent"
    span.set_attribute("app.prospect.fit_score", 85)
    span.set_attribute("app.prospect.data_quality", "high")
    span.set_attribute("app.prospect.confidence", 0.92)
    span.set_attribute("app.prospect.reasoning", "...")
  end
end

# Hook 2: Cost Tracking
config.register_span_hook(:cost_tracking) do |span, context|
  span.set_attribute("app.execution.cost_cents", 25)
  span.set_attribute("app.execution.margin", 0.18)
  span.set_attribute("app.execution.roi_percentile", 85)
end

# Hook 3: Market Analysis
config.register_span_hook(:market_analysis) do |span, context|
  if context.agent_name == "MarketAnalysisAgent"
    span.set_attribute("app.market.dimension_scores", {
      market_size: 8.5,
      competition: 6.2,
      entry_difficulty: 7.1
    })
  end
end

# Hook 4: Search Pattern Analysis
config.register_span_hook(:search_patterns) do |span, context|
  if context.tool_name == "web_search"
    span.set_attribute("app.search.query_type", "company_discovery")
    span.set_attribute("app.search.result_quality", "high")
    span.set_attribute("app.search.results_count", 42)
  end
end
```

---

## 📈 Impact Assessment

### What Phase 1 Achieves

| Metric | Impact | Use Case |
|--------|--------|----------|
| **Token Tracking** | 💰 Direct ROI | Budget forecasting, quota management |
| **Cost Calculation** | 💰 Financial control | Cost per execution, margin analysis |
| **Latency Metrics** | ⚡ Performance optimization | Identify bottlenecks, SLA tracking |
| **Tool Execution** | 🐛 Debugging | Understand LLM tool selection patterns |
| **Error Recovery** | 🛡️ Reliability | Track system resilience |
| **Agent Config** | 🔧 Configuration audit | Verify model settings per execution |

### What's NOT in Phase 1 (Application Hooks Instead)

- Prospect quality/confidence scoring
- Market analysis dimensions
- Cost per prospect
- Search query analysis
- Classification reasoning
- Buying signal detection patterns
- Any business-domain metrics

**These belong in application hooks, not RAAF core.**

---

## ✅ Verification Checklist

- [ ] All Phase 1 metrics are **generic** (apply to any agent in any application)
- [ ] No application-specific metrics included in RAAF core
- [ ] Hook mechanism design documented
- [ ] Implementation tasks clearly defined
- [ ] Expected to take ~20 hours
- [ ] Maintains backward compatibility
- [ ] All tests pass
- [ ] Rails UI displays all Phase 1 metrics

---

## 🚀 Ready for Implementation

This roadmap is **production-ready** with:

✅ Clear scope (generic metrics only)
✅ Defined implementation tasks
✅ Hook mechanism for applications
✅ Clean architecture (RAAF ≠ domain logic)
✅ Backward compatible approach

**Next Step:** Implement Phase 1 tasks (20 hours estimated effort)

---

**Document:** PHASE_1_GENERIC_METRICS_ROADMAP.md
**Version:** 1.0
**Updated:** 2025-10-24
**Status:** Ready for Implementation
