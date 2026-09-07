# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # MetricTriple — three labelled figures on one row.
        #
        # The footer of an agent tile or a tool card: Errors / p95 / Spend.
        #
        # @example
        #   render Molecules::MetricTriple.new(metrics: [
        #     { label: "Errors", value: "0.4%", tone: :ok },
        #     { label: "p95", value: "1.9s" },
        #     { label: "Spend", value: "$41.20" }
        #   ])
        #
        class MetricTriple < Base
          # @param metrics [Array<Hash>] :label, :value, optional :tone
          def initialize(metrics:, class: nil, **attrs)
            @metrics = metrics
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-triple", @class), **@attrs) do
              @metrics.each do |metric|
                div(class: "raaf-triple-cell") do
                  span(class: "raaf-triple-label") { metric[:label] }
                  render Atoms::Mono.new(metric[:value], tone: metric[:tone],
                                                         class: "raaf-triple-value")
                end
              end
            end
          end
        end
      end
    end
  end
end
