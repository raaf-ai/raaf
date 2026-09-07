# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # Stat — a headline number with its uppercase caption.
        #
        # Used inside HeroStats, and standalone wherever a figure needs a label.
        #
        # @example
        #   render Molecules::Stat.new(value: "1,204", label: "Spans today",
        #                              delta: "+12%", direction: :up)
        #
        class Stat < Base
          TONES = %i[accent success warning danger].freeze
          DIRECTIONS = { up: "arrow-up-short", down: "arrow-down-short", flat: "dash" }.freeze

          # @param value [String, Numeric]
          # @param label [String] the uppercase caption
          # @param tone [Symbol, nil] colours the value
          # @param delta [String, nil] change chip beside the value
          # @param direction [Symbol] :up, :down or :flat — colours the delta
          def initialize(value:, label:, tone: nil, delta: nil, direction: :flat, class: nil, **attrs)
            @value = value
            @label = label
            @tone = tone
            @delta = delta
            @direction = direction
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-stat", @class), **@attrs) do
              div(class: value_css) do
                plain(@value.to_s)
                delta_chip if @delta
              end
              div(class: "raaf-stat-label") { @label }
            end
          end

          private

          def value_css
            tokens("raaf-stat-value", modifier("raaf-stat-value", @tone, TONES))
          end

          def delta_chip
            span(class: "raaf-stat-delta raaf-stat-delta--#{@direction}") do
              render Atoms::Icon.new(DIRECTIONS.fetch(@direction, "dash"), size: :sm)
              plain(@delta.to_s)
            end
          end
        end
      end
    end
  end
end
