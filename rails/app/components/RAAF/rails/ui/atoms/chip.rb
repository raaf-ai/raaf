# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Chip — a filter pill, on or off, with an optional count.
        #
        # Renders a link when given an href so filters stay addressable and
        # work without JavaScript; otherwise a button.
        #
        class Chip < Base
          # @param dot [String, Symbol, nil] a span kind; draws the chip's
          #   leading dot in that kind's colour, as the Spans filter rail does.
          #   Resolved through KindBadge so the alias table lives in one place.
          def initialize(label:, active: false, count: nil, href: nil, dot: nil,
                         class: nil, **attrs)
            @label = label
            @active = active
            @count = count
            @href = href
            @dot = dot
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            css = tokens("raaf-chip", { "is-active" => @active }, @class)

            if @href
              a(href: @href, class: css, "aria-current": (@active ? "true" : nil), **@attrs) { body }
            else
              button(type: "button", class: css, "aria-pressed": @active.to_s, **@attrs) { body }
            end
          end

          private

          def body
            span(class: "raaf-kind-dot raaf-kind-dot--#{KindBadge.resolve(@dot)}") if @dot
            plain @label
            span(class: "raaf-chip-count") { @count.to_s } if @count
          end
        end
      end
    end
  end
end
