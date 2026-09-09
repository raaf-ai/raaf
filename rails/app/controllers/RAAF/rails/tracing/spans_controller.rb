# frozen_string_literal: true

require "set"

module RAAF
  module Rails
    module Tracing
      # Controller for managing and viewing individual spans
      class SpansController < ApplicationController
        before_action :set_span, only: %i[evaluate]

        # GET /spans
        # Lists spans with filtering options
        def index
          @spans = SpanRecord.includes(:trace, :parent_span, :children)

          # Counts for the kind rail are taken with every filter except kind and
          # type applied, so the chips read as facets: clicking "tool" must not
          # make the other kinds report zero.
          #
          # Both rails come from one grouped query and are folded apart in Ruby.
          # Kind is a column and type is a JSON extraction, so asking separately
          # would mean two passes over the same window to answer one question.
          @type_counts = filter_spans(SpanRecord.all, except: %i[kind type])
                         .reorder(nil)
                         .group(:kind, Arel.sql("span_attributes->>'component.type'"))
                         .count
          @kind_counts = @type_counts.each_with_object(Hash.new(0)) do |((kind, _type), count), totals|
            totals[kind] += count
          end

          # Apply filters
          @spans = filter_spans(@spans)

          # Paginate results using Kaminari
          @per_page = [params[:per_page]&.to_i || 50, 100].min
          @paginated_spans = @spans.recent.page(params[:page]).per(@per_page)

          # One flat listing, as the design draws it. The parent/child view this
          # used to build is on a trace's waterfall, where one run's tree stands
          # on its own time scale instead of interleaving every trace's.
          @display_spans = @paginated_spans

          respond_to do |format|
            format.html do
              spans_component = RAAF::Rails::Tracing::SpansIndex.new(
                spans: @display_spans,
                paginated_spans: @paginated_spans,
                kind_counts: @kind_counts,
                type_counts: @type_counts,
                params: params.permit(:search, :kind, :type, :status, :start_time, :end_time,
                                      :trace_id, :range)
              )

              render_in_layout spans_component, title: "Spans", range: current_range, range_href: range_href
            end
            format.js { render :index }
            format.json { render json: serialize_spans(@paginated_spans) }
          end
        end

        # POST /spans/:id/evaluate
        # Manually triggers evaluation for a span with a specific policy
        def evaluate
          policy_id = params[:policy_id]

          unless policy_id.present?
            respond_to do |format|
              format.html { redirect_to evaluate_return_path, alert: "Policy ID is required." }
              format.json { render json: { error: "Policy ID is required" }, status: :unprocessable_content }
            end
            return
          end

          # Check if continuous evaluation is available
          unless defined?(RAAF::Eval::Models::EvaluationPolicy) && defined?(RAAF::Rails::Continuous::EvaluationJob)
            respond_to do |format|
              format.html { redirect_to evaluate_return_path, alert: "Continuous evaluation is not available." }
              format.json do
                render json: { error: "Continuous evaluation not available" }, status: :service_unavailable
              end
            end
            return
          end

          # Find the policy
          policy = RAAF::Eval::Models::EvaluationPolicy.find_by(id: policy_id)
          unless policy
            respond_to do |format|
              format.html { redirect_to evaluate_return_path, alert: "Policy not found." }
              format.json { render json: { error: "Policy not found" }, status: :not_found }
            end
            return
          end

          # Queue the evaluation job with force: true to allow re-evaluation
          # and manual: true to run ALL checks (including manual trigger mode checks)
          begin
            claim_queue_item(policy)

            RAAF::Rails::Continuous::EvaluationJob.perform_later(
              span_id: @span.span_id,
              policy_id: policy.id,
              force: true,
              manual: true
            )

            respond_to do |format|
              format.html { redirect_to evaluate_return_path, notice: "Evaluation queued for policy '#{policy.name}'." }
              format.json do
                render json: { message: "Evaluation queued", span_id: @span.span_id, policy_id: policy.id }
              end
            end
          rescue StandardError => e
            respond_to do |format|
              format.html { redirect_to evaluate_return_path, alert: "Failed to queue evaluation: #{e.message}" }
              format.json { render json: { error: e.message }, status: :internal_server_error }
            end
          end
        end

        # GET /spans/tools
        # Lists all tool and custom call spans
        # The registry aggregates the whole filtered set, so the HTML branch has
        # no page to turn. The paginated relation below feeds the JSON caller
        # alone -- it used to be built for a "Recent calls" table the screen
        # stopped rendering, and every HTML request paid for it.
        def tools
          @total_tool_spans = filter_tool_spans(
            SpanRecord.includes(:trace).where(kind: SpanRecord::TOOL_KINDS)
          )

          respond_to do |format|
            format.html do
              tools_component = RAAF::Rails::Tracing::ToolSpans.new(
                total_tool_spans: @total_tool_spans,
                params: params.permit(:search, :function_name, :status, :trace_id, :start_time, :end_time, :range)
              )

              render_in_layout tools_component, title: "Tools", range: current_range, range_href: range_href
            end
            format.js { render :tools }
            format.json { render json: serialize_tool_spans(paginated_tool_spans) }
          end
        end

        # GET /spans/flows
        # Shows flow visualization of agent and tool interactions
        def flows
          # Honours the topbar's range control; an explicit start_time/end_time
          # still wins. Flows needs this more than the other screens do: a
          # workflow that ran yesterday leaves the default window empty, and
          # without the control there is no way to widen it from the page.
          window = parse_time_range(params)
          @start_time = window.begin
          @end_time = window.end

          # Get agent and tool spans within time range
          flow_spans = SpanRecord.includes(:trace)
                                 .where(kind: %w[agent tool custom handoff])
                                 .within_timeframe(@start_time, @end_time)

          # Apply filters if provided
          if params[:agent_name].present?
            flow_spans = flow_spans.where("span_attributes::jsonb->>'agent.name' = ? OR span_attributes::jsonb->'agent'->>'name' = ?",
                                          params[:agent_name], params[:agent_name])
          end

          flow_spans = flow_spans.where(trace_id: params[:trace_id]) if params[:trace_id].present?

          # Build flow data structure
          @flow_data = build_flow_data(flow_spans)

          # The path tab needs every span of the chosen trace in execution
          # order, not just the agent/tool ones the topology is built from.
          @path_spans = path_spans_for(params[:trace_id]) if params[:trace_id].present?
          @agents = @flow_data[:nodes].select { |n| n[:type] == "agent" }.pluck(:name).uniq.sort
          @traces = flow_spans.joins("INNER JOIN raaf_tracing_traces ON raaf_tracing_traces.trace_id = raaf_tracing_spans.trace_id").distinct.pluck(
            "raaf_tracing_spans.trace_id", "raaf_tracing_traces.workflow_name"
          )

          respond_to do |format|
            format.html do
              flows_component = RAAF::Rails::Tracing::FlowsVisualization.new(
                flow_data: @flow_data,
                agents: @agents,
                traces: @traces,
                path_spans: @path_spans,
                range: current_range,
                params: params.permit(:agent_name, :trace_id, :start_time, :end_time, :tab, :range)
              )

              render_in_layout flows_component, title: "Flows", range: current_range, range_href: range_href
            end
            format.json { render json: @flow_data }
          end
        end

        # POST /spans/destroy_all
        # Deletes all spans from the database
        def destroy_all
          count = SpanRecord.count
          SpanRecord.delete_all

          respond_to do |format|
            format.html do
              redirect_to tracing_spans_path, notice: "Successfully deleted #{count} span(s)"
            end
            format.json { render json: { message: "Successfully deleted #{count} span(s)", count: count } }
          end
        end

        private

        def paginated_tool_spans
          per_page = [params[:per_page]&.to_i || 50, 100].min
          @total_tool_spans.recent.page(params[:page]).per(per_page)
        end

        def organize_spans_hierarchically(spans)
          # Convert to array if it's an ActiveRecord relation
          spans_array = spans.to_a

          # Group spans by trace_id for better organization
          traces_with_spans = spans_array.group_by(&:trace_id)

          organized_spans = []

          # Sort traces by most recent start_time
          sorted_traces = traces_with_spans.sort_by do |_trace_id, trace_spans|
            trace_spans.map { |s| s.start_time || Time.current }.min
          end.reverse

          sorted_traces.each do |_trace_id, trace_spans|
            # Calculate correct depth for each span within this trace
            depth_cache = calculate_depths_for_trace(trace_spans)

            # Assign calculated depths to spans
            trace_spans.each do |span|
              span.define_singleton_method(:hierarchy_depth) { depth_cache[span.span_id] }
            end

            # Find root spans for this trace (no parent within this trace)
            # Note: Removed pipeline promotion logic to show true parent-child relationships
            root_spans = trace_spans.select do |s|
              s.parent_id.nil? ||
                !trace_spans.any? { |ts| ts.span_id == s.parent_id }
            end

            # Sort root spans by start_time (newest first)
            root_spans.sort_by! { |s| -(s.start_time || Time.current).to_i }

            # For each root span, add it and all its descendants
            root_spans.each do |root_span|
              organized_spans.concat(build_span_hierarchy(root_span, trace_spans))
            end
          end

          organized_spans
        end

        def calculate_depths_for_trace(trace_spans)
          depth_cache = {}
          span_map = trace_spans.index_by(&:span_id)

          # Helper method to calculate depth recursively
          calculate_depth = lambda do |span_id, visited = Set.new|
            return 0 if visited.include?(span_id) # Prevent infinite loops
            return depth_cache[span_id] if depth_cache.key?(span_id)

            span = span_map[span_id]
            return 0 unless span

            if span.parent_id.nil? || !span_map.key?(span.parent_id)
              depth_cache[span_id] = 0
            else
              visited.add(span_id)
              parent_depth = calculate_depth.call(span.parent_id, visited)
              depth_cache[span_id] = parent_depth + 1
              visited.delete(span_id)
            end

            depth_cache[span_id]
          end

          # Calculate depth for each span
          trace_spans.each do |span|
            calculate_depth.call(span.span_id)
          end

          depth_cache
        end

        def build_span_hierarchy(parent_span, all_spans)
          result = [parent_span]

          # Find direct children of this span
          children = all_spans.select { |s| s.parent_id == parent_span.span_id }

          # Sort children by start_time (newest first)
          children.sort_by! { |c| -(c.start_time || Time.current).to_i }

          # For each child, recursively add its hierarchy
          children.each do |child|
            result.concat(build_span_hierarchy(child, all_spans))
          end

          result
        end

        # Removed is_top_level_pipeline? and is_pipeline_span? methods
        # These were causing incorrect hierarchy display by promoting pipeline spans
        # Now using true parent-child relationships from the database

        # Every span of one trace, oldest first, with children preloaded so the
        # path can report each span's fan-out without a query per row.
        def path_spans_for(trace_id)
          SpanRecord.includes(:children)
                    .where(trace_id: trace_id)
                    .order(start_time: :asc)
                    .to_a
        end

        def build_flow_data(spans) # rubocop:disable Metrics/MethodLength
          nodes = {}
          edges = {}

          spans.each do |span|
            # Add nodes for agents and tools
            if span.kind == "agent"
              agent_name = span.span_attributes&.dig("agent", "name") ||
                           span.span_attributes&.dig("agent.name") ||
                           span.name.gsub("agent.", "")
              node_id = "agent_#{agent_name}"
              nodes[node_id] = {
                id: node_id,
                name: agent_name,
                type: "agent",
                count: (nodes[node_id]&.dig(:count) || 0) + 1,
                total_duration: (nodes[node_id]&.dig(:total_duration) || 0) + (span.duration_ms || 0),
                error_count: (nodes[node_id]&.dig(:error_count) || 0) + (span.error? ? 1 : 0)
              }
            elsif %w[tool custom].include?(span.kind)
              tool_name = if span.kind == "tool"
                            span.span_attributes&.dig("function", "name") ||
                              span.span_attributes&.dig("tool", "name") ||
                              span.name
                          else # custom
                            span.span_attributes&.dig("custom", "name") || span.name
                          end

              node_id = "tool_#{tool_name}"
              nodes[node_id] = {
                id: node_id,
                name: tool_name,
                type: "tool",
                kind: span.kind,
                count: (nodes[node_id]&.dig(:count) || 0) + 1,
                total_duration: (nodes[node_id]&.dig(:total_duration) || 0) + (span.duration_ms || 0),
                error_count: (nodes[node_id]&.dig(:error_count) || 0) + (span.error? ? 1 : 0)
              }
            elsif span.kind == "handoff"
              # Handle handoff spans to create edges between agents
              from_agent = span.span_attributes&.dig("handoff", "from") || span.span_attributes&.dig("handoff.from")
              to_agent = span.span_attributes&.dig("handoff", "to") || span.span_attributes&.dig("handoff.to")

              if from_agent && to_agent
                edge_id = "agent_#{from_agent}_to_agent_#{to_agent}"
                edges[edge_id] = {
                  source: "agent_#{from_agent}",
                  target: "agent_#{to_agent}",
                  type: "handoff",
                  count: (edges[edge_id]&.dig(:count) || 0) + 1,
                  total_duration: (edges[edge_id]&.dig(:total_duration) || 0) + (span.duration_ms || 0)
                }
              end
            end

            # Create edges from parent-child relationships
            next if span.parent_id.blank?

            parent_span = spans.find { |s| s.span_id == span.parent_id }
            # Agent calling a tool
            next unless parent_span && parent_span.kind == "agent" && %w[tool custom].include?(span.kind)

            agent_name = parent_span.span_attributes&.dig("agent", "name") ||
                         parent_span.span_attributes&.dig("agent.name") ||
                         parent_span.name.gsub("agent.", "")

            tool_name = if span.kind == "tool"
                          span.span_attributes&.dig("function", "name") ||
                            span.span_attributes&.dig("tool", "name") ||
                            span.name
                        else # custom
                          span.span_attributes&.dig("custom", "name") || span.name
                        end

            edge_id = "agent_#{agent_name}_to_tool_#{tool_name}"
            edges[edge_id] = {
              source: "agent_#{agent_name}",
              target: "tool_#{tool_name}",
              type: "call",
              count: (edges[edge_id]&.dig(:count) || 0) + 1,
              total_duration: (edges[edge_id]&.dig(:total_duration) || 0) + (span.duration_ms || 0),
              error_count: (edges[edge_id]&.dig(:error_count) || 0) + (span.error? ? 1 : 0)
            }
          end

          # Calculate averages and success rates
          nodes.each_value do |node|
            if node[:count].positive?
              node[:avg_duration] = (node[:total_duration] / node[:count]).round(2)
              node[:success_rate] = ((node[:count] - node[:error_count]).to_f / node[:count] * 100).round(1)
            end
          end

          edges.each_value do |edge|
            next unless edge[:count].positive?

            edge[:avg_duration] = (edge[:total_duration] / edge[:count]).round(2)
            if edge[:error_count]
              edge[:success_rate] = ((edge[:count] - edge[:error_count]).to_f / edge[:count] * 100).round(1)
            end
          end

          {
            nodes: nodes.values,
            edges: edges.values,
            stats: {
              total_agents: nodes.values.count { |n| n[:type] == "agent" },
              total_tools: nodes.values.count { |n| n[:type] == "tool" },
              total_calls: edges.values.sum { |e| e[:count] },
              time_range: { start: @start_time, end: @end_time }
            }
          }
        end

        # The queue row is what a page reads to say "Pending", and the job is
        # what creates it. Between pressing the button and a worker picking the
        # job up there is nothing on the page to show, so the redraw comes back
        # offering the same button as if nothing had happened. Claiming the row
        # here closes that window; the job's own find_or_create finds this one.
        #
        # A row that is already pending or running belongs to a job in flight —
        # resetting it would strand that job in a state it cannot complete from.
        RESETTABLE_QUEUE_STATUSES = %w[completed partial failed cancelled].freeze

        def claim_queue_item(policy)
          item = RAAF::Eval::Models::EvaluationQueueItem.find_or_create_by!(
            span_id: @span.span_id,
            trace_id: @span.trace_id,
            evaluation_policy: policy
          ) do |new_item|
            new_item.priority = policy.priority
            new_item.max_attempts = policy.max_retries
            new_item.status = "pending"
            new_item.scheduled_at = Time.current
          end

          item.retry! if RESETTABLE_QUEUE_STATUSES.include?(item.status)
          item
        rescue StandardError => e
          # The evaluation itself is queued either way; only the "Pending" badge
          # is lost, and the job will write the row a moment later.
          ::Rails.logger.warn "[SpansController] Could not claim queue item: #{e.message}"
          nil
        end

        # Where a plain (non-Turbo) evaluate POST lands. The button appears both
        # on the span page and on a policy's matching-spans panel, and pressing it
        # should leave you where you pressed it. The form says so with return_to;
        # anything that is not a path on this host falls back to the span.
        def evaluate_return_path
          candidate = params[:return_to].to_s
          return candidate if candidate.start_with?("/") && !candidate.start_with?("//")

          span_location(@span)
        end

        def set_span
          @span = SpanRecord.find_by!(span_id: params[:id])
        rescue ActiveRecord::RecordNotFound
          redirect_to tracing_spans_path, alert: "Span not found. It may have been deleted."
        end

        # @param except [Symbol, Array<Symbol>, nil] filters to skip, so the kind
        #   rail can be counted with everything else applied
        def filter_spans(spans, except: nil)
          skipped = Array(except)

          # Filter by trace
          spans = spans.where(trace_id: params[:trace_id]) if params[:trace_id].present?

          # Filter by kind
          spans = spans.by_kind(params[:kind]) if params[:kind].present? && skipped.exclude?(:kind)

          # Filter by component type — the axis that separates a search from an
          # ecosystem lookup, both of which are recorded as kind "component".
          if params[:type].present? && skipped.exclude?(:type)
            spans = spans.where("span_attributes->>'component.type' = ?", params[:type])
          end

          # Filter by status
          spans = spans.by_status(params[:status]) if params[:status].present?

          # Filter by duration
          if params[:min_duration].present?
            min_duration = params[:min_duration].to_f
            spans = spans.where(duration_ms: min_duration..)
          end

          if params[:max_duration].present?
            max_duration = params[:max_duration].to_f
            spans = spans.where(duration_ms: ..max_duration)
          end

          # Filter by time range. The window comes from the topbar and applies
          # always, which is what the range control claims when it says 24h. It
          # used to apply only when an explicit start_time/end_time was in the
          # URL, so the header named a window the listing did not keep to.
          #
          # It belongs here rather than in the action so the kind facet counts
          # are taken over the same window as the rows they label.
          time_range = parse_time_range(params)
          spans = spans.within_timeframe(time_range.begin, time_range.end)

          # Search by name or span ID
          if params[:search].present?
            search_term = "%#{params[:search]}%"
            spans = spans.where(
              "span_id ILIKE ? OR name ILIKE ?",
              search_term, search_term
            )
          end

          spans
        end

        def serialize_spans(spans)
          {
            spans: spans.map do |span|
              {
                span_id: span.span_id,
                trace_id: span.trace_id,
                parent_id: span.parent_id,
                name: span.name,
                kind: span.kind,
                status: span.status,
                start_time: span.start_time,
                end_time: span.end_time,
                duration_ms: span.duration_ms,
                trace_workflow: span.trace&.workflow_name
              }
            end,
            pagination: {
              page: spans.current_page,
              per_page: spans.limit_value,
              total_count: spans.total_count,
              total_pages: spans.total_pages
            }
          }
        end

        def filter_tool_spans(spans)
          # The registry cards link here by the name they display, and each kind
          # keeps that name somewhere else: a tool span in its function
          # attributes, a custom span in its own, and a component span only in
          # the span name, behind the tracer's `run.workflow.<kind>.` framing.
          # Matching the raw column alone sent every component card to an empty
          # list.
          if params[:function_name].present?
            spans = spans.where(
              "((span_attributes::jsonb->'function'->>'name') = :name OR " \
              "(span_attributes::jsonb->'custom'->>'name') = :name OR " \
              "name = :name OR #{SpanRecord::READABLE_NAME_SQL} = :name)",
              name: params[:function_name]
            )
          end

          # Filter by status
          spans = spans.by_status(params[:status]) if params[:status].present?

          # Filter by trace
          spans = spans.where(trace_id: params[:trace_id]) if params[:trace_id].present?

          # Search
          if params[:search].present?
            search_term = "%#{params[:search]}%"
            spans = spans.where(
              "span_id ILIKE ? OR name ILIKE ? OR " \
              "(span_attributes::jsonb->'function'->>'name') ILIKE ? OR " \
              "(span_attributes::jsonb->'custom'->>'name') ILIKE ?",
              search_term, search_term, search_term, search_term
            )
          end

          # Apply time range filter — always, for the reason in #filter_spans.
          time_range = parse_time_range(params)
          spans.within_timeframe(time_range.begin, time_range.end)
        end

        def serialize_tool_spans(spans)
          {
            tool_calls: spans.map do |span|
              attributes = span.span_attributes || {}

              if span.kind == "tool"
                function_data = attributes["function"] || {}
                function_name = function_data["name"]
                input = function_data["input"]
                output = function_data["output"]
              else
                # Custom and component spans. A custom span nests its payload;
                # a component span writes flat keys, with the results under a
                # `result` prefix (`result_count`, `result.0.title`), so the
                # prefix is what separates the call from what it returned.
                function_name = attributes.dig("custom", "name") || span.display_name
                results, arguments = attributes.partition { |key, _| key.to_s.start_with?("result") }

                input = attributes.dig("custom", "data") || arguments.to_h
                output = attributes["output"] || attributes["result"] || results.to_h.presence
              end

              {
                span_id: span.span_id,
                trace_id: span.trace_id,
                kind: span.kind,
                function_name: function_name,
                status: span.status,
                duration_ms: span.duration_ms,
                start_time: span.start_time,
                input: input,
                output: output,
                trace_workflow: span.trace&.workflow_name
              }
            end,
            pagination: {
              page: spans.current_page,
              per_page: spans.limit_value,
              total_count: spans.total_count,
              total_pages: spans.total_pages
            }
          }
        end
      end
    end
  end
end
