# frozen_string_literal: true

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

        # Paginate results
        @page = params[:page]&.to_i || 1
        @per_page = [params[:per_page]&.to_i || 50, 100].min
        @spans = paginate_records(@spans.recent, page: @page, per_page: @per_page)

        respond_to do |format|
          format.html do
            render RAAF::Rails::Tracing::SpansList.new(
              spans: @spans,
              page: @page,
              per_page: @per_page
            )
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
          format.html { render "RAAF/rails/tracing/spans/show" }
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
          format.html { render "RAAF/rails/tracing/spans/tools" }
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
        @traces = flow_spans.joins(:trace).distinct.pluck(:trace_id, "raaf_tracing_traces.workflow_name")

        respond_to do |format|
          format.html { render "RAAF/rails/tracing/spans/flows" }
          format.json { render json: @flow_data }
        end
      end

      private

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
        redirect_to spans_path, alert: "Span not found. It may have been deleted."
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
