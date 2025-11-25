# Spec Tasks

These are the tasks to be completed for the spec detailed in @.agent-os/specs/2025-11-25-continuous-evaluation-database-system/spec.md

> Created: 2025-11-25
> Status: Implementation Complete

## Tasks

- [x] 1. **Database Schema and Migrations**
  - [x] 1.1 Create migration for `raaf_evaluation_policies` table
  - [x] 1.2 Create migration for `raaf_evaluation_queue` table
  - [x] 1.3 Create migration for `raaf_evaluation_results` table
  - [x] 1.4 Create migration for `raaf_evaluation_metrics` table
  - [x] 1.5 Add indexes for query performance
  - [x] 1.6 Run migrations and verify schema

- [x] 2. **ActiveRecord Models**
  - [x] 2.1 Write tests for EvaluationPolicy model
  - [x] 2.2 Implement EvaluationPolicy model with validations and scopes
  - [x] 2.3 Write tests for EvaluationQueue model
  - [x] 2.4 Implement EvaluationQueue model with state transitions
  - [x] 2.5 Write tests for EvaluationResult model
  - [x] 2.6 Implement EvaluationResult model
  - [x] 2.7 Write tests for EvaluationMetric model
  - [x] 2.8 Implement EvaluationMetric model with upsert logic
  - [x] 2.9 Verify all model tests pass

- [x] 3. **Core Services**
  - [x] 3.1 Write tests for EvaluatorDiscovery service
  - [x] 3.2 Implement EvaluatorDiscovery service (integrate with DSL registry)
  - [x] 3.3 Write tests for PolicyMatcher service
  - [x] 3.4 Implement PolicyMatcher service (span matching, sampling logic)
  - [x] 3.5 Verify all service tests pass

- [x] 4. **Background Jobs (Solid Queue)**
  - [x] 4.1 Add solid_queue gem to raaf-rails
  - [x] 4.2 Configure Solid Queue (queues, workers, dispatchers)
  - [x] 4.3 Write tests for EvaluationJob
  - [x] 4.4 Implement EvaluationJob (executes evaluators, stores results)
  - [x] 4.5 Write tests for MetricsAggregationJob
  - [x] 4.6 Implement MetricsAggregationJob (hourly/daily/weekly rollups)
  - [x] 4.7 Write tests for ResetDailyCountersJob
  - [x] 4.8 Implement ResetDailyCountersJob
  - [x] 4.9 Verify all job tests pass

- [x] 5. **Span Creation Hook**
  - [x] 5.1 Write tests for span after_commit hook
  - [x] 5.2 Implement after_commit callback on SpanRecord
  - [x] 5.3 Add configuration flag for enabling/disabling continuous eval
  - [x] 5.4 Verify hook overhead is <5ms
  - [x] 5.5 Verify all hook tests pass

- [x] 6. **Controllers**
  - [x] 6.1 Write tests for EvaluatorsController
  - [x] 6.2 Implement EvaluatorsController (list/show evaluators from registry)
  - [x] 6.3 Write tests for PoliciesController
  - [x] 6.4 Implement PoliciesController (CRUD, activate/deactivate/duplicate)
  - [x] 6.5 Write tests for QueueController
  - [x] 6.6 Implement QueueController (list, retry, cancel)
  - [x] 6.7 Write tests for ResultsController
  - [x] 6.8 Implement ResultsController (list with filtering, show details)
  - [x] 6.9 Write tests for AnalyticsController
  - [x] 6.10 Implement AnalyticsController (dashboard, JSON data endpoints)
  - [x] 6.11 Verify all controller tests pass

- [x] 7. **Routes**
  - [x] 7.1 Add evaluation namespace routes to raaf-rails engine
  - [x] 7.2 Verify all routes are accessible

- [x] 8. **UI Components (Phlex)**
  - [x] 8.1 Add "Evaluations" section to dashboard navigation
  - [x] 8.2 Create PolicyList component
  - [x] 8.3 Create PolicyForm component with evaluator selection
  - [x] 8.4 Create PolicyShow component with stats
  - [x] 8.5 Create QueueList component with status indicators
  - [x] 8.6 Create QueueShow component with results
  - [x] 8.7 Create ResultsList component with filtering
  - [x] 8.8 Create ResultShow component with details
  - [x] 8.9 Create AnalyticsDashboard component (filters, overview stats)

- [x] 9. **D3.js Charts**
  - [x] 9.1 Add D3.js via importmap
  - [x] 9.2 Write JavaScript tests for PassRateChartController
  - [x] 9.3 Implement PassRateChartController (time-series line chart)
  - [x] 9.4 Write JavaScript tests for ScoreDistributionChartController
  - [x] 9.5 Implement ScoreDistributionChartController (histogram)
  - [x] 9.6 Create ModelComparisonTable component
  - [x] 9.7 Create FailureAnalysisChart component
  - [x] 9.8 Verify charts render correctly with test data

- [x] 10. **Feature Tests**
  - [x] 10.1 Write feature test for policy creation workflow
  - [x] 10.2 Write feature test for policy activation/deactivation
  - [x] 10.3 Write feature test for queue monitoring
  - [x] 10.4 Write feature test for results browsing
  - [x] 10.5 Write feature test for analytics dashboard
  - [x] 10.6 Verify all feature tests pass

- [x] 11. **DSL Deprecation**
  - [x] 11.1 Remove `history do...end` DSL support from EvaluatorDefinition
  - [x] 11.2 Remove HistoryDSL class
  - [x] 11.3 Add deprecation warnings for HistoricalStorage
  - [x] 11.4 Create migration rake task for existing configs
  - [x] 11.5 Update documentation with migration guide

- [x] 12. **Documentation and Cleanup**
  - [x] 12.1 Add YARD documentation to new classes
  - [x] 12.2 Update RAAF_EVAL.md with continuous evaluation section
  - [x] 12.3 Update CLAUDE.md with new features
  - [x] 12.4 Run full test suite and verify 100% pass
  - [x] 12.5 Run RuboCop and fix any violations
