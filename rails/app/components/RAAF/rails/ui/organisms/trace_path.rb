# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # TracePath — one trace as a vertical path of hops.
        #
        # The waterfall answers "when did this happen"; the path answers "what
        # called what", which is why it carries a note per hop rather than a
        # bar. It is the flows screen's third tab.
        #
        # @example
        #   render Organisms::TracePath.new(nodes: [
        #     { kind: "pipeline", name: "Discovery::Pipeline", note: "6 steps",
        #       duration: "11.4s", level: 0, tone: :bad }
        #   ])
        #
        class TracePath < Base
          # @param nodes [Array<Hash>] :kind, :name, :note, :duration, :level, :tone, :href
          # @param empty [Hash, nil] arguments for Molecules::EmptyState
          def initialize(nodes:, empty: nil, class: nil, **attrs)
            @nodes = Array(nodes)
            @empty = empty
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-tracepath", @class), **@attrs) do
              if @nodes.empty?
                render Molecules::EmptyState.new(**(@empty || default_empty))
              else
                @nodes.each_with_index { |node, i| hop(node, i) }
              end
            end
          end

          private

          def default_empty
            { icon: "signpost-split", title: "No path to show",
              text: "Pick a trace to see the order its spans ran in." }
          end

          def hop(node, index)
            render Molecules::PathNode.new(
              kind: node[:kind],
              name: node[:name],
              note: node[:note],
              duration: node[:duration],
              level: node[:level].to_i,
              tone: node[:tone] || :ok,
              first: index.zero?,
              last: index == @nodes.length - 1,
              href: node[:href]
            )
          end
        end
      end
    end
  end
end
