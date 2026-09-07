# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # TopologyGraph — who hands off to whom, over a time window.
        #
        # Nodes are ranked from the edges rather than positioned by the caller:
        # anything with no incoming edge is a source, anything with no outgoing
        # edge is a sink, and what is left is the middle rank the traffic flows
        # through. The connector columns between the ranks carry the handoff
        # volume, and take the worst tone of the edges they stand for, which is
        # what makes a failing path read at a glance.
        #
        # @example
        #   render Organisms::TopologyGraph.new(
        #     nodes: [{ id: "a", name: "Search::TermBuilder", count: 2780, error_rate: 0.1 }],
        #     edges: [{ source: "a", target: "b", count: 5994 }]
        #   )
        #
        class TopologyGraph < Base
          # Above this share of runs a node is failing, not merely warning.
          BAD_ERROR_RATE = 5.0
          WARN_ERROR_RATE = 1.0

          # A rank taller than this stops being a diagram and becomes a list,
          # so it is cut — and says so, rather than quietly dropping the tail.
          RANK_LIMIT = 6

          # @param nodes [Array<Hash>] :id, :name, :count, :error_rate, :note, :href, :tone
          # @param edges [Array<Hash>] :source, :target, :count, :tone
          # @param limit [Integer] most tiles to draw per rank
          # @param empty [Hash, nil] arguments for Molecules::EmptyState
          def initialize(nodes:, edges: [], limit: RANK_LIMIT, empty: nil, class: nil, **attrs)
            @nodes = Array(nodes)
            @edges = Array(edges)
            @limit = limit
            @empty = empty
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            if @nodes.empty?
              render Molecules::EmptyState.new(**(@empty || default_empty))
              return
            end

            div(class: css, **@attrs) do
              # Nothing handed off to anything: there is no flow to draw, so
              # the nodes stand as a plain grid rather than as one rank
              # pointing an arrow at an empty one.
              next @nodes.each { |node| tile(node) } if @edges.empty?

              rank(sources)
              connector(0) if middle.any?
              rank(middle) if middle.any?
              connector(middle.any? ? 1 : 0)
              rank(sinks)
            end
          end

          # True when the graph has edges to draw. The flows screen reads this
          # so its subtitle does not promise edge widths that are not there.
          def linked?
            @edges.any?
          end

          private

          def css
            tokens("raaf-topo",
                   { "raaf-topo--loose" => @edges.empty?,
                     "raaf-topo--flat" => @edges.any? && middle.empty? },
                   @class)
          end

          def default_empty
            { icon: "diagram-3", title: "No handoffs in this window",
              text: "Nothing handed off between agents in the selected time range." }
          end

          def incoming
            @incoming ||= @edges.group_by { |e| e[:target] }
          end

          def outgoing
            @outgoing ||= @edges.group_by { |e| e[:source] }
          end

          def sources
            @sources ||= @nodes.reject { |n| incoming.key?(n[:id]) }
          end

          def sinks
            @sinks ||= @nodes.select { |n| incoming.key?(n[:id]) && !outgoing.key?(n[:id]) }
          end

          # Whatever is neither a pure source nor a pure sink — the hubs the
          # traffic passes through. A node with no edges at all lands in
          # `sources`, which is where an isolated agent belongs.
          def middle
            @middle ||= @nodes - sources - sinks
          end

          # Ranks are drawn busiest first and cut at the limit, so what is on
          # screen is always the traffic that matters most.
          def rank(nodes)
            ordered = nodes.sort_by { |node| -node[:count].to_i }
            shown = ordered.first(@limit)
            hidden = ordered.length - shown.length

            div(class: "raaf-topo-rank") do
              shown.each { |node| tile(node) }
              span(class: "raaf-topo-more") { "+#{hidden} more, not drawn" } if hidden.positive?
            end
          end

          def tile(node)
            tag = node[:href] ? :a : :div
            attributes = { class: tokens("raaf-topo-node", "raaf-topo-node--#{tone_for(node)}") }
            attributes[:href] = node[:href] if node[:href]

            public_send(tag, **attributes) do
              div(class: "raaf-topo-node-head") do
                render Atoms::Dot.new(tone: tone_for(node), pulse: tone_for(node) == :bad)
                span(class: "raaf-topo-node-name") { node[:name] }
              end
              render Atoms::Mono.new(stats_for(node), class: "raaf-topo-node-stats")
              span(class: "raaf-topo-node-note") { node[:note] } if node[:note]
            end
          end

          def tone_for(node)
            return node[:tone] if node[:tone]

            rate = node[:error_rate].to_f
            return :bad if rate >= BAD_ERROR_RATE
            return :warn if rate >= WARN_ERROR_RATE

            :ok
          end

          def stats_for(node)
            parts = []
            parts << "#{humanise(node[:count])} runs" if node[:count]
            parts << "#{'%.1f' % node[:error_rate].to_f}% err" if node[:error_rate]
            parts.join(" · ")
          end

          def humanise(count)
            value = count.to_i
            return "#{(value / 1000.0).round(1)}k" if value >= 1000

            value.to_s
          end

          # The connector standing between rank `index` and the next one.
          def connector(index)
            edges = edges_for(index)
            tone = worst_tone(edges)

            div(class: tokens("raaf-topo-link", "raaf-topo-link--#{tone}"),
                "aria-hidden": "true") do
              span(class: "raaf-topo-link-line")
              span(class: "raaf-topo-link-head")
              next if edges.empty?

              render Atoms::Mono.new(humanise(edges.sum { |e| e[:count].to_i }),
                                     class: "raaf-topo-link-count")
            end
          end

          def edges_for(index)
            from, to = if index.zero? && middle.any?
                         [sources, middle]
                       else
                         [middle.any? ? middle : sources, sinks]
                       end
            from_ids = from.pluck(:id)
            to_ids = to.pluck(:id)

            @edges.select { |e| from_ids.include?(e[:source]) && to_ids.include?(e[:target]) }
          end

          def worst_tone(edges)
            tones = edges.filter_map { |e| e[:tone] }
            return :bad if tones.include?(:bad)
            return :warn if tones.include?(:warn)

            :ok
          end
        end
      end
    end
  end
end
