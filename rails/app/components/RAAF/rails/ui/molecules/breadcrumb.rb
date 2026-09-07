# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # Breadcrumb — the trail above a page title.
        #
        # The last crumb is always rendered as the current page, whether or not
        # it carries an href, so callers can pass a uniform list.
        #
        # @example
        #   render Molecules::Breadcrumb.new(items: [
        #     { label: "Traces", href: traces_path },
        #     { label: trace.workflow_name }
        #   ])
        #
        class Breadcrumb < Base
          # @param items [Array<Hash>] each with :label and an optional :href
          # @param separator [String] glyph between crumbs
          def initialize(items:, separator: "/", class: nil, **attrs)
            @items = items
            @separator = separator
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            nav(class: tokens("raaf-breadcrumb", @class), "aria-label": "Breadcrumb", **@attrs) do
              @items.each_with_index do |item, index|
                span(class: "raaf-breadcrumb-sep", "aria-hidden": "true") { @separator } if index.positive?
                crumb(item, last: index == @items.size - 1)
              end
            end
          end

          private

          def crumb(item, last:)
            if item[:href] && !last
              a(href: item[:href], class: "raaf-breadcrumb-item") { item[:label] }
            else
              span(class: "raaf-breadcrumb-item is-active", "aria-current": "page") { item[:label] }
            end
          end
        end
      end
    end
  end
end
