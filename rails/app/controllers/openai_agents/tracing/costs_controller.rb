# frozen_string_literal: true

module RAAF
  module Tracing
    class CostsController < ApplicationController
      before_action :set_cost_manager
      before_action :set_time_range, only: %i[index breakdown trends forecast]
      before_action :set_tenant_filters, only: %i[index breakdown trends forecast]

      def index
        @cost_breakdown = @cost_manager.get_cost_breakdown(
          timeframe: @time_range,
          **@tenant_filters
        )

        @forecast = @cost_manager.forecast_costs(
          timeframe: 30.days,
          **@tenant_filters
        )

        @budget_status = get_budget_status
        @recommendations = @cost_manager.get_cost_optimization_recommendations(
          timeframe: @time_range,
          **@tenant_filters
        )

        respond_to do |format|
          format.html
          format.json do
            render json: {
              breakdown: @cost_breakdown,
              forecast: @forecast,
              budget_status: @budget_status,
              recommendations: @recommendations
            }
          end
        end
      end

      def breakdown
        breakdown = @cost_manager.get_cost_breakdown(
          timeframe: @time_range,
          **@tenant_filters
        )

        respond_to do |format|
          format.json { render json: breakdown }
          format.csv do
            csv_data = generate_breakdown_csv(breakdown)
            send_data csv_data, filename: "cost_breakdown_#{Date.current}.csv", type: "text/csv"
          end
        end
      end

      def trends
        trends_data = {
          daily_trends: get_daily_cost_trends,
          model_trends: get_model_usage_trends,
          workflow_trends: get_workflow_cost_trends,
          tenant_trends: get_tenant_cost_trends
        }

        respond_to do |format|
          format.json { render json: trends_data }
        end
      end

      def forecast
        timeframe_days = params[:days]&.to_i || 30
        forecast_timeframe = timeframe_days.days

        forecast = @cost_manager.forecast_costs(
          timeframe: forecast_timeframe,
          **@tenant_filters
        )

        respond_to do |format|
          format.json { render json: forecast }
        end
      end

      def budgets
        if request.post?
          create_budget
        else
          list_budgets
        end
      end

      def budget_status
        budget_status = @cost_manager.get_budget_status(**@tenant_filters)

        respond_to do |format|
          format.json { render json: budget_status }
        end
      end

      def optimization
        recommendations = @cost_manager.get_cost_optimization_recommendations(
          timeframe: @time_range,
          **@tenant_filters
        )

        # Get detailed optimization analysis
        optimization_analysis = {
          recommendations: recommendations,
          potential_total_savings: recommendations.sum { |r| r[:potential_savings] || 0 },
          quick_wins: recommendations.select { |r| r[:effort] == "low" && r[:impact] != "low" },
          high_impact: recommendations.select { |r| r[:impact] == "high" },
          implementation_roadmap: generate_implementation_roadmap(recommendations)
        }

        respond_to do |format|
          format.html { @optimization_analysis = optimization_analysis }
          format.json { render json: optimization_analysis }
        end
      end

      def reports
        format = params[:format] || "json"
        timeframe = parse_timeframe_param(params[:timeframe] || "30d")

        report = @cost_manager.generate_cost_report(
          format: format.to_sym,
          timeframe: timeframe,
          **@tenant_filters
        )

        case format
        when "json"
          render json: JSON.parse(report)
        when "csv"
          send_data report, filename: "cost_report_#{Date.current}.csv", type: "text/csv"
        when "pdf"
          send_data report, filename: "cost_report_#{Date.current}.pdf", type: "application/pdf"
        else
          render json: { error: "Unsupported format" }, status: 400
        end
      end

      def allocation
        if request.post?
          create_cost_allocation
        else
          list_cost_allocations
        end
      end

      def tenant_summary
        tenant_id = params[:tenant_id]
        return render json: { error: "Tenant ID required" }, status: 400 unless tenant_id

        summary = generate_tenant_cost_summary(tenant_id)

        respond_to do |format|
          format.json { render json: summary }
        end
      end

      def alerts
        # Get cost-related alerts
        alerts = generate_cost_alerts

        respond_to do |format|
          format.json { render json: { alerts: alerts } }
        end
      end

      private

      def set_cost_manager
        @cost_manager = RAAF::Tracing::CostManager.new(
          tenant_field: "tenant_id",
          project_field: "project_id",
          user_field: "user_id",
          enable_budgets: true,
          enable_optimization: true
        )
      end

      def set_time_range
        timeframe_param = params[:timeframe] || "24h"
        @time_range = parse_timeframe_param(timeframe_param)
      end

      def set_tenant_filters
        @tenant_filters = {
          tenant_id: params[:tenant_id],
          project_id: params[:project_id],
          user_id: params[:user_id]
        }.compact
      end

      def parse_timeframe_param(param)
        case param
        when /^(\d+)h$/
          ::Regexp.last_match(1).to_i.hours
        when /^(\d+)d$/
          ::Regexp.last_match(1).to_i.days
        when /^(\d+)w$/
          ::Regexp.last_match(1).to_i.weeks
        when /^(\d+)m$/
          ::Regexp.last_match(1).to_i.months
        else
          24.hours
        end
      end

      def get_budget_status
        return nil unless @tenant_filters.any?

        status = @cost_manager.get_budget_status(**@tenant_filters)
        status[:error] ? nil : status
      end

      def get_daily_cost_trends
        end_time = Time.current
        start_time = end_time - 30.days

        daily_costs = []
        current_day = start_time.to_date

        while current_day <= end_time.to_date
          day_breakdown = @cost_manager.get_cost_breakdown(
            timeframe: 1.day,
            **@tenant_filters
          )

          daily_costs << {
            date: current_day,
            total_cost: day_breakdown[:totals][:total_cost],
            trace_count: day_breakdown[:totals][:total_traces],
            avg_cost_per_trace: day_breakdown[:totals][:avg_cost_per_trace]
          }

          current_day += 1.day
        end

        daily_costs
      end

      def get_model_usage_trends
        # Get model usage trends over time
        breakdown = @cost_manager.get_cost_breakdown(
          timeframe: @time_range,
          **@tenant_filters
        )

        breakdown[:by_model].map do |model, data|
          {
            model: model,
            cost: data[:cost],
            percentage: (data[:cost] / breakdown[:totals][:total_cost] * 100).round(2),
            traces: data[:traces],
            tokens: data[:input_tokens] + data[:output_tokens]
          }
        end # rubocop:disable Style/MultilineBlockChain
        .sort_by { |m| -m[:cost] }
      end

      def get_workflow_cost_trends
        breakdown = @cost_manager.get_cost_breakdown(
          timeframe: @time_range,
          **@tenant_filters
        )

        breakdown[:by_workflow].map do |workflow, data|
          {
            workflow: workflow,
            cost: data[:cost],
            percentage: (data[:cost] / breakdown[:totals][:total_cost] * 100).round(2),
            traces: data[:traces],
            avg_cost_per_trace: (data[:cost] / data[:traces]).round(6)
          }
        end # rubocop:disable Style/MultilineBlockChain
        .sort_by { |w| -w[:cost] }
      end

      def get_tenant_cost_trends
        breakdown = @cost_manager.get_cost_breakdown(
          timeframe: @time_range,
          **@tenant_filters
        )

        breakdown[:by_tenant].map do |tenant, data|
          {
            tenant_id: tenant,
            cost: data[:cost],
            percentage: (data[:cost] / breakdown[:totals][:total_cost] * 100).round(2),
            traces: data[:traces],
            workflows: data[:workflows]
          }
        end # rubocop:disable Style/MultilineBlockChain
        .sort_by { |t| -t[:cost] }
      end

      def create_budget
        budget_params = params.require(:budget).permit(:amount, :period, :currency, :tenant_id, :project_id, :user_id)

        budget = @cost_manager.set_budget(
          tenant_id: budget_params[:tenant_id],
          project_id: budget_params[:project_id],
          user_id: budget_params[:user_id],
          amount: budget_params[:amount].to_f,
          period: budget_params[:period]&.to_sym || :monthly,
          currency: budget_params[:currency]
        )

        render json: { budget: budget, status: "created" }
      rescue StandardError => e
        render json: { error: e.message }, status: 400
      end

      def list_budgets
        # This would list all budgets - implementation depends on storage mechanism
        render json: { budgets: [], message: "Budget listing not yet implemented" }
      end

      def create_cost_allocation
        allocation_params = params.require(:allocation).permit(:trace_id,
                                                               allocations: %i[tenant_id percentage amount])

        allocation = @cost_manager.track_cost_allocation(
          allocation_params[:trace_id],
          allocation_params[:allocations]
        )

        render json: { allocation: allocation, status: "created" }
      rescue StandardError => e
        render json: { error: e.message }, status: 400
      end

      def list_cost_allocations
        # This would list cost allocations - implementation depends on storage mechanism
        render json: { allocations: [], message: "Allocation listing not yet implemented" }
      end

      def generate_tenant_cost_summary(tenant_id)
        summary = {
          tenant_id: tenant_id,
          current_month: {},
          last_month: {},
          year_to_date: {},
          trends: {},
          top_workflows: [],
          budget_status: nil
        }

        # Current month
        summary[:current_month] = @cost_manager.get_cost_breakdown(
          timeframe: Time.current.beginning_of_month..Time.current,
          tenant_id: tenant_id
        )[:totals]

        # Last month
        last_month_start = 1.month.ago.beginning_of_month
        last_month_end = 1.month.ago.end_of_month
        summary[:last_month] = @cost_manager.get_cost_breakdown(
          timeframe: last_month_end - last_month_start,
          tenant_id: tenant_id
        )[:totals]

        # Year to date
        summary[:year_to_date] = @cost_manager.get_cost_breakdown(
          timeframe: Time.current.beginning_of_year..Time.current,
          tenant_id: tenant_id
        )[:totals]

        # Budget status
        budget_status = @cost_manager.get_budget_status(tenant_id: tenant_id)
        summary[:budget_status] = budget_status unless budget_status[:error]

        summary
      end

      def generate_cost_alerts
        alerts = []

        # Check for budget alerts
        if @tenant_filters.any?
          budget_status = get_budget_status
          if budget_status && budget_status[:alert_triggered]
            alerts << {
              type: "budget_alert",
              severity: budget_status[:percentage_used] > 95 ? "critical" : "warning",
              title: "Budget Alert: #{budget_status[:percentage_used]}% used",
              message: "Current spend: #{budget_status[:current_spend]}, Budget: #{budget_status[:budget][:amount]}",
              data: budget_status
            }
          end
        end

        # Check for cost spikes
        recent_costs = @cost_manager.get_cost_breakdown(timeframe: 24.hours, **@tenant_filters)
        # This would need to be offset
        previous_costs = @cost_manager.get_cost_breakdown(timeframe: 24.hours, **@tenant_filters)

        if recent_costs[:totals][:total_cost] > previous_costs[:totals][:total_cost] * 2
          alerts << {
            type: "cost_spike",
            severity: "warning",
            title: "Cost Spike Detected",
            message: "Costs have doubled compared to previous period",
            data: {
              current: recent_costs[:totals][:total_cost],
              previous: previous_costs[:totals][:total_cost]
            }
          }
        end

        alerts
      end

      def generate_implementation_roadmap(recommendations)
        # Group recommendations by effort level and create implementation timeline
        quick_wins = recommendations.select { |r| r[:effort] == "low" }
        medium_effort = recommendations.select { |r| r[:effort] == "medium" }
        high_effort = recommendations.select { |r| r[:effort] == "high" }

        {
          phase_one: {
            title: "Quick Wins (Week 1-2)",
            recommendations: quick_wins,
            estimated_savings: quick_wins.sum { |r| r[:potential_savings] || 0 }
          },
          phase_two: {
            title: "Medium Effort (Week 3-6)",
            recommendations: medium_effort,
            estimated_savings: medium_effort.sum { |r| r[:potential_savings] || 0 }
          },
          phase_three: {
            title: "Long-term (Month 2-3)",
            recommendations: high_effort,
            estimated_savings: high_effort.sum { |r| r[:potential_savings] || 0 }
          }
        }
      end

      def generate_breakdown_csv(breakdown)
        require "csv"

        CSV.generate do |csv|
          # Header
          csv << %w[Category Subcategory Cost Traces Percentage]

          # By Model
          breakdown[:by_model].each do |model, data|
            percentage = (data[:cost] / breakdown[:totals][:total_cost] * 100).round(2)
            csv << ["Model", model, data[:cost], data[:traces], "#{percentage}%"]
          end

          # By Workflow
          breakdown[:by_workflow].each do |workflow, data|
            percentage = (data[:cost] / breakdown[:totals][:total_cost] * 100).round(2)
            csv << ["Workflow", workflow, data[:cost], data[:traces], "#{percentage}%"]
          end

          # By Tenant
          breakdown[:by_tenant].each do |tenant, data|
            percentage = (data[:cost] / breakdown[:totals][:total_cost] * 100).round(2)
            csv << ["Tenant", tenant, data[:cost], data[:traces], "#{percentage}%"]
          end
        end
      end
    end
  end
end
