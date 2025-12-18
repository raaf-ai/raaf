# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Controller for analytics and data visualization
      class AnalyticsController < BaseController
        # Alias the models for cleaner code
        EvaluationResult = RAAF::Eval::Models::ContinuousEvaluationResult
        EvaluationMetric = RAAF::Eval::Models::EvaluationMetric

        before_action :set_filters

        # GET /raaf/rails/continuous/analytics
        def show
          @agents = EvaluationResult.distinct.pluck(:agent_name).compact.sort
          @environments = EvaluationResult.distinct.pluck(:environment).compact.sort
          @models = EvaluationResult.distinct.pluck(:model).compact.sort

          @overview_stats = calculate_overview_stats

          respond_to do |format|
            format.html do
              analytics_dashboard = RAAF::Rails::Continuous::AnalyticsDashboard.new(
                stats: @overview_stats,
                agents: @agents,
                environments: @environments,
                filters: params.permit(:agent, :environment, :from, :to).to_h
              )
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Continuous Evaluation Analytics") do
                render analytics_dashboard
              end
              render layout
            end
            format.json { render json: @overview_stats }
          end
        end

        # GET /raaf/rails/continuous/analytics/pass_rate_data
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

        # GET /raaf/rails/continuous/analytics/score_distribution_data
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

        # GET /raaf/rails/continuous/analytics/model_comparison_data
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

        # GET /raaf/rails/continuous/analytics/failure_analysis_data
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
