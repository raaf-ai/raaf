# frozen_string_literal: true

require "raaf/cost_manager"

module RAAF
  module Rails
    # Main dashboard controller for RAAF Rails Engine
    # Provides comprehensive analytics, monitoring, and cost tracking
    class DashboardController < ApplicationController
      include RAAF::Rails::TimeRange

      # GET /dashboard
      # Main dashboard with overview metrics
      def index
        @time_range = parse_time_range(params)

        # Overview statistics
        @overview_stats = calculate_overview_stats(@time_range)

        # Top workflows
        @top_workflows = RAAF::Rails::Tracing::TraceRecord.top_workflows(limit: 10, timeframe: @time_range)

        # Recent activity
        @recent_traces = RAAF::Rails::Tracing::TraceRecord.recent.limit(10).includes(:spans)
        @recent_errors = RAAF::Rails::Tracing::SpanRecord.errors.recent.limit(10).includes(:trace)

        # Performance trends (simplified for now)
        @performance_trends = calculate_performance_trends(@time_range)
        @agent_series = agent_series(@top_workflows, @time_range)

        respond_to do |format|
          format.html do
            # Failures grouped the way the Errors screen groups them, over the
            # window the topbar selected. The screen used to group the ten most
            # recent error spans itself, regardless of range, which put failures
            # from outside the window beside a KPI row reporting none.
            @error_signatures = RAAF::Rails::Tracing::SpanRecord
                                .error_signatures(timeframe: @time_range, limit: 6)
            @workflow_spend = RAAF::Rails::Tracing::SpanRecord
                              .spend_by_workflow(timeframe: @time_range)

            dashboard_component = RAAF::Rails::Tracing::DashboardIndex.new(
              overview_stats: @overview_stats,
              top_workflows: @top_workflows,
              recent_traces: @recent_traces,
              error_signatures: @error_signatures,
              workflow_spend: @workflow_spend,
              agent_series: @agent_series
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(
              title: "Dashboard", range: current_range, range_href: range_href
            ) do
              render dashboard_component
            end

            render layout
          end
          format.json do
            render json: {
              overview: @overview_stats,
              workflows: @top_workflows,
              recent_traces: serialize_recent_traces(@recent_traces),
              recent_errors: serialize_recent_errors(@recent_errors),
              trends: @performance_trends
            }
          end
        end
      end

      # GET /dashboard/performance
      # Performance analytics dashboard
      def performance
        @time_range = parse_time_range(params)

        # Performance metrics by span kind
        @performance_by_kind = %w[agent llm tool handoff].to_h do |kind|
          metrics = RAAF::Rails::Tracing::SpanRecord.performance_metrics(kind: kind, timeframe: @time_range)
          [kind, metrics]
        end

        # Slowest operations
        @slowest_spans = RAAF::Rails::Tracing::SpanRecord.slow(1000).within_timeframe(@time_range.begin,
                                                                                      @time_range.end)
                                                         .includes(:trace)
                                                         .order(duration_ms: :desc)
                                                         .limit(20)

        # Performance trends over time
        @performance_over_time = calculate_performance_over_time(@time_range)

        respond_to do |format|
          format.html do
            performance_component = RAAF::Rails::Tracing::PerformanceDashboard.new(
              performance_by_kind: @performance_by_kind,
              slowest_spans: @slowest_spans,
              performance_over_time: @performance_over_time,
              params: params.permit(:start_time, :end_time, :kind)
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(
              title: "Performance Dashboard", range: current_range, range_href: range_href
            ) do
              render performance_component
            end

            render layout
          end
          format.json do
            render json: {
              performance_by_kind: @performance_by_kind,
              slowest_spans: serialize_spans(@slowest_spans),
              performance_over_time: @performance_over_time
            }
          end
        end
      end

      # GET /dashboard/costs
      # What the window cost and where it went.
      def costs
        @time_range = parse_time_range(params)

        respond_to do |format|
          format.html do
            @cost_rollup = RAAF::Rails::Tracing::SpanRecord.cost_rollup(timeframe: @time_range)

            costs_component = RAAF::Rails::Tracing::CostsIndex.new(
              cost_data: @cost_rollup.merge(
                window_hours: (@time_range.end - @time_range.begin) / 3600.0,
                breakdowns: [{ title: "By model", rows: @cost_rollup[:by_model] },
                             { title: "By agent", rows: @cost_rollup[:by_agent] }]
              ),
              params: params.permit(:range)
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(
              title: "Cost & usage", range: current_range, range_href: range_href
            ) do
              render costs_component
            end

            render layout
          end
          # The JSON payload predates the screen and keeps its own shape, built
          # by CostManager over whole traces. It is left alone so a caller
          # polling this endpoint is not broken by the screen changing.
          format.json { render json: legacy_cost_payload(@time_range) }
        end
      end

      # GET /dashboard/errors
      # What broke, grouped by exception rather than listed span by span.
      def errors
        @time_range = parse_time_range(params)

        respond_to do |format|
          format.html do
            @signatures = RAAF::Rails::Tracing::SpanRecord.error_signatures(timeframe: @time_range)

            errors_component = RAAF::Rails::Tracing::ErrorsDashboard.new(
              signatures: @signatures,
              params: params.permit(:range)
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(
              title: "Errors", range: current_range, range_href: range_href
            ) do
              render errors_component
            end

            render layout
          end
          # The JSON payload predates the screen and is left as it was: the
          # ungrouped list is what a caller polling this endpoint asked for.
          format.json do
            @error_analysis = RAAF::Rails::Tracing::SpanRecord.error_analysis(timeframe: @time_range)
            @error_trends = calculate_error_trends(@time_range)
            @per_page = [params[:per_page]&.to_i || 25, 100].min
            @recent_errors = RAAF::Rails::Tracing::SpanRecord
                             .errors.within_timeframe(@time_range.begin, @time_range.end)
                             .includes(:trace).recent.page(params[:page]).per(@per_page)

            render json: {
              error_analysis: @error_analysis,
              error_trends: @error_trends,
              recent_errors: serialize_error_spans(@recent_errors)
            }
          end
        end
      end

      # GET /dashboard/agents
      # The fleet: one row per agent over the selected range.
      def agents
        @time_range = parse_time_range(params)
        @agents = RAAF::Rails::Tracing::SpanRecord.agent_rollup(timeframe: @time_range)

        respond_to do |format|
          format.html do
            agents_component = RAAF::Rails::Tracing::AgentsIndex.new(
              agents: @agents,
              params: params.permit(:health, :range)
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(
              title: "Agents", range: current_range, range_href: range_href
            ) do
              render agents_component
            end

            render layout
          end
          format.json { render json: { agents: @agents } }
        end
      end

      def conversations
        render RAAF::Rails::SimpleDashboard.new(title: "Conversations")
      end

      def analytics
        render RAAF::Rails::SimpleDashboard.new(title: "Analytics")
      end

      private

      # The cost JSON this endpoint has always returned, built by CostManager
      # over whole traces. Kept verbatim so the payload does not change under a
      # caller; the HTML screen reads SpanRecord.cost_rollup instead, which
      # bills the same spans the Agents screen does.
      def legacy_cost_payload(time_range)
        cost_manager = RAAF::Tracing::CostManager.new
        cost_analysis = RAAF::Rails::Tracing::SpanRecord.cost_analysis(timeframe: time_range)

        total_cost = 0.0
        total_input_tokens = 0
        total_output_tokens = 0
        total_llm_calls = 0
        model_costs = {}

        RAAF::Rails::Tracing::TraceRecord
          .within_timeframe(time_range.begin, time_range.end)
          .includes(:spans).find_each do |trace|
          trace_cost = cost_manager.calculate_trace_cost(trace)
          total_cost += trace_cost[:total_cost]

          trace_cost[:models_used]&.each do |model, data|
            model_costs[model] ||= { cost: 0.0, calls: 0, input_tokens: 0, output_tokens: 0 }
            model_costs[model][:cost] += data[:cost]
            model_costs[model][:calls] += data[:spans]
            model_costs[model][:input_tokens] += data[:input_tokens]
            model_costs[model][:output_tokens] += data[:output_tokens]

            total_input_tokens += data[:input_tokens]
            total_output_tokens += data[:output_tokens]
            total_llm_calls += data[:spans]
          end
        end

        if total_llm_calls.positive?
          cost_analysis[:total_input_tokens] = total_input_tokens
          cost_analysis[:total_output_tokens] = total_output_tokens
          cost_analysis[:total_tokens] = total_input_tokens + total_output_tokens
          cost_analysis[:total_llm_calls] = total_llm_calls
          cost_analysis[:avg_tokens_per_call] =
            ((total_input_tokens + total_output_tokens).to_f / total_llm_calls).round(2)
        end

        {
          cost_analysis: cost_analysis,
          cost_by_model: calculate_cost_by_model(time_range),
          usage_over_time: calculate_usage_over_time(time_range),
          top_workflows: calculate_top_consuming_workflows(time_range)
        }
      end

      # The design gives every agent card a sparkline of its recent activity.
      # One query for the whole grid, bucketed in Ruby: `date_trunc` cannot
      # divide an arbitrary window into a fixed number of columns, and the
      # window here is whatever the topbar says.
      AGENT_SERIES_BUCKETS = 18

      # Per workflow: the run count per bucket, and the buckets that contain a
      # failed run. The design colours those bars red — a sparkline that is one
      # flat colour says only "it ran", which the run count beside it already
      # says. Status travels with the timestamp so this stays one query.
      #
      # Each bucket also carries when it began and how many of its runs failed,
      # which is what the tile's hover readout is built from. A red bar tells a
      # reader that something failed but not when, and "when" is the only
      # question a spike on a sparkline actually raises.
      def agent_series(workflows, range)
        names = Array(workflows).filter_map { |w| w[:workflow_name] }
        span = range.end - range.begin
        return {} if names.empty? || span <= 0

        rows = RAAF::Rails::Tracing::TraceRecord
               .where(workflow_name: names, started_at: range)
               .pluck(:workflow_name, :started_at, :status)

        starts = bucket_starts(range, span)

        rows.each_with_object({}) do |(name, started_at, status), series|
          bucket = (((started_at - range.begin) / span) * AGENT_SERIES_BUCKETS).floor
          bucket = bucket.clamp(0, AGENT_SERIES_BUCKETS - 1)

          entry = series[name] ||= {
            counts: Array.new(AGENT_SERIES_BUCKETS, 0),
            fails: Array.new(AGENT_SERIES_BUCKETS, 0),
            starts: starts, tones: {}
          }
          entry[:counts][bucket] += 1
          next unless status == "failed"

          entry[:fails][bucket] += 1
          entry[:tones][bucket] = :bad
        end
      rescue StandardError
        {}
      end

      # One frozen array shared by every workflow — the buckets are cut from
      # the same window, so they begin at the same instants.
      def bucket_starts(range, span)
        Array.new(AGENT_SERIES_BUCKETS) do |index|
          range.begin + (span * index / AGENT_SERIES_BUCKETS)
        end.freeze
      end

      # How many bars the trend series on this dashboard are cut into.
      SERIES_BUCKETS = 24

      # The bucket geometry for a window: how wide each bucket is, how many
      # there are, and when each begins.
      #
      # Its own step because three series are cut from it and they are read
      # side by side. Bars an hour wide beside bars thirty hours wide are two
      # answers to the same question.
      def series_plan(time_range)
        hours = ((time_range.end - time_range.begin) / 1.hour).ceil
        width_hours = [hours / SERIES_BUCKETS, 1].max
        count = [(hours.to_f / width_hours).ceil, 1].max

        { width_hours: width_hours, count: count,
          starts: Array.new(count) { |index| time_range.begin + (index * width_hours).hours } }
      end

      # The aggregates for each non-empty bucket, keyed by bucket index.
      #
      # The bucketing happens in one GROUP BY rather than in a Ruby loop that
      # queried per bucket. Those loops issued four or five queries each — on
      # the performance screen around 120 for one page — and at a 30-day range
      # a single bucket's count took over three seconds, because each one
      # scanned a thirty-hour slice on its own.
      #
      # Buckets are half-open, so a span on a boundary lands in exactly one of
      # them. The per-bucket loops used an inclusive range at both ends and
      # counted such a span twice. `least` keeps a row sitting exactly on the
      # window's upper bound in the last bucket instead of one past the end.
      #
      # @return [Hash] bucket index => the aggregate values, in select order
      def series_rows(model, column, time_range, plan, aggregates)
        sql = model.sanitize_sql_array(
          [<<~SQL.squish, time_range.begin, plan[:width_hours] * 3600, time_range.begin, time_range.end]
            SELECT least(floor(extract(epoch from (#{column} - ?::timestamptz)) / ?)::int, #{plan[:count] - 1})
                     AS bucket,
                   #{aggregates}
            FROM #{model.table_name}
            WHERE #{column} >= ?::timestamptz AND #{column} <= ?::timestamptz
            GROUP BY 1
          SQL
        )

        model.connection.select_rows(sql).to_h { |row| [row.first.to_i, row.drop(1)] }
      end

      def calculate_overview_stats(time_range)
        traces = RAAF::Rails::Tracing::TraceRecord.within_timeframe(time_range.begin, time_range.end)
        spans = RAAF::Rails::Tracing::SpanRecord.within_timeframe(time_range.begin, time_range.end)

        {
          total_traces: traces.count,
          completed_traces: traces.completed.count,
          failed_traces: traces.failed.count,
          running_traces: traces.running.count,
          total_spans: spans.count,
          error_spans: spans.errors.count,
          avg_trace_duration: traces.where.not(ended_at: nil)
                                    .average("EXTRACT(EPOCH FROM (ended_at - started_at))")
                                    &.round(2),
          success_rate: if traces.any?
                          ((traces.completed.count.to_f / traces.count) * 100).round(2)
                        else
                          0
                        end,
          error_rate: if spans.any?
                        ((spans.errors.count.to_f / spans.count) * 100).round(2)
                      else
                        0
                      end
        }
      end

      def calculate_performance_trends(time_range)
        plan = series_plan(time_range)
        rows = series_rows(
          RAAF::Rails::Tracing::TraceRecord, "started_at", time_range, plan,
          <<~SQL.squish
            count(*),
            avg(extract(epoch from (ended_at - started_at))) FILTER (WHERE ended_at IS NOT NULL),
            count(*) FILTER (WHERE status = 'failed')
          SQL
        )

        plan[:starts].each_with_index.map do |start, index|
          count, avg_duration, errors = rows[index]

          { timestamp: start,
            trace_count: count.to_i,
            avg_duration: avg_duration&.to_f&.round(2),
            error_count: errors.to_i }
        end
      end

      def calculate_performance_over_time(time_range)
        plan = series_plan(time_range)
        rows = series_rows(
          RAAF::Rails::Tracing::SpanRecord, "start_time", time_range, plan,
          <<~SQL.squish
            count(*),
            avg(duration_ms),
            percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms),
            count(*) FILTER (WHERE status = 'error')
          SQL
        )

        plan[:starts].each_with_index.map do |start, index|
          count, avg_duration, p95, errors = rows[index]

          { timestamp: start,
            span_count: count.to_i,
            avg_duration: avg_duration&.to_f&.round(2),
            p95_duration: p95&.to_f&.round(2),
            error_count: errors.to_i }
        end
      end

      # Token usage per model over a window.
      #
      # Every span that recorded a model and tokens counts, whichever key shape
      # it used. Filtering on kind: "llm" and digging llm.usage.* matched almost
      # nothing — the DSL agent records both on the agent span — so this table
      # was empty on a dashboard reporting real spend.
      def calculate_cost_by_model(time_range)
        spans = RAAF::Rails::Tracing::SpanRecord
                .within_timeframe(time_range.begin, time_range.end)
                .with_token_usage
                .for_billing

        model_stats = {}

        spans.find_each do |span|
          usage = span.token_usage
          model = usage[:model]
          total = RAAF::Tracing::SpanUsage.total_tokens(usage)
          next unless model && total

          model_stats[model] ||= {
            call_count: 0,
            input_tokens: 0,
            output_tokens: 0,
            total_tokens: 0
          }

          model_stats[model][:call_count] += 1
          model_stats[model][:input_tokens] += usage[:input].to_i
          model_stats[model][:output_tokens] += usage[:output].to_i
          model_stats[model][:total_tokens] += total
        end

        model_stats
      end

      def calculate_usage_over_time(time_range)
        # Similar bucketing approach for token usage over time
        hours = ((time_range.end - time_range.begin) / 1.hour).ceil
        bucket_size = [hours / 24, 1].max

        buckets = []
        current_time = time_range.begin

        while current_time < time_range.end
          bucket_end = [current_time + bucket_size.hours, time_range.end].min

          usages = RAAF::Rails::Tracing::SpanRecord
                   .within_timeframe(current_time, bucket_end)
                   .with_token_usage
                   .for_billing
                   .map(&:token_usage)
                   .select { |usage| RAAF::Tracing::SpanUsage.total_tokens(usage) }

          total_input_tokens = usages.sum { |usage| usage[:input].to_i }
          total_output_tokens = usages.sum { |usage| usage[:output].to_i }

          buckets << {
            timestamp: current_time,
            llm_calls: usages.count,
            input_tokens: total_input_tokens,
            output_tokens: total_output_tokens,
            total_tokens: usages.sum { |usage| RAAF::Tracing::SpanUsage.total_tokens(usage).to_i }
          }

          current_time = bucket_end
        end

        buckets
      end

      def calculate_top_consuming_workflows(time_range)
        traces = RAAF::Rails::Tracing::TraceRecord.within_timeframe(time_range.begin, time_range.end)
        cost_manager = RAAF::Tracing::CostManager.new

        workflow_usage = {}

        traces.includes(:spans).find_each do |trace|
          usages = trace.span_usages
          total_tokens = trace.total_tokens.to_i

          # Calculate cost for this trace
          trace_cost = cost_manager.calculate_trace_cost(trace)

          workflow_usage[trace.workflow_name] ||= {
            trace_count: 0,
            total_tokens: 0,
            llm_calls: 0,
            total_cost: 0.0
          }

          workflow_usage[trace.workflow_name][:trace_count] += 1
          workflow_usage[trace.workflow_name][:total_tokens] += total_tokens
          workflow_usage[trace.workflow_name][:llm_calls] += usages.count
          workflow_usage[trace.workflow_name][:total_cost] += trace_cost[:total_cost]
        end

        # Sort by total tokens descending
        workflow_usage.sort_by { |_, stats| -stats[:total_tokens] }.first(10).to_h
      end

      def calculate_error_trends(time_range)
        plan = series_plan(time_range)
        rows = series_rows(
          RAAF::Rails::Tracing::SpanRecord, "start_time", time_range, plan,
          "count(*), count(*) FILTER (WHERE status = 'error')"
        )

        plan[:starts].each_with_index.map do |start, index|
          total, errors = rows[index]
          total = total.to_i
          errors = errors.to_i

          { timestamp: start,
            total_spans: total,
            error_spans: errors,
            error_rate: total.positive? ? ((errors.to_f / total) * 100).round(2) : 0 }
        end
      end

      def serialize_recent_traces(traces)
        traces.map do |trace|
          {
            trace_id: trace.trace_id,
            workflow_name: trace.workflow_name,
            status: trace.status,
            started_at: trace.started_at,
            duration_ms: trace.duration_ms,
            span_count: trace.spans.count
          }
        end
      end

      def serialize_recent_errors(spans)
        spans.map do |span|
          {
            span_id: span.span_id,
            trace_id: span.trace_id,
            name: span.name,
            kind: span.kind,
            start_time: span.start_time,
            workflow_name: span.trace&.workflow_name,
            error_details: span.error_details
          }
        end
      end

      def serialize_error_spans(spans)
        spans.map do |span|
          {
            span_id: span.span_id,
            trace_id: span.trace_id,
            name: span.name,
            kind: span.kind,
            start_time: span.start_time,
            duration_ms: span.duration_ms,
            workflow_name: span.trace&.workflow_name,
            error_details: span.error_details
          }
        end
      end

      def serialize_spans(spans)
        spans.map do |span|
          {
            span_id: span.span_id,
            trace_id: span.trace_id,
            name: span.name,
            kind: span.kind,
            start_time: span.start_time,
            duration_ms: span.duration_ms,
            workflow_name: span.trace&.workflow_name
          }
        end
      end
    end
  end
end
