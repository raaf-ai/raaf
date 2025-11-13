# Product Roadmap

> Last Updated: 2025-01-12
> Version: 5.0.0
> Status: Phase 3 Complete (Integrated), Architecture Unified

## Overview

RAAF Eval provides a unified evaluation and testing framework integrated directly into the RAAF tracing dashboard:
- **raaf-eval** - Core evaluation engine and RSpec integration (Phases 1-2) ✅
- **Evaluation UI** - Integrated into raaf-rails tracing dashboard as tabs and features (Phase 3) ✅

**Architecture:** Single unified RAAF platform UI with monitoring and evaluation as integrated features, not separate applications.

**Current Focus:**
- Active Record integration and metrics (Phase 4)
- Planning continuous evaluation capabilities for production monitoring (Phase 5)

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

**Completed in raaf-rails (integrated evaluation features):**
- ✅ Evaluation tab in unified RAAF dashboard navigation
- ✅ SpanBrowser with "Evaluate" action integrated into trace views
- ✅ PromptEditor with Monaco Editor integration and split-pane diff view
- ✅ SettingsForm for AI configuration (model, temperature, max_tokens, etc.)
- ✅ ExecutionProgress with real-time updates via Turbo Streams
- ✅ ResultsComparison with side-by-side diff and metrics
- ✅ MetricsPanel with detailed metrics and delta indicators
- ✅ ConfigurationComparison for multi-config analysis
- ✅ Session management for save/resume functionality
- ✅ Background job execution with EvaluationExecutionJob
- ✅ Shared authentication and layout with tracing dashboard
- ✅ Seamless navigation between monitoring and evaluation

**Architecture:** Evaluation features fully integrated into raaf-rails tracing dashboard as part of a unified RAAF platform experience.

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

## Phase 6: Continuous Evaluation (2 weeks)

**Goal:** Enable automatic evaluation of spans as they are created in production, supporting real-time monitoring, regression detection, and compliance tracking without impacting application performance.

**Success Criteria:**
- Spans can be automatically evaluated using configurable evaluators upon creation
- Evaluation runs asynchronously without blocking span creation
- Users can configure which spans to evaluate (all, sampled, filtered)
- Results aggregated and accessible via dashboard with alerting capabilities

### Must-Have Features

- [ ] Evaluator Registry System - Central registry for registering evaluator types (LLM judges, rule-based, statistical) with span hooks `M`
- [ ] Span Creation Hooks - After-commit callbacks on span creation that trigger evaluation jobs `S`
- [ ] Background Job Execution - Async evaluation job processing using Rails background jobs (Sidekiq/GoodJob) `M`
- [ ] Evaluation Configuration Management - UI and API for configuring continuous evaluation rules (which spans, which evaluators) `M`
- [ ] Result Aggregation Engine - Aggregate evaluation results across spans for trend analysis and monitoring `M`
- [ ] Continuous Evaluation Dashboard - Real-time view of ongoing evaluations with status, metrics, and trends `L`
- [ ] Storage Optimization - Efficient storage for high-volume continuous evaluation results with data retention policies `M`
- [ ] Performance Monitoring - Track evaluation job performance and system impact metrics `S`

### Should-Have Features

- [ ] Intelligent Sampling - Sample spans for evaluation based on statistical significance, error rates, or custom rules `M`
- [ ] Real-Time Alerting - Trigger alerts when continuous evaluations detect anomalies or regressions `M`
- [ ] Evaluation Result Versioning - Track changes in evaluation results over time with version control `S`
- [ ] A/B Testing Support - Compare agent configurations in production using continuous evaluation `L`
- [ ] Cost Management - Track and limit evaluation costs for continuous evaluation at scale `M`

### Use Cases Supported

1. **Production Monitoring**: Continuous quality checks on live agent interactions
2. **Regression Testing**: Automatic detection when agent behavior degrades
3. **Continuous Optimization**: Ongoing A/B testing and performance tracking
4. **Compliance/Audit**: Automatic verification against regulatory/policy requirements

### Architecture Highlights

- **Plugin-based evaluator system** for extensibility (LLM judges, rule-based, statistical, custom)
- **Configurable span filtering** (evaluate all vs sample vs targeted)
- **Async-first design** with zero production impact (background job processing)
- **Cost-aware execution** with budget controls and throttling
- **Multi-dimensional aggregation** for trend analysis (by agent, model, time, evaluator)

### Performance Characteristics

- **Span creation latency:** +0-5ms (hook registration only, no blocking)
- **Evaluation latency:** Seconds to minutes (async processing, user-configurable)
- **Throughput:** Scales with worker count (independent of application)
- **Storage growth:** Time-series partitioning with configurable retention policies

### Dependencies

**Required (Blocking):**
- Phase 1 completion (evaluation engine) ✅
- Phase 2 completion (RSpec integration for evaluators) ✅
- Phase 4 completion (metrics aggregation infrastructure) ⚠️ **Must complete first**
- Background job infrastructure (Sidekiq/GoodJob) - **New dependency**

**Optional (Enhancing):**
- Phase 3 completion (UI components integrated into dashboard) ✅
- Phase 5 completion (alerting infrastructure reuse)
