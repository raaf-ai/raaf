# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Icon — a Bootstrap Icons glyph with size and tone set by class.
        #
        # Decorative by default: the glyph carries `aria-hidden` unless a
        # `label` is given, in which case it is exposed as an image with that
        # accessible name.
        #
        # @example
        #   render Atoms::Icon.new("exclamation-triangle-fill", tone: :warning)
        #
        class Icon < Base
          SIZES = %i[sm lg xl].freeze
          TONES = %i[muted accent success warning danger info].freeze

          # @param name [String] Bootstrap Icons name without the `bi-` prefix
          # @param size [Symbol, nil] :sm, :lg or :xl
          # @param tone [Symbol, nil] semantic colour
          # @param label [String, nil] accessible name; omit when decorative
          def initialize(name, size: nil, tone: nil, label: nil, class: nil, **attrs)
            @name = name
            @size = size
            @tone = tone
            @label = label
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            span(class: css, **accessibility, **@attrs) do
              i(class: "bi bi-#{@name}")
            end
          end

          private

          def css
            tokens(
              "raaf-icon",
              modifier("raaf-icon", @size, SIZES),
              modifier("raaf-icon", @tone, TONES),
              @class
            )
          end

          def accessibility
            return { "aria-hidden": "true" } unless @label

            { role: "img", "aria-label": @label }
          end
        end
      end
    end
  end
end
