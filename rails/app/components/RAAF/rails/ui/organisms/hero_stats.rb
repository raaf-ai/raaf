# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # HeroStats — the dashboard's opening statement: a greeting over a
        # divided row of headline numbers.
        #
        # The column count is passed to CSS as a custom property so the row
        # divides evenly for any number of stats without a class per count.
        #
        # @example
        #   render Organisms::HeroStats.new(
        #     title: "Tracing overview",
        #     subtitle: "1,204 spans across 87 traces in the last 24 hours",
        #     stats: [
        #       { value: 87, label: "Traces" },
        #       { value: 1_204, label: "Spans" },
        #       { value: "2.4s", label: "P95 duration", tone: :accent }
        #     ]
        #   )
        #
        class HeroStats < Base
          # @param stats [Array<Hash>] arguments for each Molecules::Stat
          # @param title [String, nil]
          # @param subtitle [String, nil]
          def initialize(stats:, title: nil, subtitle: nil, class: nil, **attrs)
            @stats = stats
            @title = title
            @subtitle = subtitle
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-hero-stats", @class), **@attrs) do
              if @title || @subtitle
                div(class: "raaf-hero-stats-head") do
                  h1(class: "raaf-hero-stats-title") { @title } if @title
                  p(class: "raaf-hero-stats-sub") { @subtitle } if @subtitle
                end
              end

              div(class: "raaf-hero-stats-row", style: "--raaf-hero-stat-count: #{@stats.size}") do
                @stats.each { |stat| render Molecules::Stat.new(**stat) }
              end
            end
          end
        end
      end
    end
  end
end
