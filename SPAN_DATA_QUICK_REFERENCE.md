# Span & Trace Data - Quick Reference Guide

## 📊 Complete Data Capture Framework

A visual guide to all data that can be captured in RAAF spans and traces for complete observability.

---

## 🎯 What Can Be Captured (6 Categories)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    RAAF SPAN DATA FRAMEWORK                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1️⃣  AGENT-LEVEL DATA (8 types)                                    │
│      └─ Guardrails, Context, Handoffs, Tools, Errors, Prompts,  │
│         Schema, JSON Repair                                       │
│                                                                     │
│  2️⃣  LLM-LEVEL DATA (7 types)                                      │
│      └─ Tokens, Costs, Latency, Retries, Provider Info,          │
│         Capabilities, Rate Limiting                              │
│                                                                     │
│  3️⃣  TOOL-LEVEL DATA (6 types)                                     │
│      └─ Selection, Parameters, Duration, Errors, Size, Chaining  │
│                                                                     │
│  4️⃣  PIPELINE-LEVEL DATA (4 types)                                 │
│      └─ Sequence, Transformations, Parallel Metrics,             │
│         Performance                                               │
│                                                                     │
│  5️⃣  CONTEXT/STATE DATA (4 types)                                  │
│      └─ Variables, Size Evolution, Memory, Threading              │
│                                                                     │
│  6️⃣  QUALITY METRICS (4 types)                                     │
│      └─ Response Quality, Validation, Guardrails, Fallbacks       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔴 IMMEDIATE PRIORITY (Implement Next)

### Token Usage & Costs ⭐⭐⭐

**Why:** Direct financial impact, essential for production budgeting

```
┌──────────────────────┐
│   Token Tracking     │
├──────────────────────┤
│ Input tokens:   1250 │  ──┐
│ Output tokens:   342 │    ├─ Enables:
│ Cache read:      500 │  ──┤  • Cost calculation
│ Total:         2092 │    │   • Quota tracking
│ Efficiency:   16.3% │  ──┘   • Cache ROI
└──────────────────────┘

Cost Calculation:
├─ Input:  1250 × $0.005 = $0.0625  (100K tokens)
├─ Output:  342 × $0.015 = $0.0513  (100K tokens)
├─ Savings: 500 × ($0.005 - $0.001) = $0.0020 (cached)
└─ Total:  $0.1118 per request
```

**Implementation:**
```ruby
span.set_attribute("tokens.input", 1250)
span.set_attribute("tokens.output", 342)
span.set_attribute("tokens.cache_read", 500)
span.set_attribute("cost.total_cents", 12)  # $0.12
```

---

### Tool Execution & Performance ⭐⭐⭐

**Why:** Understand LLM decisions, identify bottlenecks

```
┌────────────────────────┐
│   Tool Execution       │
├────────────────────────┤
│ Tool: web_search       │
│ Input: {query: "..."}  │
│ Duration: 1234ms       │
│ Result size: 2.3KB     │
│ Retries: 0             │
│ Success: ✓             │
└────────────────────────┘

Benefits:
├─ Debug LLM tool selection
├─ Identify slow tools
├─ Track tool failures
└─ Understand agent behavior
```

**Implementation:**
```ruby
span.add_event("tool.execution", attributes: {
  tool_name: "web_search",
  duration_ms: 1234,
  result_size: 2345,
  success: true
})
```

---

### Pipeline Performance ⭐⭐⭐

**Why:** End-to-end visibility, SLA tracking

```
┌──────────────────────────────────────────┐
│  Pipeline Execution Timeline             │
├──────────────────────────────────────────┤
│                                          │
│ MarketAnalyzer:   |====| 15000ms         │
│ ProspectScorer:   |========| 30000ms     │
│ Handoff overhead: || 1000ms              │
│                                          │
├──────────────────────────────────────────┤
│ Total: 46000ms                           │
│ Critical path: 30000ms                   │
│ Throughput: 2.1 items/sec                │
└──────────────────────────────────────────┘
```

**Implementation:**
```ruby
span.set_attribute("pipeline.total_duration_ms", 46000)
span.set_attribute("pipeline.agent.MarketAnalyzer_ms", 15000)
span.set_attribute("pipeline.agent.ProspectScorer_ms", 30000)
```

---

### Error Recovery Tracking ⭐⭐⭐

**Why:** Understand resilience, track system stability

```
┌──────────────────────────────────┐
│   Retry Pattern                  │
├──────────────────────────────────┤
│ Attempt 1: ❌ Timeout            │
│           └─ Wait 1000ms         │
│ Attempt 2: ❌ Rate limited       │
│           └─ Wait 2000ms         │
│ Attempt 3: ✅ Success!           │
│                                  │
│ Total delay: 3000ms              │
│ Final status: Recovered ✓         │
└──────────────────────────────────┘
```

**Implementation:**
```ruby
span.add_event("retry.attempt", attributes: {
  attempt: 1,
  error: "ConnectionTimeout",
  backoff_ms: 1000
})
```

---

## 🟠 MEDIUM PRIORITY (Next Quarter)

### Guardrail Tracking

**Why:** Security compliance, content filtering audit

```
Input Guardrail
├─ Profanity filter
└─ ❌ Triggered: "adult content"

Output Guardrail
├─ PII redaction
├─ ✅ Passed
└─ Fields redacted: 3
```

### Context Management

**Why:** Understand data flow, memory optimization

```
Initial Context
├─ user_id: "123"
├─ product: "BIM Software"
└─ Size: 1.2KB

Final Context
├─ user_id: "123"
├─ product: "BIM Software"
├─ market_analysis: {...}
├─ prospects: [...]
└─ Size: 3.4KB

Growth: +2.2KB (183%)
```

### Handoff Tracking

**Why:** Understand agent chains, debug orchestration

```
MarketAnalyzer ──> ProspectScorer ──> OutreachPlanner

Handoff 1:
├─ Data passed: 5.2KB
├─ Duration: 245ms
└─ Status: ✅ Success

Handoff 2:
├─ Data passed: 6.8KB
├─ Duration: 189ms
└─ Status: ✅ Success
```

### Schema Validation Quality

**Why:** Track LLM consistency, improve prompts

```
Schema Validation Results

Pass Rate: 94.5% ✅
├─ Valid: 945/1000
└─ Invalid: 55/1000

Common Violations:
├─ type_mismatch: 35 (64%)
├─ missing_field: 15 (27%)
└─ extra_fields: 5 (9%)

Trend: Improving (95% → 94% → 93% → 94.5%)
```

---

## 🟢 NICE-TO-HAVE (Following Quarter)

### Quality Metrics

```
Response Quality Score: 87/100

├─ Relevance: 92/100 ✅
├─ Completeness: 88/100 ✅
├─ Hallucination: None ✅
└─ User satisfaction: 4.3/5 ⭐⭐⭐⭐
```

### Parallel Execution

```
Parallel Analysis:
├─ Branch 1 (CompetitorAnalysis): 5000ms
├─ Branch 2 (MarketAnalysis): 3200ms
├─ Branch 3 (TrendAnalysis): 4500ms
├─ Synchronization wait: 1200ms
└─ Efficiency: 85.7%

Sequential would take: 12700ms
Parallel takes: 5000ms (+ 1200ms sync)
Speedup: 2.5x ✅
```

### Memory Usage

```
Process Memory Evolution

Start:   125 MB
Mid:     156 MB  (+31 MB)
End:     148 MB  (+23 MB)
Peak:    167 MB

Per-Agent Allocation:
├─ MarketAnalyzer: 15 MB
├─ ProspectScorer: 20 MB
└─ Context overhead: 8 MB
```

---

## 📈 IMPACT BY CATEGORY

```
Category              | Data Points | Impact Level | Complexity
─────────────────────┼─────────────┼──────────────┼────────────
Token Usage          |      6      |   ⭐⭐⭐     | Low
Cost Calculation     |      6      |   ⭐⭐⭐     | Low
Latency Metrics      |      5      |   ⭐⭐⭐     | Low
Tool Execution       |      6      |   ⭐⭐⭐     | Medium
Error Recovery       |      5      |   ⭐⭐⭐     | Low
Pipeline Performance |      4      |   ⭐⭐⭐     | Low
─────────────────────┼─────────────┼──────────────┼────────────
Guardrails           |      7      |   ⭐⭐      | Medium
Context Management   |      4      |   ⭐⭐      | Medium
Handoffs             |      6      |   ⭐⭐      | Medium
Schema Validation    |      5      |   ⭐⭐      | Low
─────────────────────┼─────────────┼──────────────┼────────────
Quality Metrics      |      4      |   ⭐        | High
Memory Tracking      |      5      |   ⭐        | High
Parallel Metrics     |      5      |   ⭐        | High
Concurrency Data     |      4      |   ⭐        | High
```

---

## 🚀 QUICK START: Phase 1 Implementation

### Step 1: Add to LLM Span Collector

```ruby
# File: raaf/tracing/lib/raaf/tracing/span_collectors/llm_collector.rb

span usage_input_tokens: ->(comp) { comp.usage[:prompt_tokens] || 0 }
span usage_output_tokens: ->(comp) { comp.usage[:completion_tokens] || 0 }
span usage_cache_read: ->(comp) { comp.usage[:cache_read_input_tokens] || 0 }
span usage_total_tokens: ->(comp) { comp.usage[:total_tokens] || 0 }

span cost_input: ->(comp) do
  calc = TokenCostCalculator.new(model: comp.model)
  calc.input_cost(comp.usage[:prompt_tokens])
end

span cost_total: ->(comp) do
  calc = TokenCostCalculator.new(model: comp.model)
  (calc.input_cost(comp.usage[:prompt_tokens]) +
   calc.output_cost(comp.usage[:completion_tokens])).round(2)
end

span latency_total_ms: ->(comp) { comp.elapsed_time_ms || 0 }
```

### Step 2: Update Rails UI Component

```ruby
# File: raaf/rails/app/components/.../llm_span_component.rb

def llm_config
  @llm_config ||= {
    "input_tokens" => extract_span_attribute("llm.usage_input_tokens"),
    "output_tokens" => extract_span_attribute("llm.usage_output_tokens"),
    "cache_read" => extract_span_attribute("llm.usage_cache_read"),
    "total_tokens" => extract_span_attribute("llm.usage_total_tokens"),
    "cost_input" => extract_span_attribute("llm.cost_input"),
    "cost_total" => extract_span_attribute("llm.cost_total"),
    "latency_ms" => extract_span_attribute("llm.latency_total_ms")
  }.compact
end
```

### Step 3: Display in UI

```erb
<div class="grid grid-cols-3 gap-4">
  <div>
    <dt>Input Tokens</dt>
    <dd><%= llm_config["input_tokens"] %></dd>
  </div>

  <div>
    <dt>Output Tokens</dt>
    <dd><%= llm_config["output_tokens"] %></dd>
  </div>

  <div>
    <dt>Cost</dt>
    <dd>$<%= llm_config["cost_total"] %></dd>
  </div>

  <div>
    <dt>Latency</dt>
    <dd><%= llm_config["latency_ms"] %>ms</dd>
  </div>
</div>
```

---

## 📋 Data Capture Checklist

### Phase 1: Immediate (This Month)
- [ ] Token usage tracking (6 attributes)
- [ ] Cost calculation (6 attributes)
- [ ] Pipeline performance metrics (4 attributes)
- [ ] Tool execution details (6 events)
- [ ] Error recovery tracking (5 events)
- [ ] Latency metrics (3 attributes)

**Effort:** ~20 hours
**Value:** 💰 Cost visibility, ⚡ Performance insights

### Phase 2: Medium (Next Quarter)
- [ ] Guardrail tracking (7 attributes)
- [ ] Context management (4 attributes)
- [ ] Handoff decisions (6 attributes)
- [ ] Schema validation metrics (5 attributes)
- [ ] Prompt tracking (4 attributes)
- [ ] Retry analytics (5 events)

**Effort:** ~25 hours
**Value:** 🔒 Security audit, 🎯 Quality improvement

### Phase 3: Advanced (Following Quarter)
- [ ] Quality metrics (4 attributes)
- [ ] Parallel execution analytics (5 events)
- [ ] Memory consumption tracking (5 attributes)
- [ ] Thread/concurrency data (4 attributes)
- [ ] Tool chaining analysis (4 events)
- [ ] Fallback tracking (4 events)

**Effort:** ~20 hours
**Value:** ✨ Analytics, 📊 Advanced optimization

---

## 🎯 Key Takeaways

1. **Phase 1 is Critical**: Tokens, costs, and performance metrics have highest impact
2. **Security Matters**: Guardrails tracking is important for compliance
3. **Data Quality**: Schema validation and quality metrics improve over time
4. **Progressive Rollout**: Implement in phases to manage complexity
5. **Easy ROI**: Phase 1 provides immediate financial visibility

---

**Document:** SPAN_DATA_QUICK_REFERENCE.md
**Version:** 1.0
**Updated:** 2025-10-24
**Status:** Ready for implementation
