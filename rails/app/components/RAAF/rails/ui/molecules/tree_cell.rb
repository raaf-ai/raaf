# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # TreeCell — a span's name, indented to its depth in the trace tree.
        #
        # Carries the expander and the node mark so a hierarchy view is just a
        # DataGrid with this in the first column, rather than a second table.
        # `expand-button` and `data-span-id` are the hooks the layout's
        # span-hierarchy script binds to — load-bearing, do not rename.
        #
        class TreeCell < Base
          def initialize(name:, id: nil, level: 0, children: false, expandable: false,
                         relation: nil, class: nil, **attrs)
            @name = name
            @id = id
            @level = level
            @children = children
            @expandable = expandable
            @relation = relation
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-tree-cell", @class),
                style: ("--raaf-tree-level: #{@level}" if @expandable), **@attrs) do
              affordances if @expandable
              mark

              div(class: "raaf-tree-body") do
                span(class: "raaf-tree-name") { @name }
                span(class: "raaf-tree-relation") { @relation } if @relation
              end
            end
          end

          private

          def affordances
            div(class: "raaf-tree-elbow") if @level.positive?

            if @children
              button(type: "button", class: "expand-button", data: { span_id: @id },
                     "aria-expanded": "false", "aria-label": "Toggle children") { "▶" }
            else
              div(class: "raaf-tree-spacer")
            end
          end

          def mark
            kind = if @level.zero? then :root
                   elsif @children then :parent
                   else :leaf
                   end
            icon = { root: "house-fill", parent: "node-plus-fill", leaf: "dot" }[kind]

            span(class: "raaf-tree-mark raaf-tree-mark--#{kind}") do
              render Atoms::Icon.new(icon, size: :sm)
            end
          end
        end
      end
    end
  end
end
