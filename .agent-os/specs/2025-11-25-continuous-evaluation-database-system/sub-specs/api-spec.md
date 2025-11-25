# API Specification

This is the API specification for the spec detailed in @.agent-os/specs/2025-11-25-continuous-evaluation-database-system/spec.md

> Created: 2025-11-25
> Version: 1.0.0

## Overview

This spec adds new Rails controllers and routes for managing evaluation policies, monitoring the queue, browsing results, and viewing analytics. All endpoints are integrated into the existing raaf-rails dashboard and follow RESTful conventions.

## Route Structure

```ruby
# config/routes.rb (within raaf-rails engine)
namespace :raaf do
  namespace :rails do
    # Existing tracing routes...

    # New evaluation routes
    namespace :evaluation do
      resources :policies do
        member do
          post :activate
          post :deactivate
          post :duplicate
        end
      end

      # Evaluator discovery endpoint
      resources :evaluators, only: [:index, :show]

      resources :queue, only: [:index, :show] do
        member do
          post :retry
          post :cancel
        end
        collection do
          post :retry_failed
          delete :clear_completed
        end
      end

      resources :results, only: [:index, :show]

      resource :analytics, only: [:show] do
        get :pass_rate_data
        get :score_distribution_data
        get :model_comparison_data
        get :failure_analysis_data
      end
    end
  end
end
```

## Controllers

### 1. PoliciesController

Manages evaluation policy CRUD and activation.

```ruby
module RAAF
  module Rails
    module Evaluation
      class PoliciesController < BaseController
        before_action :set_policy, only: [:show, :edit, :update, :destroy, :activate, :deactivate, :duplicate]

        # GET /raaf/rails/evaluation/policies
        def index
          @policies = EvaluationPolicy.order(created_at: :desc)
          @policies = @policies.where(active: params[:active] == 'true') if params[:active].present?
          @policies = @policies.where('agent_name ILIKE ?', "%#{params[:agent]}%") if params[:agent].present?
        end

        # GET /raaf/rails/evaluation/policies/:id
        def show
          @recent_results = @policy.evaluation_results.recent.limit(10)
          @today_stats = @policy.today_stats
        end

        # GET /raaf/rails/evaluation/policies/new
        def new
          @policy = EvaluationPolicy.new(default_policy_attributes)
          @available_evaluators = RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details
        end

        # POST /raaf/rails/evaluation/policies
        def create
          @policy = EvaluationPolicy.new(policy_params)
          if @policy.save
            redirect_to evaluation_policy_path(@policy), notice: 'Policy created successfully.'
          else
            render :new, status: :unprocessable_entity
          end
        end

        # GET /raaf/rails/evaluation/policies/:id/edit
        def edit
          @available_evaluators = RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details
        end

        # PATCH /raaf/rails/evaluation/policies/:id
        def update
          if @policy.update(policy_params)
            redirect_to evaluation_policy_path(@policy), notice: 'Policy updated successfully.'
          else
            render :edit, status: :unprocessable_entity
          end
        end

        # DELETE /raaf/rails/evaluation/policies/:id
        def destroy
          @policy.destroy
          redirect_to evaluation_policies_path, notice: 'Policy deleted.'
        end

        # POST /raaf/rails/evaluation/policies/:id/activate
        def activate
          @policy.update!(active: true)
          redirect_to evaluation_policies_path, notice: 'Policy activated.'
        end

        # POST /raaf/rails/evaluation/policies/:id/deactivate
        def deactivate
          @policy.update!(active: false)
          redirect_to evaluation_policies_path, notice: 'Policy deactivated.'
        end

        # POST /raaf/rails/evaluation/policies/:id/duplicate
        def duplicate
          new_policy = @policy.dup
          new_policy.name = "#{@policy.name} (Copy)"
          new_policy.active = false
          new_policy.save!
          redirect_to edit_evaluation_policy_path(new_policy), notice: 'Policy duplicated.'
        end

        private

        def set_policy
          @policy = EvaluationPolicy.find(params[:id])
        end

        def policy_params
          params.require(:evaluation_policy).permit(
            :name, :description, :agent_name, :environment, :model_pattern, :version_pattern,
            :sampling_mode, :sample_rate, :sample_every_n, :max_daily_evaluations,
            :priority, :queue_name, :max_concurrent_evaluations, :max_retries,
            :retention_days, :retention_count, :active,
            evaluators: [:type, :name, config: {}],
            metadata: {}
          )
        end

        def default_policy_attributes
          {
            sampling_mode: 'percentage',
            sample_rate: 10,
            priority: 50,
            retention_days: 90,
            evaluators: []
          }
        end
      end
    end
  end
end
```

### 2. EvaluatorsController

Provides discovery of available evaluators from the DSL registry. These evaluators are defined in end-user applications (like ProspectsRadar) and are automatically registered when the Rails app boots.

```ruby
module RAAF
  module Rails
    module Evaluation
      class EvaluatorsController < BaseController
        # GET /raaf/rails/evaluation/evaluators
        # Returns list of all available evaluators from the registry
        def index
          @evaluators = RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details

          respond_to do |format|
            format.html
            format.json { render json: @evaluators }
          end
        end

        # GET /raaf/rails/evaluation/evaluators/:id
        # Returns details for a specific evaluator
        def show
          @evaluator = find_evaluator(params[:id])

          if @evaluator
            respond_to do |format|
              format.html
              format.json { render json: @evaluator }
            end
          else
            respond_to do |format|
              format.html { render 'shared/not_found', status: :not_found }
              format.json { render json: { error: 'Evaluator not found' }, status: :not_found }
            end
          end
        end

        private

        def find_evaluator(name)
          RAAF::Eval::Continuous::EvaluatorDiscovery.evaluator_details.find do |e|
            e[:name] == name
          end
        end
      end
    end
  end
end
```

### 3. QueueController

Monitors and manages the evaluation queue.

```ruby
module RAAF
  module Rails
    module Evaluation
      class QueueController < BaseController
        before_action :set_queue_item, only: [:show, :retry, :cancel]

        # GET /raaf/rails/evaluation/queue
        def index
          @queue_items = EvaluationQueue.order(created_at: :desc)
          @queue_items = @queue_items.where(status: params[:status]) if params[:status].present?
          @queue_items = @queue_items.where(evaluation_policy_id: params[:policy_id]) if params[:policy_id].present?
          @queue_items = @queue_items.page(params[:page]).per(50)

          @stats = {
            pending: EvaluationQueue.where(status: 'pending').count,
            running: EvaluationQueue.where(status: 'running').count,
            failed: EvaluationQueue.where(status: 'failed').count,
            completed_1h: EvaluationQueue.where(status: 'completed').where('completed_at > ?', 1.hour.ago).count
          }
        end

        # GET /raaf/rails/evaluation/queue/:id
        def show
          @results = @queue_item.evaluation_results
        end

        # POST /raaf/rails/evaluation/queue/:id/retry
        def retry
          @queue_item.update!(status: 'pending', attempts: 0, error_message: nil)
          RAAF::Eval::Continuous::EvaluationJob.perform_later(
            span_id: @queue_item.span_id,
            policy_id: @queue_item.evaluation_policy_id
          )
          redirect_to evaluation_queue_index_path, notice: 'Evaluation requeued.'
        end

        # POST /raaf/rails/evaluation/queue/:id/cancel
        def cancel
          @queue_item.update!(status: 'cancelled')
          redirect_to evaluation_queue_index_path, notice: 'Evaluation cancelled.'
        end

        # POST /raaf/rails/evaluation/queue/retry_failed
        def retry_failed
          failed_items = EvaluationQueue.where(status: 'failed')
          count = failed_items.count
          failed_items.find_each do |item|
            item.update!(status: 'pending', attempts: 0, error_message: nil)
            RAAF::Eval::Continuous::EvaluationJob.perform_later(
              span_id: item.span_id,
              policy_id: item.evaluation_policy_id
            )
          end
          redirect_to evaluation_queue_index_path, notice: "#{count} evaluations requeued."
        end

        # DELETE /raaf/rails/evaluation/queue/clear_completed
        def clear_completed
          count = EvaluationQueue.where(status: ['completed', 'cancelled']).delete_all
          redirect_to evaluation_queue_index_path, notice: "#{count} completed items cleared."
        end

        private

        def set_queue_item
          @queue_item = EvaluationQueue.find(params[:id])
        end
      end
    end
  end
end
```

### 4. ResultsController

Browses evaluation results with filtering.

```ruby
module RAAF
  module Rails
    module Evaluation
      class ResultsController < BaseController
        # GET /raaf/rails/evaluation/results
        def index
          @results = EvaluationResult.order(created_at: :desc)

          # Filtering
          @results = @results.where(agent_name: params[:agent]) if params[:agent].present?
          @results = @results.where(environment: params[:environment]) if params[:environment].present?
          @results = @results.where(status: params[:status]) if params[:status].present?
          @results = @results.where(evaluator_name: params[:evaluator]) if params[:evaluator].present?
          @results = @results.where('created_at >= ?', params[:from].to_date) if params[:from].present?
          @results = @results.where('created_at <= ?', params[:to].to_date.end_of_day) if params[:to].present?

          @results = @results.page(params[:page]).per(50)

          # Summary stats
          @summary = {
            total: @results.total_count,
            passed: EvaluationResult.where(status: 'passed').count,
            failed: EvaluationResult.where(status: 'failed').count,
            warning: EvaluationResult.where(status: 'warning').count
          }

          # Filter options
          @agents = EvaluationResult.distinct.pluck(:agent_name).sort
          @environments = EvaluationResult.distinct.pluck(:environment).compact.sort
          @evaluators = EvaluationResult.distinct.pluck(:evaluator_name).sort
        end

        # GET /raaf/rails/evaluation/results/:id
        def show
          @result = EvaluationResult.find(params[:id])
          @span = RAAF::Rails::Tracing::SpanRecord.find_by(span_id: @result.span_id)
          @other_results = EvaluationResult.where(span_id: @result.span_id).where.not(id: @result.id)
        end
      end
    end
  end
end
```

### 5. AnalyticsController

Provides data for D3.js visualizations.

```ruby
module RAAF
  module Rails
    module Evaluation
      class AnalyticsController < BaseController
        before_action :set_filters

        # GET /raaf/rails/evaluation/analytics
        def show
          @agents = EvaluationResult.distinct.pluck(:agent_name).sort
          @environments = EvaluationResult.distinct.pluck(:environment).compact.sort
          @models = EvaluationResult.distinct.pluck(:model).compact.sort

          @overview_stats = calculate_overview_stats
        end

        # GET /raaf/rails/evaluation/analytics/pass_rate_data
        # Returns JSON for D3.js time-series chart
        def pass_rate_data
          period_type = determine_period_type(@date_range)

          data = EvaluationMetric
            .where(agent_name: @agent)
            .where(period_type: period_type)
            .where(period_start: @date_range)
            .order(:period_start)
            .map do |metric|
              {
                date: metric.period_start.iso8601,
                pass_rate: metric.total_evaluations > 0 ?
                  (metric.passed_count.to_f / metric.total_evaluations * 100).round(2) : 0,
                total: metric.total_evaluations,
                passed: metric.passed_count,
                failed: metric.failed_count
              }
            end

          render json: data
        end

        # GET /raaf/rails/evaluation/analytics/score_distribution_data
        # Returns JSON for D3.js histogram
        def score_distribution_data
          # Get most recent daily metric with score distribution
          metric = EvaluationMetric
            .where(agent_name: @agent)
            .where(period_type: 'daily')
            .where(period_start: @date_range)
            .order(period_start: :desc)
            .first

          distribution = metric&.score_distribution || {}

          # Format for D3 histogram
          data = (0..9).map do |i|
            range_start = i * 0.1
            range_end = (i + 1) * 0.1
            key = "#{range_start.round(1)}-#{range_end.round(1)}"
            {
              range: key,
              count: distribution[key] || 0,
              percentage: 0  # Will be calculated client-side
            }
          end

          render json: data
        end

        # GET /raaf/rails/evaluation/analytics/model_comparison_data
        # Returns JSON for comparison table
        def model_comparison_data
          data = EvaluationResult
            .where(agent_name: @agent)
            .where(created_at: @date_range)
            .group(:model)
            .select(
              'model',
              'COUNT(*) as total_evaluations',
              'SUM(CASE WHEN status = \'passed\' THEN 1 ELSE 0 END) as passed_count',
              'AVG(score) as avg_score',
              'AVG((metrics->>\'latency_ms\')::numeric) as avg_latency_ms',
              'SUM((metrics->>\'cost\')::numeric) as total_cost'
            )
            .map do |row|
              {
                model: row.model || 'Unknown',
                total_evaluations: row.total_evaluations,
                pass_rate: (row.passed_count.to_f / row.total_evaluations * 100).round(2),
                avg_score: row.avg_score&.round(4),
                avg_latency_ms: row.avg_latency_ms&.round(0),
                total_cost: row.total_cost&.round(4)
              }
            end

          render json: data
        end

        # GET /raaf/rails/evaluation/analytics/failure_analysis_data
        # Returns JSON for failure breakdown
        def failure_analysis_data
          failed_results = EvaluationResult
            .where(agent_name: @agent)
            .where(status: 'failed')
            .where(created_at: @date_range)

          # Group by evaluator and extract common failure reasons
          by_evaluator = failed_results.group(:evaluator_name).count
          total_failures = failed_results.count

          data = by_evaluator.map do |evaluator, count|
            {
              evaluator: evaluator,
              count: count,
              percentage: (count.to_f / total_failures * 100).round(1)
            }
          end.sort_by { |d| -d[:count] }

          render json: data
        end

        private

        def set_filters
          @agent = params[:agent] || EvaluationResult.first&.agent_name
          @environment = params[:environment]

          # Default to last 30 days
          @from_date = params[:from]&.to_date || 30.days.ago.to_date
          @to_date = params[:to]&.to_date || Date.current
          @date_range = @from_date.beginning_of_day..@to_date.end_of_day
        end

        def determine_period_type(date_range)
          days = (date_range.end - date_range.begin) / 1.day
          if days <= 2
            'hourly'
          elsif days <= 90
            'daily'
          else
            'weekly'
          end
        end

        def calculate_overview_stats
          results = EvaluationResult.where(agent_name: @agent).where(created_at: @date_range)
          total = results.count
          passed = results.where(status: 'passed').count

          {
            total_evaluations: total,
            pass_rate: total > 0 ? (passed.to_f / total * 100).round(1) : 0,
            avg_score: results.average(:score)&.round(4) || 0,
            total_agents: EvaluationResult.where(created_at: @date_range).distinct.count(:agent_name)
          }
        end
      end
    end
  end
end
```

## Endpoints Summary

### Policies

| Method | Path | Action | Description |
|--------|------|--------|-------------|
| GET | `/raaf/rails/evaluation/policies` | index | List all policies with filtering |
| GET | `/raaf/rails/evaluation/policies/new` | new | New policy form |
| POST | `/raaf/rails/evaluation/policies` | create | Create policy |
| GET | `/raaf/rails/evaluation/policies/:id` | show | Policy details |
| GET | `/raaf/rails/evaluation/policies/:id/edit` | edit | Edit policy form |
| PATCH | `/raaf/rails/evaluation/policies/:id` | update | Update policy |
| DELETE | `/raaf/rails/evaluation/policies/:id` | destroy | Delete policy |
| POST | `/raaf/rails/evaluation/policies/:id/activate` | activate | Activate policy |
| POST | `/raaf/rails/evaluation/policies/:id/deactivate` | deactivate | Deactivate policy |
| POST | `/raaf/rails/evaluation/policies/:id/duplicate` | duplicate | Duplicate policy |

### Evaluators

| Method | Path | Action | Description |
|--------|------|--------|-------------|
| GET | `/raaf/rails/evaluation/evaluators` | index | List all available evaluators from registry |
| GET | `/raaf/rails/evaluation/evaluators/:id` | show | Evaluator details and configuration options |

### Queue

| Method | Path | Action | Description |
|--------|------|--------|-------------|
| GET | `/raaf/rails/evaluation/queue` | index | List queue items |
| GET | `/raaf/rails/evaluation/queue/:id` | show | Queue item details |
| POST | `/raaf/rails/evaluation/queue/:id/retry` | retry | Retry failed item |
| POST | `/raaf/rails/evaluation/queue/:id/cancel` | cancel | Cancel pending item |
| POST | `/raaf/rails/evaluation/queue/retry_failed` | retry_failed | Retry all failed |
| DELETE | `/raaf/rails/evaluation/queue/clear_completed` | clear_completed | Clear completed |

### Results

| Method | Path | Action | Description |
|--------|------|--------|-------------|
| GET | `/raaf/rails/evaluation/results` | index | List results with filtering |
| GET | `/raaf/rails/evaluation/results/:id` | show | Result details |

### Analytics

| Method | Path | Action | Description |
|--------|------|--------|-------------|
| GET | `/raaf/rails/evaluation/analytics` | show | Analytics dashboard |
| GET | `/raaf/rails/evaluation/analytics/pass_rate_data` | pass_rate_data | JSON for time-series |
| GET | `/raaf/rails/evaluation/analytics/score_distribution_data` | score_distribution_data | JSON for histogram |
| GET | `/raaf/rails/evaluation/analytics/model_comparison_data` | model_comparison_data | JSON for table |
| GET | `/raaf/rails/evaluation/analytics/failure_analysis_data` | failure_analysis_data | JSON for breakdown |

## Request/Response Examples

### List Available Evaluators

**Request:**
```http
GET /raaf/rails/evaluation/evaluators
Accept: application/json
```

**Response:**
```json
[
  {
    "name": "company_quality",
    "class_name": "CompanyQualityEvaluator",
    "type": "rule_based",
    "description": "Validates company data quality and completeness",
    "configurable_options": [
      { "name": "min_score", "type": "float", "default": 0.7 },
      { "name": "required_fields", "type": "array", "default": ["name", "kvk_number"] }
    ]
  },
  {
    "name": "dmu_completeness",
    "class_name": "DmuCompletenessEvaluator",
    "type": "rule_based",
    "description": "Checks DMU discovery results for completeness",
    "configurable_options": [
      { "name": "min_contacts", "type": "integer", "default": 1 }
    ]
  },
  {
    "name": "response_quality",
    "class_name": "ResponseQualityEvaluator",
    "type": "llm_judge",
    "description": "Uses LLM to judge response quality",
    "configurable_options": [
      { "name": "judge_model", "type": "string", "default": "gpt-4o" },
      { "name": "criteria", "type": "array", "default": ["relevance", "accuracy", "completeness"] }
    ]
  },
  {
    "name": "token_limit",
    "class_name": "RAAF::Eval::Evaluators::TokenLimitEvaluator",
    "type": "rule_based",
    "description": "Checks if token usage is within limits",
    "configurable_options": [
      { "name": "max_tokens", "type": "integer", "default": 4000 }
    ]
  }
]
```

### Create Policy

**Request:**
```http
POST /raaf/rails/evaluation/policies
Content-Type: application/x-www-form-urlencoded

evaluation_policy[name]=DMU+Discovery+Production
evaluation_policy[agent_name]=DmuDiscovery
evaluation_policy[environment]=production
evaluation_policy[sampling_mode]=percentage
evaluation_policy[sample_rate]=10
evaluation_policy[max_daily_evaluations]=1000
evaluation_policy[evaluators][][type]=rule_based
evaluation_policy[evaluators][][name]=token_limit
evaluation_policy[evaluators][][config][max_tokens]=4000
```

**Response:**
```http
HTTP/1.1 302 Found
Location: /raaf/rails/evaluation/policies/1
```

### Get Pass Rate Data

**Request:**
```http
GET /raaf/rails/evaluation/analytics/pass_rate_data?agent=DmuDiscovery&from=2025-11-01&to=2025-11-25
Accept: application/json
```

**Response:**
```json
[
  { "date": "2025-11-01T00:00:00Z", "pass_rate": 85.5, "total": 100, "passed": 85, "failed": 15 },
  { "date": "2025-11-02T00:00:00Z", "pass_rate": 88.2, "total": 110, "passed": 97, "failed": 13 },
  { "date": "2025-11-03T00:00:00Z", "pass_rate": 82.1, "total": 95, "passed": 78, "failed": 17 }
]
```

### Get Model Comparison Data

**Request:**
```http
GET /raaf/rails/evaluation/analytics/model_comparison_data?agent=DmuDiscovery
Accept: application/json
```

**Response:**
```json
[
  {
    "model": "gemini-2.5-flash",
    "total_evaluations": 847,
    "pass_rate": 89.2,
    "avg_score": 0.82,
    "avg_latency_ms": 1200,
    "total_cost": 2.54
  },
  {
    "model": "gpt-4o",
    "total_evaluations": 166,
    "pass_rate": 91.6,
    "avg_score": 0.87,
    "avg_latency_ms": 2100,
    "total_cost": 8.32
  }
]
```

## Error Handling

All controllers inherit from `RAAF::Rails::Evaluation::BaseController` which provides:

```ruby
module RAAF
  module Rails
    module Evaluation
      class BaseController < RAAF::Rails::ApplicationController
        rescue_from ActiveRecord::RecordNotFound, with: :not_found
        rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

        private

        def not_found
          respond_to do |format|
            format.html { render 'shared/not_found', status: :not_found }
            format.json { render json: { error: 'Not found' }, status: :not_found }
          end
        end

        def unprocessable_entity(exception)
          respond_to do |format|
            format.html { render :edit, status: :unprocessable_entity }
            format.json { render json: { errors: exception.record.errors }, status: :unprocessable_entity }
          end
        end
      end
    end
  end
end
```

## Authorization

Policy management requires appropriate permissions. Integration with existing RAAF Rails authorization:

```ruby
class EvaluationPolicy < ApplicationPolicy
  def index?
    user.can_view_evaluations?
  end

  def create?
    user.can_manage_evaluation_policies?
  end

  def update?
    user.can_manage_evaluation_policies?
  end

  def destroy?
    user.can_manage_evaluation_policies?
  end

  def activate?
    user.can_manage_evaluation_policies?
  end

  def deactivate?
    user.can_manage_evaluation_policies?
  end
end
```
