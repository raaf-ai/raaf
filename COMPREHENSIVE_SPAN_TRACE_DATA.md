# Comprehensive Span & Trace Data Recommendations

## Executive Summary

Beyond temperature and basic model settings, there are **40+ data points** that would provide deeper observability into agent execution, debugging capability, cost tracking, and quality metrics.

This document provides a complete framework for enhanced tracing in RAAF with prioritized recommendations.

---

## 1. AGENT-LEVEL DATA 🤖

### 1.1 Input/Output Guardrails (HIGH PRIORITY)

**Why capture:** Track security violations, content filtering, policy compliance

```ruby
# Capture these:
span.set_attribute("guardrail.name", "profanity_filter")
span.set_attribute("guardrail.triggered", true)
span.set_attribute("guardrail.type", "output")  # input or output
span.set_attribute("guardrail.blocked_reason", "Adult content detected")
span.set_attribute("guardrail.duration_ms", 125)
```

**Data points:**
- Guardrail name/type
- Whether triggered
- Blocked content reason
- Original vs filtered length
- Execution time
- Input vs output violation

**Storage:** Span attributes + events

---

### 1.2 Memory/Context Management (MEDIUM PRIORITY)

**Why capture:** Understand context flow, memory usage, performance optimization

```ruby
# Capture these:
span.set_attribute("context.initial_size", 3)
span.set_attribute("context.final_size", 5)
span.set_attribute("context.keys", "user_id,product,market")
span.add_event("context.modified", attributes: {
  added: "market_analysis,scoring_results",
  removed: ""
})
```

**Data points:**
- Initial context size/keys
- Final context size/keys
- What was added/removed
- Context variable types
- Memory consumption

**Storage:** Span attributes + events

---

### 1.3 Handoff Decisions (MEDIUM PRIORITY)

**Why capture:** Understand agent chains, debug orchestration, trace workflow

```ruby
# Capture these:
span.set_attribute("handoff.from", "MarketAnalyzer")
span.set_attribute("handoff.to", "ProspectScorer")
span.set_attribute("handoff.reason", "Market analysis complete, ready for scoring")
span.set_attribute("handoff.data_size", 5432)
span.add_event("handoff.initiated", attributes: {
  success: true,
  duration_ms: 245
})
```

**Data points:**
- Source and target agents
- Handoff reason
- Data size passed
- Success/failure
- Timing

**Storage:** Span attributes + events

---

### 1.4 Tool Execution Details (HIGH PRIORITY)

**Why capture:** Debug tool usage, identify bottlenecks, understand LLM decisions

```ruby
# Capture these:
span.add_event("tool.execution", attributes: {
  tool_name: "web_search",
  input_args: "{\"query\":\"BIM modellering\"}",
  result_size_bytes: 2345,
  duration_ms: 1234,
  success: true,
  retry_count: 0
})
```

**Data points:**
- Tool name and arguments
- Execution duration
- Result size
- Success/failure
- Retry attempts
- Metadata (duration_ms, timestamp, agent_name)

**Storage:** Span events (supports multiple tool calls)

---

### 1.5 Error Recovery Attempts (HIGH PRIORITY)

**Why capture:** Understand resilience, track failures, debug issues

```ruby
# Capture these:
span.add_event("retry.attempt", attributes: {
  attempt: 1,
  error: "ConnectionTimeout",
  backoff_ms: 1000,
  next_retry_in_ms: 1000
})

span.add_event("retry.exhausted", attributes: {
  total_attempts: 3,
  final_error: "Max retries exceeded"
})
```

**Data points:**
- Retry count
- Error reasons per retry
- Backoff strategy used
- Delay applied
- Circuit breaker status
- Recovery success

**Storage:** Span events

---

### 1.6 Prompt Variations (MEDIUM PRIORITY)

**Why capture:** Audit LLM inputs, track prompt evolution, template usage

```ruby
# Capture these:
span.set_attribute("prompt.system_length", 1250)
span.set_attribute("prompt.user_length", 342)
span.set_attribute("prompt.template", "ScoringPromptV2")
span.set_attribute("prompt.variables_used", "product,market,company")
```

**Data points:**
- System/user prompt text (truncated to 500 chars)
- Prompt template name
- Dynamic vs static
- Variables substituted
- Prompt length

**Storage:** Span attributes

---

### 1.7 Schema Validation Results (MEDIUM PRIORITY)

**Why capture:** Track LLM output quality, identify patterns, improve prompts

```ruby
# Capture these:
span.add_event("schema.validation", attributes: {
  valid: false,
  violations: 2,
  violation_types: ["missing_field", "type_mismatch"],
  mode: "tolerant",
  duration_ms: 45
})
```

**Data points:**
- Validation pass/fail
- Violation count and details
- Validation mode
- Field mapping transformations
- Execution time

**Storage:** Span events

---

### 1.8 JSON Repair Operations (LOW PRIORITY)

**Why capture:** Understand LLM output quality, track malformed JSON frequency

```ruby
# Capture these:
span.add_event("json.repair", attributes: {
  repairs_applied: "trailing_comma,markdown_extraction",
  original_size: 1234,
  repaired_size: 1200,
  success: true
})
```

**Data points:**
- Repair operations needed
- Original vs repaired size
- Success rate
- Common patterns

**Storage:** Span events

---

## 2. LLM-LEVEL DATA 💰

### 2.1 Token Usage (Detailed) - HIGH PRIORITY ⭐

**Why capture:** Cost tracking, quota management, prompt optimization

```ruby
# Capture these:
span.set_attribute("tokens.input", 1250)
span.set_attribute("tokens.output", 342)
span.set_attribute("tokens.cache_read", 500)           # New OpenAI feature
span.set_attribute("tokens.cache_created", 300)        # Cache writes
span.set_attribute("tokens.total", 2392)
span.set_attribute("tokens.efficiency_percent", 21.4)  # output / total * 100
```

**Data points:**
- Input/output tokens
- Cache read/creation tokens
- Total tokens
- Token efficiency ratio

**Why it matters:**
- 💰 Direct cost calculation
- 📊 Quota tracking
- 🚀 Cache ROI analysis
- 🎯 Prompt optimization targets

**Storage:** Span attributes

---

### 2.2 Cost Calculations - HIGH PRIORITY ⭐

**Why capture:** Budget tracking, cost attribution, financial reporting

```ruby
# Capture these:
span.set_attribute("cost.input_cents", 15)           # $0.15
span.set_attribute("cost.output_cents", 8)           # $0.08
span.set_attribute("cost.cache_savings_cents", 5)    # Savings!
span.set_attribute("cost.total_cents", 18)           # $0.18
span.set_attribute("cost.per_token_cents", 0.75)
span.set_attribute("cost.model", "gpt-4o")
span.set_attribute("cost.provider", "ResponsesProvider")
```

**Data points:**
- Input cost
- Output cost
- Cache savings
- Total cost
- Cost per token
- Model/provider

**Why it matters:**
- 💰 Budget management
- 📈 Cost per workflow
- 🎯 ROI calculation
- 📊 Financial forecasting

**Storage:** Span attributes

---

### 2.3 Latency/Timing Metrics - HIGH PRIORITY ⭐

**Why capture:** Performance SLAs, infrastructure optimization, user experience

```ruby
# Capture these:
span.set_attribute("latency.total_ms", 2345)         # End-to-end
span.set_attribute("latency.ttft_ms", 450)           # Time to first token
span.set_attribute("latency.per_token_ms", 6.8)      # Throughput
span.set_attribute("latency.network_ms", 150)        # Infrastructure quality
```

**Data points:**
- Total latency
- Time to first token
- Time per token
- Network latency
- Queue wait time

**Why it matters:**
- ⚡ Performance SLAs
- 📊 Bottleneck identification
- 🌍 Infrastructure quality
- 👥 User experience

**Storage:** Span attributes

---

### 2.4 Retry Attempts & Backoff - MEDIUM PRIORITY

**Why capture:** Stability metrics, reliability tracking, provider issues

```ruby
# Capture these:
span.add_event("llm.retry", attributes: {
  attempt: 1,
  status_code: 429,
  error: "Rate limited",
  backoff_ms: 1000,
  success: false
})

span.add_event("llm.retry.succeeded", attributes: {
  total_attempts: 2,
  total_delay_ms: 2500
})
```

**Data points:**
- Retry count
- HTTP status codes
- Error messages
- Backoff delays
- Final success

**Storage:** Span events

---

### 2.5 Provider-Specific Metadata - MEDIUM PRIORITY

**Why capture:** Multi-provider support, provider issue tracking, correlation

```ruby
# Capture these:
span.set_attribute("provider.name", "ResponsesProvider")
span.set_attribute("provider.endpoint", "/v1/responses")
span.set_attribute("provider.request_id", "req_1234567890")
span.set_attribute("provider.rate_limit_remaining", "450/500")
span.set_attribute("provider.api_version", "v1")
```

**Data points:**
- Provider name
- API endpoint
- Request ID
- Rate limit info
- API version
- Batch size

**Storage:** Span attributes

---

### 2.6 Model Capabilities Used - MEDIUM PRIORITY

**Why capture:** Feature usage tracking, capability constraints

```ruby
# Capture these:
span.set_attribute("model.capabilities.tools", "web_search,calculator")
span.set_attribute("model.capabilities.response_format", "json_schema")
span.set_attribute("model.capabilities.vision", false)
span.set_attribute("model.capabilities.parallel_tools", true)
span.set_attribute("model.capabilities.streaming", false)
```

**Data points:**
- Tools used
- Response format
- Vision capability
- Parallel tool calls
- Streaming used

**Storage:** Span attributes

---

### 2.7 Rate Limiting Information - MEDIUM PRIORITY

**Why capture:** Quota tracking, quota breaches, rate limit planning

```ruby
# Capture these:
span.add_event("rate_limit.status", attributes: {
  remaining_requests: "450",
  limit_requests: "500",
  remaining_tokens: "2.3M",
  limit_tokens: "3M",
  reset_time: "2025-10-24T14:32:00Z"
})

span.add_event("rate_limit.exceeded") if http_429
```

**Data points:**
- Rate limit remaining
- Rate limit total
- Tokens remaining
- Tokens total
- Reset time

**Storage:** Span events

---

## 3. TOOL-LEVEL DATA 🔧

### 3.1 Tool Selection Reasoning - MEDIUM PRIORITY

**Why capture:** Understand LLM decision logic, debug tool usage

```ruby
# Capture these:
span.set_attribute("tool.available", "web_search,calculate,get_news")
span.add_event("tool.selected", attributes: {
  tool_name: "web_search",
  reason: "Need current information about market trends",
  order: 1
})
```

**Data points:**
- Available tools
- Selected tools
- Selection reason
- Call order

**Storage:** Span attributes + events

---

### 3.2 Tool Parameter Values & Validation - MEDIUM PRIORITY

**Why capture:** Debug LLM mistakes, track parameter patterns

```ruby
# Capture these:
span.add_event("tool.parameters", attributes: {
  parameters_json: "{\"query\":\"BIM Netherlands\"}",
  valid: true,
  validation_errors: ""
})
```

**Data points:**
- Parameter values (truncated)
- Validation results
- Type mismatches
- Missing required fields
- Default values used

**Storage:** Span events

---

### 3.3 Tool Execution Duration - MEDIUM PRIORITY

**Why capture:** Identify bottlenecks, understand tool performance

```ruby
# Capture these:
span.set_attribute("tool.execution_ms", 1234)
span.set_attribute("tool.api_call_ms", 850)
span.set_attribute("tool.processing_ms", 384)
```

**Data points:**
- Total execution time
- API call duration
- Processing time

**Storage:** Span attributes

---

### 3.4 Tool Error Handling - MEDIUM PRIORITY

**Why capture:** Track tool failures, debug issues

```ruby
# Capture these:
span.add_event("tool.error", attributes: {
  error_type: "NetworkTimeout",
  error_message: "Connection timeout after 30s",
  retry_count: 2,
  fallback_used: "cache_response"
})
```

**Data points:**
- Error type/message
- Retry behavior
- Fallback strategy
- Recovery success

**Storage:** Span events

---

### 3.5 Tool Result Size/Complexity - LOW PRIORITY

**Why capture:** Memory management, context window optimization

```ruby
# Capture these:
span.set_attribute("tool.result_size_bytes", 2456)
span.set_attribute("tool.result_type", "Array")
span.set_attribute("tool.result_truncated", false)
```

**Data points:**
- Result size
- Result complexity
- Truncation status
- Original size if truncated

**Storage:** Span attributes

---

### 3.6 Tool Chaining - LOW PRIORITY

**Why capture:** Understand complex workflows

```ruby
# Capture these:
span.add_event("tool.chain", attributes: {
  chain_sequence: "search_web -> summarize -> verify",
  chaining_successful: true,
  iterations: 1
})
```

**Data points:**
- Chained tools
- Dependencies
- Success status
- Iteration count

**Storage:** Span events

---

## 4. PIPELINE-LEVEL DATA 🔄

### 4.1 Agent Sequence/Execution Order - MEDIUM PRIORITY

**Why capture:** Understand orchestration, identify bottlenecks

```ruby
# Capture these:
span.set_attribute("pipeline.agent_sequence", "MarketAnalyzer -> ProspectScorer")
span.set_attribute("pipeline.execution_mode", "sequential")
span.set_attribute("pipeline.critical_path_ms", 45000)

span.add_event("pipeline.agent_executed", attributes: {
  agent: "MarketAnalyzer",
  duration_ms: 15000,
  position: 1,
  of_total: 2
})
```

**Data points:**
- Agent sequence
- Execution mode (sequential/parallel)
- Each agent's timing
- Critical path
- Position tracking

**Storage:** Span attributes + events

---

### 4.2 Data Transformations Between Agents - MEDIUM PRIORITY

**Why capture:** Understand data flow, identify loss/corruption

```ruby
# Capture these:
span.add_event("pipeline.data_transformation", attributes: {
  from_agent: "MarketAnalyzer",
  to_agent: "ProspectScorer",
  input_size: 5000,
  output_size: 8000,
  fields_added: "market_score,strategic_fit",
  fields_removed: ""
})
```

**Data points:**
- Input to agent
- Output from agent
- Transformations applied
- Data loss/gain
- Schema compliance

**Storage:** Span events

---

### 4.3 Parallel Execution Metrics - MEDIUM PRIORITY

**Why capture:** Understand parallelism benefits, optimize concurrency

```ruby
# Capture these:
span.add_event("pipeline.parallel_execution", attributes: {
  branch_count: 3,
  slowest_branch: "CompetitorAnalyzer",
  slowest_branch_ms: 5000,
  sync_wait_ms: 1200,
  efficiency_percent: 85.7
})
```

**Data points:**
- Branch count
- Slowest branch
- Synchronization wait time
- Parallelism efficiency

**Storage:** Span events

---

### 4.4 Pipeline Performance Metrics - HIGH PRIORITY ⭐

**Why capture:** End-to-end performance, SLA tracking

```ruby
# Capture these:
span.set_attribute("pipeline.total_duration_ms", 47500)
span.set_attribute("pipeline.overhead_ms", 2500)  # Coordination cost
span.set_attribute("pipeline.agent.MarketAnalyzer_ms", 15000)
span.set_attribute("pipeline.agent.ProspectScorer_ms", 30000)
span.set_attribute("pipeline.throughput_items_per_sec", 2.1)
```

**Data points:**
- Total pipeline duration
- Per-agent durations
- Overhead time
- Throughput

**Storage:** Span attributes

---

## 5. CONTEXT/STATE DATA 📚

### 5.1 Context Variables at Each Step - LOW PRIORITY

**Why capture:** Debug context flow, understand mutations

```ruby
# Capture these:
span.add_event("context.snapshot", attributes: {
  stage: "start",
  keys: "user_id,product,market",
  size_bytes: 1234
})

span.add_event("context.mutation", attributes: {
  added: "market_analysis,prospects",
  removed: ""
})
```

**Data points:**
- Initial/final context
- Keys present
- Mutations (additions/removals)
- Variable types

**Storage:** Span events

---

### 5.2 Context Size Evolution - LOW PRIORITY

**Why capture:** Memory optimization, scaling predictions

```ruby
# Capture these:
span.set_attribute("context.initial_size_bytes", 1200)
span.set_attribute("context.final_size_bytes", 3400)
span.set_attribute("context.max_size_bytes", 3400)
span.set_attribute("context.growth_rate_bytes_per_agent", 1100)
```

**Data points:**
- Initial/final size
- Max size reached
- Growth rate
- Per-agent contribution

**Storage:** Span attributes

---

### 5.3 Memory Consumption - LOW PRIORITY

**Why capture:** Production optimization, resource planning

```ruby
# Capture these:
span.set_attribute("memory.initial_mb", 125)
span.set_attribute("memory.final_mb", 156)
span.set_attribute("memory.delta_mb", 31)
```

**Data points:**
- Process memory before/after
- Delta
- Peak usage

**Storage:** Span attributes

---

### 5.4 Thread/Concurrency Context - LOW PRIORITY

**Why capture:** Multi-threaded debugging, lock contention

```ruby
# Capture these:
span.set_attribute("thread.id", 47232)
span.set_attribute("thread.pool_size", 8)

span.add_event("sync.mutex_acquired", attributes: {
  mutex_name: "configuration_lock",
  wait_ms: 45
})
```

**Data points:**
- Thread ID
- Pool size
- Lock contention
- Synchronization events

**Storage:** Span attributes + events

---

## 6. QUALITY METRICS ✨

### 6.1 Response Quality Indicators - MEDIUM PRIORITY

**Why capture:** Understand output quality, identify improvements

```ruby
# Capture these:
span.set_attribute("quality.score", 85)
span.set_attribute("quality.hallucination_detected", false)
span.set_attribute("quality.relevance_score", 92)
span.set_attribute("quality.completeness_score", 88)
```

**Data points:**
- Overall quality score
- Hallucination detection
- Relevance score
- Completeness score
- User satisfaction (if available)

**Storage:** Span attributes

---

### 6.2 Schema Validation Statistics - MEDIUM PRIORITY

**Why capture:** Track LLM consistency, improve prompts

```ruby
# Capture these:
span.set_attribute("validation.pass_rate_percent", 94.5)
span.set_attribute("validation.violation_count", 1)
span.set_attribute("validation.most_common_violation", "type_mismatch")
```

**Data points:**
- Pass rate
- Violation count
- Common violation types
- Trend analysis

**Storage:** Span attributes

---

### 6.3 Guardrail Violations - MEDIUM PRIORITY

**Why capture:** Safety tracking, compliance

```ruby
# Capture these:
span.set_attribute("safety.guardrail_triggered", "profanity_filter")
span.set_attribute("safety.violation_rate_percent", 2.3)
```

**Data points:**
- Violation type
- Frequency
- Rate across requests

**Storage:** Span attributes

---

### 6.4 Fallback Usage - MEDIUM PRIORITY

**Why capture:** Understand failure recovery, system stability

```ruby
# Capture these:
span.add_event("fallback.triggered", attributes: {
  fallback_type: "retry",
  success: true,
  latency_increase_ms: 2500
})
```

**Data points:**
- Fallback type
- Success rate
- Latency impact
- Frequency

**Storage:** Span events

---

## PRIORITY IMPLEMENTATION ROADMAP

### Phase 1: Core Observability (IMMEDIATE)
- ✅ Agent model settings (DONE)
- ⭐ **Token usage (detailed)**
- ⭐ **Cost calculations**
- ⭐ **Pipeline performance metrics**
- ⭐ **Tool execution details**
- ⭐ **Error recovery tracking**

### Phase 2: Enhanced Debugging (NEXT QUARTER)
- **Guardrail tracking**
- **Context management**
- **Handoff decisions**
- **Prompt tracking**
- **Schema validation**
- **Latency metrics**

### Phase 3: Quality & Analytics (FOLLOWING QUARTER)
- **Quality metrics**
- **Validation statistics**
- **Tool chaining**
- **Memory tracking**
- **Concurrency metrics**
- **Fallback analysis**

---

## IMPLEMENTATION EXAMPLE

Here's how to implement comprehensive token + cost tracking:

```ruby
class EnhancedLLMSpanCollector < BaseCollector
  def collect_result(component, result)
    attrs = super(component, result)

    # Token usage
    attrs["llm.tokens.input"] = result.usage[:prompt_tokens] || 0
    attrs["llm.tokens.output"] = result.usage[:completion_tokens] || 0
    attrs["llm.tokens.cache_read"] = result.usage[:cache_read_input_tokens] || 0
    attrs["llm.tokens.cache_created"] = result.usage[:cache_creation_input_tokens] || 0
    attrs["llm.tokens.total"] = result.usage[:total_tokens] || 0

    # Cost calculation
    calculator = TokenCostCalculator.new(model: result.model)
    input_cost = calculator.input_cost(result.usage[:prompt_tokens])
    output_cost = calculator.output_cost(result.usage[:completion_tokens])
    cache_savings = calculator.cache_benefit(result.usage[:cache_read_input_tokens])

    attrs["cost.input_cents"] = input_cost
    attrs["cost.output_cents"] = output_cost
    attrs["cost.cache_savings_cents"] = cache_savings
    attrs["cost.total_cents"] = input_cost + output_cost - cache_savings

    # Latency
    attrs["latency.total_ms"] = result.elapsed_time_ms
    attrs["latency.ttft_ms"] = result.time_to_first_token_ms if result.streaming?

    attrs
  end
end
```

---

## STORAGE & PERFORMANCE GUIDELINES

### Attribute Limits
```ruby
max_attribute_length = 2000      # Truncate large values
max_event_count = 100            # Events per span
max_attributes_per_span = 200    # Total attributes
```

### Truncation Strategy
```ruby
# User inputs: 200 chars max
# Tool results: 500 chars max
# Error messages: 200 chars max
# Prompts: 500 chars max
# JSON responses: 1000 chars max
```

### Privacy/Security
```ruby
# Never log:
- API keys, credentials
- PII (unless encrypted)
- Full user inputs
- Sensitive data

# Always truncate:
- Long prompts
- Large tool results
- Full error stacktraces (first 5 lines only)
```

---

## BENEFITS SUMMARY

| Data Category | Benefit | Impact |
|---------------|---------|--------|
| Token usage | Cost tracking, optimization | 💰 20-30% cost reduction |
| Latency metrics | Performance SLAs | ⚡ Identify bottlenecks |
| Tool execution | Debug LLM decisions | 🔧 Faster troubleshooting |
| Error recovery | Reliability metrics | 🛡️ System stability |
| Guardrails | Safety compliance | 🔒 Security audit trail |
| Quality metrics | Output improvements | ✨ Continuous improvement |
| Pipeline metrics | Orchestration visibility | 🔄 Workflow optimization |

---

**Status:** Recommended for implementation phases 2-3
**Priority:** Medium (after Phase 1 completion)
**Estimated Effort:** 40-60 hours total across all phases
