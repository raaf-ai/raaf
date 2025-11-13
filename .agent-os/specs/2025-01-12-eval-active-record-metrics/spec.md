# Spec Requirements Document

> Spec: RAAF Eval Active Record Integration & Metrics
> Created: 2025-01-12
> Status: Planning
> Phase: Phase 4 of RAAF Eval Roadmap

## Overview

### Feature Purpose

This spec implements Phase 4 of the RAAF Eval roadmap, adding Active Record integration and comprehensive metrics tracking to the evaluation framework. It enables linking evaluation runs to application models, provides aggregate performance metrics, tracks agent behavior over time, and establishes baseline comparison capabilities for regression detection.

### Goals

1. **Connect Evaluations to Application Context**: Enable linking evaluation runs to Active Record models (Products, Users, Campaigns, etc.) to understand evaluation history in the context of real production entities
2. **Aggregate Performance Visibility**: Provide comprehensive metrics dashboard showing success rates, token usage, latency, and cost across all evaluations
3. **Historical Performance Tracking**: Track agent performance trends over time to identify improvements and regressions as prompts and models evolve
4. **Baseline Regression Detection**: Establish baseline evaluations and automatically detect when new configurations perform worse than established standards

### Success Criteria

1. Evaluation runs can be linked to any Active Record model via polymorphic associations
2. Metrics dashboard displays real-time aggregate metrics (success rate, token usage, latency, cost) with filtering capabilities
3. Time-series charts visualize agent performance trends over 7/30/90 day windows
4. Users can mark evaluations as baselines and receive automatic regression detection
5. Metrics update in near-real-time (< 5 min lag) as evaluations complete via background jobs
6. All features integrate seamlessly into the unified RAAF dashboard (DEC-004 architecture)

## User Stories

### Story 1: Link Evaluations to Application Models

As a **RAAF developer**, I want to **link evaluation runs to specific Active Record models** (e.g., a Product, User, or Campaign), so that **I can track which production entities have been evaluated and view their evaluation history**.

**Workflow:**
1. Developer creates an evaluation run for a specific agent/span
2. During evaluation setup, developer can optionally select an Active Record model to link
3. System stores polymorphic association (`evaluatable_type`, `evaluatable_id`)
4. Developer navigates to model detail page (e.g., Product#show)
5. Page displays all evaluations related to that product with metrics and results
6. Clicking an evaluation shows full comparison view with original span and evaluation results

**Problem Solved:** Currently evaluations exist in isolation without connection to the application models they're testing. This makes it hard to understand which products/campaigns/users have been evaluated and what their evaluation history looks like. Linking provides critical business context.

### Story 2: View Aggregate Evaluation Metrics

As a **team lead**, I want to **view aggregate metrics across all evaluations** (success rates, token usage, latency, cost), so that **I can understand overall agent performance and identify optimization opportunities**.

**Workflow:**
1. User navigates to "Metrics" tab in unified RAAF dashboard
2. Dashboard displays aggregate metrics for all evaluations:
   - **Success Rate**: Percentage of evaluations that succeeded (no errors)
   - **Token Usage**: Average, min, max, P50, P95, P99 token counts
   - **Latency**: Average, min, max, P50, P95, P99 response times
   - **Estimated Cost**: Total and per-evaluation cost based on token usage and model pricing
3. User filters metrics by:
   - Agent name (dropdown with all evaluated agents)
   - Model name (dropdown with all models used)
   - Time range (7 days, 30 days, 90 days, custom range)
   - Linked model type (Product, User, Campaign, etc.)
4. Metrics update automatically as new evaluations complete (via Turbo Stream broadcasts)
5. User exports metrics to CSV/JSON for external analysis or reporting

**Problem Solved:** No visibility into aggregate performance across evaluations. Users must manually analyze individual evaluation results, making it impossible to understand overall agent behavior or identify trends requiring optimization.

### Story 3: Track Agent Performance Trends Over Time

As a **developer**, I want to **see how agent performance changes over time** as I modify prompts and models, so that **I can identify regressions and validate improvements**.

**Workflow:**
1. User selects a specific agent in the metrics dashboard
2. System displays time-series charts showing trends over selected period:
   - **Success Rate Trend**: Line chart showing success percentage over time
   - **Token Usage Trend**: Line chart with average tokens per evaluation
   - **Latency Trend**: Line chart showing P50/P95 latency over time
   - **Cost Trend**: Cumulative and per-evaluation cost over time
3. Charts show data points for each day/week (depending on time range selected)
4. User can hover over data points to see exact values and drill down to evaluations
5. Timeline annotations show when configuration changes were made (new baselines, model changes)
6. User clicks a data point to see all evaluations contributing to that metric
7. Comparison view shows before/after performance when configuration changes occurred

**Problem Solved:** Currently no way to visualize agent performance over time. Difficult to correlate prompt/model changes with performance impact. Regressions go undetected until users manually notice problems in production.

### Story 4: Compare Performance Against Baselines

As a **QA engineer**, I want to **establish baseline evaluations and compare new runs against them**, so that **I can detect regressions before deploying changes**.

**Workflow:**
1. User completes an evaluation run that represents ideal/acceptable performance
2. User clicks "Mark as Baseline" button in evaluation results view
3. System prompts for baseline type: "Default" (applies to all), "Model-Specific" (applies only to this model), "Configuration-Specific" (applies to exact config)
4. User adds optional description explaining why this is the baseline
5. System captures metrics snapshot (success rate, avg tokens, avg latency) and saves baseline
6. Future evaluation runs for the same agent automatically compare against active baseline
7. Results page shows side-by-side baseline vs current metrics with delta indicators:
   - Green (+5%) for improvements
   - Red (-10%) for regressions
   - Yellow (±2%) for neutral changes
8. System flags regressions when metrics fall below baseline thresholds (configurable)
9. User can update, deactivate, or replace baselines as standards evolve

**Problem Solved:** No systematic way to detect regressions. Comparisons are manual and ad-hoc. Changes that degrade agent performance go unnoticed until production issues occur. Baselines provide objective standards for acceptable behavior.

## Spec Scope

### 1. Active Record Polymorphic Associations

**Database Schema:**
- Add polymorphic association columns to `evaluation_runs` table:
  - `evaluatable_type` (string) - Model class name (e.g., "Product", "User")
  - `evaluatable_id` (integer) - Model instance ID
  - Composite index on `[evaluatable_type, evaluatable_id]` for efficient querying
- Support reverse associations (e.g., `product.evaluation_runs`)

**Model Updates:**
- `EvaluationRun` model gains `belongs_to :evaluatable, polymorphic: true, optional: true`
- Host app models can add `has_many :evaluation_runs, as: :evaluatable` as needed
- Query methods for finding evaluations by linked model type/instance

**UI Integration:**
- Evaluation creation form includes optional model selector (searchable dropdown)
- Model selector supports all registered Active Record models in host application
- Evaluation results page displays linked model with link to model detail page
- Model detail pages (in host app) can embed evaluation history widget

### 2. Metrics Calculation Engine

**Metrics Storage:**
- New `evaluation_metrics` table for aggregated time-series data:
  - Dimensions: `agent_name`, `model_name`, `evaluatable_type`, `metric_type`, `aggregation_period`
  - Time: `period_start` (timestamp), `aggregation_period` (hour/day/week/month)
  - Values: `value` (decimal), `sample_count` (integer)
  - Metadata: JSONB field for percentiles (min, max, p50, p95, p99)
  - Indexes for efficient time-range queries and filtering

**Metric Types:**
- `success_rate` - Percentage of evaluations without errors
- `token_usage_avg` - Average tokens used per evaluation
- `token_usage_p95` - 95th percentile token usage
- `latency_avg` - Average response time in milliseconds
- `latency_p95` - 95th percentile latency
- `cost_total` - Total estimated cost (based on token usage × model pricing)
- `cost_per_eval` - Average cost per evaluation

**Calculation Strategy:**
- Incremental updates: Calculate only new metrics when evaluations complete
- Background jobs: `EvaluationMetricsAggregationJob` runs after each evaluation
- Scheduled aggregation: Daily job recalculates aggregates for previous periods
- PostgreSQL aggregation functions for efficient percentile calculations
- Consider materialized views for complex multi-dimensional aggregations

### 3. Metrics Dashboard

**Main Dashboard View:**
- New "Metrics" tab in unified RAAF dashboard navigation
- Overview panel showing global metrics (all agents, all time):
  - Total evaluations run
  - Overall success rate
  - Total tokens used
  - Total estimated cost
- Agent selector dropdown to filter to specific agent
- Time range selector (7d, 30d, 90d, custom date range)
- Model filter dropdown
- Evaluatable type filter (Product, User, etc.)

**Metrics Display Panels:**
- Success Rate Panel: Large percentage with trend indicator (↑↓)
- Token Usage Panel: Average with min/max/p95 in smaller text
- Latency Panel: Average latency with P50/P95/P99 breakdown
- Cost Panel: Total cost with per-evaluation average
- Each panel shows comparison to previous period (e.g., "+5% vs last 7 days")

**Export Functionality:**
- "Export" button generates CSV or JSON file
- Includes all metrics for selected filters and time range
- Filename includes date range and filters (e.g., `raaf-metrics-2025-01-01-to-2025-01-12-agent-research.csv`)

**Real-Time Updates:**
- Turbo Stream broadcasts update metrics when evaluations complete
- Minimal lag (< 5 minutes) between evaluation completion and metric display
- Background job publishes to Turbo Stream channel after aggregation

### 4. Historical Tracking

**Time-Series Charts:**
- Line charts for each metric type (success rate, tokens, latency, cost)
- X-axis: Time (dates), Y-axis: Metric value
- Data points aggregated by day for 7-30 day ranges, by week for 90+ day ranges
- Hover tooltips show exact values and sample count
- Click data point to drill down to evaluations in that time period

**Trend Analysis:**
- Trend indicators show direction and magnitude (↑ +15%, ↓ -8%, → ±2%)
- Comparison period configurable (vs previous 7 days, vs previous 30 days)
- Moving average overlay to smooth out daily variance
- Annotations for baseline changes and configuration updates

**Drill-Down Navigation:**
- Click chart data point → filtered evaluation list for that time period
- Click evaluation → full evaluation detail page
- Breadcrumb navigation back to metrics dashboard

**Chart Library:**
- Use Chartkick gem for Ruby/Rails integration
- Renders using Chart.js for interactive charts
- Phlex components wrap Chartkick for consistent styling

### 5. Baseline Comparison

**Baseline Management:**
- New `evaluation_baselines` table:
  - Foreign key to `evaluation_run` (the baseline evaluation)
  - `agent_name`, `model_name` for filtering
  - `baseline_type`: "default", "model_specific", "configuration_specific"
  - `active` boolean (only one active baseline per type per agent)
  - `description` text field for documentation
  - `metrics_snapshot` JSONB storing captured metrics at baseline time

**Baseline Creation UI:**
- "Mark as Baseline" button on evaluation results page
- Modal dialog for baseline configuration:
  - Baseline type selector (radio buttons)
  - Description field (textarea)
  - Preview of metrics being captured
  - Confirmation button
- Success notification with link to baselines list

**Baseline Comparison Display:**
- Side-by-side comparison table on evaluation results page:
  - Column 1: Baseline metrics
  - Column 2: Current evaluation metrics
  - Column 3: Delta (absolute and percentage)
- Color-coded indicators:
  - Green for improvements (lower latency, lower cost, higher success rate)
  - Red for regressions (higher latency, higher cost, lower success rate)
  - Yellow for neutral changes (within ±2% threshold)
- Threshold configuration per metric (e.g., "flag if success rate drops > 5%")

**Regression Detection:**
- Automatic flagging when evaluation metrics worse than baseline
- Thresholds configurable per metric type in system settings
- Visual indicators on evaluation results page ("⚠️ Regression Detected")
- Regression summary shows which metrics regressed and by how much
- Optional notifications (future phase) for automated alerting

**Baseline Management Pages:**
- Baselines list page showing all active baselines
- Table with agent, model, type, description, created date
- Actions: View baseline evaluation, Update description, Deactivate, Replace
- Filter by agent name and baseline type

## Out of Scope

The following features are **deferred to Phase 5** (collaboration and advanced features):

- **Real-Time Alerting System**: Notifications via email/Slack when metrics cross thresholds
- **Custom Metric Definitions**: User-defined domain-specific metrics with custom calculation logic
- **Advanced Statistical Analysis**: Correlation analysis, predictive trending, anomaly detection
- **Multi-Project/Multi-Team Aggregation**: Metrics across multiple RAAF deployments or teams
- **External Monitoring Integration**: Exporting metrics to DataDog, New Relic, Prometheus, etc.
- **Evaluation Scheduling**: Automated periodic evaluation runs
- **Evaluation Session Sharing**: Shareable links for evaluation results with team members
- **Batch Evaluation Mode**: Running evaluations across multiple spans automatically

## Technical Architecture

### Database Schema

**Migration 1: Add Polymorphic Associations to Evaluation Runs**

```ruby
class AddEvaluatableToEvaluationRuns < ActiveRecord::Migration[7.0]
  def change
    add_column :evaluation_runs, :evaluatable_type, :string
    add_column :evaluation_runs, :evaluatable_id, :integer
    add_index :evaluation_runs, [:evaluatable_type, :evaluatable_id],
              name: 'index_eval_runs_on_evaluatable'
  end
end
```

**Migration 2: Create Evaluation Metrics Table**

```ruby
class CreateEvaluationMetrics < ActiveRecord::Migration[7.0]
  def change
    create_table :evaluation_metrics do |t|
      t.string :agent_name, null: false
      t.string :model_name
      t.string :evaluatable_type
      t.string :metric_type, null: false # success_rate, token_usage_avg, latency_avg, cost_total
      t.string :aggregation_period, null: false # hour, day, week, month
      t.datetime :period_start, null: false
      t.decimal :value, precision: 20, scale: 6
      t.integer :sample_count, default: 0
      t.jsonb :metadata, default: {} # min, max, p50, p95, p99
      t.timestamps

      t.index [:agent_name, :metric_type, :period_start],
              name: 'index_eval_metrics_on_agent_metric_period'
      t.index [:period_start, :aggregation_period],
              name: 'index_eval_metrics_on_period'
      t.index :evaluatable_type
    end
  end
end
```

**Migration 3: Create Evaluation Baselines Table**

```ruby
class CreateEvaluationBaselines < ActiveRecord::Migration[7.0]
  def change
    create_table :evaluation_baselines do |t|
      t.references :evaluation_run, null: false, foreign_key: true
      t.string :agent_name, null: false
      t.string :model_name
      t.string :baseline_type, null: false, default: 'default'
        # 'default' | 'model_specific' | 'configuration_specific'
      t.boolean :active, default: true
      t.text :description
      t.jsonb :metrics_snapshot, default: {} # captured metrics at baseline time
      t.timestamps

      t.index [:agent_name, :baseline_type, :active],
              name: 'index_eval_baselines_on_agent_type_active'
      t.index :active
    end
  end
end
```

### Active Record Models

**EvaluationRun Model Updates:**

```ruby
# eval/lib/raaf/eval/models/evaluation_run.rb
module RAAF
  module Eval
    class EvaluationRun < ActiveRecord::Base
      # Existing associations
      has_many :evaluation_spans
      has_many :evaluation_configurations
      has_many :evaluation_results

      # NEW: Polymorphic association to any model
      belongs_to :evaluatable, polymorphic: true, optional: true

      # NEW: Baseline association
      has_one :baseline, class_name: 'EvaluationBaseline', dependent: :destroy

      # NEW: Scopes for filtering
      scope :for_model_type, ->(type) { where(evaluatable_type: type) }
      scope :for_model, ->(model) {
        where(evaluatable_type: model.class.name, evaluatable_id: model.id)
      }
      scope :with_baseline, -> { joins(:baseline).where(evaluation_baselines: { active: true }) }
      scope :without_baseline, -> {
        left_joins(:baseline).where(evaluation_baselines: { id: nil })
      }

      # NEW: Check if this run is a baseline
      def baseline?
        baseline.present? && baseline.active?
      end

      # NEW: Get active baseline for comparison
      def comparison_baseline
        return nil unless agent_name

        EvaluationBaseline
          .active
          .for_agent(agent_name)
          .for_model(model_name)
          .order(created_at: :desc)
          .first
      end
    end
  end
end
```

**EvaluationMetric Model:**

```ruby
# eval/lib/raaf/eval/models/evaluation_metric.rb
module RAAF
  module Eval
    class EvaluationMetric < ActiveRecord::Base
      METRIC_TYPES = %w[
        success_rate
        token_usage_avg
        token_usage_p95
        latency_avg
        latency_p95
        cost_total
        cost_per_eval
      ].freeze

      AGGREGATION_PERIODS = %w[hour day week month].freeze

      validates :agent_name, presence: true
      validates :metric_type, presence: true, inclusion: { in: METRIC_TYPES }
      validates :aggregation_period, presence: true, inclusion: { in: AGGREGATION_PERIODS }
      validates :period_start, presence: true
      validates :value, presence: true

      # Scopes for querying
      scope :for_agent, ->(agent_name) { where(agent_name: agent_name) }
      scope :for_model, ->(model_name) { where(model_name: model_name) }
      scope :for_evaluatable_type, ->(type) { where(evaluatable_type: type) }
      scope :of_type, ->(metric_type) { where(metric_type: metric_type) }
      scope :in_period, ->(period) { where(aggregation_period: period) }
      scope :between, ->(start_time, end_time) {
        where('period_start >= ? AND period_start <= ?', start_time, end_time)
      }

      # Calculate metrics from evaluation results
      def self.calculate_for_period(agent_name:, period_start:, period_end:, aggregation_period: 'day')
        # Implementation in MetricsCalculator service
      end

      # Get time series data for charting
      def self.time_series(agent_name:, metric_type:, start_date:, end_date:, period: 'day')
        for_agent(agent_name)
          .of_type(metric_type)
          .in_period(period)
          .between(start_date, end_date)
          .order(:period_start)
          .pluck(:period_start, :value)
      end
    end
  end
end
```

**EvaluationBaseline Model:**

```ruby
# eval/lib/raaf/eval/models/evaluation_baseline.rb
module RAAF
  module Eval
    class EvaluationBaseline < ActiveRecord::Base
      BASELINE_TYPES = %w[default model_specific configuration_specific].freeze

      belongs_to :evaluation_run

      validates :agent_name, presence: true
      validates :baseline_type, presence: true, inclusion: { in: BASELINE_TYPES }
      validates :metrics_snapshot, presence: true

      # Only one active baseline per agent/model/type combination
      validates :agent_name, uniqueness: {
        scope: [:model_name, :baseline_type, :active],
        conditions: -> { where(active: true) },
        message: 'already has an active baseline of this type'
      }

      # Scopes
      scope :active, -> { where(active: true) }
      scope :for_agent, ->(agent_name) { where(agent_name: agent_name) }
      scope :for_model, ->(model_name) { where(model_name: model_name) }
      scope :of_type, ->(type) { where(baseline_type: type) }

      # Capture metrics snapshot from evaluation run
      def capture_metrics_snapshot!
        update!(
          metrics_snapshot: {
            success_rate: evaluation_run.success_rate,
            avg_tokens: evaluation_run.average_token_usage,
            avg_latency_ms: evaluation_run.average_latency,
            total_cost: evaluation_run.total_cost
          }
        )
      end

      # Compare another evaluation run to this baseline
      def compare_to(evaluation_run)
        BaselineComparisonService.new(
          baseline: self,
          evaluation_run: evaluation_run
        ).compare
      end

      # Deactivate this baseline (when replacing with new one)
      def deactivate!
        update!(active: false)
      end
    end
  end
end
```

### API Endpoints (raaf-rails)

**Metrics Controller:**

```ruby
# rails/lib/raaf/rails/controllers/metrics_controller.rb
module RAAF
  module Rails
    class MetricsController < ApplicationController
      # GET /raaf/metrics
      def index
        @agents = EvaluationRun.distinct.pluck(:agent_name).sort
        @models = EvaluationRun.distinct.pluck(:model_name).compact.sort
        @evaluatable_types = EvaluationRun.distinct.pluck(:evaluatable_type).compact.sort

        @metrics = MetricsQuery.new(
          agent: params[:agent],
          model: params[:model],
          evaluatable_type: params[:evaluatable_type],
          time_range: params[:time_range] || '7d'
        ).aggregate_metrics

        render Evaluation::MetricsDashboard.new(
          metrics: @metrics,
          agents: @agents,
          models: @models,
          evaluatable_types: @evaluatable_types,
          filters: params
        )
      end

      # GET /raaf/metrics/trends?agent=X&metric=success_rate&period=day
      def trends
        @time_series = EvaluationMetric.time_series(
          agent_name: params[:agent],
          metric_type: params[:metric],
          start_date: start_date_from_params,
          end_date: Date.today,
          period: params[:period] || 'day'
        )

        render json: { data: @time_series }
      end

      # GET /raaf/metrics/export.csv
      def export
        metrics = MetricsQuery.new(filter_params).detailed_metrics

        respond_to do |format|
          format.csv do
            send_data MetricsExporter.to_csv(metrics),
                      filename: "raaf-metrics-#{Date.today}.csv"
          end
          format.json do
            render json: { metrics: metrics }
          end
        end
      end

      private

      def filter_params
        params.permit(:agent, :model, :evaluatable_type, :time_range, :start_date, :end_date)
      end

      def start_date_from_params
        if params[:time_range]
          case params[:time_range]
          when '7d' then 7.days.ago
          when '30d' then 30.days.ago
          when '90d' then 90.days.ago
          else Date.today - 7.days
          end
        else
          Date.parse(params[:start_date])
        end
      end
    end
  end
end
```

**Baselines Controller:**

```ruby
# rails/lib/raaf/rails/controllers/baselines_controller.rb
module RAAF
  module Rails
    class BaselinesController < ApplicationController
      # GET /raaf/baselines
      def index
        @baselines = EvaluationBaseline
          .active
          .includes(:evaluation_run)
          .order(created_at: :desc)

        @baselines = @baselines.for_agent(params[:agent]) if params[:agent]
        @baselines = @baselines.of_type(params[:baseline_type]) if params[:baseline_type]

        render Evaluation::BaselinesIndex.new(
          baselines: @baselines,
          agents: EvaluationRun.distinct.pluck(:agent_name).sort
        )
      end

      # POST /raaf/baselines
      def create
        @evaluation_run = EvaluationRun.find(params[:evaluation_run_id])

        # Deactivate existing baseline of same type if requested
        if params[:replace_existing]
          EvaluationBaseline
            .active
            .for_agent(@evaluation_run.agent_name)
            .of_type(params[:baseline_type])
            .update_all(active: false)
        end

        @baseline = EvaluationBaseline.create!(
          evaluation_run: @evaluation_run,
          agent_name: @evaluation_run.agent_name,
          model_name: @evaluation_run.model_name,
          baseline_type: params[:baseline_type] || 'default',
          description: params[:description]
        )

        @baseline.capture_metrics_snapshot!

        redirect_to raaf_evaluation_run_path(@evaluation_run),
                    notice: 'Baseline created successfully'
      rescue ActiveRecord::RecordInvalid => e
        redirect_to raaf_evaluation_run_path(@evaluation_run),
                    alert: "Failed to create baseline: #{e.message}"
      end

      # PATCH /raaf/baselines/:id
      def update
        @baseline = EvaluationBaseline.find(params[:id])
        @baseline.update!(baseline_params)

        redirect_to raaf_baselines_path,
                    notice: 'Baseline updated successfully'
      end

      # DELETE /raaf/baselines/:id
      def destroy
        @baseline = EvaluationBaseline.find(params[:id])
        @baseline.deactivate!

        redirect_to raaf_baselines_path,
                    notice: 'Baseline deactivated successfully'
      end

      private

      def baseline_params
        params.require(:baseline).permit(:description, :active)
      end
    end
  end
end
```

**Evaluation Runs Controller Updates:**

```ruby
# rails/lib/raaf/rails/controllers/evaluation_runs_controller.rb (EXISTING - ADD TO)
module RAAF
  module Rails
    class EvaluationRunsController < ApplicationController
      # EXISTING: index, show, create, etc.

      # NEW: Show evaluation with baseline comparison
      def show
        @evaluation_run = EvaluationRun
          .includes(:evaluation_spans, :evaluation_results, :evaluatable, :baseline)
          .find(params[:id])

        @baseline = @evaluation_run.comparison_baseline
        @comparison = @baseline ? @baseline.compare_to(@evaluation_run) : nil

        render Evaluation::EvaluationRunShow.new(
          evaluation_run: @evaluation_run,
          baseline: @baseline,
          comparison: @comparison
        )
      end

      # NEW: Allow linking evaluatable during creation
      def create
        # Existing evaluation creation logic...

        if params[:evaluatable_type] && params[:evaluatable_id]
          @evaluation_run.update!(
            evaluatable_type: params[:evaluatable_type],
            evaluatable_id: params[:evaluatable_id]
          )
        end

        # Rest of creation flow...
      end
    end
  end
end
```

### Services

**MetricsCalculator Service:**

```ruby
# eval/lib/raaf/eval/services/metrics_calculator.rb
module RAAF
  module Eval
    class MetricsCalculator
      def initialize(agent_name:, period_start:, period_end:, aggregation_period: 'day')
        @agent_name = agent_name
        @period_start = period_start
        @period_end = period_end
        @aggregation_period = aggregation_period
      end

      def calculate_and_store
        evaluation_runs = EvaluationRun
          .where(agent_name: @agent_name)
          .where('created_at >= ? AND created_at < ?', @period_start, @period_end)

        return if evaluation_runs.empty?

        metrics = calculate_metrics(evaluation_runs)
        store_metrics(metrics)
      end

      private

      def calculate_metrics(evaluation_runs)
        results = evaluation_runs.flat_map(&:evaluation_results)

        {
          success_rate: calculate_success_rate(evaluation_runs),
          token_usage_avg: calculate_token_usage_avg(results),
          token_usage_p95: calculate_token_usage_p95(results),
          latency_avg: calculate_latency_avg(results),
          latency_p95: calculate_latency_p95(results),
          cost_total: calculate_cost_total(results),
          cost_per_eval: calculate_cost_per_eval(results)
        }
      end

      def calculate_success_rate(runs)
        successful = runs.count { |r| r.status == 'success' }
        (successful.to_f / runs.count * 100).round(2)
      end

      def calculate_token_usage_avg(results)
        tokens = results.map(&:token_usage).compact
        return 0 if tokens.empty?
        (tokens.sum.to_f / tokens.count).round(2)
      end

      def calculate_token_usage_p95(results)
        tokens = results.map(&:token_usage).compact.sort
        return 0 if tokens.empty?
        percentile_index = (tokens.length * 0.95).ceil - 1
        tokens[percentile_index]
      end

      def calculate_latency_avg(results)
        latencies = results.map(&:latency_ms).compact
        return 0 if latencies.empty?
        (latencies.sum.to_f / latencies.count).round(2)
      end

      def calculate_latency_p95(results)
        latencies = results.map(&:latency_ms).compact.sort
        return 0 if latencies.empty?
        percentile_index = (latencies.length * 0.95).ceil - 1
        latencies[percentile_index]
      end

      def calculate_cost_total(results)
        results.sum(&:estimated_cost)
      end

      def calculate_cost_per_eval(results)
        return 0 if results.empty?
        (calculate_cost_total(results) / results.count).round(4)
      end

      def store_metrics(metrics)
        metrics.each do |metric_type, value|
          EvaluationMetric.create!(
            agent_name: @agent_name,
            metric_type: metric_type.to_s,
            aggregation_period: @aggregation_period,
            period_start: @period_start,
            value: value,
            sample_count: sample_count_for_metric(metric_type)
          )
        end
      end

      def sample_count_for_metric(metric_type)
        EvaluationRun
          .where(agent_name: @agent_name)
          .where('created_at >= ? AND created_at < ?', @period_start, @period_end)
          .count
      end
    end
  end
end
```

**BaselineComparisonService:**

```ruby
# eval/lib/raaf/eval/services/baseline_comparison_service.rb
module RAAF
  module Eval
    class BaselineComparisonService
      REGRESSION_THRESHOLDS = {
        success_rate: -5.0,    # Flag if drops > 5%
        avg_tokens: 20.0,      # Flag if increases > 20%
        avg_latency_ms: 20.0,  # Flag if increases > 20%
        total_cost: 15.0       # Flag if increases > 15%
      }.freeze

      def initialize(baseline:, evaluation_run:)
        @baseline = baseline
        @evaluation_run = evaluation_run
      end

      def compare
        {
          baseline_metrics: @baseline.metrics_snapshot,
          current_metrics: current_metrics,
          deltas: calculate_deltas,
          regressions: detect_regressions,
          has_regression: has_regression?
        }
      end

      private

      def current_metrics
        {
          success_rate: @evaluation_run.success_rate,
          avg_tokens: @evaluation_run.average_token_usage,
          avg_latency_ms: @evaluation_run.average_latency,
          total_cost: @evaluation_run.total_cost
        }
      end

      def calculate_deltas
        deltas = {}
        current_metrics.each do |key, current_value|
          baseline_value = @baseline.metrics_snapshot[key]
          next unless baseline_value

          absolute_delta = current_value - baseline_value
          percentage_delta = ((absolute_delta / baseline_value) * 100).round(2)

          deltas[key] = {
            absolute: absolute_delta,
            percentage: percentage_delta,
            direction: absolute_delta > 0 ? 'up' : (absolute_delta < 0 ? 'down' : 'neutral')
          }
        end
        deltas
      end

      def detect_regressions
        regressions = []
        calculate_deltas.each do |metric, delta|
          threshold = REGRESSION_THRESHOLDS[metric]
          next unless threshold

          if metric == :success_rate
            # Lower is worse for success rate
            regressions << metric if delta[:percentage] < threshold
          else
            # Higher is worse for tokens, latency, cost
            regressions << metric if delta[:percentage] > threshold
          end
        end
        regressions
      end

      def has_regression?
        detect_regressions.any?
      end
    end
  end
end
```

**MetricsQuery Service:**

```ruby
# eval/lib/raaf/eval/services/metrics_query.rb
module RAAF
  module Eval
    class MetricsQuery
      def initialize(agent: nil, model: nil, evaluatable_type: nil, time_range: '7d')
        @agent = agent
        @model = model
        @evaluatable_type = evaluatable_type
        @time_range = parse_time_range(time_range)
      end

      def aggregate_metrics
        {
          success_rate: avg_metric('success_rate'),
          token_usage_avg: avg_metric('token_usage_avg'),
          token_usage_p95: avg_metric('token_usage_p95'),
          latency_avg: avg_metric('latency_avg'),
          latency_p95: avg_metric('latency_p95'),
          cost_total: sum_metric('cost_total'),
          cost_per_eval: avg_metric('cost_per_eval'),
          sample_count: total_sample_count
        }
      end

      def detailed_metrics
        scope = EvaluationMetric.between(@time_range[:start], @time_range[:end])
        scope = scope.for_agent(@agent) if @agent
        scope = scope.for_model(@model) if @model
        scope = scope.for_evaluatable_type(@evaluatable_type) if @evaluatable_type

        scope.order(period_start: :desc)
      end

      private

      def parse_time_range(range_string)
        case range_string
        when '7d'
          { start: 7.days.ago, end: Time.current }
        when '30d'
          { start: 30.days.ago, end: Time.current }
        when '90d'
          { start: 90.days.ago, end: Time.current }
        else
          { start: 7.days.ago, end: Time.current }
        end
      end

      def base_scope
        scope = EvaluationMetric.between(@time_range[:start], @time_range[:end])
        scope = scope.for_agent(@agent) if @agent
        scope = scope.for_model(@model) if @model
        scope = scope.for_evaluatable_type(@evaluatable_type) if @evaluatable_type
        scope
      end

      def avg_metric(metric_type)
        base_scope.of_type(metric_type).average(:value)&.round(2) || 0
      end

      def sum_metric(metric_type)
        base_scope.of_type(metric_type).sum(:value).round(2)
      end

      def total_sample_count
        base_scope.sum(:sample_count)
      end
    end
  end
end
```

### Background Jobs

**EvaluationMetricsAggregationJob:**

```ruby
# eval/lib/raaf/eval/jobs/evaluation_metrics_aggregation_job.rb
module RAAF
  module Eval
    class EvaluationMetricsAggregationJob < ApplicationJob
      queue_as :raaf_eval

      def perform(agent_name:, period_start: nil, period_end: nil)
        period_start ||= 1.hour.ago
        period_end ||= Time.current

        MetricsCalculator.new(
          agent_name: agent_name,
          period_start: period_start,
          period_end: period_end,
          aggregation_period: 'hour'
        ).calculate_and_store

        # Broadcast updated metrics to dashboard
        broadcast_metrics_update(agent_name)
      end

      private

      def broadcast_metrics_update(agent_name)
        metrics = MetricsQuery.new(agent: agent_name, time_range: '7d').aggregate_metrics

        Turbo::StreamsChannel.broadcast_replace_to(
          "raaf_metrics_#{agent_name}",
          target: "metrics_panel_#{agent_name}",
          partial: "raaf/rails/evaluation/metrics_panel",
          locals: { agent_name: agent_name, metrics: metrics }
        )
      end
    end
  end
end
```

**BaselineComparisonJob:**

```ruby
# eval/lib/raaf/eval/jobs/baseline_comparison_job.rb
module RAAF
  module Eval
    class BaselineComparisonJob < ApplicationJob
      queue_as :raaf_eval

      def perform(evaluation_run_id)
        evaluation_run = EvaluationRun.find(evaluation_run_id)
        baseline = evaluation_run.comparison_baseline

        return unless baseline

        comparison = baseline.compare_to(evaluation_run)

        # Store comparison results in evaluation run
        evaluation_run.update!(
          baseline_comparison: comparison,
          has_regression: comparison[:has_regression]
        )

        # Broadcast regression alert if needed
        broadcast_regression_alert(evaluation_run, comparison) if comparison[:has_regression]
      end

      private

      def broadcast_regression_alert(evaluation_run, comparison)
        # Future: Send notifications, update UI with alerts
        Rails.logger.warn(
          "Regression detected in evaluation run #{evaluation_run.id}: " \
          "#{comparison[:regressions].join(', ')}"
        )
      end
    end
  end
end
```

**DailyMetricsAggregationJob:**

```ruby
# eval/lib/raaf/eval/jobs/daily_metrics_aggregation_job.rb
module RAAF
  module Eval
    class DailyMetricsAggregationJob < ApplicationJob
      queue_as :raaf_eval

      # Run once per day to aggregate previous day's metrics
      def perform(date = Date.yesterday)
        agents = EvaluationRun.distinct.pluck(:agent_name)

        agents.each do |agent_name|
          MetricsCalculator.new(
            agent_name: agent_name,
            period_start: date.beginning_of_day,
            period_end: date.end_of_day,
            aggregation_period: 'day'
          ).calculate_and_store
        end
      end
    end
  end
end
```

### UI Components (Phlex)

**MetricsDashboard Component:**

```ruby
# rails/lib/raaf/rails/evaluation/metrics_dashboard.rb
module RAAF
  module Rails
    module Evaluation
      class MetricsDashboard < ApplicationComponent
        def initialize(metrics:, agents:, models:, evaluatable_types:, filters:)
          @metrics = metrics
          @agents = agents
          @models = models
          @evaluatable_types = evaluatable_types
          @filters = filters
        end

        def view_template
          div(class: "metrics-dashboard p-6") do
            render_header
            render_filters
            render_overview_panel
            render_metrics_panels
            render_trends_section
          end
        end

        private

        def render_header
          div(class: "mb-6") do
            h1(class: "text-3xl font-bold text-gray-900") { "Evaluation Metrics" }
            p(class: "mt-2 text-gray-600") do
              "Aggregate metrics and performance trends across all evaluations"
            end
          end
        end

        def render_filters
          div(class: "bg-white p-4 rounded-lg shadow mb-6") do
            form(method: :get, class: "grid grid-cols-1 md:grid-cols-4 gap-4") do
              # Agent filter
              div do
                label(for: "agent", class: "block text-sm font-medium text-gray-700 mb-2") { "Agent" }
                select(
                  name: "agent",
                  id: "agent",
                  class: "w-full rounded-md border-gray-300",
                  onchange: "this.form.submit()"
                ) do
                  option(value: "", selected: !@filters[:agent]) { "All Agents" }
                  @agents.each do |agent|
                    option(value: agent, selected: @filters[:agent] == agent) { agent }
                  end
                end
              end

              # Model filter
              div do
                label(for: "model", class: "block text-sm font-medium text-gray-700 mb-2") { "Model" }
                select(
                  name: "model",
                  id: "model",
                  class: "w-full rounded-md border-gray-300",
                  onchange: "this.form.submit()"
                ) do
                  option(value: "", selected: !@filters[:model]) { "All Models" }
                  @models.each do |model|
                    option(value: model, selected: @filters[:model] == model) { model }
                  end
                end
              end

              # Time range filter
              div do
                label(for: "time_range", class: "block text-sm font-medium text-gray-700 mb-2") { "Time Range" }
                select(
                  name: "time_range",
                  id: "time_range",
                  class: "w-full rounded-md border-gray-300",
                  onchange: "this.form.submit()"
                ) do
                  [['7d', 'Last 7 Days'], ['30d', 'Last 30 Days'], ['90d', 'Last 90 Days']].each do |value, label|
                    option(value: value, selected: (@filters[:time_range] || '7d') == value) { label }
                  end
                end
              end

              # Export button
              div(class: "flex items-end") do
                a(
                  href: raaf_metrics_export_path(format: :csv, **@filters),
                  class: "w-full btn btn-secondary"
                ) do
                  "Export CSV"
                end
              end
            end
          end
        end

        def render_overview_panel
          div(class: "bg-blue-50 p-4 rounded-lg mb-6") do
            h2(class: "text-lg font-semibold text-blue-900 mb-3") { "Overview" }
            div(class: "grid grid-cols-2 md:grid-cols-4 gap-4") do
              render_overview_stat("Total Evaluations", @metrics[:sample_count], "📊")
              render_overview_stat("Success Rate", "#{@metrics[:success_rate]}%", "✅")
              render_overview_stat("Total Tokens", number_with_delimiter(@metrics[:token_usage_avg] * @metrics[:sample_count]), "🔢")
              render_overview_stat("Total Cost", "$#{@metrics[:cost_total]}", "💰")
            end
          end
        end

        def render_overview_stat(label, value, emoji)
          div(class: "text-center") do
            div(class: "text-2xl mb-1") { emoji }
            div(class: "text-2xl font-bold text-gray-900") { value }
            div(class: "text-sm text-gray-600") { label }
          end
        end

        def render_metrics_panels
          div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-6") do
            render MetricsPanel.new(
              title: "Success Rate",
              value: "#{@metrics[:success_rate]}%",
              icon: "✅",
              trend: nil # TODO: Calculate trend
            )

            render MetricsPanel.new(
              title: "Avg Token Usage",
              value: number_with_delimiter(@metrics[:token_usage_avg].to_i),
              subtitle: "P95: #{number_with_delimiter(@metrics[:token_usage_p95].to_i)}",
              icon: "🔢",
              trend: nil
            )

            render MetricsPanel.new(
              title: "Avg Latency",
              value: "#{@metrics[:latency_avg].to_i}ms",
              subtitle: "P95: #{@metrics[:latency_p95].to_i}ms",
              icon: "⏱️",
              trend: nil
            )

            render MetricsPanel.new(
              title: "Total Cost",
              value: "$#{@metrics[:cost_total].round(2)}",
              subtitle: "Avg: $#{@metrics[:cost_per_eval].round(4)}",
              icon: "💰",
              trend: nil
            )
          end
        end

        def render_trends_section
          return unless @filters[:agent]

          div(class: "bg-white p-6 rounded-lg shadow") do
            h2(class: "text-xl font-semibold text-gray-900 mb-4") do
              "Performance Trends - #{@filters[:agent]}"
            end

            div(class: "grid grid-cols-1 md:grid-cols-2 gap-6") do
              render_trend_chart("Success Rate", "success_rate")
              render_trend_chart("Token Usage", "token_usage_avg")
              render_trend_chart("Latency", "latency_avg")
              render_trend_chart("Cost", "cost_per_eval")
            end
          end
        end

        def render_trend_chart(title, metric_type)
          div do
            h3(class: "text-lg font-medium text-gray-700 mb-3") { title }
            div(id: "chart_#{metric_type}", class: "h-64") do
              # Chartkick line chart rendered here
              line_chart(
                raaf_metrics_trends_path(
                  agent: @filters[:agent],
                  metric: metric_type,
                  period: 'day',
                  format: :json
                ),
                library: { scales: { y: { beginAtZero: true } } }
              )
            end
          end
        end
      end
    end
  end
end
```

**MetricsPanel Component:**

```ruby
# rails/lib/raaf/rails/evaluation/metrics_panel.rb
module RAAF
  module Rails
    module Evaluation
      class MetricsPanel < ApplicationComponent
        def initialize(title:, value:, icon:, subtitle: nil, trend: nil)
          @title = title
          @value = value
          @icon = icon
          @subtitle = subtitle
          @trend = trend
        end

        def view_template
          div(class: "bg-white p-6 rounded-lg shadow") do
            div(class: "flex items-start justify-between") do
              div do
                p(class: "text-sm font-medium text-gray-600 mb-1") { @title }
                div(class: "flex items-baseline") do
                  span(class: "text-3xl font-bold text-gray-900") { @value }
                  span(class: "ml-2 text-3xl") { @icon }
                end
                p(class: "text-sm text-gray-500 mt-1") { @subtitle } if @subtitle
              end

              render_trend_indicator if @trend
            end
          end
        end

        private

        def render_trend_indicator
          return unless @trend

          color = trend_color(@trend[:direction])
          icon = trend_icon(@trend[:direction])

          div(class: "flex items-center text-sm #{color}") do
            span(class: "mr-1") { icon }
            span { "#{@trend[:percentage]}%" }
          end
        end

        def trend_color(direction)
          case direction
          when 'up' then 'text-green-600'
          when 'down' then 'text-red-600'
          else 'text-gray-600'
          end
        end

        def trend_icon(direction)
          case direction
          when 'up' then '↑'
          when 'down' then '↓'
          else '→'
          end
        end
      end
    end
  end
end
```

**BaselineComparison Component:**

```ruby
# rails/lib/raaf/rails/evaluation/baseline_comparison.rb
module RAAF
  module Rails
    module Evaluation
      class BaselineComparison < ApplicationComponent
        def initialize(baseline:, comparison:)
          @baseline = baseline
          @comparison = comparison
        end

        def view_template
          div(class: "bg-white p-6 rounded-lg shadow") do
            render_header
            render_regression_alert if @comparison[:has_regression]
            render_comparison_table
          end
        end

        private

        def render_header
          div(class: "flex items-center justify-between mb-4") do
            h3(class: "text-lg font-semibold text-gray-900") { "Baseline Comparison" }
            span(class: "text-sm text-gray-500") do
              "Baseline: #{@baseline.baseline_type.humanize}"
            end
          end
        end

        def render_regression_alert
          div(class: "bg-red-50 border-l-4 border-red-500 p-4 mb-4") do
            div(class: "flex") do
              div(class: "flex-shrink-0") do
                span(class: "text-2xl") { "⚠️" }
              end
              div(class: "ml-3") do
                h4(class: "text-sm font-medium text-red-800 mb-1") { "Regression Detected" }
                p(class: "text-sm text-red-700") do
                  "The following metrics regressed compared to baseline: " \
                  "#{@comparison[:regressions].map(&:to_s).map(&:humanize).join(', ')}"
                end
              end
            end
          end
        end

        def render_comparison_table
          table(class: "min-w-full divide-y divide-gray-200") do
            thead(class: "bg-gray-50") do
              tr do
                th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Metric" }
                th(class: "px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase") { "Baseline" }
                th(class: "px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase") { "Current" }
                th(class: "px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase") { "Delta" }
              end
            end
            tbody(class: "bg-white divide-y divide-gray-200") do
              render_metric_row("Success Rate", :success_rate, "%")
              render_metric_row("Avg Tokens", :avg_tokens, "")
              render_metric_row("Avg Latency", :avg_latency_ms, "ms")
              render_metric_row("Total Cost", :total_cost, "$")
            end
          end
        end

        def render_metric_row(label, metric_key, unit)
          baseline_value = @comparison[:baseline_metrics][metric_key]
          current_value = @comparison[:current_metrics][metric_key]
          delta = @comparison[:deltas][metric_key]

          return unless baseline_value && current_value && delta

          is_regression = @comparison[:regressions].include?(metric_key)

          tr(class: is_regression ? "bg-red-50" : "") do
            td(class: "px-4 py-3 text-sm font-medium text-gray-900") { label }
            td(class: "px-4 py-3 text-sm text-gray-600 text-right") do
              format_value(baseline_value, unit)
            end
            td(class: "px-4 py-3 text-sm text-gray-900 text-right") do
              format_value(current_value, unit)
            end
            td(class: "px-4 py-3 text-sm text-right") do
              render_delta(delta, is_regression)
            end
          end
        end

        def format_value(value, unit)
          case unit
          when "$" then "$#{value.round(2)}"
          when "%" then "#{value.round(2)}%"
          when "ms" then "#{value.to_i}ms"
          else value.round(2).to_s + unit
          end
        end

        def render_delta(delta, is_regression)
          color_class = is_regression ? "text-red-600 font-semibold" : delta_color(delta[:direction])
          icon = delta_icon(delta[:direction])

          span(class: color_class) do
            "#{icon} #{delta[:percentage]}%"
          end
        end

        def delta_color(direction)
          case direction
          when 'up' then 'text-green-600'
          when 'down' then 'text-red-600'
          else 'text-gray-600'
          end
        end

        def delta_icon(direction)
          case direction
          when 'up' then '↑'
          when 'down' then '↓'
          else '→'
          end
        end
      end
    end
  end
end
```

**ModelLinker Component:**

```ruby
# rails/lib/raaf/rails/evaluation/model_linker.rb
module RAAF
  module Rails
    module Evaluation
      class ModelLinker < ApplicationComponent
        def initialize(form:, evaluatable_types:)
          @form = form
          @evaluatable_types = evaluatable_types
        end

        def view_template
          div(class: "mb-4") do
            label(class: "block text-sm font-medium text-gray-700 mb-2") do
              "Link to Model (Optional)"
            end

            div(class: "grid grid-cols-2 gap-4") do
              # Model type selector
              div do
                select(
                  name: "evaluatable_type",
                  id: "evaluatable_type",
                  class: "w-full rounded-md border-gray-300",
                  data: { action: "change->model-linker#typeChanged" }
                ) do
                  option(value: "") { "-- Select Model Type --" }
                  @evaluatable_types.each do |type|
                    option(value: type) { type }
                  end
                end
              end

              # Model instance selector (populated via Stimulus)
              div do
                select(
                  name: "evaluatable_id",
                  id: "evaluatable_id",
                  class: "w-full rounded-md border-gray-300",
                  disabled: true,
                  data: { model_linker_target: "instanceSelect" }
                ) do
                  option(value: "") { "-- Select Instance --" }
                end
              end
            end

            p(class: "mt-2 text-xs text-gray-500") do
              "Optional: Link this evaluation to a specific model instance for tracking"
            end
          end
        end
      end
    end
  end
end
```

### Stimulus Controllers

**model_linker_controller.js:**

```javascript
// rails/lib/raaf/rails/javascript/controllers/model_linker_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["instanceSelect"]

  async typeChanged(event) {
    const modelType = event.target.value

    if (!modelType) {
      this.instanceSelectTarget.disabled = true
      this.instanceSelectTarget.innerHTML = '<option value="">-- Select Instance --</option>'
      return
    }

    // Fetch instances for selected model type
    const response = await fetch(`/raaf/eval/model_instances?type=${modelType}`)
    const instances = await response.json()

    // Populate instance selector
    this.instanceSelectTarget.innerHTML = '<option value="">-- Select Instance --</option>'
    instances.forEach(instance => {
      const option = document.createElement('option')
      option.value = instance.id
      option.text = instance.display_name
      this.instanceSelectTarget.appendChild(option)
    })

    this.instanceSelectTarget.disabled = false
  }
}
```

## Integration Points

### 1. Unified RAAF Dashboard Integration (DEC-004)

All evaluation metrics features integrate into the existing `raaf-rails` tracing dashboard:

**Navigation Updates:**
- Add "Metrics" tab to main navigation (alongside "Traces", "Agents", "Evaluation")
- Metrics tab accessible at `/raaf/metrics`
- Consistent header, sidebar, and layout with rest of dashboard

**Span Browser Integration:**
- Add "View Metrics" link to span detail pages
- Show evaluation history for spans that have been evaluated
- Link from metrics dashboard drill-down back to original spans

**Shared Components:**
- Reuse existing dashboard layout components
- Reuse span browser components for drill-down views
- Reuse authentication and authorization system
- Reuse Turbo Streams infrastructure for real-time updates

### 2. Background Job Integration

**Job Queue Setup:**
- Use existing Sidekiq or GoodJob configuration from raaf-rails
- Add `raaf_eval` queue for evaluation-related jobs
- Configure job priorities: `EvaluationMetricsAggregationJob` (high), `DailyMetricsAggregationJob` (low)

**Job Triggers:**
- After evaluation completion: Trigger `EvaluationMetricsAggregationJob`
- After baseline creation: No job needed (synchronous)
- Scheduled daily: Trigger `DailyMetricsAggregationJob` at 2 AM
- After evaluation with baseline: Trigger `BaselineComparisonJob`

### 3. Host Application Integration

**Model Registration:**
- Host app can register models for evaluation linking via initializer:

```ruby
# config/initializers/raaf_eval.rb
RAAF::Eval.configure do |config|
  config.evaluatable_models = [Product, User, Campaign]
end
```

**Model Detail Pages:**
- Host app can embed evaluation history widget:

```ruby
# app/views/products/show.html.erb
<%= render RAAF::Rails::Evaluation::EvaluationHistory.new(model: @product) %>
```

**Reverse Associations:**
- Host app models can add associations:

```ruby
class Product < ApplicationRecord
  has_many :evaluation_runs, as: :evaluatable, class_name: 'RAAF::Eval::EvaluationRun'
end
```

### 4. Turbo Streams Integration

**Real-Time Metric Updates:**
- Broadcast to `raaf_metrics_#{agent_name}` channel when metrics update
- Subscribe to channel on metrics dashboard page
- Update metric panels without page reload

**Regression Alerts:**
- Broadcast to `raaf_regressions` channel when regression detected
- Display toast notification on dashboard
- Update evaluation list with regression indicator

## Testing Strategy

### 1. Unit Tests (RSpec)

**Model Tests:**
- `EvaluationMetric` validations and scopes
- `EvaluationBaseline` validations and uniqueness constraints
- `EvaluationRun` polymorphic association behavior
- Time-series query methods

**Service Tests:**
- `MetricsCalculator` correctly calculates all metric types
- `MetricsCalculator` handles empty datasets gracefully
- `BaselineComparisonService` detects regressions accurately
- `MetricsQuery` applies filters correctly

**Job Tests:**
- `EvaluationMetricsAggregationJob` calculates and stores metrics
- `BaselineComparisonJob` compares evaluation to baseline
- `DailyMetricsAggregationJob` aggregates daily metrics
- Job error handling and retries

### 2. Integration Tests (RSpec)

**Metrics Dashboard:**
- Metrics dashboard displays aggregate metrics correctly
- Filtering by agent/model/time range works
- Export to CSV/JSON generates correct data
- Real-time updates via Turbo Streams

**Baseline Workflow:**
- Creating baseline from evaluation run
- Baseline comparison displays on subsequent evaluations
- Regression detection flags appropriate metrics
- Deactivating and replacing baselines

**Model Linking:**
- Linking evaluation to polymorphic model
- Querying evaluations by linked model
- Displaying evaluation history on model detail pages

### 3. System Tests (Playwright)

**End-to-End Workflows:**
- Complete flow: Run evaluation → View metrics → Create baseline → Run new evaluation → See comparison
- Navigate from span browser → evaluation → metrics dashboard → back to span
- Filter metrics by multiple criteria and export results
- Link evaluation to model and view history on model page

**UI Interaction:**
- Time-series charts render correctly and respond to interactions
- Baseline creation modal workflow
- Model linker dropdown behavior
- Real-time metric updates without page reload

### 4. Performance Tests

**Metrics Calculation:**
- Benchmark metrics calculation for 1000+ evaluation runs
- Verify database query efficiency (no N+1 queries)
- Test aggregation job performance with large datasets

**Dashboard Load Times:**
- Metrics dashboard loads in < 500ms with 10,000 evaluation runs
- Time-series charts render in < 200ms
- Export functionality handles large datasets (10,000+ rows)

## Expected Deliverables

1. **Database Migrations** - Three migrations for polymorphic associations, metrics storage, and baselines
2. **Active Record Models** - Updates to EvaluationRun, new EvaluationMetric and EvaluationBaseline models
3. **Services** - MetricsCalculator, BaselineComparisonService, MetricsQuery services
4. **Background Jobs** - Three job classes for metrics aggregation and baseline comparison
5. **Controllers** - MetricsController and BaselinesController with all endpoints
6. **Phlex Components** - MetricsDashboard, MetricsPanel, BaselineComparison, ModelLinker, TrendChart components
7. **Stimulus Controllers** - JavaScript for model linker dropdown behavior
8. **Routes** - New routes for metrics, baselines, and related actions integrated into raaf-rails
9. **Tests** - Comprehensive RSpec unit/integration tests and Playwright system tests
10. **Documentation** - User guide for metrics dashboard, baseline workflow, and model linking
11. **Migration Guide** - Guide for existing RAAF Eval users upgrading from Phase 3 to Phase 4

## Spec Documentation

- **Tasks:** @.agent-os/specs/2025-01-12-eval-active-record-metrics/tasks.md
- **Technical Specification:** @.agent-os/specs/2025-01-12-eval-active-record-metrics/sub-specs/technical-spec.md
- **Database Schema:** @.agent-os/specs/2025-01-12-eval-active-record-metrics/sub-specs/database-schema.md
- **API Specification:** @.agent-os/specs/2025-01-12-eval-active-record-metrics/sub-specs/api-spec.md
- **Tests Specification:** @.agent-os/specs/2025-01-12-eval-active-record-metrics/sub-specs/tests.md
