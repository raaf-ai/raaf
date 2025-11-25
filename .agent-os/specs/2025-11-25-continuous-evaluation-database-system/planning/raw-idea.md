# Raw Idea: Continuous Evaluation System with Database-Driven Configuration

**Feature Name:** Continuous Evaluation System with Database-Driven Configuration

**Description:**

Create a comprehensive continuous evaluation system for RAAF that:

1. **Moves evaluation configuration from DSL to database** - Replace the current `history do ... end` blocks in evaluator definitions with database-driven `evaluation_policies` table that can be configured per agent, per environment, per model version

2. **Implements an evaluation queue** - Spans selected for evaluation are queued in `evaluation_queue` table to control concurrency and enable retry logic

3. **Supports sampling configuration** - Configure "1 in N" runs to be evaluated for consistency monitoring, with percentage-based sampling and daily limits for cost control

4. **Stores all evaluation results in database** - Both automated and human evaluations stored in `evaluation_results` table with full metrics, scores, and reasoning

5. **Pre-aggregates metrics for dashboards** - `evaluation_metrics` table with hourly/daily/weekly rollups for fast graph rendering

6. **Provides management UI** - Integrated into raaf-rails dashboard:
   - Policy management (CRUD for evaluation rules)
   - Queue monitor (pending/running evaluations)
   - Results browser (filter by agent, environment, status)
   - Human review interface (for manual evaluations)
   - Analytics dashboard (graphs showing pass rate over time, score distribution, automated vs human comparison, model comparison)

7. **Compares automated vs human evaluations** - Track correlation between AI judges and human reviewers to calibrate evaluation quality

The system should use background jobs (Sidekiq/GoodJob) for async evaluation execution with zero impact on production span creation.

## Context

This feature represents Phase 6 of the RAAF Eval roadmap: Continuous Evaluation. It builds on the existing evaluation engine (Phases 1-2), RSpec integration, and UI components (Phase 3) to enable automatic, database-driven evaluation of production spans.

## Key Goals

- Zero impact on production span creation performance
- Flexible, configurable evaluation policies without code changes
- Cost control through sampling and limits
- Fast dashboard rendering via pre-aggregated metrics
- Human-in-the-loop validation and calibration
- Complete audit trail of all evaluations

## Date Created

2025-11-25
