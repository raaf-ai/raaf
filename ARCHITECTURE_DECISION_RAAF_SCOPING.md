# Architecture Decision: RAAF Scoping and Extensibility

> **Decision:** RAAF maintains generic agent framework scope. Applications extend observability via hooks.
>
> **Date:** 2025-10-24
> **Status:** Decided and Documented
> **Impact:** Shapes roadmap, implementation priorities, and extensibility patterns

---

## 📋 Summary

**User Statement (October 24, 2025):**
> "I want RAAF to ONLY contain generic agent information and maybe have a hook for application data"

This single statement fundamentally reframes RAAF's observability strategy, separating framework-level metrics from application-level domain data.

**Decision:** ✅ **Adopt hook-based extensibility architecture**

---

## 🎯 The Problem This Solves

### Previous Approach (Problematic)

Created comprehensive roadmap for 40+ data points including:
- ✅ Generic metrics (tokens, costs, latency) - appropriate for RAAF
- ❌ Domain-specific metrics (prospect scores, market analysis dimensions) - inappropriate for RAAF
- ❌ Application-level reasoning (why did AI make this decision?) - inappropriate for RAAF
- ❌ Cost tracking per business outcome - inappropriate for RAAF

**Result:** RAAF core would become bloated with application-specific observability, making it:
- Hard to maintain (every application has different needs)
- Tightly coupled (RAAF knows about prospects, markets, etc.)
- Non-reusable (patterns designed for ProspectsRadar, not general agents)
- Difficult for other applications to use

### Adopted Approach (This Decision)

**Two-tier architecture:**

1. **RAAF Core** - Generic, reusable metrics that apply to ANY agent in ANY application
   - Token usage and costs (financial impact, all applications care)
   - Latency metrics (performance, all applications need)
   - Tool execution data (understanding LLM decisions, all applications need)
   - Error recovery tracking (reliability, all applications need)
   - Agent configuration (execution context, all applications need)

2. **Application Hooks** - Domain-specific metrics registered by applications
   - ProspectsRadar: prospect quality, market scoring, cost per discovery
   - Other applications: whatever domain-specific data they need
   - Registered at initialization, runs after RAAF metrics captured
   - No changes to RAAF code required

**Result:** Clean architecture where:
- ✅ RAAF stays focused and reusable
- ✅ Applications add exactly what they need
- ✅ No RAAF modifications required for new applications
- ✅ All data stored together (span_attributes JSONB)
- ✅ UI can display both RAAF and app metrics seamlessly

---

## 🏗️ Architecture Components

### 1. RAAF Generic Metrics (Phase 1 Immediate)

**Token Usage & Costs** (~6 attributes)
```
llm.tokens.input, output, cache_read, cache_creation
llm.cost.total_cents, input_cents, output_cents, cached_cents
```
**Why generic:** Every LLM execution uses tokens. All applications need cost tracking.

**Latency Metrics** (~5 attributes)
```
llm.latency.total_ms, first_token_ms, ttft_percentile
agent.duration_ms, tool.duration_ms
```
**Why generic:** Performance optimization is universal concern. Every application cares about speed.

**Tool Execution Data** (~6 attributes/events)
```
tool.name, duration_ms, status, retry_count, error_type
span.add_event("tool.execution", {...})
```
**Why generic:** Understanding what tools LLM called is framework-level concern.

**Error Recovery Tracking** (~5 events)
```
error.retry (attempt, error_type, backoff_ms)
error.recovery (final_status, total_attempts, total_delay_ms)
```
**Why generic:** All applications need reliability tracking and retry visibility.

**Agent Configuration** (~10 attributes)
```
agent.temperature, max_tokens, top_p, frequency_penalty, presence_penalty
agent.tool_choice, parallel_tool_calls, response_format
agent.model, provider
```
**Why generic:** Standard agent configuration applies to all agents.

**Status & Lifecycle** (~6 attributes)
```
agent.status, start_time, end_time, execution_success
provider, model_version
```
**Why generic:** Execution context is framework concern.

### 2. Application Hooks (ProspectsRadar Example)

**Hook 1: Prospect Quality Scoring**
```
app.prospect.fit_score, data_quality, confidence, decision_reasoning
```
**Why application-specific:** "Quality" means different things in different domains. Only ProspectsRadar cares about prospect fit.

**Hook 2: Market Analysis Scoring**
```
app.market.dimension_market_size, competition, entry_difficulty, ...
app.market.overall_score
```
**Why application-specific:** Market analysis scoring is specific to ProspectsRadar's business model.

**Hook 3: Cost per Outcome**
```
app.cost.raaf_cents, overhead_cents, total_cents
app.cost.cost_per_market, cost_per_prospect, margin_percent
```
**Why application-specific:** Cost structure varies by application. ProspectsRadar's ROI calculation different from other apps.

**Hook 4: Search Query Analysis**
```
app.search.query_type, result_quality, target_market, specificity_score
```
**Why application-specific:** What makes a "good" search query depends on your domain.

**Hook 5: Stakeholder/Buying Signal Tracking**
```
app.stakeholders.found_count, average_confidence, discovery_method
app.signals.buying_signal_type, confidence, source
```
**Why application-specific:** Only relevant to ProspectsRadar's sales intelligence use case.

---

## 💡 Key Insight: The Separation Line

**Simple rule to determine if data belongs in RAAF or hooks:**

**RAAF:** "Does this metric apply to agents in general?"
- ✅ Token counting (yes, applies to all LLM calls)
- ✅ Latency tracking (yes, all agents have execution time)
- ✅ Tool execution (yes, any agent can call tools)
- ✅ Error recovery (yes, any agent might fail and retry)
- ❌ Prospect quality (no, only sales apps care)
- ❌ Market scoring (no, only market discovery apps care)
- ❌ Cost per outcome (no, metric depends on business model)

**Application Hooks:** "Is this specific to this application's domain?"
- ✅ Prospect quality scoring (ProspectsRadar-specific)
- ✅ Market analysis (ProspectsRadar-specific)
- ✅ Buying signal detection (ProspectsRadar-specific)
- ✅ Any company/industry-specific reasoning (ProspectsRadar-specific)

---

## 🔄 Implementation Timeline

### Phase 1: RAAF Generic Metrics (20 hours)

**RAAF Core Changes:**
- [ ] LLM collector: Add token and cost tracking
- [ ] Tool collector: Capture execution data
- [ ] Error collector: Add retry/recovery tracking
- [ ] Agent collector: Already has config tracking ✅
- [ ] Status collector: Add lifecycle tracking

**Rails UI:**
- [ ] Update LLM span component for tokens/costs
- [ ] Update Tool span component for execution data
- [ ] Update error visualization
- [ ] Update dashboard

**No Application-Specific Code in RAAF**

### Phase 2: Hook Infrastructure (15 hours)

**RAAF Core Changes:**
- [ ] Create Hook Registry
- [ ] Create SpanHookContext
- [ ] Add hook execution points
- [ ] Implement enable/disable_hook
- [ ] Comprehensive hook tests

**Hook Examples (Documentation):**
- [ ] Example hooks for common patterns
- [ ] Hook testing patterns
- [ ] Performance guidance

**Still No Application-Specific Code in RAAF**

### Phase 3: ProspectsRadar Hooks (10 hours)

**ProspectsRadar Application Code:**
- [ ] Register prospect quality hook
- [ ] Register market analysis hook
- [ ] Register cost tracking hook
- [ ] Register search analysis hook
- [ ] Register stakeholder hook

**Rails UI Updates:**
- [ ] Display application-level attributes
- [ ] Group app metrics separately from RAAF
- [ ] Create app-level dashboards

**This is APPLICATION code, not RAAF core**

---

## 🎯 Benefits of This Architecture

### For RAAF Framework
✅ **Remains Generic** - No application-specific logic
✅ **Reusable** - Works for sales, support, research, any agent application
✅ **Maintainable** - Clear scope, smaller codebase
✅ **Testable** - Framework tests don't need mock data from multiple domains
✅ **Extensible** - New applications just register hooks

### For Applications (like ProspectsRadar)
✅ **Clean Integration** - Just register hooks at init time
✅ **No Forking** - Don't need to modify RAAF
✅ **Domain-Focused** - Can capture domain-specific metrics freely
✅ **Data Together** - All metrics (RAAF + app) in single JSONB
✅ **Flexible** - Add/remove hooks as needs evolve

### For Operations/Observability Teams
✅ **Complete Picture** - Framework metrics + app metrics in same UI
✅ **Cost Visibility** - RAAF costs + app overhead tracked separately
✅ **Performance Tracking** - RAAF latency + app latency visible
✅ **Audit Trail** - All executions tracked in consistent format
✅ **Reusable Patterns** - Same hook patterns across all applications

---

## 📊 Data Storage Model

### Single JSONB Column: span_attributes

```json
{
  // RAAF Generic Metrics (Phase 1)
  "agent.name": "ProspectScoringAgent",
  "agent.temperature": 0.7,
  "agent.max_tokens": 2000,
  "agent.duration_ms": 5230,

  "llm.tokens.input": 1250,
  "llm.tokens.output": 342,
  "llm.cost.total_cents": 12,
  "llm.latency.total_ms": 2450,

  "tool.name": "web_search",
  "tool.duration_ms": 1234,
  "tool.status": "success",

  "agent.status": "success",
  "agent.execution_success": true,

  // Application-Specific Metrics (ProspectsRadar Hooks)
  "app.prospect.fit_score": 85,
  "app.prospect.confidence": 0.87,
  "app.prospect.decision_reasoning": "Company size matches target market",

  "app.market.dimension_market_size": 8.5,
  "app.market.dimension_competition": 6.2,
  "app.market.overall_score": 7.35,

  "app.cost.raaf_cents": 12,
  "app.cost.overhead_cents": 15,
  "app.cost.total_cents": 27,
  "app.cost.cost_per_prospect": 0.9,

  "app.search.query_type": "company_discovery",
  "app.search.result_quality": "high"
}
```

**Advantages:**
- ✅ All data in single queryable column
- ✅ RAAF and app metrics query together
- ✅ Easy to extend (just add keys)
- ✅ Backward compatible (new keys don't break existing queries)
- ✅ UI can display both without special logic

---

## 🚀 What This Means for the Roadmap

### Original Roadmap (40+ data points) - REVISED

**Phase 1: RAAF Generic (20 hours)**
- Token usage & costs (6 attributes)
- Latency metrics (5 attributes)
- Tool execution (6 attributes)
- Error recovery (5 events)
- Agent config (10 attributes) ✅ Already done
- Lifecycle tracking (6 attributes)
- **Total: ~35 RAAF-specific attributes**

**Phase 2: Hook Infrastructure (15 hours)**
- Hook registry & execution
- Context objects
- Enable/disable capability
- Documentation & patterns
- **Total: Framework enablement**

**Phase 3: ProspectsRadar Hooks (10 hours)**
- Prospect quality (4 attributes)
- Market analysis (6 attributes)
- Cost tracking (5 attributes)
- Search analysis (4 attributes)
- Stakeholder tracking (4 attributes)
- **Total: ~23 ProspectsRadar-specific attributes**

**Total Effort: ~45 hours (vs original 65 hour 3-phase estimate)**
**Cleaner Architecture: Clear separation of concerns**

---

## ✅ Decision Checklist

- ✅ **Decision Made:** RAAF = generic, hooks = domain-specific
- ✅ **Scope Clear:** Generic metrics defined, application metrics moved to hooks
- ✅ **Architecture Designed:** Two-tier system with hook execution points
- ✅ **Implementation Planned:** 3-phase approach (RAAF → Hooks → ProspectsRadar)
- ✅ **Benefits Articulated:** Why this approach is better
- ✅ **Examples Provided:** ProspectsRadar hooks as reference
- ✅ **Storage Model:** Single JSONB column for all metrics
- ✅ **UI Strategy:** Display both RAAF and app metrics together

---

## 📚 Related Documents

1. **PHASE_1_GENERIC_METRICS_ROADMAP.md**
   - Detailed Phase 1 implementation tasks
   - Generic metrics specifications
   - Why each metric is generic

2. **APPLICATION_HOOKS_DESIGN.md**
   - Complete hook mechanism design
   - Hook API and execution model
   - Implementation patterns
   - Testing strategies

3. **SPAN_DATA_QUICK_REFERENCE.md** (Original)
   - Still valid for understanding data types
   - Section on "Nice-to-Have" data now moves to hooks

---

## 🎓 Key Principles Established

1. **RAAF = Framework, Not Domain**
   - RAAF captures metrics that apply to agents in general
   - Domain-specific metrics belong in applications

2. **Hooks Over Modifications**
   - Applications extend without modifying RAAF
   - Hooks registered at initialization
   - Clean, testable, reusable pattern

3. **Single Source of Truth**
   - All metrics in span_attributes JSONB
   - No separate tracking systems
   - Unified observability

4. **Progressive Rollout**
   - Phase 1: Core generic metrics
   - Phase 2: Hook infrastructure
   - Phase 3: Application-specific hooks

---

## 🔮 Future Considerations

**Not Addressed Now (Possible Future Enhancement):**
- Span hook events (in addition to attributes)
- Processor-level hooks (pre/post processing)
- Span filtering based on hook conditions
- Cost allocation between RAAF and applications
- Analytics views combining RAAF and app metrics

**These can be added as needs emerge without changing the fundamental architecture.**

---

## 📝 Conclusion

By clearly separating **RAAF generic metrics** from **application-specific metrics**, we achieve:

- ✅ Framework reusability across applications
- ✅ Clean, maintainable codebase
- ✅ Extensibility without forking
- ✅ Domain-specific observability where needed
- ✅ Unified storage and querying

**Status:** Architecture decision finalized and documented.
**Next Step:** Implement Phase 1 generic metrics (20 hours).

---

**Document:** ARCHITECTURE_DECISION_RAAF_SCOPING.md
**Decision:** DEC-024 (NEW)
**Date:** 2025-10-24
**Status:** ✅ DECIDED
**Impact:** High - Shapes RAAF roadmap and all future observability work
