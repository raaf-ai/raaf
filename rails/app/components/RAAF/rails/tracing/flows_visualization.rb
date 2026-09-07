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
        # steps are the nodes ordered by the wall clock they account for. The
        # bar is each node's share of that total, which is the same reading
        # the designed screen gives.

        def pipeline_panel
          render(Organisms::Card.new(title: "Pipeline heat · #{window_label}",
                                     subtitle: "share of the window's wall clock, slowest first")) do
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
          render(Organisms::Card.new(title: path_title, subtitle: path_subtitle)) do |card|
            card.actions { open_waterfall } if @params[:trace_id].present?
            render Organisms::TracePath.new(nodes: path_nodes, empty: path_empty)
          end
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
              text: "Filter this screen by a trace to see the order its spans ran in." }
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
