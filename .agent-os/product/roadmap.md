# Product Roadmap

> Last Updated: 2025-01-12
> Version: 3.0.0
> Status: Phase 3 Complete (Standalone), Integration Planning

## Overview

RAAF Eval is fully implemented with two complementary gems:
- **raaf-eval** - Core evaluation engine and RSpec integration (Phases 1-2) ✅
- **raaf-eval-ui** - Interactive web UI for evaluation experiments (Phase 3) ✅

**Current Focus:** Integration with future RAAF tracing dashboard UI (see [INTEGRATION_GUIDE.md](../eval-ui/INTEGRATION_GUIDE.md))

## Phase 1: Foundation & Core Infrastructure (2 weeks) ✅ **COMPLETE**

**Goal:** Establish the raaf-eval gem structure and core evaluation engine
**Success Criteria:** Can create evaluation runs, store results, and access span data programmatically

### Must-Have Features

- [x] Create raaf-eval gem structure in RAAF mono-repo - Initialize gem with proper dependencies `S` ✅
- [x] Design and implement evaluation database schema - Tables for evaluation runs, span snapshots, configurations, results `M` ✅
- [x] Build span data access layer - API for querying and retrieving RAAF trace spans with filtering `M` ✅
- [x] Implement evaluation engine - Core logic for re-running agents with modified configurations `L` ✅
- [x] Create evaluation result storage - Persist results with comparison to original span data `S` ✅

### Should-Have Features

- [x] Add basic logging and error handling - Comprehensive error tracking for evaluation failures `S` ✅
- [x] Implement configuration validation - Ensure valid AI settings before running evaluations `S` ✅

### Implementation Summary

**Completed:**
- ✅ Full gem structure in `eval/` directory
- ✅ Database models (EvaluationRun, EvaluationSpan, EvaluationConfiguration, EvaluationResult)
- ✅ SpanAccessor for span data retrieval
- ✅ SpanSerializer for span capture
- ✅ EvaluationEngine for re-execution
- ✅ Configuration validation and error handling

### Dependencies

- raaf-core (tracing system) ✅
- raaf-tracing (span access) ✅
- PostgreSQL database setup ✅

## Phase 2: RSpec Integration (1 week) ✅ **COMPLETE** (2025-01-12)

**Goal:** Enable developers to write and run evaluation tests using RSpec
**Success Criteria:** Can write RSpec tests that run evaluations and make assertions about results

### Must-Have Features

- [x] Create RSpec helper module - Provide eval-specific matchers and helpers `M` ✅
- [x] Implement evaluation DSL for RSpec - Clean syntax for defining evaluation scenarios `M` ✅
- [x] Add RSpec matchers for common assertions - Matchers for output quality, token usage, latency `M` ✅
- [x] Enable CI/CD integration - Ensure evals can run in automated test pipelines `S` ✅

### Should-Have Features

- [x] Add parallel evaluation execution - Speed up test runs by evaluating multiple configs simultaneously `M` ✅
- [x] Implement test data factories - FactoryBot factories for creating test scenarios `S` ✅

### Implementation Summary

**Completed:**
- ✅ 8 matcher files with 40+ matchers (performance, quality, regression, statistical, safety, structural, LLM)
- ✅ Complete test coverage for all matchers (5 new test files created)
- ✅ Comprehensive RSpec integration documentation (RSPEC_INTEGRATION.md - 16KB)
- ✅ Helper methods (evaluate_span, evaluate_latest_span, find_span, query_spans, latest_span_for)
- ✅ Fluent evaluation DSL (SpanEvaluator with method chaining)
- ✅ LLM judge integration
- ✅ CI/CD documentation (GitHub Actions, GitLab CI examples)
- ✅ Best practices guide

### Dependencies

- Phase 1 completion (evaluation engine) ✅
- RSpec Rails integration ✅

## Phase 3: Web UI for Interactive Evaluation (2 weeks) ✅ **COMPLETE**

**Goal:** Provide a visual interface for browsing spans, editing prompts, and running evaluations
**Success Criteria:** Can select spans, modify AI settings/prompts in browser, and view results side-by-side

### Must-Have Features

- [x] Create Rails controllers and routes - RESTful endpoints for evaluation UI `S` ✅
- [x] Build span browser component - Filterable table of RAAF spans with selection interface `L` ✅
- [x] Implement prompt editor interface - Monaco/CodeMirror editor with syntax highlighting `M` ✅
- [x] Create AI settings form - UI for modifying model, temperature, max_tokens, etc. `S` ✅
- [x] Build evaluation results viewer - Display original vs new results with diff highlighting `M` ✅
- [x] Add side-by-side comparison view - Compare multiple configurations simultaneously `M` ✅

### Should-Have Features

- [x] Implement real-time evaluation updates - Stream evaluation progress using Turbo Streams `M` ✅
- [x] Add keyboard shortcuts - Quick navigation and actions in the UI `S` ✅
- [x] Create evaluation session persistence - Save and resume evaluation sessions `S` ✅

### Implementation Summary

**Completed in raaf-eval-ui gem:**
- ✅ Complete Rails engine with controllers, routes, and components
- ✅ SpanBrowser component with filtering, search, pagination
- ✅ PromptEditor with Monaco Editor integration and split-pane diff view
- ✅ SettingsForm for AI configuration (model, temperature, max_tokens, etc.)
- ✅ ExecutionProgress with real-time updates via Turbo Streams
- ✅ ResultsComparison with side-by-side diff and metrics
- ✅ MetricsPanel with detailed metrics and delta indicators
- ✅ ConfigurationComparison for multi-config analysis
- ✅ Session management for save/resume functionality
- ✅ Background job execution with EvaluationExecutionJob
- ✅ Configurable authentication and authorization
- ✅ Optional host app layout inheritance

**Note:** Phase 3 provides standalone evaluation UI. See [INTEGRATION_GUIDE.md](../eval-ui/INTEGRATION_GUIDE.md) for integration patterns with future tracing dashboard UI.

### Dependencies

- Phase 1 completion (evaluation engine) ✅
- Phlex component library ✅
- Turbo Rails ✅
- Stimulus Rails ✅

## Phase 4: Active Record Integration & Metrics (1.5 weeks)

**Goal:** Connect evaluations to Active Record models and provide comprehensive metrics
**Success Criteria:** Can link evaluations to models, view aggregate metrics, and track performance over time

### Must-Have Features

- [ ] Implement Active Record polymorphic associations - Link evaluations to any AR model `M`
- [ ] Build metrics calculation engine - Compute success rates, token usage, latency, cost `M`
- [ ] Create metrics dashboard - Aggregate view of evaluation performance `L`
- [ ] Add historical tracking - Track agent performance trends over time `M`
- [ ] Implement baseline comparison - Compare new evals against established baselines `M`

### Should-Have Features

- [ ] Add automated regression detection - Flag when configurations perform worse than baseline `M`
- [ ] Create custom metric definitions - Allow users to define domain-specific evaluation metrics `L`
- [ ] Build metric alerting system - Notify when key metrics cross thresholds `S`

### Dependencies

- Phase 1 completion (evaluation storage)
- Phase 3 completion (UI for displaying metrics)

## Phase 4.5: Integration with Tracing Dashboard (Future) ⏭️

**Goal:** Seamlessly integrate evaluation UI with RAAF tracing dashboard when it exists
**Success Criteria:** Users can navigate from production traces to evaluation experiments and back

### Must-Have Features

- [ ] Add "Evaluate This Span" buttons in tracing dashboard span views
- [ ] Create "View Original Trace" links in evaluation results
- [ ] Share authentication and authorization between engines
- [ ] Unified navigation bar across both UIs
- [ ] Extract shared span browser component

### Should-Have Features

- [ ] Evaluation queue widget in tracing dashboard
- [ ] "Recently Evaluated" indicator on spans in trace browser
- [ ] Unified RAAF platform layout
- [ ] Bulk span selection for batch evaluation from trace browser

### Documentation

See [INTEGRATION_GUIDE.md](../eval-ui/INTEGRATION_GUIDE.md) for complete integration patterns and recommendations.

**Status:** Planning phase - waiting for tracing dashboard UI to exist

### Dependencies

- Full tracing dashboard UI implementation
- Phase 1-3 completion ✅

## Phase 5: Advanced Features & Collaboration (1.5 weeks)

**Goal:** Enable team collaboration and advanced evaluation workflows
**Success Criteria:** Can share evaluations, export data, and automate evaluation processes

### Must-Have Features

- [ ] Implement evaluation session sharing - Generate shareable links for evaluation results `S`
- [ ] Build data export functionality - Export evaluation data to CSV/JSON formats `M`
- [ ] Add evaluation templates - Save and reuse common evaluation configurations `M`
- [ ] Create batch evaluation mode - Run evaluations across multiple spans automatically `M`

### Should-Have Features

- [ ] Implement evaluation scheduling - Automatically run evaluations on a schedule `M`
- [ ] Add evaluation annotations - Allow users to comment on evaluation results `S`
- [ ] Create evaluation reports - Generate formatted reports for stakeholder sharing `M`
- [ ] Build API for external integration - RESTful API for programmatic evaluation access `L`

### Dependencies

- Phase 1-4 completion
- RAAF authentication and authorization system
