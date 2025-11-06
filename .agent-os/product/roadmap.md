# Product Roadmap

> Last Updated: 2025-11-06
> Version: 1.0.0
> Status: Planning

## Phase 1: Foundation & Core Infrastructure (2 weeks)

**Goal:** Establish the raaf-eval gem structure and core evaluation engine
**Success Criteria:** Can create evaluation runs, store results, and access span data programmatically

### Must-Have Features

- [ ] Create raaf-eval gem structure in RAAF mono-repo - Initialize gem with proper dependencies `S`
- [ ] Design and implement evaluation database schema - Tables for evaluation runs, span snapshots, configurations, results `M`
- [ ] Build span data access layer - API for querying and retrieving RAAF trace spans with filtering `M`
- [ ] Implement evaluation engine - Core logic for re-running agents with modified configurations `L`
- [ ] Create evaluation result storage - Persist results with comparison to original span data `S`

### Should-Have Features

- [ ] Add basic logging and error handling - Comprehensive error tracking for evaluation failures `S`
- [ ] Implement configuration validation - Ensure valid AI settings before running evaluations `S`

### Dependencies

- raaf-core (tracing system)
- raaf-tracing (span access)
- PostgreSQL database setup

## Phase 2: RSpec Integration (1 week)

**Goal:** Enable developers to write and run evaluation tests using RSpec
**Success Criteria:** Can write RSpec tests that run evaluations and make assertions about results

### Must-Have Features

- [ ] Create RSpec helper module - Provide eval-specific matchers and helpers `M`
- [ ] Implement evaluation DSL for RSpec - Clean syntax for defining evaluation scenarios `M`
- [ ] Add RSpec matchers for common assertions - Matchers for output quality, token usage, latency `M`
- [ ] Enable CI/CD integration - Ensure evals can run in automated test pipelines `S`

### Should-Have Features

- [ ] Add parallel evaluation execution - Speed up test runs by evaluating multiple configs simultaneously `M`
- [ ] Implement test data factories - FactoryBot factories for creating test scenarios `S`

### Dependencies

- Phase 1 completion (evaluation engine)
- RSpec Rails integration

## Phase 3: Web UI for Interactive Evaluation (2 weeks)

**Goal:** Provide a visual interface for browsing spans, editing prompts, and running evaluations
**Success Criteria:** Can select spans, modify AI settings/prompts in browser, and view results side-by-side

### Must-Have Features

- [ ] Create Rails controllers and routes - RESTful endpoints for evaluation UI `S`
- [ ] Build span browser component - Filterable table of RAAF spans with selection interface `L`
- [ ] Implement prompt editor interface - Monaco/CodeMirror editor with syntax highlighting `M`
- [ ] Create AI settings form - UI for modifying model, temperature, max_tokens, etc. `S`
- [ ] Build evaluation results viewer - Display original vs new results with diff highlighting `M`
- [ ] Add side-by-side comparison view - Compare multiple configurations simultaneously `M`

### Should-Have Features

- [ ] Implement real-time evaluation updates - Stream evaluation progress using Turbo Streams `M`
- [ ] Add keyboard shortcuts - Quick navigation and actions in the UI `S`
- [ ] Create evaluation session persistence - Save and resume evaluation sessions `S`

### Dependencies

- Phase 1 completion (evaluation engine)
- raaf-rails (UI infrastructure)
- Phlex component library

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
