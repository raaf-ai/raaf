# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # StatGrid — the KPI row at the top of a console screen.
        #
        # Reflows on its own via auto-fit tracks, so no screen declares
        # breakpoints for it.
        #
        # `layout:` is the row's presentation rather than each tile's, since a
        # KPI row where one tile carried its icon somewhere else would be a
        # mistake rather than a choice. A tile may still override it.
        #
        # @example
        #   render Organisms::StatGrid.new(stats: [
        #     { label: "Runs", value: "12,480", delta: "+8.2%", icon: "diagram-3" }
        #   ])
        #
        class StatGrid < Base
          # @param stats [Array<Hash>, nil] arguments for each StatCard
          # @param layout [Symbol, nil] :corner or :leading, for every tile
          def initialize(stats: nil, layout: nil, class: nil, **attrs)
            @stats = stats
            @layout = layout
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-stat-grid", @class), **@attrs) do
              if block
                yield
              else
                @stats.to_a.each { |stat| render Molecules::StatCard.new(**tile(stat)) }
              end
            end
          end

          private

          def tile(stat)
            @layout ? { layout: @layout }.merge(stat) : stat
          end
        end
      end
    end
  end
end
