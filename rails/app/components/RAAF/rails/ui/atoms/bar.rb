# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Bar — a single track with a proportional fill.
        #
        # The percentage travels as a custom property, keeping the markup free
        # of layout values and letting the stylesheet own the transition.
        #
        class Bar < Base
          TONES = %i[ok warn bad].freeze

          # @param pct [Numeric] 0–100; clamped
          # @param tone [Symbol, nil] :ok, :warn or :bad; default is the accent
          # @param label [String, nil] accessible name
          def initialize(pct:, tone: nil, label: nil, class: nil, **attrs)
            @pct = pct.to_f.clamp(0, 100)
            @tone = tone
            @label = label
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-bar", modifier("raaf-bar", @tone, TONES), @class),
                role: "progressbar", "aria-label": @label,
                "aria-valuenow": @pct.round, "aria-valuemin": 0, "aria-valuemax": 100, **@attrs) do
              div(class: "raaf-bar-fill", style: "--raaf-bar-pct: #{@pct.round(2)}%")
            end
          end
        end
      end
    end
  end
end
