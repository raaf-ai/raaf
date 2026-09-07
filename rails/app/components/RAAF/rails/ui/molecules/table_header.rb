# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # TableHeader — uppercase column captions on the table's fluid grid.
        #
        # Always rendered by Organisms::DataGrid rather than directly, so the
        # header and its rows cannot fall out of step on the column template.
        #
        class TableHeader < Base
          # @param columns [Array<Hash>] :label and optional :align
          # @param template [String] the CSS grid template for the row
          def initialize(columns:, template:, class: nil, **attrs)
            @columns = columns
            @template = template
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-tbl-head", @class), role: "row",
                style: "--raaf-cols: #{@template}", **@attrs) do
              @columns.each do |column|
                div(class: tokens("raaf-tbl-head-cell",
                                  { "raaf-tbl-cell--right" => column[:align] == :right }),
                    role: "columnheader") { column[:label] }
              end
            end
          end
        end
      end
    end
  end
end
