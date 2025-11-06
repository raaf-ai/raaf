# Spec Requirements Document

> Spec: RAAF Eval Web UI for Interactive Evaluation
> Created: 2025-11-06
> Status: Planning

## Overview

Provide a visual web interface for interactive agent evaluation, enabling RAAF developers to browse production spans, modify prompts and settings in a rich editor, run evaluations with live progress updates, and compare results side-by-side with diff highlighting.

## User Stories

### Story 1: Browse and Select Production Spans for Evaluation

As a RAAF developer debugging an agent issue, I want to browse recent production spans in a filterable table and select interesting ones for evaluation, so that I can reproduce and test fixes against real-world scenarios.

**Workflow:** Developer opens RAAF Eval UI → sees table of recent spans with filters (agent name, model, date range, success/failure) → applies filters to find problematic spans → selects span → span details displayed with input, output, metadata → clicks "Evaluate This Span" → evaluation setup screen opens with span pre-loaded.

### Story 2: Modify Prompts and Settings in Interactive Editor

As a RAAF user optimizing agent performance, I want to edit prompts and AI settings in a rich code editor with syntax highlighting and validation, so that I can quickly iterate on agent configurations without writing code.

**Workflow:** Developer has selected span → sees evaluation editor with three panes: original configuration (read-only), new configuration (editable), settings form → edits prompt in Monaco editor with syntax highlighting → modifies temperature slider (0.0-2.0) → changes model dropdown (GPT-4, Claude, Gemini, etc.) → editor validates JSON/YAML → previews token count estimate → clicks "Run Evaluation" → evaluation executes with live progress.

### Story 3: View Side-by-Side Results with Diff Highlighting

As a RAAF framework maintainer reviewing evaluation results, I want to see baseline and new outputs side-by-side with diff highlighting and metrics comparison, so that I can quickly assess the impact of changes.

**Workflow:** Evaluation completes → results page shows three-column layout: baseline (left), new result (middle), metrics comparison (right) → text outputs have syntax highlighting → differences highlighted with color coding (additions green, deletions red, changes yellow) → metrics show delta indicators (↑↓) and percentage changes → expandable sections for tool calls, handoffs, detailed metrics → can save evaluation as session for later review.

## Spec Scope

1. **Rails Controllers and Routes** - RESTful endpoints for evaluation UI (`/eval/spans`, `/eval/evaluations`, `/eval/results`)
2. **Span Browser Component** - Phlex component with filterable/sortable table, pagination, search, and span detail modal
3. **Prompt Editor Interface** - Monaco Editor integration with syntax highlighting, validation, and configuration forms
4. **AI Settings Form** - Form for modifying model, provider, temperature, max_tokens, top_p, and other parameters with validation
5. **Evaluation Execution UI** - Interface for running evaluations with real-time progress updates via Turbo Streams
6. **Results Viewer Component** - Three-column layout with diff highlighting, metrics comparison, and expandable details
7. **Side-by-Side Comparison** - Compare multiple configurations simultaneously with tabbed interface
8. **Session Persistence** - Save evaluation configurations and results as named sessions for later review

## Out of Scope

- Active Record polymorphic associations (deferred to Phase 4)
- Metrics dashboard and historical tracking (deferred to Phase 4)
- Evaluation scheduling and automation (deferred to Phase 5)
- Team collaboration features like comments and sharing (deferred to Phase 5)
- Evaluation templates and batch mode (deferred to Phase 5)

## Expected Deliverable

1. **Working Rails engine** (`raaf-eval-ui`) mountable in any Rails application
2. **Span browser** that can filter, search, and paginate through production spans from Phase 1 database
3. **Interactive prompt editor** with Monaco Editor showing original and modified configurations side-by-side
4. **AI settings form** with dropdowns for models/providers and validated inputs for parameters
5. **Live evaluation execution** with progress bar and Turbo Stream updates showing evaluation status
6. **Results comparison view** with diff-highlighted outputs and metrics delta indicators
7. **Session management** to save, load, and delete evaluation sessions
8. **Responsive design** that works on desktop and tablet (mobile view optional)
9. **Configurable authentication** that works with Devise, Sorcery, or custom auth solutions
10. **Complete documentation** including installation, configuration, and usage examples

## Spec Documentation

- **Tasks:** @.agent-os/specs/2025-11-06-raaf-eval-web-ui/tasks.md
- **Technical Specification:** @.agent-os/specs/2025-11-06-raaf-eval-web-ui/sub-specs/technical-spec.md
- **Tests Specification:** @.agent-os/specs/2025-11-06-raaf-eval-web-ui/sub-specs/tests.md
