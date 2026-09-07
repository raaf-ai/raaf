# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # MetricGrid — a row of MetricCards that wraps on narrow viewports.
        #
        # Pass `metrics:` for the common case, or a block for tiles that need
        # more than the MetricCard arguments.
        #
        # @example
        #   render Organisms::MetricGrid.new(metrics: [
        #     { label: "Traces", value: 1_204, icon: "diagram-3" },
        #     { label: "Errors", value: 17, icon: "x-octagon", tone: :danger }
        #   ])
        #
        class MetricGrid < Base
          # @param metrics [Array<Hash>, nil] arguments for each MetricCard
          def initialize(metrics: nil, class: nil, **attrs)
            @metrics = metrics
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-metric-grid", @class), **@attrs) do
              if block
                yield
              else
                @metrics.to_a.each { |metric| render Molecules::MetricCard.new(**metric) }
              end
            end
          end
        end
      end
    end
  end
end
