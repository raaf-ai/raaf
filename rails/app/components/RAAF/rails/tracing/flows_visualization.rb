# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # The Flows screen: the same window seen three ways.
      #
      # Topology answers "who hands off to whom", pipeline heat answers "where
      # does the time go", and the path answers "what happened in this one
      # run". They are tabs rather than three screens because they are three
      # questions about one set of spans, and the tab is a URL parameter so a
      # link can point at the view that makes the argument.
      #
      class FlowsVisualization < BaseComponent
        TABS = [
          { id: "topology", label: "Handoff topology" },
          { id: "pipeline", label: "Pipeline heat" },
          { id: "trace", label: "Single trace path" }
        ].freeze

        # Above this share of runs a node is failing, not merely warning.
        BAD_ERROR_RATE = 5.0
        WARN_ERROR_RATE = 1.0

        # @param flow_data [Hash] :nodes and :edges, as built by SpansController
        # @param agents [Array<String>]
        # @param traces [Array<Array>] [trace_id, workflow_name] pairs
        # @param path_spans [Array<SpanRecord>] spans of the selected trace
        # @param range [String] the selected topbar range, named in the panel
        #   headings so a reader can see which window produced the numbers
        def initialize(flow_data:, agents: [], traces: [], path_spans: nil,
                       range: "24h", params: {})
          @flow_data = flow_data || {}
          @agents = agents
          @traces = traces
          @path_spans = path_spans
          @range = range
          @params = params
        end

        # The design opens this screen on its tabs. The shell already shows
        # "Tracing / Flows" in the topbar, so a banner repeating it here would
        # cost a tab's worth of height to say nothing.
        def view_template
          div(class: "raaf-page") do
            render Molecules::Tabs.new(variant: :underline, items: tab_items)
            panel
          end
        end

        private

        # "last 24h" reads as the design writes it; the control that changes it
        # is the range in the topbar.
        def window_label
          "last #{@range}"
        end

        def tab
          @tab ||= TABS.pluck(:id).include?(@params[:tab]) ? @params[:tab] : "topology"
        end

        def tab_items
          TABS.map do |item|
            { label: item[:label], active: item[:id] == tab,
              href: flows_tracing_spans_path(@params.to_h.merge("tab" => item[:id])) }
          end
        end

        def panel
          case tab
          when "pipeline" then pipeline_panel
          when "trace" then path_panel
          else topology_panel
          end
        end

        # ── Topology ──────────────────────────────────────────────────────

        def topology_panel
          graph = Organisms::TopologyGraph.new(nodes: topology_nodes, edges: topology_edges)

          render(Organisms::Card.new(title: "Handoff topology · #{window_label}",
                                     subtitle: topology_subtitle(graph))) do
            render graph
          end
        end

        # Without handoffs there are no edges, and promising edge widths that
        # are not on screen is worse than saying so.
        def topology_subtitle(graph)
          return "red is a failing agent · no handoffs recorded in this window" unless graph.linked?

          "edge width is handoff volume · red is a failing path"
        end

        def topology_nodes
          nodes.map do |node|
            { id: node[:id],
              name: readable(node[:name]),
              count: node[:count],
              error_rate: error_rate(node),
              note: node[:type] == "tool" ? "tool · #{average_duration(node)}" : nil }
          end
        end

        # An edge is failing when either end of it is, which is what makes a
        # broken hop visible from the connector rather than only from the node.
        def topology_edges
          edges.map do |edge|
            { source: edge[:source], target: edge[:target], count: edge[:count],
              tone: worst_tone(edge) }
          end
        end

        def worst_tone(edge)
          tones = [edge[:source], edge[:target]].filter_map do |id|
            node = nodes.find { |n| n[:id] == id }
            tone_for(error_rate(node)) if node
          end

          return :bad if tones.include?(:bad)
          return :warn if tones.include?(:warn)

          :ok
        end

        # ── Pipeline heat ─────────────────────────────────────────────────
        #
        # There is no declared pipeline structure in the trace store, so the
        # steps are the nodes ordered by the time they account for. The bar is
        # each node's share of the summed span durations.
        #
        # That sum is not the window's wall clock, which is what this panel
        # used to claim. Spans that ran in parallel each contribute their full
        # duration, and a nested span is counted inside its parent as well as
        # on its own, so the total exceeds the elapsed time — often by a lot on
        # a run that fans out. Producing a real wall-clock share would mean
        # taking the union of the intervals, which answers a different question
        # from the one the bars are ranked by. The label says what is measured
        # instead.

        def pipeline_panel
          render(Organisms::Card.new(title: "Pipeline heat · #{window_label}",
                                     subtitle: "share of total span time, slowest first")) do
            render Organisms::PipelineSteps.new(
              steps: pipeline_steps,
              empty: { icon: "list-ol", title: "No spans in this window",
                       text: "Nothing ran in the selected time range." }
            )
          end
        end

        def pipeline_steps
          total = nodes.sum { |node| node[:total_duration].to_f }
          return [] if total.zero?

          nodes.sort_by { |node| -node[:total_duration].to_f }.map do |node|
            rate = error_rate(node)

            { kind: node[:type] == "tool" ? (node[:kind] || "tool") : "agent",
              name: readable(node[:name]),
              pct: (node[:total_duration].to_f / total) * 100,
              duration: duration(node[:total_duration]),
              error_rate: rate,
              tone: tone_for(rate) }
          end
        end

        # ── Single trace path ─────────────────────────────────────────────

        def path_panel
          trace_picker
          render(Organisms::Card.new(title: path_title, subtitle: path_subtitle)) do |card|
            card.actions { open_waterfall } if @params[:trace_id].present?
            render Organisms::TracePath.new(nodes: path_nodes, empty: path_empty)
          end
        end

        # The tab reads `trace_id` and its picker had been removed, so one of
        # the three tabs was reachable only by editing the query string. The
        # controller was still loading the trace list — it was being used to
        # look up a title and nothing else.
        #
        # A select rather than a chip rail: a window can hold hundreds of
        # traces, and the point of the tab is to pick one of them.
        def trace_picker
          return if trace_options.empty?

          form(action: flows_tracing_spans_path, method: "get", class: "raaf-filterbar") do
            render Atoms::Select.new(name: "trace_id", options: trace_options,
                                     selected: @params[:trace_id],
                                     include_blank: "Pick a trace…")
            input(type: "hidden", name: "tab", value: "trace")
            carried_path_params.each { |key, value| input(type: "hidden", name: key, value: value) }
            render Atoms::Button.new(label: "Show path", size: :sm, type: "submit")
          end
        end

        # Labelled by workflow so the list reads as runs rather than as ids,
        # with the id kept beside it because a window usually holds several
        # runs of the same workflow.
        def trace_options
          @trace_options ||= @traces.to_a.filter_map do |trace_id, workflow_name|
            next if trace_id.blank?

            ["#{workflow_name.presence || 'trace'} · #{truncate_id(trace_id)}", trace_id]
          end
        end

        def carried_path_params
          { agent_name: @params[:agent_name], range: @params[:range],
            start_time: @params[:start_time], end_time: @params[:end_time] }
            .compact.reject { |_, value| value.to_s.empty? }
        end

        def path_title
          return "Single trace path" if @params[:trace_id].blank?

          workflow = @traces.to_a.find { |id, _| id == @params[:trace_id] }&.last

          workflow.presence || "Single trace path"
        end

        def path_subtitle
          @params[:trace_id].presence
        end

        def open_waterfall
          render Atoms::Button.new(label: "Open waterfall", size: :sm, variant: :secondary,
                                   icon: "bar-chart-steps",
                                   href: tracing_trace_path(@params[:trace_id]))
        end

        def path_empty
          if @params[:trace_id].blank?
            { icon: "signpost-split", title: "Pick a trace",
              text: "Choose a run above to see the order its spans ran in." }
          else
            { icon: "signpost-split", title: "No spans",
              text: "That trace recorded no spans." }
          end
        end

        # Depth is computed from the parent chain within the loaded set rather
        # than by walking to the database per span, which on a wide trace was
        # one query per row.
        def path_nodes
          spans = Array(@path_spans)
          return [] if spans.empty?

          depths = depth_map(spans)

          spans.map do |span|
            { kind: span.kind,
              name: span.display_name,
              note: note_for(span),
              duration: duration(span.duration_ms),
              level: depths[span.span_id].to_i,
              tone: span_tone(span),
              href: trace_span_path(span.span_id, span.trace_id) }
          end
        end

        def depth_map(spans)
          by_id = spans.index_by(&:span_id)

          spans.each_with_object({}) do |span, depths|
            depth = 0
            cursor = span
            while cursor&.parent_id && (parent = by_id[cursor.parent_id]) && depth < 32
              depth += 1
              cursor = parent
            end
            depths[span.span_id] = depth
          end
        end

        def note_for(span)
          return span.skip_reason.presence || "skipped" if span.skipped?
          return span.error_details&.dig(:exception_type).presence || "failed" if span.error?

          children = span.children.size
          children.positive? ? pluralize(children, "child span") : nil
        end

        def span_tone(span)
          return :bad if span.error?
          return :idle if span.cancelled?

          :ok
        end

        # ── Shared ────────────────────────────────────────────────────────

        def nodes
          @nodes ||= Array(@flow_data[:nodes])
        end

        def edges
          @edges ||= Array(@flow_data[:edges])
        end

        def error_rate(node)
          count = node[:count].to_i
          return 0.0 if count.zero?

          (node[:error_count].to_f / count) * 100
        end

        def tone_for(rate)
          return :bad if rate >= BAD_ERROR_RATE
          return :warn if rate >= WARN_ERROR_RATE

          :ok
        end

        def average_duration(node)
          count = node[:count].to_i
          return "—" if count.zero?

          duration(node[:total_duration].to_f / count)
        end

        def duration(milliseconds)
          return "—" unless milliseconds

          milliseconds < 1000 ? "#{milliseconds.round}ms" : "#{'%.1f' % (milliseconds / 1000.0)}s"
        end

        # Custom spans arrive named `run.workflow.custom.Foo::Bar.baz`. The
        # prefix is machinery, and a tile is 220px wide; only the name is
        # trimmed, never the node id, so the edges still resolve.
        def readable(name)
          name.to_s.sub(/\Arun\.workflow\.(custom\.|agent\.)?/, "")
        end
      end
    end
  end
end
