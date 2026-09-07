# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Dot — a small status dot, optionally pulsing.
        #
        # @example
        #   render Atoms::Dot.new(tone: :ok, pulse: true)
        #
        class Dot < Base
          TONES = %i[ok warn bad info idle].freeze
          SIZES = %i[lg].freeze

          # @param tone [Symbol] :ok, :warn, :bad, :info or :idle
          # @param pulse [Boolean] gently fade in and out
          # @param glow [Boolean] halo the dot in its own colour
          # @param size [Symbol, nil] :lg
          # @param label [String, nil] accessible name; omit when decorative
          def initialize(tone: :idle, pulse: false, glow: false, size: nil, label: nil, class: nil, **attrs)
            @tone = tone
            @pulse = pulse
            @glow = glow
            @size = size
            @label = label
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            span(class: css, role: (@label ? "img" : nil), "aria-label": @label,
                 "aria-hidden": (@label ? nil : "true"), **@attrs)
          end

          private

          def css
            tokens(
              "raaf-dot",
              modifier("raaf-dot", @tone, TONES),
              modifier("raaf-dot", @size, SIZES),
              { "raaf-dot--glow" => @glow, "raaf-dot--pulse" => @pulse },
              @class
            )
          end
        end
      end
    end
  end
end
