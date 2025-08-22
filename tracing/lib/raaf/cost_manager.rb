# frozen_string_literal: true

require "raaf/logging"

module RAAF
  module Tracing
    class CostManager
      include RAAF::Tracing
      include RAAF::Logger

      # Advanced cost management with multi-tenant allocation, budgeting, and optimization

      DEFAULT_PRICING = {
        "gpt-4" => { input: 0.00003, output: 0.00006 },
        "gpt-4o" => { input: 0.000005, output: 0.000015 },
        "gpt-4o-mini" => { input: 0.00000015, output: 0.0000006 },
        "gpt-3.5-turbo" => { input: 0.0000015, output: 0.000002 },
        "claude-3-5-sonnet" => { input: 0.000003, output: 0.000015 },
        "claude-3-opus" => { input: 0.000015, output: 0.000075 },
        "claude-3-haiku" => { input: 0.00000025, output: 0.00000125 }
      }.freeze

      def initialize(config = {})
        @config = {
          # Pricing configuration
          pricing: config[:pricing] || DEFAULT_PRICING,
          default_currency: config[:default_currency] || "USD",

          # Multi-tenant settings
          tenant_field: config[:tenant_field] || "tenant_id",
          project_field: config[:project_field] || "project_id",
          user_field: config[:user_field] || "user_id",

          # Budget settings
          enable_budgets: config[:enable_budgets] != false,
          budget_alert_thresholds: config[:budget_alert_thresholds] || [50, 80, 95],
          budget_enforcement: config[:budget_enforcement] || false,

          # Cost optimization
          enable_optimization: config[:enable_optimization] != false,
          optimization_recommendations: config[:optimization_recommendations] != false,

          # Reporting
          reporting_timezone: config[:reporting_timezone] || "UTC",
          cost_aggregation_interval: config[:cost_aggregation_interval] || 3600
        }

        @budgets = {}
        @cost_cache = {}
      end

      def calculate_span_cost(span)
        unless span.kind == "llm" && span.span_attributes
          return { total_cost: 0.0, input_tokens: 0, output_tokens: 0,
                   model: "unknown" }
        end

        # Debug logging
        log_debug_tracing("Calculating cost for span",
          span_id: span.span_id,
          has_attributes: !span.span_attributes.nil?
        )

        usage = span.span_attributes.dig("llm", "usage")
        return { total_cost: 0.0, input_tokens: 0, output_tokens: 0, model: "unknown" } unless usage

        model = span.span_attributes.dig("llm", "request", "model") || "gpt-4"
        input_tokens = usage["input_tokens"] || 0
        output_tokens = usage["output_tokens"] || 0

        pricing = @config[:pricing][model] || @config[:pricing]["gpt-4"]

        input_cost = input_tokens * pricing[:input]
        output_cost = output_tokens * pricing[:output]
        total_cost = input_cost + output_cost

        {
          model: model,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          input_cost: input_cost,
          output_cost: output_cost,
          total_cost: total_cost,
          currency: @config[:default_currency],
          calculated_at: Time.now
        }
      end

      def calculate_trace_cost(trace)
        llm_spans = trace.spans.where(kind: "llm")

        total_cost = 0.0
        total_input_tokens = 0
        total_output_tokens = 0
        llm_spans.count
        models_used = {}

        llm_spans.each do |span|
          span_cost = calculate_span_cost(span)

          total_cost += span_cost[:total_cost]
          total_input_tokens += span_cost[:input_tokens]
          total_output_tokens += span_cost[:output_tokens]

          model = span_cost[:model]
          models_used[model] ||= { spans: 0, cost: 0.0, input_tokens: 0, output_tokens: 0 }
          models_used[model][:spans] += 1
          models_used[model][:cost] += span_cost[:total_cost]
          models_used[model][:input_tokens] += span_cost[:input_tokens]
          models_used[model][:output_tokens] += span_cost[:output_tokens]
        end

        # Add tenant information
        tenant_info = extract_tenant_info(trace)

        {
          trace_id: trace.trace_id,
          total_cost: total_cost,
          total_input_tokens: total_input_tokens,
          total_output_tokens: total_output_tokens,
          models_used: models_used,
          llm_span_count: llm_spans.count,
          currency: @config[:default_currency],
          **tenant_info
        }
      end

      def get_cost_breakdown(timeframe: 24*3600, tenant_id: nil, project_id: nil, user_id: nil)
        end_time = Time.now
        start_time = end_time - timeframe

        traces = TraceRecord.within_timeframe(start_time, end_time)
        traces = filter_by_tenant(traces, tenant_id, project_id, user_id)

        breakdown = {
          period: {
            start: start_time,
            end: end_time,
            duration_hours: (timeframe / 3600).round(2)
          },
          totals: {
            total_cost: 0.0,
            total_traces: traces.count,
            total_input_tokens: 0,
            total_output_tokens: 0,
            total_llm_calls: 0,
            avg_cost_per_trace: 0.0
          },
          by_model: {},
          by_tenant: {},
          by_project: {},
          by_user: {},
          by_workflow: {},
          hourly_breakdown: [],
          cost_trends: []
        }

        traces.includes(:spans).each do |trace|
          trace_cost = calculate_trace_cost(trace)

          # Update totals
          breakdown[:totals][:total_cost] += trace_cost[:total_cost]
          breakdown[:totals][:total_input_tokens] += trace_cost[:total_input_tokens]
          breakdown[:totals][:total_output_tokens] += trace_cost[:total_output_tokens]
          breakdown[:totals][:total_llm_calls] += trace_cost[:llm_span_count]

          # Model breakdown
          trace_cost[:models_used].each do |model, model_data|
            breakdown[:by_model][model] ||= { cost: 0.0, traces: 0, input_tokens: 0, output_tokens: 0, spans: 0 }
            breakdown[:by_model][model][:cost] += model_data[:cost]
            breakdown[:by_model][model][:traces] += 1
            breakdown[:by_model][model][:input_tokens] += model_data[:input_tokens]
            breakdown[:by_model][model][:output_tokens] += model_data[:output_tokens]
            breakdown[:by_model][model][:spans] += model_data[:spans]
          end

          # Tenant breakdown
          if trace_cost[:tenant_id]
            tenant_key = trace_cost[:tenant_id]
            breakdown[:by_tenant][tenant_key] ||= { cost: 0.0, traces: 0, workflows: Set.new }
            breakdown[:by_tenant][tenant_key][:cost] += trace_cost[:total_cost]
            breakdown[:by_tenant][tenant_key][:traces] += 1
            breakdown[:by_tenant][tenant_key][:workflows].add(trace.workflow_name)
          end

          # Project breakdown
          if trace_cost[:project_id]
            project_key = trace_cost[:project_id]
            breakdown[:by_project][project_key] ||= { cost: 0.0, traces: 0 }
            breakdown[:by_project][project_key][:cost] += trace_cost[:total_cost]
            breakdown[:by_project][project_key][:traces] += 1
          end

          # User breakdown
          if trace_cost[:user_id]
            user_key = trace_cost[:user_id]
            breakdown[:by_user][user_key] ||= { cost: 0.0, traces: 0 }
            breakdown[:by_user][user_key][:cost] += trace_cost[:total_cost]
            breakdown[:by_user][user_key][:traces] += 1
          end

          # Workflow breakdown
          workflow_key = trace.workflow_name
          breakdown[:by_workflow][workflow_key] ||= { cost: 0.0, traces: 0 }
          breakdown[:by_workflow][workflow_key][:cost] += trace_cost[:total_cost]
          breakdown[:by_workflow][workflow_key][:traces] += 1
        end

        # Calculate averages
        if breakdown[:totals][:total_traces] > 0
          breakdown[:totals][:avg_cost_per_trace] =
            (breakdown[:totals][:total_cost] / breakdown[:totals][:total_traces]).round(6)
        end

        # Convert sets to arrays for JSON serialization
        breakdown[:by_tenant].each_value do |data|
          data[:workflows] = data[:workflows].to_a if data[:workflows].is_a?(Set)
        end

        # Generate hourly breakdown
        breakdown[:hourly_breakdown] = generate_hourly_breakdown(start_time, end_time, tenant_id, project_id, user_id)

        # Generate cost trends
        breakdown[:cost_trends] = generate_cost_trends(start_time, end_time, tenant_id, project_id, user_id)

        breakdown
      end

      def set_budget(amount:, tenant_id: nil, project_id: nil, user_id: nil, period: :monthly, currency: nil)
        budget_key = generate_budget_key(tenant_id, project_id, user_id)
        currency ||= @config[:default_currency]

        @budgets[budget_key] = {
          tenant_id: tenant_id,
          project_id: project_id,
          user_id: user_id,
          amount: amount,
          period: period,
          currency: currency,
          created_at: Time.now,
          updated_at: Time.now
        }

        # Persist budget if storage is available
        persist_budget(@budgets[budget_key]) if respond_to?(:persist_budget)

        @budgets[budget_key]
      end

      def get_budget_status(tenant_id: nil, project_id: nil, user_id: nil, period: :monthly)
        budget_key = generate_budget_key(tenant_id, project_id, user_id)
        budget = @budgets[budget_key]

        return { error: "No budget set" } unless budget

        # Calculate period dates
        period_start, period_end = calculate_period_dates(period)

        # Get current spend
        current_spend = get_cost_breakdown(
          timeframe: period_end - period_start,
          tenant_id: tenant_id,
          project_id: project_id,
          user_id: user_id
        )[:totals][:total_cost]

        percentage_used = (current_spend / budget[:amount] * 100).round(2)
        remaining = budget[:amount] - current_spend

        status = {
          budget: budget,
          period: { start: period_start, end: period_end },
          current_spend: current_spend,
          remaining: remaining,
          percentage_used: percentage_used,
          is_over_budget: current_spend > budget[:amount],
          alert_triggered: false,
          alert_level: nil
        }

        # Check alert thresholds
        @config[:budget_alert_thresholds].each do |threshold|
          if percentage_used >= threshold
            status[:alert_triggered] = true
            status[:alert_level] = threshold
          end
        end

        status
      end

      def get_cost_optimization_recommendations(timeframe: 7*24*3600, tenant_id: nil, project_id: nil)
        return [] unless @config[:enable_optimization]

        @optimization_engine.analyze_and_recommend(
          timeframe: timeframe,
          tenant_id: tenant_id,
          project_id: project_id
        )
      end

      def forecast_costs(timeframe: 30*24*3600, tenant_id: nil, project_id: nil, user_id: nil)
        # Historical data for forecasting
        historical_period = timeframe
        historical_costs = get_cost_breakdown(
          timeframe: historical_period,
          tenant_id: tenant_id,
          project_id: project_id,
          user_id: user_id
        )

        # Simple linear regression forecast
        daily_costs = historical_costs[:hourly_breakdown]
                      .group_by { |h| h[:date] }
                      .transform_values { |hours| hours.sum { |h| h[:cost] } }

        return { error: "Insufficient data for forecasting" } if daily_costs.size < 7

        trend = calculate_cost_trend(daily_costs.values)

        forecast_days = (timeframe / (24*3600)).to_i
        forecasted_costs = []

        forecast_days.times do |day|
          base_cost = daily_costs.values.last || 0
          trend_adjustment = trend * day
          forecasted_cost = [base_cost + trend_adjustment, 0].max

          forecasted_costs << {
            date: Date.today + day,
            forecasted_cost: forecasted_cost.round(6),
            confidence: calculate_forecast_confidence(day, daily_costs.size)
          }
        end

        total_forecasted = forecasted_costs.sum { |f| f[:forecasted_cost] }

        {
          timeframe: timeframe,
          total_forecasted_cost: total_forecasted,
          avg_daily_cost: (total_forecasted / forecast_days).round(6),
          forecast_data: forecasted_costs,
          trend: if trend > 0
                   "increasing"
                 else
                   (trend < 0 ? "decreasing" : "stable")
                 end,
          historical_avg: daily_costs.values.sum.to_f / daily_costs.size
        }
      end

      def generate_cost_report(format: :json, timeframe: 30*24*3600, **filters)
        breakdown = get_cost_breakdown(timeframe: timeframe, **filters)
        forecast = forecast_costs(timeframe: 30*24*3600, **filters)
        recommendations = get_cost_optimization_recommendations(timeframe: timeframe, **filters)

        report = {
          generated_at: Time.now,
          timeframe: timeframe,
          filters: filters,
          summary: breakdown[:totals],
          detailed_breakdown: breakdown,
          forecast: forecast,
          optimization_recommendations: recommendations,
          budget_status: nil
        }

        # Add budget status if applicable
        if filters[:tenant_id] || filters[:project_id] || filters[:user_id]
          budget_status = get_budget_status(**filters.slice(:tenant_id, :project_id, :user_id))
          report[:budget_status] = budget_status unless budget_status[:error]
        end

        case format
        when :json
          report.to_json
        when :csv
          generate_csv_report(report)
        when :pdf
          generate_pdf_report(report)
        else
          report
        end
      end

      def track_cost_allocation(trace_id, allocations)
        # Custom cost allocation for specific traces
        # Useful for complex multi-tenant scenarios

        allocation_data = {
          trace_id: trace_id,
          allocations: allocations, # Array of { tenant_id, percentage, amount }
          created_at: Time.current
        }

        # Store allocation data
        store_cost_allocation(allocation_data) if respond_to?(:store_cost_allocation)

        allocation_data
      end

      private

      def extract_tenant_info(trace)
        metadata = trace.metadata || {}

        {
          tenant_id: metadata[@config[:tenant_field]],
          project_id: metadata[@config[:project_field]],
          user_id: metadata[@config[:user_field]]
        }
      end

      def filter_by_tenant(traces, tenant_id, project_id, user_id)
        return traces unless tenant_id || project_id || user_id

        # This would need to be implemented based on how tenant info is stored
        # For now, filter by metadata
        traces.select do |trace|
          metadata = trace.metadata || {}

          (tenant_id.nil? || metadata[@config[:tenant_field]] == tenant_id) &&
            (project_id.nil? || metadata[@config[:project_field]] == project_id) &&
            (user_id.nil? || metadata[@config[:user_field]] == user_id)
        end
      end

      def generate_budget_key(tenant_id, project_id, user_id)
        [tenant_id, project_id, user_id].compact.join(":")
      end

      def calculate_period_dates(period)
        case period
        when :daily
          [Time.now.to_date.to_time, Time.now.to_date.to_time + 24*3600 - 1]
        when :weekly
          [Time.current.beginning_of_week, Time.current.end_of_week]
        when :monthly
          [Time.current.beginning_of_month, Time.current.end_of_month]
        when :yearly
          [Time.current.beginning_of_year, Time.current.end_of_year]
        else
          [Time.current.beginning_of_month, Time.current.end_of_month]
        end
      end

      def generate_hourly_breakdown(start_time, end_time, tenant_id, project_id, user_id)
        breakdown = []

        current_hour = start_time.beginning_of_hour
        while current_hour < end_time
          hour_end = current_hour + 3600

          hour_traces = TraceRecord.within_timeframe(current_hour, hour_end)
          hour_traces = filter_by_tenant(hour_traces, tenant_id, project_id, user_id)

          hour_cost = hour_traces.sum { |trace| calculate_trace_cost(trace)[:total_cost] }

          breakdown << {
            hour: current_hour,
            date: current_hour.to_date,
            cost: hour_cost.round(6),
            trace_count: hour_traces.count
          }

          current_hour += 3600
        end

        breakdown
      end

      def generate_cost_trends(start_time, end_time, tenant_id, project_id, user_id)
        daily_costs = {}

        current_day = start_time.to_date
        while current_day <= end_time.to_date
          day_start = current_day.beginning_of_day
          day_end = current_day.end_of_day

          day_traces = TraceRecord.within_timeframe(day_start, day_end)
          day_traces = filter_by_tenant(day_traces, tenant_id, project_id, user_id)

          day_cost = day_traces.sum { |trace| calculate_trace_cost(trace)[:total_cost] }

          daily_costs[current_day] = {
            date: current_day,
            cost: day_cost.round(6),
            trace_count: day_traces.count
          }

          current_day += 24*3600
        end

        daily_costs.values
      end

      def calculate_cost_trend(daily_costs)
        return 0 if daily_costs.size < 2

        # Simple linear regression
        n = daily_costs.size
        sum_x = (0...n).sum
        sum_y = daily_costs.sum
        sum_xy = daily_costs.each_with_index.sum { |cost, i| cost * i }
        sum_x2 = (0...n).sum { |i| i * i }

        slope = ((n * sum_xy) - (sum_x * sum_y)).to_f / ((n * sum_x2) - (sum_x * sum_x))
        slope.round(8)
      end

      def calculate_forecast_confidence(days_ahead, historical_days)
        # Confidence decreases as we forecast further out and with less historical data
        base_confidence = [100 - (days_ahead * 2), 10].max
        data_penalty = historical_days < 14 ? 20 : 0

        [base_confidence - data_penalty, 5].max
      end

      def generate_csv_report(report)
        # Generate CSV format report
        # This would be implemented based on specific requirements
        "CSV report generation not yet implemented"
      end

      def generate_pdf_report(report)
        # Generate PDF format report
        # This would be implemented based on specific requirements
        "PDF report generation not yet implemented"
      end

      # Optimization Engine
      class OptimizationEngine
        def initialize(config)
          @config = config
        end

        def analyze_and_recommend(timeframe:, tenant_id: nil, project_id: nil)
          recommendations = []

          # Analyze token usage patterns
          token_recommendations = analyze_token_usage(timeframe, tenant_id, project_id)
          recommendations.concat(token_recommendations)

          # Analyze model usage
          model_recommendations = analyze_model_usage(timeframe, tenant_id, project_id)
          recommendations.concat(model_recommendations)

          # Analyze workflow efficiency
          workflow_recommendations = analyze_workflow_efficiency(timeframe, tenant_id, project_id)
          recommendations.concat(workflow_recommendations)

          recommendations.sort_by { |r| -r[:potential_savings] }
        end

        private

        def analyze_token_usage(timeframe, tenant_id, project_id)
          recommendations = []

          # This would analyze actual token usage patterns and suggest optimizations
          # For example:
          # - Excessive prompt lengths
          # - Redundant API calls
          # - Inefficient tool usage

          recommendations << {
            type: "token_optimization",
            title: "Optimize prompt lengths",
            description: "Consider shortening prompts by removing redundant context",
            potential_savings: 15.0,
            impact: "medium",
            effort: "low"
          }

          recommendations
        end

        def analyze_model_usage(timeframe, tenant_id, project_id)
          recommendations = []

          # Analyze if cheaper models could be used for certain tasks
          recommendations << {
            type: "model_optimization",
            title: "Use GPT-4o-mini for simple tasks",
            description: "Switch to GPT-4o-mini for classification and simple Q&A tasks",
            potential_savings: 80.0,
            impact: "high",
            effort: "low"
          }

          recommendations
        end

        def analyze_workflow_efficiency(timeframe, tenant_id, project_id)
          recommendations = []

          # Analyze workflow patterns for optimization opportunities
          recommendations << {
            type: "workflow_optimization",
            title: "Batch similar requests",
            description: "Group similar LLM requests to reduce overhead",
            potential_savings: 25.0,
            impact: "medium",
            effort: "medium"
          }

          recommendations
        end
      end
    end
  end
end
