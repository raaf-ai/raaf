# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # NavGroup — a collapsible section of sidebar items.
        #
        # Built on <details>, so collapsing works without JavaScript and the
        # open/closed state is exposed to assistive technology for free. The
        # design opens the group containing the current page, plus Monitor and
        # Tracing; everything else starts closed with an item count.
        #
        class NavGroup < Base
          # @param label [String] the uppercase group caption
          # @param items [Array<Hash>] :key, :label, :icon, :href, :badge
          # @param current [Symbol, nil] key of the active item
          # @param open [Boolean] whether the group starts expanded
          def initialize(label:, items:, current: nil, open: false, class: nil, **attrs)
            @label = label
            @items = items
            @current = current
            @open = open
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            details(class: tokens("raaf-nav-group", @class), open: expanded?, **@attrs) do
              summary do
                i(class: "bi bi-chevron-right raaf-nav-group-caret", "aria-hidden": "true")
                span(class: "raaf-nav-group-label") { @label }
                span(class: "raaf-nav-group-count") { @items.size.to_s }
              end

              div(class: "raaf-nav-group-items") do
                @items.each { |item| render NavItem.new(**item, active: item[:key] == @current) }
              end
            end
          end

          private

          # Always expand the group holding the current page, whatever the default.
          def expanded?
            @open || @items.any? { |item| item[:key] == @current }
          end
        end
      end
    end
  end
end
