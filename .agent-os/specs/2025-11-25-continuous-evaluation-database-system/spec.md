# Spec Requirements Document

> Spec: Continuous Evaluation with Database-Driven Configuration
> Created: 2025-11-25
> Status: Ready for Implementation

## Overview

Implement a comprehensive continuous evaluation system that moves evaluation configuration from DSL code to database tables, enabling per-agent/environment/model configuration without code changes. The system includes an evaluation queue for controlled execution, sampling strategies for cost management, storage for both automated and human evaluations, pre-aggregated metrics for fast dashboard rendering, and a complete management UI integrated into the raaf-rails dashboard.

## User Stories

### Automatic Production Monitoring

As a **RAAF application developer**, I want to automatically evaluate a percentage of my agent's production runs, so that I can detect regressions and quality issues without manual intervention.

The developer configures an evaluation policy in the UI specifying:
- Which agent(s) to monitor (e.g., "DmuDiscovery")
- Which environment (e.g., "production")
- Sampling rate (e.g., "10%" or "1 in 5 runs")
- Which evaluators to run (e.g., token limit check, quality assessment)
- Daily evaluation limits for cost control

When spans are created matching these criteria, they are automatically queued for evaluation. Results are stored and aggregated for dashboard viewing.

### Evaluation Analytics Dashboard

As a **team lead**, I want to see graphs showing how my agents' evaluation pass rates change over time, so that I can identify trends, compare models, and make data-driven decisions about prompt optimization.

The dashboard shows:
- Pass rate over time (line chart) per agent
- Score distribution (histogram)
- Model comparison (table with pass rates, latency, cost)
- Failure analysis (breakdown of why evaluations fail)
- Filter by agent, environment, model, date range

### Configuration Without Code Changes

As a **DevOps engineer**, I want to adjust evaluation sampling rates and enable/disable evaluators without deploying code, so that I can respond quickly to cost concerns or quality issues.

The UI provides:
- Policy list with active/paused status
- Edit form for all policy settings
- Immediate effect after save (no deployment needed)
- Audit log of configuration changes

## Spec Scope

1. **Evaluation Policies Table** - Database-driven configuration replacing DSL `history do...end` blocks, supporting per-agent, per-environment, per-model settings with sampling rates and evaluator configuration

2. **Evaluation Queue System** - Queue table for pending evaluations with priority, retry logic, and concurrency control using Solid Queue for background processing

3. **Evaluation Results Storage** - Unified storage for automated evaluation results with full metrics, scores, reasoning, and provenance tracking

4. **Pre-aggregated Metrics** - Hourly/daily/weekly rollup tables for fast dashboard queries showing pass rates, score distributions, and trends over time

5. **Policy Management UI** - CRUD interface for evaluation policies with evaluator configuration, sampling settings, and activation controls

6. **Queue Monitor UI** - Real-time view of pending/running/failed evaluations with retry and cancel actions

7. **Results Browser UI** - Filterable list of evaluation results with detail views showing scores, metrics, and reasoning

8. **Analytics Dashboard UI** - D3.js-powered graphs showing pass rate trends, score distributions, model comparisons, and failure analysis

## Out of Scope

- Human review interface (will be a separate feature for end-user app integration)
- Automated vs human evaluation comparison (depends on human review feature)
- A/B testing support (future phase)
- Real-time alerting and notifications (future phase)
- Evaluation result versioning (future phase)
- External API for programmatic access (Phase 5 feature)

## Expected Deliverable

1. Users can create evaluation policies via UI that automatically evaluate production spans matching configured criteria (agent, environment, model) at specified sampling rates

2. Users can view a dashboard with D3.js time-series charts showing evaluation pass rates over time, filterable by agent, environment, and date range

3. Users can browse evaluation results, see detailed scores and metrics, and filter by status (passed/failed/warning)

4. System processes evaluations asynchronously via Solid Queue with zero impact on span creation latency (<5ms hook overhead)

5. Pre-aggregated metrics enable dashboard queries to complete in <100ms even with millions of evaluation results

## Spec Documentation

- Tasks: @.agent-os/specs/2025-11-25-continuous-evaluation-database-system/tasks.md
- Technical Specification: @.agent-os/specs/2025-11-25-continuous-evaluation-database-system/sub-specs/technical-spec.md
- Database Schema: @.agent-os/specs/2025-11-25-continuous-evaluation-database-system/sub-specs/database-schema.md
- API Specification: @.agent-os/specs/2025-11-25-continuous-evaluation-database-system/sub-specs/api-spec.md
- Tests Specification: @.agent-os/specs/2025-11-25-continuous-evaluation-database-system/sub-specs/tests.md
