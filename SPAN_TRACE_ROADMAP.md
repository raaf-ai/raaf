# RAAF Span & Trace Enhancement Roadmap

## Executive Summary

We've identified **40+ data points** across 6 categories that would significantly enhance observability, cost tracking, debugging, and quality metrics in RAAF.

**Total Implementation:** 3 phases over 2-3 quarters
**Priority Phases:** Phase 1 (immediate) + Phase 2 (next quarter)
**Phase 1 Timeline:** 3-4 weeks, ~20 hours effort
**Phase 1 Value:** 💰💰💰 High (direct cost tracking impact)

---

## 📊 The 40+ Data Points by Category

### 1. Agent-Level Data (8 types)

| # | Data Type | Examples | Why Important | Priority |
|---|-----------|----------|---------------|----------|
| 1 | Input/Output Guardrails | Profanity, PII filtering | Security audit trail | 🟠 Medium |
| 2 | Memory/Context Management | Context vars, growth rate | Memory optimization | 🟠 Medium |
| 3 | Handoff Decisions | From/to agents, data size | Workflow tracing | 🟠 Medium |
| 4 | Tool Execution Details | Duration, results, retries | Bottleneck identification | 🔴 **HIGH** |
| 5 | Error Recovery Attempts | Retry count, backoff delays | System resilience | 🔴 **HIGH** |
| 6 | Prompt Variations | Template used, variables | Audit trail | 🟠 Medium |
| 7 | Schema Validation Results | Pass/fail, violations | Output quality | 🟠 Medium |
| 8 | JSON Repair Operations | Repairs applied, success | LLM output quality | 🟢 Low |

**Total:** 8 distinct agent-level data streams

---

### 2. LLM-Level Data (7 types) ⭐ HIGHEST VALUE

| # | Data Type | Examples | Why Important | Priority |
|---|-----------|----------|---------------|----------|
| 1 | Token Usage (Detailed) | Input, output, cache read | 💰 Cost calculation | 🔴 **HIGH** |
| 2 | Cost Calculations | Per-request, per-agent | 💰 Budget tracking | 🔴 **HIGH** |
| 3 | Latency/Timing | TTFT, per-token, network | ⚡ Performance SLAs | 🔴 **HIGH** |
| 4 | Retry Attempts & Backoff | Count, errors, delays | 🛡️ Reliability metrics | 🔴 **HIGH** |
| 5 | Provider-Specific Metadata | Request ID, rate limits | 🔗 Multi-provider support | 🟠 Medium |
| 6 | Model Capabilities Used | Tools, response format | 📊 Feature usage tracking | 🟠 Medium |
| 7 | Rate Limiting Information | Remaining quota, reset time | 🎯 Quota management | 🟠 Medium |

**Total:** 7 distinct LLM data streams
**Phase 1 Impact:** 💰💰💰 Direct cost visibility

---

### 3. Tool-Level Data (6 types)

| # | Data Type | Examples | Why Important | Priority |
|---|-----------|----------|---------------|----------|
| 1 | Tool Selection Reasoning | Available vs selected | 🔍 Debug LLM decisions | 🟠 Medium |
| 2 | Parameter Values & Validation | Args, validation errors | 🔍 Catch LLM mistakes | 🟠 Medium |
| 3 | Execution Duration | API call, processing time | ⚡ Bottleneck ID | 🔴 **HIGH** |
| 4 | Error Handling | Error type, fallback | 🛡️ Tool resilience | 🟠 Medium |
| 5 | Result Size/Complexity | Bytes, nesting depth | 📊 Memory management | 🟢 Low |
| 6 | Tool Chaining/Dependencies | Sequence, iterations | 🔄 Workflow understanding | 🟢 Low |

**Total:** 6 distinct tool data streams

---

### 4. Pipeline-Level Data (4 types)

| # | Data Type | Examples | Why Important | Priority |
|---|-----------|----------|---------------|----------|
| 1 | Agent Sequence/Order | Sequential vs parallel | 🔄 Orchestration visibility | 🟠 Medium |
| 2 | Data Transformations | Input/output per agent | 🔍 Data flow tracing | 🟠 Medium |
| 3 | Parallel Execution Metrics | Branches, sync wait time | ⚡ Parallelism efficiency | 🟠 Medium |
| 4 | Pipeline Performance Metrics | Total duration, throughput | ⚡ SLA tracking | 🔴 **HIGH** |

**Total:** 4 distinct pipeline data streams

---

### 5. Context/State Data (4 types)

| # | Data Type | Examples | Why Important | Priority |
|---|-----------|----------|---------------|----------|
| 1 | Context Variables @ Each Step | Keys, mutations | 🔍 Debug context flow | 🟢 Low |
| 2 | Context Size Evolution | Growth rate, max size | 📊 Memory prediction | 🟢 Low |
| 3 | Memory Consumption | Process MB before/after | 📊 Resource planning | 🟢 Low |
| 4 | Thread/Concurrency Context | Thread ID, pool size | 🔍 Multi-threaded debugging | 🟢 Low |

**Total:** 4 distinct context/state data streams

---

### 6. Quality Metrics (4 types)

| # | Data Type | Examples | Why Important | Priority |
|---|-----------|----------|---------------|----------|
| 1 | Response Quality Indicators | Score, hallucination | ✨ Output quality | 🟠 Medium |
| 2 | Schema Validation Stats | Pass rate, violations | ✨ LLM consistency | 🟠 Medium |
| 3 | Guardrail Violations | Violation rate, types | 🔒 Compliance tracking | 🟠 Medium |
| 4 | Fallback Usage | Type, success rate | 🛡️ Recovery effectiveness | 🟠 Medium |

**Total:** 4 distinct quality metric streams

---

## 🎯 Phase 1: Immediate Priority (This Month)

### Phase 1 Scope: 6 Focus Areas

#### 1. Token Usage Tracking (6 data points)

```ruby
# Captures:
- Input tokens
- Output tokens
- Cache read tokens (new OpenAI feature!)
- Cache creation tokens (cost savings!)
- Total tokens
- Efficiency ratio (output/total)

# Value: Enables accurate cost calculation
# Effort: ~2 hours
# Files: LLM collector + UI component
```

**Sample Dashboard Display:**
```
LLM Usage Summary
├─ Input: 1,250 tokens
├─ Output: 342 tokens
├─ Cache Hit: 500 tokens (saved!)
├─ Total: 2,092 tokens
└─ Efficiency: 16.3%
```

---

#### 2. Cost Calculation (6 data points)

```ruby
# Captures:
- Input cost ($0.0625 for example)
- Output cost ($0.0513 for example)
- Cache savings ($0.0020 for example)
- Total cost per request ($0.118)
- Cost per token
- Model + Provider tracking

# Value: Direct financial tracking per request
# Effort: ~3 hours (includes calculator class)
# Files: LLM collector + cost calculator + UI
```

**Sample Dashboard Display:**
```
Cost Breakdown
├─ Input: $0.0625 (100K token rate: $5.00)
├─ Output: $0.0513 (100K token rate: $15.00)
├─ Cache Savings: -$0.0020 (4% reduction!)
├─ Total: $0.1118 per request
└─ Per Token: $0.00533
```

---

#### 3. Tool Execution Details (6 data points)

```ruby
# Captures:
- Tool name
- Input arguments
- Execution duration (ms)
- Result size (bytes)
- Success/failure
- Retry count

# Value: Identify bottlenecks, debug LLM tool selection
# Effort: ~3 hours
# Files: Tool collector + UI component
```

**Sample Dashboard Display:**
```
Tool Execution
├─ Tool: web_search
├─ Query: "BIM Netherlands"
├─ Duration: 1,234 ms
├─ Result Size: 2,345 bytes
├─ Status: ✅ Success
└─ Retries: 0
```

---

#### 4. Pipeline Performance Metrics (4 data points)

```ruby
# Captures:
- Total pipeline duration
- Per-agent durations
- Overhead time (coordination cost)
- Throughput (items/sec)

# Value: End-to-end visibility, SLA tracking
# Effort: ~2 hours
# Files: Pipeline span setup + UI
```

**Sample Dashboard Display:**
```
Pipeline Performance
├─ Total: 46,234 ms
│  ├─ MarketAnalyzer: 15,000 ms
│  ├─ ProspectScorer: 30,000 ms
│  └─ Overhead: 1,234 ms
├─ Throughput: 2.16 items/sec
└─ Status: Within SLA ✅
```

---

#### 5. Error Recovery Tracking (5 data points)

```ruby
# Captures:
- Retry attempt count
- Error per attempt
- Backoff delay applied
- Circuit breaker status
- Final success/failure

# Value: System resilience metrics, failure analysis
# Effort: ~3 hours
# Files: Error handling + collector
```

**Sample Dashboard Display:**
```
Error Recovery
├─ Attempt 1: ❌ ConnectionTimeout → Wait 1000ms
├─ Attempt 2: ❌ RateLimited → Wait 2000ms
├─ Attempt 3: ✅ Success
├─ Total Recovery Time: 3,000 ms
└─ Status: Recovered (2 retries)
```

---

#### 6. Latency Metrics (3 data points)

```ruby
# Captures:
- Total LLM latency
- Time to first token (TTFT)
- Latency per token

# Value: Performance SLA compliance, perceived latency
# Effort: ~2 hours
# Files: LLM collector + UI
```

**Sample Dashboard Display:**
```
Latency Breakdown
├─ Total: 2,345 ms
├─ Time to First Token: 450 ms
├─ Per Token: 6.8 ms
└─ Network Latency: 150 ms
```

---

## Phase 1: Implementation Timeline

```
Week 1: Core Infrastructure
├─ Create TokenCostCalculator class
├─ Update LLM span collector (token capture)
└─ Add utility helpers for cost calculation
  Effort: 6 hours

Week 2: Tool & Pipeline Integration
├─ Update Tool span collector (execution details)
├─ Setup Pipeline performance tracking
├─ Add error recovery event recording
  Effort: 6 hours

Week 3: Rails UI Components
├─ Create LLMConfig component with costs
├─ Create Tool Execution section
├─ Create Pipeline Performance dashboard
├─ Add Error Recovery timeline
  Effort: 5 hours

Week 4: Testing & Documentation
├─ Integration tests
├─ UI validation
├─ Documentation
├─ Deployment
  Effort: 3 hours

Total: ~20 hours (2.5 engineering weeks)
```

---

## 💰 Phase 1 Value Proposition

### Immediate Business Impact

**Cost Tracking:**
- ✅ Accurate per-request cost calculation
- ✅ Cost attribution by agent/tool
- ✅ Cache benefit tracking ($0.0020 per request = 4% savings!)
- ✅ Budget forecasting by workload

**Performance Insights:**
- ✅ TTFT monitoring for user experience
- ✅ Tool bottleneck identification
- ✅ Pipeline SLA tracking
- ✅ Throughput analysis

**Reliability:**
- ✅ Retry pattern analysis
- ✅ Error categorization
- ✅ Recovery effectiveness
- ✅ System stability metrics

### Example Impact Analysis

**For ProspectsRadar (estimated 1M API calls/month):**

```
Current State:
├─ Estimated cost: ~$2,000/month (blind estimate)
├─ No cost visibility per workflow
└─ Performance issues unidentified

After Phase 1:
├─ Exact cost: $1,850/month (with cache: -$75/month savings)
├─ Cost per prospect scoring: $0.018
├─ Bottleneck found: Tool latency consuming 60% of time
├─ Tools optimized: -200ms per request = 15% speedup
└─ Direct ROI: $900/year savings + better performance
```

---

## 🟠 Phase 2: Medium Priority (Next Quarter)

### Phase 2 Scope: 6 Focus Areas

1. **Guardrail Tracking** (7 data points)
   - Security audit trail
   - Content filtering metrics
   - PII detection tracking

2. **Context Management** (4 data points)
   - Context flow visualization
   - Memory growth patterns
   - Variable mutations

3. **Handoff Tracking** (6 data points)
   - Agent chain visibility
   - Data transformation tracking
   - Handoff success metrics

4. **Schema Validation Metrics** (5 data points)
   - Pass rate tracking
   - Violation pattern analysis
   - Quality improvement trends

5. **Prompt Variation Tracking** (4 data points)
   - Template usage
   - Variable substitution
   - Prompt evolution

6. **Provider Analytics** (7 data points)
   - Multi-provider cost comparison
   - Rate limit tracking
   - API version management

**Phase 2 Effort:** ~25 hours
**Phase 2 Value:** 🔒 Security audit trail, 📊 Quality improvements

---

## 🟢 Phase 3: Advanced (Following Quarter)

### Phase 3 Scope: 6 Focus Areas

1. **Quality Metrics** (4 data points) - Response quality scoring
2. **Parallel Execution Analytics** (5 data points) - Parallelism ROI
3. **Memory Tracking** (5 data points) - Resource planning
4. **Concurrency Metrics** (4 data points) - Threading optimization
5. **Tool Chaining Analysis** (4 data points) - Workflow patterns
6. **Fallback Tracking** (4 data points) - Resilience analysis

**Phase 3 Effort:** ~20 hours
**Phase 3 Value:** ✨ Advanced analytics, 📊 Deep optimization

---

## 📋 Implementation Checklist

### Phase 1: IMMEDIATE (3-4 weeks)

**Token Tracking**
- [ ] Add token capture to LLM collector
- [ ] Create TokenCostCalculator class
- [ ] Add UI section for token metrics
- [ ] Test with real agent executions

**Cost Calculation**
- [ ] Implement cost calculator for OpenAI
- [ ] Add cache benefit calculation
- [ ] Create cost attributes in spans
- [ ] Add cost display to UI

**Tool Execution**
- [ ] Capture tool execution events
- [ ] Add tool duration tracking
- [ ] Add result size tracking
- [ ] Create tool execution UI section

**Pipeline Performance**
- [ ] Add pipeline span tracking
- [ ] Capture per-agent durations
- [ ] Calculate critical path
- [ ] Create pipeline dashboard

**Error Recovery**
- [ ] Add retry event recording
- [ ] Capture backoff delays
- [ ] Track recovery success
- [ ] Create error recovery timeline UI

**Latency Metrics**
- [ ] Add latency captures
- [ ] Calculate TTFT if streaming
- [ ] Create latency dashboard
- [ ] Set latency alerts

**Documentation**
- [ ] Update API docs
- [ ] Create user guide
- [ ] Add examples
- [ ] Document cost calculation formula

---

## 🚀 Quick Start: Phase 1 Minimal Implementation

If you want to start immediately with **just the highest-value metrics**:

### Minimal Phase 1 (1 week, ~8 hours)

Focus on **tokens + costs + performance** only:

```ruby
# Step 1: LLM Collector (2 hours)
span usage_input_tokens: ->(comp) { comp.usage[:prompt_tokens] || 0 }
span usage_output_tokens: ->(comp) { comp.usage[:completion_tokens] || 0 }
span usage_total_tokens: ->(comp) { comp.usage[:total_tokens] || 0 }
span cost_total: ->(comp) { calc_cost(comp) }
span latency_ms: ->(comp) { comp.elapsed_time_ms || 0 }

# Step 2: UI Component (3 hours)
# Display tokens and cost in grid layout

# Step 3: Testing (2 hours)
# Verify data capture and display

# Step 4: Deploy (1 hour)
```

**Minimal Value:**
- 💰 Cost visibility (token-based)
- ⚡ Latency tracking
- 📊 Basic performance metrics

---

## 📊 Comparison: Current vs Future State

```
CURRENT STATE (Today)
═════════════════════════════════════════════════════════
Agent Span View:
├─ Agent name ✓
├─ Model ✓
├─ Status ✓
├─ Duration ✓
├─ Temperature ✓ (NEW - just added!)
└─ ... no visibility into cost, tokens, tools, errors

Questions You CANNOT Answer:
├─ How much did this agent cost?
├─ How many tokens did it use?
├─ Which tool was slow?
├─ Did it retry? How many times?
├─ How long did it wait at each stage?
└─ Is output quality improving?


FUTURE STATE (Phase 1 Complete)
═════════════════════════════════════════════════════════
Agent Span View:
├─ Agent Configuration (name, model, settings)
├─ Token Usage (input, output, cache, total)
├─ Cost Breakdown (input cost, output cost, savings, total)
├─ Performance Metrics (latency, TTFT, per-token)
├─ Tool Execution (name, duration, result, status)
├─ Error Recovery (retries, backoff, success)
└─ Pipeline Timeline (sequential agent execution)

Questions You CAN Now Answer:
├─ Cost per request: $0.118 ✓
├─ Total tokens used: 2,092 ✓
├─ Slowest tool: web_search @ 1,234ms ✓
├─ Retry pattern: 2 attempts, total 3sec delay ✓
├─ TTFT: 450ms (acceptable) ✓
└─ Quality trending: Pass rate 94.5% (improving) ✓
```

---

## 🎯 Success Metrics

### Phase 1 Success Criteria

- ✅ All token data captured for 100% of LLM calls
- ✅ Cost calculated within ±2% of actual OpenAI invoices
- ✅ Latency metrics accurate to within ±5%
- ✅ Tool execution details captured for 100% of tool calls
- ✅ Error recovery tracking captures 100% of retry events
- ✅ Pipeline performance metrics show <1% overhead
- ✅ UI dashboard loads in <2 seconds
- ✅ All data queryable via database
- ✅ Documentation complete and tested
- ✅ Team trained on new metrics

### Phase 1 Business KPIs

- 📊 Cost visibility: ±2% accuracy to OpenAI invoice
- ⚡ Performance tracking: SLA baseline established
- 🛡️ Reliability: Retry patterns identified
- 🎯 Optimization targets: Bottlenecks identified (tools, latency)
- 💡 Data quality: Baseline established for future improvements

---

## 🔗 Related Documents

For more details, see:

1. **COMPREHENSIVE_SPAN_TRACE_DATA.md**
   - Complete framework with all 40+ data points
   - Detailed implementation patterns
   - Code examples for each category

2. **SPAN_DATA_QUICK_REFERENCE.md**
   - Visual guide with examples
   - Priority matrix
   - Quick implementation checklist

3. **AGENT_SETTINGS_UI_DISPLAY.md**
   - Implementation guide for settings display
   - Already completed (Phase 0 ✓)

4. **TEST_AGENT_SETTINGS_CAPTURE.md**
   - How to test the settings capture
   - Example usage patterns

---

## 📞 Next Steps

### Immediate (This Week)
1. Review this roadmap
2. Discuss Phase 1 scope with team
3. Prioritize: Full Phase 1 vs Minimal Phase 1

### Short-term (This Month)
4. Allocate 2-3 engineering weeks for Phase 1
5. Begin token tracking implementation
6. Create cost calculator class
7. Update UI components

### Medium-term (Next Quarter)
8. Complete Phase 1 full rollout
9. Gather metrics and ROI analysis
10. Plan Phase 2 (guardrails, context, handoffs)

---

## 📄 Document Info

**File:** SPAN_TRACE_ROADMAP.md
**Version:** 1.0
**Created:** 2025-10-24
**Status:** Ready for Review
**Effort Estimate:** 65 hours total (20 + 25 + 20)
**Timeline:** 2-3 quarters
**Priority:** Phase 1 (immediate), Phase 2 (next quarter)

---

**Summary:** We have a clear, phased roadmap to add 40+ valuable data points to RAAF spans. Phase 1 (tokens, costs, performance) delivers immediate business value with 20 hours of effort. Phases 2-3 add security audit trail, quality metrics, and advanced analytics.

Ready to start Phase 1? Let's build complete observability! 🚀
