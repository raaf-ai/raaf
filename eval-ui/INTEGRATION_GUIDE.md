# RAAF Eval UI Integration Guide

> Version: 1.0.0
> Last Updated: 2025-01-12
> Status: Foundation Document

## Overview

This guide explains how RAAF Eval UI integrates with the broader RAAF ecosystem, particularly around tracing data and evaluation workflows. It addresses the relationship between trace viewing and evaluation experimentation to avoid duplication while providing complementary functionality.

## Current RAAF UI Landscape

### Tracing Infrastructure (raaf-tracing)

**Purpose:** Core tracing system with API endpoints for metrics and dashboards

**Components:**
- Span capture and storage
- Trace aggregation and querying
- Dashboard API endpoints (`/tracing/dashboard.json`, `/tracing/dashboard/performance.json`, etc.)
- Performance metrics and cost tracking

**Access:** Programmatic API (no full web UI currently)

### Eval UI (raaf-eval-ui)

**Purpose:** Interactive evaluation and experimentation with agent behavior

**Components:**
- Span browser for selecting evaluation targets
- Prompt editor with syntax highlighting (Monaco Editor)
- AI settings configuration forms
- Evaluation execution engine
- Side-by-side results comparison
- Real-time progress updates (Turbo Streams)

**Access:** Mountable Rails engine at `/eval` (or custom path)

## The Integration Challenge

### Apparent Overlap

Both systems deal with span data, which creates the appearance of duplication:

| Feature | Tracing Dashboard | Eval UI |
|---------|------------------|----------|
| View spans | ✅ (via API) | ✅ (Span Browser) |
| Filter by time | ✅ | ✅ |
| Filter by agent | ✅ | ✅ |
| View span details | ✅ | ✅ |
| Performance metrics | ✅ | ✅ |

### Critical Distinction

However, the purposes are fundamentally different:

**Tracing Dashboard (Production View)**
- **Read-only** view of what happened
- Purpose: Monitoring, debugging, performance analysis
- Answers: "How is the system performing?"
- User flow: View traces → Analyze patterns → Debug issues
- Like: APM tools (DataDog, New Relic, CloudWatch)

**Eval UI (Experimentation Lab)**
- **Interactive** modification and re-execution
- Purpose: Testing changes before deployment, optimization
- Answers: "What would happen if I changed X?"
- User flow: Select span → Modify settings → Re-run → Compare results
- Like: A/B testing tools, experiment platforms

## Integration Architecture

### Recommended Approach: Complementary, Not Duplicate

Rather than eliminate duplication by merging UIs, embrace the different purposes with smart integration points.

### Integration Pattern 1: Cross-Linking

**From Tracing Dashboard → Eval UI:**
```
Trace Detail View:
┌─────────────────────────────────────┐
│ Span ID: abc-123                    │
│ Agent: MarketAnalysis               │
│ Duration: 2.3s                      │
│                                     │
│ [View Full Trace] [🔬 Evaluate]    │
│                    ↓                │
│         Opens raaf-eval-ui with    │
│         span pre-selected          │
└─────────────────────────────────────┘
```

**From Eval UI → Tracing Dashboard:**
```
Evaluation Results:
┌─────────────────────────────────────┐
│ Baseline Result    vs  New Result   │
│ (from span abc-123)                 │
│                                     │
│ [📊 View Original Trace]           │
│           ↓                         │
│    Opens tracing dashboard         │
│    showing full context            │
└─────────────────────────────────────┘
```

### Integration Pattern 2: Shared Data Access

Both UIs query the same tracing data but for different purposes:

```ruby
# Tracing Dashboard: Read-only aggregations
RAAF::Tracing::Trace.where(created_at: 24.hours.ago..).average(:duration)

# Eval UI: Individual span selection for experiments
RAAF::Tracing::Span.find_by(id: params[:span_id])
```

**No duplication** - just different queries against the same data source.

### Integration Pattern 3: Unified Navigation (Future)

When a full tracing dashboard UI exists, create unified navigation:

```
RAAF Dashboard
├── 📊 Monitoring (Production Traces)
│   ├── Dashboard
│   ├── Traces
│   ├── Spans
│   └── Performance
│
└── 🔬 Evaluation (Experiments)
    ├── Select Spans
    ├── Active Experiments
    ├── Results History
    └── A/B Tests
```

Mount both engines under a unified namespace:
```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount RAAF::Tracing::UI::Engine, at: "/raaf/monitoring"
  mount RAAF::Eval::UI::Engine, at: "/raaf/eval"

  # Unified root at /raaf
  get "/raaf", to: "raaf/dashboard#index"
end
```

## Implementation Roadmap

### Phase 1: Current State ✅
- ✅ Eval UI exists as standalone engine
- ✅ Span browser in eval UI for experimentation
- ✅ Tracing API endpoints provide dashboard data
- ✅ No visual overlap (no full tracing dashboard UI yet)

### Phase 2: Smart Cross-Linking (Recommended Next Step)

**When tracing dashboard UI exists:**

1. **Add Evaluation Actions to Trace Views** (2 hours)
   ```ruby
   # In tracing dashboard span detail view
   class RAAF::Tracing::SpanDetailComponent < Phlex::HTML
     def template
       # ... span details ...

       div(class: "actions") do
         link_to "Evaluate This Span",
                 eval_evaluation_path(span_id: @span.id),
                 class: "btn btn-primary"
       end
     end
   end
   ```

2. **Add Trace Context to Eval UI** (2 hours)
   ```ruby
   # In eval UI results view
   class RAAF::Eval::UI::ResultsComponent < Phlex::HTML
     def template
       # ... results comparison ...

       if @evaluation.baseline_span_id
         link_to "View Original Trace",
                 tracing_span_path(@evaluation.baseline_span_id),
                 class: "btn btn-secondary"
       end
     end
   end
   ```

3. **Shared Span Selection Component** (4 hours)
   - Extract span browser to shared gem
   - Use in both tracing dashboard and eval UI
   - Add context-specific actions (view vs evaluate)

### Phase 3: Unified Layout and Navigation (4 hours)

Create a shared RAAF application layout:

```ruby
# lib/raaf/ui/shared/layout.rb
module RAAF
  module UI
    module Shared
      class Layout < Phlex::HTML
        def template(&block)
          html do
            head do
              title { "RAAF Platform" }
              # Shared assets
            end

            body do
              render Navigation.new
              main(&block)
            end
          end
        end
      end

      class Navigation < Phlex::HTML
        def template
          nav(class: "raaf-nav") do
            a(href: "/raaf/monitoring") { "📊 Monitoring" }
            a(href: "/raaf/eval") { "🔬 Evaluation" }
          end
        end
      end
    end
  end
end
```

### Phase 4: Advanced Integration (8 hours)

**Evaluation Queue in Tracing Dashboard:**
- Add "Select for Evaluation" checkboxes in trace browser
- Build evaluation queue showing selected spans
- Bulk actions: "Evaluate Selected with Config X"

**Recent Evaluations Widget:**
- Show recently evaluated spans in tracing dashboard
- Quick comparison: "This span evaluated 3 times with different configs"

## Configuration

### Mounting the Eval UI

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Standalone mount (current)
  mount RAAF::Eval::UI::Engine, at: "/eval"

  # OR integrated mount (future)
  mount RAAF::Eval::UI::Engine, at: "/raaf/eval"
end
```

### Authentication Integration

```ruby
# config/initializers/raaf_eval_ui.rb
RAAF::Eval::UI.configure do |config|
  # Share authentication with tracing dashboard
  config.authenticate_with = :devise

  # Use same authorization rules
  config.authorize_span_access = ->(span, user) do
    # Same logic as tracing dashboard
    user.can_access_span?(span)
  end
end
```

### Shared Layout (When Available)

```ruby
# config/initializers/raaf_eval_ui.rb
RAAF::Eval::UI.configure do |config|
  # Use shared RAAF layout instead of standalone
  config.layout = "raaf/shared/application"
end
```

## Use Cases

### Use Case 1: Performance Investigation

**Workflow:**
1. Developer notices slow response time in tracing dashboard
2. Clicks on slow span → Views trace details
3. Clicks "🔬 Evaluate This Span"
4. Eval UI opens with span loaded
5. Tests with different model/settings
6. Finds configuration that's 40% faster
7. Updates production configuration

**Tools Used:**
- Tracing dashboard: Identify problem
- Eval UI: Experiment with solutions

### Use Case 2: Prompt Optimization

**Workflow:**
1. QA engineer wants to improve agent output quality
2. Opens Eval UI directly (no tracing needed)
3. Selects recent span from production
4. Modifies prompt in editor
5. Runs A/B test with 5 prompt variations
6. Compares quality metrics side-by-side
7. Chooses best prompt, deploys to production

**Tools Used:**
- Eval UI only: Self-contained experimentation

### Use Case 3: Regression Testing

**Workflow:**
1. Developer updates core agent logic
2. Runs eval suite in CI/CD (RSpec integration)
3. Tests detect 5% quality regression
4. Opens failing test in Eval UI
5. Compares baseline vs new results visually
6. Identifies root cause, fixes code
7. Re-runs tests, all pass

**Tools Used:**
- RSpec (raaf-eval): Automated testing
- Eval UI: Visual debugging
- Tracing dashboard: Context about baseline behavior

## Best Practices

### DO: Embrace Different Purposes

```ruby
# ✅ Use tracing for monitoring
RAAF::Tracing.dashboard_metrics(time_range: 24.hours)

# ✅ Use eval UI for experimentation
evaluation = RAAF::Eval::EvaluationRun.create(
  span_id: problematic_span.id,
  configuration: { model: "gpt-4o", temperature: 0.5 }
)
```

### DON'T: Try to Make One UI Do Everything

```ruby
# ❌ Don't add evaluation features to tracing dashboard
# ❌ Don't add production monitoring to eval UI
```

### DO: Link Between Systems

```ruby
# ✅ Add navigation helpers
RAAF::Eval::UI.evaluation_from_span(span_id)
RAAF::Tracing.span_from_evaluation(evaluation_id)
```

### DO: Share Components Where Appropriate

```ruby
# ✅ Shared span display component
RAAF::UI::Shared::SpanCard.new(span: @span, context: :monitoring)
RAAF::UI::Shared::SpanCard.new(span: @span, context: :evaluation)
```

## Migration Path

### For New RAAF Users

1. Install raaf-eval-ui for experimentation
2. Use built-in span browser (no duplication concern)
3. When tracing dashboard exists, add cross-links

### For Existing RAAF Users (with tracing UI)

1. Install raaf-eval-ui alongside tracing dashboard
2. Add "Evaluate" buttons to trace views
3. Configure shared authentication/authorization
4. Optionally: migrate to unified layout

## Future Enhancements

### Proposed: Shared Component Library (raaf-ui-components)

Create a separate gem with reusable UI components:

```
raaf-ui-components/
├── span_card.rb       # Display span info
├── span_browser.rb    # Filter and search spans
├── metrics_panel.rb   # Show metrics
├── comparison_view.rb # Side-by-side comparison
└── layout.rb          # Shared layout
```

Used by both:
- Tracing dashboard (read-only context)
- Eval UI (evaluation context)

### Proposed: Unified RAAF Platform Gem (raaf-platform)

A meta-gem that combines all UI components:

```ruby
gem 'raaf-platform'
# Automatically includes:
# - raaf-tracing-ui
# - raaf-eval-ui
# - raaf-ui-components
# - Unified routing and navigation
```

## Summary

### Key Points

1. **Not Redundant:** Tracing views production data (monitoring), Eval UI experiments with changes (testing)
2. **Complementary:** Use both together for complete workflow (identify → experiment → deploy)
3. **Different Users:** Tracing = DevOps/SRE, Eval UI = Developers/QA/Product
4. **Integration Strategy:** Cross-link between systems, don't merge into one

### Immediate Action Items

If you're implementing integration:

1. ✅ **Install eval UI** - No conflicts with tracing API
2. ✅ **Use span browser** - It's purpose-built for evaluation
3. ⏭️ **Add cross-links** - When tracing dashboard UI exists
4. ⏭️ **Shared layout** - When ready for unified platform

### Questions?

- "Should I wait for tracing UI before using eval UI?" **No** - eval UI works standalone
- "Will there be duplicate span browsers?" **No** - different purposes (view vs evaluate)
- "Can they share code?" **Yes** - extract shared components when patterns emerge
- "Which should users see first?" **Depends** - Monitoring for ops, Eval for development

## References

- [RAAF Tracing Documentation](../tracing/README.md)
- [RAAF Eval Documentation](../eval/README.md)
- [RSpec Integration Guide](./RSPEC_INTEGRATION.md)
- [Eval UI Component Reference](./COMPONENT_REFERENCE.md)

---

**Document Status:** Foundation document for integration planning
**Next Update:** After tracing dashboard UI is implemented
**Maintainer:** RAAF Core Team
