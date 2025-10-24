# Application Hooks Design: Domain-Specific Span Data

> **Purpose:** Enable applications to inject custom, domain-specific data into RAAF spans without modifying RAAF core
>
> **Architecture:** Hook-based extensibility pattern for span customization
> **Status:** Design Document (Ready for Implementation)
> **Updated:** 2025-10-24

---

## 🎯 Problem Statement

**RAAF Scope:** Generic agent execution metrics (tokens, costs, latency, tool execution)

**Application Needs:** Domain-specific metrics (prospect quality, market scoring, cost per outcome, search patterns)

**Challenge:** How to support application-specific data without bloating RAAF core?

**Solution:** Hook-based extensibility that applications register during initialization.

---

## 🏗️ Architecture Overview

### Two-Layer Data Capture

```
┌─────────────────────────────────────────────────────┐
│         RAAF SPAN COLLECTION (Core)                 │
├─────────────────────────────────────────────────────┤
│  • Token usage (input, output, cache)               │
│  • Costs (input, output, savings)                   │
│  • Latency (total, first-token, ttft)               │
│  • Tool execution (name, duration, status)          │
│  • Error recovery (retry, backoff, final status)    │
│  • Agent config (model settings, provider)          │
│  • Execution status (start, end, success/failure)   │
└─────────────────────────────────────────────────────┘
                      ↓ (after core collection)
┌─────────────────────────────────────────────────────┐
│    APPLICATION HOOKS (Domain-Specific)              │
├─────────────────────────────────────────────────────┤
│  hook_1: Prospect Quality Scoring                   │
│    └─ prospect.fit_score, confidence, reasoning     │
│                                                     │
│  hook_2: Cost Tracking Per Outcome                  │
│    └─ execution.cost_cents, margin, roi_percentile  │
│                                                     │
│  hook_3: Market Analysis Scoring                    │
│    └─ market.dimension_scores (size, competition...)│
│                                                     │
│  hook_4: Search Pattern Analysis                    │
│    └─ search.query_type, result_quality, count      │
│                                                     │
│  hook_5: Application-Specific (Custom)              │
│    └─ Any domain-specific metrics                   │
└─────────────────────────────────────────────────────┘
                      ↓ (after all hooks)
┌─────────────────────────────────────────────────────┐
│        STORED IN span_attributes (JSONB)            │
├─────────────────────────────────────────────────────┤
│  All RAAF metrics + All application metrics         │
│  In single JSONB column for efficient querying      │
└─────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Clean Separation**: RAAF captures generic, applications capture domain-specific
2. **No Modification**: Applications don't modify RAAF code
3. **Pluggable**: Hooks register at initialization time
4. **Composable**: Multiple hooks can run for same span
5. **Testable**: Mock hooks in tests without touching RAAF
6. **Type-Safe**: Hook interface clearly defined
7. **Performant**: Minimal overhead (< 1ms per span)

---

## 📐 Hook Mechanism Design

### 1. Hook Registration API

```ruby
# In RAAF core: Hook registry and registration
module RAAF
  class Configuration
    def initialize
      @span_hooks = []
      @event_hooks = []
      @processor_hooks = []
    end

    def register_span_hook(name = nil, &block)
      @span_hooks << {
        name: name || "anonymous_#{@span_hooks.length}",
        block: block,
        enabled: true
      }
    end

    def register_event_hook(name = nil, &block)
      @event_hooks << {
        name: name || "anonymous_#{@event_hooks.length}",
        block: block,
        enabled: true
      }
    end

    def register_processor_hook(processor)
      @processor_hooks << processor
    end

    attr_reader :span_hooks, :event_hooks, :processor_hooks

    def disable_hook(name)
      all_hooks = @span_hooks + @event_hooks
      hook = all_hooks.find { |h| h[:name] == name }
      hook[:enabled] = false if hook
    end

    def enable_hook(name)
      all_hooks = @span_hooks + @event_hooks
      hook = all_hooks.find { |h| h[:name] == name }
      hook[:enabled] = true if hook
    end
  end
end

# Global configuration access
RAAF.configuration.register_span_hook(:prospect_quality) do |span, context|
  # Application code here
end
```

### 2. Hook Execution Points

**Span Hooks** - After span attributes are set:
```ruby
# In RAAF::Tracing::SpanCollector
def finalize_span(span, component)
  # Step 1: RAAF collects generic data
  set_generic_attributes(span, component)

  # Step 2: Invoke all registered hooks
  RAAF.configuration.span_hooks.each do |hook_config|
    next unless hook_config[:enabled]

    context = SpanHookContext.new(
      span: span,
      component: component,
      span_type: determine_span_type(component)
    )

    hook_config[:block].call(span, context)
  end

  # Step 3: Store span
  span.finish
end
```

**Event Hooks** - After span events are recorded:
```ruby
# For sequential events (retries, tool calls, etc.)
def add_event_with_hooks(span, event_name, attributes)
  # Step 1: Add event to span
  span.add_event(event_name, attributes: attributes)

  # Step 2: Invoke event hooks
  RAAF.configuration.event_hooks.each do |hook_config|
    next unless hook_config[:enabled]

    context = EventHookContext.new(
      span: span,
      event_name: event_name,
      event_attributes: attributes
    )

    hook_config[:block].call(span, context)
  end
end
```

### 3. Hook Context (What Applications Receive)

```ruby
# RAAF provides context object to all hooks
class SpanHookContext
  attr_reader :span, :component, :span_type, :parent_span, :trace_id

  def initialize(span:, component:, span_type:, parent_span: nil, trace_id: nil)
    @span = span
    @component = component
    @span_type = span_type  # :agent, :llm, :tool, :handoff, :pipeline
    @parent_span = parent_span
    @trace_id = trace_id
  end

  # Helper methods for common queries
  def agent_name
    @component.name if @component.respond_to?(:name)
  end

  def tool_name
    @component.name if @span_type == :tool
  end

  def model
    @component.model if @component.respond_to?(:model)
  end

  def is_agent_span?
    @span_type == :agent
  end

  def is_tool_span?
    @span_type == :tool
  end

  def is_llm_span?
    @span_type == :llm
  end

  # Direct access to span attributes (what was already set)
  def existing_attributes
    @span.attributes || {}
  end

  # Check if specific RAAF metric exists
  def has_metric?(metric_name)
    @span.attributes&.key?(metric_name)
  end

  def get_metric(metric_name)
    @span.attributes&.dig(metric_name)
  end
end
```

### 4. Hook Function Signature

```ruby
# All hooks follow this signature:
# def my_hook(span, context)
#   span.set_attribute("app.key", value)
# end

# Example hook with full context access
RAAF.configuration.register_span_hook(:example_hook) do |span, context|
  # Span: OpenTelemetry::SDK::Trace::Span object
  # context: SpanHookContext object

  # Check span type
  if context.is_agent_span?
    span.set_attribute("app.agent_hook_ran", true)
  end

  # Access component information
  agent_name = context.agent_name
  span.set_attribute("app.source_agent", agent_name) if agent_name

  # Check what RAAF already captured
  if context.has_metric?("llm.tokens.input")
    input_tokens = context.get_metric("llm.tokens.input")
    span.set_attribute("app.token_ratio", input_tokens.to_f / 1000)
  end

  # Conditional data capture
  case context.span_type
  when :agent
    span.set_attribute("app.span_level", "agent")
  when :tool
    span.set_attribute("app.span_level", "tool")
  when :llm
    span.set_attribute("app.span_level", "llm")
  end
end
```

---

## 💼 Application Implementation Patterns

### Pattern 1: Conditional Hook Based on Agent Name

```ruby
# config/initializers/raaf_hooks.rb
RAAF.configure do |config|
  config.register_span_hook(:prospect_scoring) do |span, context|
    # Only run for specific agent
    next unless context.agent_name == "ProspectScoringAgent"

    # Calculate and store application-specific metrics
    span.set_attribute("app.prospect.quality_score", 85)
    span.set_attribute("app.prospect.data_completeness", 0.92)
    span.set_attribute("app.prospect.confidence", 0.87)
  end
end
```

### Pattern 2: Tool-Level Customization

```ruby
RAAF.configure do |config|
  config.register_span_hook(:tool_analysis) do |span, context|
    next unless context.is_tool_span?

    tool_name = context.tool_name
    case tool_name
    when "web_search"
      span.set_attribute("app.search.query_type", classify_query)
      span.set_attribute("app.search.result_quality", assess_quality)
    when "database_lookup"
      span.set_attribute("app.db.result_count", fetch_count)
      span.set_attribute("app.db.cache_hit", was_cached?)
    end
  end
end
```

### Pattern 3: Cost Tracking

```ruby
RAAF.configure do |config|
  config.register_span_hook(:cost_tracking) do |span, context|
    # Only on agent spans (top level)
    next unless context.is_agent_span?

    # Get RAAF's cost metric
    raaf_cost_cents = context.get_metric("llm.cost.total_cents") || 0

    # Add application overhead
    overhead_cents = calculate_infrastructure_cost
    total_cents = raaf_cost_cents + overhead_cents

    span.set_attribute("app.cost.raaf_cents", raaf_cost_cents)
    span.set_attribute("app.cost.overhead_cents", overhead_cents)
    span.set_attribute("app.cost.total_cents", total_cents)
    span.set_attribute("app.cost.margin_percent", calculate_margin(total_cents))
  end
end
```

### Pattern 4: Hierarchical Span Analysis

```ruby
RAAF.configure do |config|
  config.register_span_hook(:execution_analysis) do |span, context|
    # Analyze span hierarchy
    span.set_attribute("app.span.type", context.span_type.to_s)
    span.set_attribute("app.span.depth", calculate_depth(context.parent_span))

    # Track metrics by level
    if context.is_agent_span?
      span.set_attribute("app.execution.level", "agent")
      span.set_attribute("app.execution.total_duration_ms", get_duration(span))
    elsif context.is_llm_span?
      span.set_attribute("app.execution.level", "llm")
      input_tokens = context.get_metric("llm.tokens.input")
      span.set_attribute("app.efficiency.tokens_per_ms", calculate_efficiency(input_tokens))
    elsif context.is_tool_span?
      span.set_attribute("app.execution.level", "tool")
      tool_duration = context.get_metric("tool.duration_ms")
      span.set_attribute("app.performance.fast?", tool_duration < 1000)
    end
  end
end
```

### Pattern 5: Multi-Hook Composition

```ruby
RAAF.configure do |config|
  # Hook 1: Market Analysis
  config.register_span_hook(:market_analysis) do |span, context|
    next unless context.agent_name == "MarketAnalysisAgent"

    span.set_attribute("app.market.size_score", 8.5)
    span.set_attribute("app.market.competition_score", 6.2)
    span.set_attribute("app.market.overall_score", 7.35)
  end

  # Hook 2: Cost Analysis (runs independently)
  config.register_span_hook(:cost_analysis) do |span, context|
    next unless context.is_agent_span?

    span.set_attribute("app.cost.total_cents", 45)
    span.set_attribute("app.cost.per_market", 45.0 / 3)
  end

  # Hook 3: Performance Analysis (runs independently)
  config.register_span_hook(:performance_analysis) do |span, context|
    next unless context.is_agent_span?

    duration_ms = get_span_duration(span)
    span.set_attribute("app.performance.duration_seconds", (duration_ms / 1000.0).round(2))
    span.set_attribute("app.performance.slow?", duration_ms > 30000)
  end

  # All three hooks run in order, independently
  # Span ends up with attributes from all three hooks
end
```

---

## 🔍 ProspectsRadar Hook Examples

### Hook 1: Prospect Quality Scoring

```ruby
RAAF.configure do |config|
  config.register_span_hook(:prospect_quality_scoring) do |span, context|
    next unless context.agent_name == "ProspectScoringAgent"
    next unless context.is_agent_span?

    # Get RAAF metrics first
    execution_time_ms = context.get_metric("agent.duration_ms")

    # Application-specific data
    span.set_attribute("app.prospect.fit_score", calculate_fit_score)
    span.set_attribute("app.prospect.data_quality", assess_data_quality)
    span.set_attribute("app.prospect.confidence", calculate_confidence)
    span.set_attribute("app.prospect.decision_reasoning", collect_reasoning)
    span.set_attribute("app.prospect.time_to_score_ms", execution_time_ms)
  end
end
```

### Hook 2: Market Discovery Cost & ROI

```ruby
RAAF.configure do |config|
  config.register_span_hook(:market_discovery_roi) do |span, context|
    next unless context.agent_name == "MarketDiscoveryExecutor"
    next unless context.is_agent_span?

    # Combine RAAF and app metrics for ROI calculation
    raaf_cost_cents = context.get_metric("llm.cost.total_cents") || 0
    infrastructure_cost_cents = 15  # App-specific overhead

    total_cost_cents = raaf_cost_cents + infrastructure_cost_cents
    markets_discovered = get_markets_from_result(span)
    cost_per_market = markets_discovered > 0 ? total_cost_cents / markets_discovered : 0

    span.set_attribute("app.market_discovery.raaf_cost_cents", raaf_cost_cents)
    span.set_attribute("app.market_discovery.infrastructure_cost_cents", infrastructure_cost_cents)
    span.set_attribute("app.market_discovery.total_cost_cents", total_cost_cents)
    span.set_attribute("app.market_discovery.markets_discovered", markets_discovered)
    span.set_attribute("app.market_discovery.cost_per_market_cents", cost_per_market)
  end
end
```

### Hook 3: Dimension Scoring Tracking

```ruby
RAAF.configure do |config|
  config.register_span_hook(:market_dimension_tracking) do |span, context|
    next unless context.agent_name == "MarketScoringAgent"
    next unless context.is_agent_span?

    dimension_scores = extract_dimension_scores_from_result(span)

    span.set_attribute("app.market.dimension_market_size", dimension_scores[:market_size])
    span.set_attribute("app.market.dimension_competition", dimension_scores[:competition])
    span.set_attribute("app.market.dimension_entry_difficulty", dimension_scores[:entry_difficulty])
    span.set_attribute("app.market.dimension_revenue_opportunity", dimension_scores[:revenue_opportunity])
    span.set_attribute("app.market.dimension_strategic_alignment", dimension_scores[:strategic_alignment])
    span.set_attribute("app.market.dimension_product_fit", dimension_scores[:product_fit])
    span.set_attribute("app.market.overall_score", calculate_overall_score(dimension_scores))
  end
end
```

### Hook 4: Search Query Analysis

```ruby
RAAF.configure do |config|
  config.register_span_hook(:search_query_analysis) do |span, context|
    next unless context.is_tool_span?
    next unless context.tool_name == "web_search"

    # Analyze what was searched
    search_query = extract_tool_input(span)

    span.set_attribute("app.search.query_length", search_query.length)
    span.set_attribute("app.search.query_type", classify_search_query(search_query))
    span.set_attribute("app.search.target_market", extract_market_from_query(search_query))
    span.set_attribute("app.search.specificity_score", assess_query_specificity(search_query))
  end
end
```

### Hook 5: Stakeholder Discovery

```ruby
RAAF.configure do |config|
  config.register_span_hook(:stakeholder_discovery) do |span, context|
    next unless context.agent_name == "StakeholderDiscoveryAgent"
    next unless context.is_agent_span?

    stakeholder_count = count_stakeholders_found(span)
    average_confidence = calculate_average_confidence(span)

    span.set_attribute("app.stakeholders.found_count", stakeholder_count)
    span.set_attribute("app.stakeholders.average_confidence", average_confidence)
    span.set_attribute("app.stakeholders.discovery_method", "ai_research")
    span.set_attribute("app.stakeholders.linkedin_urls_found", count_linkedin_urls(span))
  end
end
```

---

## 🧪 Testing Hooks

### Unit Test Pattern

```ruby
# spec/support/raaf_hooks_spec_helper.rb
module RAFHooksSpecHelper
  def mock_hook(name = :test_hook)
    called = []

    RAAF.configuration.register_span_hook(name) do |span, context|
      called << { span: span, context: context }
    end

    yield(called) if block_given?

    # Cleanup
    RAAF.configuration.disable_hook(name)
  end
end

# spec/hooks/prospect_quality_hook_spec.rb
describe "Prospect Quality Hook" do
  include RAFHooksSpecHelper

  it "adds quality score to span" do
    mock_hook(:test_quality) do |called|
      # Execute agent
      agent = ProspectScoringAgent.new
      result = agent.run

      # Verify hook was called
      expect(called.length).to eq(1)

      # Verify hook added attributes
      span_context = called.first[:context]
      expect(span_context.agent_name).to eq("ProspectScoringAgent")
    end
  end
end
```

### Integration Test Pattern

```ruby
describe "Application Hooks Integration" do
  it "captures RAAF metrics and applies hooks" do
    # Create agent with tracing
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(RAAF::Tracing::ActiveRecordProcessor.new)

    agent = ProspectScoringAgent.new
    runner = RAAF::Runner.new(agent: agent, tracer: tracer)
    result = runner.run("Score this prospect")

    # Verify RAAF metrics exist
    span_record = SpanRecord.last
    expect(span_record.span_attributes["agent.temperature"]).to be_present
    expect(span_record.span_attributes["llm.tokens.input"]).to be_present

    # Verify application hooks added data
    expect(span_record.span_attributes["app.prospect.quality_score"]).to be_present
    expect(span_record.span_attributes["app.prospect.confidence"]).to be_present
  end
end
```

---

## 🎯 Performance Considerations

### Overhead Analysis

```
Hook Execution Overhead (per span):

1. Hook lookup:               < 0.1ms
2. Context object creation:   < 0.1ms
3. Hook block execution:      0.5-2ms (depends on hook complexity)
4. Attribute setting:         < 0.1ms (OpenTelemetry optimized)
───────────────────────────────────────
Total per span:               < 3ms

Example span timing:
- Agent span: 5230ms total + 1ms hooks = 5231ms (0.02% overhead)
- Tool span: 1234ms total + 0.5ms hooks = 1234.5ms (0.04% overhead)
- LLM span: 2450ms total + 0.5ms hooks = 2450.5ms (0.02% overhead)
```

### Best Practices

1. **Keep hooks lightweight** - Quick attribute setting only
2. **Avoid expensive operations** - No database queries in hooks
3. **Use conditional checks** - Skip hooks for irrelevant spans early
4. **Cache results** - Compute once, use in multiple hooks
5. **Lazy evaluation** - Only compute what's needed

---

## 📋 Implementation Checklist

### Phase 1: Hook Infrastructure
- [ ] Add hook registry to RAAF::Configuration
- [ ] Create SpanHookContext class
- [ ] Add hook execution points in collectors
- [ ] Implement enable/disable_hook methods
- [ ] Write comprehensive hook tests

### Phase 2: ProspectsRadar Hooks
- [ ] Prospect quality scoring hook
- [ ] Market discovery ROI hook
- [ ] Dimension scoring hook
- [ ] Search query analysis hook
- [ ] Stakeholder discovery hook

### Phase 3: Documentation & Examples
- [ ] Document hook API thoroughly
- [ ] Create hook development guide
- [ ] Provide hook testing patterns
- [ ] Update Rails UI for app-level attributes

---

## 🚀 Benefits Achieved

✅ **Clean Architecture**: RAAF core stays generic, applications add domain logic
✅ **No Coupling**: Applications don't modify RAAF code
✅ **Reusable**: Same hooks pattern works across different applications
✅ **Flexible**: Each application registers exactly what it needs
✅ **Testable**: Mock hooks without affecting RAAF
✅ **Observable**: All metrics (RAAF + app) in single JSONB column
✅ **Performant**: < 3ms overhead per span

---

## 📖 Example: Complete Hook Setup

```ruby
# config/initializers/raaf_hooks.rb
RAAF.configure do |config|
  # ProspectsRadar domain-specific hooks

  config.register_span_hook(:prospect_quality) do |span, context|
    next unless context.agent_name == "ProspectScoringAgent"

    span.set_attribute("app.prospect.fit_score", 85)
    span.set_attribute("app.prospect.confidence", 0.87)
  end

  config.register_span_hook(:market_analysis) do |span, context|
    next unless context.agent_name == "MarketAnalysisAgent"

    span.set_attribute("app.market.size_score", 8.5)
    span.set_attribute("app.market.competition_score", 6.2)
    span.set_attribute("app.market.overall_score", 7.35)
  end

  config.register_span_hook(:cost_tracking) do |span, context|
    next unless context.is_agent_span?

    raaf_cost = context.get_metric("llm.cost.total_cents") || 0
    app_overhead = 15

    span.set_attribute("app.cost.total_cents", raaf_cost + app_overhead)
    span.set_attribute("app.cost.per_outcome", (raaf_cost + app_overhead) / 3.0)
  end
end
```

Then in Rails UI, all attributes (both RAAF and app) appear together in span_attributes JSONB:

```json
{
  "agent.name": "ProspectScoringAgent",
  "agent.temperature": "0.7",
  "llm.tokens.input": "1250",
  "llm.cost.total_cents": "12",
  "app.prospect.fit_score": "85",
  "app.prospect.confidence": "0.87",
  "app.cost.total_cents": "27"
}
```

---

**Document:** APPLICATION_HOOKS_DESIGN.md
**Version:** 1.0
**Updated:** 2025-10-24
**Status:** Design Ready (Implementation Next)
