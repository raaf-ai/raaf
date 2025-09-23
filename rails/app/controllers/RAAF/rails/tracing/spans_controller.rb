# frozen_string_literal: true

require 'set'

module RAAF
  module Rails
    module Tracing
    # Controller for managing and viewing individual spans
    class SpansController < ApplicationController
      before_action :set_span, only: %i[show events]

      # GET /spans
      # Lists spans with filtering options
      def index
        @spans = SpanRecord.includes(:trace, :parent_span, :children)

        # Apply filters
        @spans = filter_spans(@spans)

        # For hierarchical view, we'll organize spans differently
        if params[:view] == 'hierarchical'
          @spans = organize_spans_hierarchically(@spans)
          # Don't paginate for hierarchical view to maintain structure
          @page = 1
          @per_page = [@spans.count, 1].max  # Ensure @per_page is at least 1 to avoid division by zero
        else
          # Paginate results for normal view
          @page = params[:page]&.to_i || 1
          @per_page = [params[:per_page]&.to_i || 50, 100].min
          @spans = paginate_records(@spans.recent, page: @page, per_page: @per_page)
        end

        # Calculate pagination info
        @total_count = SpanRecord.count
        @total_pages = @per_page > 0 ? (@total_count.to_f / @per_page).ceil : 1

        respond_to do |format|
          format.html do
            spans_component = RAAF::Rails::Tracing::SpansIndex.new(
              spans: @spans,
              params: params.permit(:search, :kind, :status, :start_time, :end_time, :trace_id, :view),
              page: @page,
              total_pages: @total_pages,
              per_page: @per_page,
              total_count: @total_count
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Spans") do
              render spans_component
            end

            render layout
          end
          format.js { render :index }
          format.json { render json: serialize_spans(@spans) }
        end
      end

      # GET /spans/:id
      # Shows detailed view of a specific span
      def show
        @trace = @span.trace
        @operation_details = @span.operation_details
        @error_details = @span.error_details if @span.error?
        @event_timeline = @span.event_timeline

        respond_to do |format|
          format.html do
            detail_component = RAAF::Rails::Tracing::SpanDetail.new(
              span: @span,
              trace: @trace,
              operation_details: @operation_details,
              error_details: @error_details,
              event_timeline: @event_timeline
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Span Detail - #{@span.name}") do
              render detail_component
            end

            render layout
          end
          format.js { render :show }
          format.json { render json: serialize_span_detail(@span) }
        end
      end

      # GET /spans/:id/events
      # Lists events for a specific span
      def events
        @events = @span.event_timeline

        respond_to do |format|
          format.html { render :show }
          format.js { render :events }
          format.json { render json: { events: @events } }
        end
      end

      # GET /spans/tools
      # Lists all tool and custom call spans
      def tools
        # Include both 'tool' and 'custom' spans
        @tool_spans_base = SpanRecord.includes(:trace)
                                     .where(kind: %w[tool custom])

        # Apply filters
        @tool_spans_base = filter_tool_spans(@tool_spans_base)

        # Store the unpaginated query for statistics
        @total_tool_spans = @tool_spans_base

        # Paginate results
        @page = params[:page]&.to_i || 1
        @per_page = [params[:per_page]&.to_i || 50, 100].min
        @tool_spans = paginate_records(@tool_spans_base.recent, page: @page, per_page: @per_page)

        respond_to do |format|
          format.html do
            # Calculate pagination info
            @total_count = @tool_spans_base.count
            @total_pages = (@total_count.to_f / @per_page).ceil

            tools_component = RAAF::Rails::Tracing::ToolSpans.new(
              tool_spans: @tool_spans,
              total_tool_spans: @total_tool_spans,
              params: params.permit(:search, :function_name, :status, :trace_id, :start_time, :end_time),
              page: @page,
              total_pages: @total_pages,
              per_page: @per_page,
              total_count: @total_count
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Tool Spans") do
              render tools_component
            end

            render layout
          end
          format.js { render :tools }
          format.json { render json: serialize_tool_spans(@tool_spans) }
        end
      end

      # GET /spans/flows
      # Shows flow visualization of agent and tool interactions
      def flows
        # Get time range from params or default to last 24 hours
        @start_time = params[:start_time].present? ? Time.zone.parse(params[:start_time]) : 24.hours.ago
        @end_time = params[:end_time].present? ? Time.zone.parse(params[:end_time]) : Time.current

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
        @agents = @flow_data[:nodes].select { |n| n[:type] == "agent" }.pluck(:name).uniq.sort
        @traces = flow_spans.joins("INNER JOIN raaf_tracing_traces ON raaf_tracing_traces.trace_id = raaf_tracing_spans.trace_id").distinct.pluck("raaf_tracing_spans.trace_id", "raaf_tracing_traces.workflow_name")

        respond_to do |format|
          format.html do
            flows_component = RAAF::Rails::Tracing::FlowsVisualization.new(
              flow_data: @flow_data,
              agents: @agents,
              traces: @traces,
              params: params.permit(:agent_name, :trace_id, :start_time, :end_time)
            )

            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Flow Visualization") do
              render flows_component
            end

            render layout
          end
          format.json { render json: @flow_data }
        end
      end

      private

      def organize_spans_hierarchically(spans)
        # Convert to array if it's an ActiveRecord relation
        spans_array = spans.to_a

        # Group spans by trace_id for better organization
        traces_with_spans = spans_array.group_by(&:trace_id)

        organized_spans = []

        # Sort traces by most recent start_time
        sorted_traces = traces_with_spans.sort_by do |trace_id, trace_spans|
          trace_spans.map { |s| s.start_time || Time.current }.min
        end.reverse

        sorted_traces.each do |trace_id, trace_spans|
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

          # Sort root spans by start_time
          root_spans.sort_by! { |s| s.start_time || Time.current }

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

        # Sort children by start_time to maintain chronological order
        children.sort_by! { |c| c.start_time || Time.current }

        # For each child, recursively add its hierarchy
        children.each do |child|
          result.concat(build_span_hierarchy(child, all_spans))
        end

        result
      end

      # Removed is_top_level_pipeline? and is_pipeline_span? methods
      # These were causing incorrect hierarchy display by promoting pipeline spans
      # Now using true parent-child relationships from the database

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

      def set_span
        @span = SpanRecord.find_by!(span_id: params[:id])
      rescue ActiveRecord::RecordNotFound
        redirect_to tracing_spans_path, alert: "Span not found. It may have been deleted."
      end

      def filter_spans(spans)
        # Filter by trace
        spans = spans.where(trace_id: params[:trace_id]) if params[:trace_id].present?

        # Filter by kind
        spans = spans.by_kind(params[:kind]) if params[:kind].present?

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

        # Filter by time range
        if params[:start_time].present? || params[:end_time].present?
          time_range = parse_time_range(params)
          spans = spans.within_timeframe(time_range.begin, time_range.end)
        end

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
            page: @page,
            per_page: @per_page
          }
        }
      end

      def serialize_span_detail(span)
        {
          span: {
            span_id: span.span_id,
            trace_id: span.trace_id,
            parent_id: span.parent_id,
            name: span.name,
            kind: span.kind,
            status: span.status,
            start_time: span.start_time,
            end_time: span.end_time,
            duration_ms: span.duration_ms,
            attributes: span.span_attributes,
            events: span.events,
            depth: span.depth
          },
          trace: if span.trace
                   {
                     trace_id: span.trace.trace_id,
                     workflow_name: span.trace.workflow_name,
                     status: span.trace.status
                   }
                 end,
          operation_details: @operation_details,
          error_details: @error_details,
          children: span.children.map do |child|
            {
              span_id: child.span_id,
              name: child.name,
              kind: child.kind,
              status: child.status,
              duration_ms: child.duration_ms
            }
          end
        }
      end

      def filter_tool_spans(spans)
        # Filter by function name (handle both tool and custom spans)
        if params[:function_name].present?
          spans = spans.where(
            "((span_attributes::jsonb->'function'->>'name') = ? OR (span_attributes::jsonb->'custom'->>'name') = ? OR name = ?)",
            params[:function_name], params[:function_name], params[:function_name]
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

        # Apply time range filter
        if params[:start_time].present? || params[:end_time].present?
          time_range = parse_time_range(params)
          spans = spans.within_timeframe(time_range.begin, time_range.end)
        end

        spans
      end

      def serialize_tool_spans(spans)
        {
          tool_calls: spans.map do |span|
            if span.kind == "tool"
              function_data = span.span_attributes&.dig("function") || {}
              function_name = function_data["name"]
              input = function_data["input"]
              output = function_data["output"]
            else # custom
              function_name = span.span_attributes&.dig("custom", "name") || span.name
              input = span.span_attributes&.dig("custom", "data") || {}
              output = span.span_attributes&.dig("output") || span.span_attributes&.dig("result")
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
            page: @page,
            per_page: @per_page
          }
        }
      end
    end
  end
      end
end
