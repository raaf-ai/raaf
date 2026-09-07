# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # TableRow — one grid row, optionally a link.
        #
        # Cells are declared as an array so a row cannot silently disagree with
        # its header about how many columns there are; a cell may be a string
        # or a component.
        #
        # A cell marked `interactive: true` carries its own controls — a
        # `button_to`, say. Such a row cannot be an `<a>`: a form inside an
        # anchor is invalid, and a click on the button would navigate as well
        # as post. The link moves into the first cell instead and is stretched
        # over the row by CSS, so the row still opens the record and the
        # controls still work.
        #
        class TableRow < Base
          # @param cells [Array<Hash>] :value (String or component), :align, :primary, :muted,
          #   :interactive (the cell owns controls, so the row link steps aside)
          # @param template [String] the CSS grid template
          # @param href [String, nil] makes the row a link
          def initialize(cells:, template:, href: nil, class: nil, **attrs)
            @cells = cells
            @template = template
            @href = href
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            css = tokens("raaf-tbl-row",
                         { "raaf-tbl-row--interactive" => @href,
                           "raaf-tbl-row--linked" => stretched? },
                         @class)
            style = "--raaf-cols: #{@template}"

            if @href && !stretched?
              a(href: @href, class: css, style: style, role: "row", **@attrs) { cells }
            else
              div(class: css, style: style, role: "row", **@attrs) { cells }
            end
          end

          private

          # Only a row that both links somewhere and carries controls needs the
          # stretched link; every other row keeps the markup it always had.
          def stretched?
            @href.present? && @cells.any? { |cell| cell[:interactive] }
          end

          def cells
            @cells.each_with_index do |cell, index|
              div(class: cell_css(cell), role: "cell") do
                if stretched? && index.zero?
                  # The first cell names the record, so the stretched link
                  # takes its accessible name from it rather than needing one
                  # invented in an aria-label.
                  a(href: @href, class: "raaf-tbl-stretch") { slot(cell[:value]) }
                else
                  slot(cell[:value])
                end
              end
            end
          end

          def cell_css(cell)
            tokens(
              "raaf-tbl-cell",
              { "raaf-tbl-cell--primary" => cell[:primary],
                "raaf-tbl-cell--right" => cell[:align] == :right,
                "raaf-tbl-cell--muted" => cell[:muted],
                "raaf-tbl-cell--actions" => cell[:interactive] }
            )
          end
        end
      end
    end
  end
end
