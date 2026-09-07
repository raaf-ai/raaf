# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # ProgressBar — a fraction of a track.
        #
        # The width travels as a CSS custom property rather than an inline
        # `width:` declaration, which keeps the markup free of styling and lets
        # the stylesheet own the transition.
        #
        # @example
        #   render Atoms::ProgressBar.new(value: 87, tone: :accent)
        #
        class ProgressBar < Base
          TONES = %i[accent warning danger].freeze
          SIZES = %i[thin hair].freeze

          # @param value [Numeric] current value
          # @param max [Numeric] value representing a full bar
          # @param tone [Symbol, nil] see TONES
          # @param size [Symbol, nil] :thin or :hair
          # @param label [String, nil] accessible name for the progress role
          def initialize(value:, max: 100, tone: nil, size: nil, label: nil, class: nil, **attrs)
            @value = value.to_f
            @max = max.to_f
            @tone = tone
            @size = size
            @label = label
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: css, role: "progressbar", "aria-label": @label,
                "aria-valuenow": @value.round, "aria-valuemin": 0, "aria-valuemax": @max.round,
                **@attrs) do
              div(class: "raaf-progress-fill", style: "--raaf-progress-width: #{percent}%")
            end
          end

          private

          def css
            tokens(
              "raaf-progress",
              modifier("raaf-progress", @tone, TONES),
              modifier("raaf-progress", @size, SIZES),
              @class
            )
          end

          def percent
            return 0 if @max <= 0

            ((@value / @max) * 100).clamp(0, 100).round(2)
          end
        end
      end
    end
  end
end
