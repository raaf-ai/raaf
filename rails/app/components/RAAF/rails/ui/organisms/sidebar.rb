# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # Sidebar — brand, collapsible nav groups, and a version footer.
        # Matches Shell.dc.html.
        #
        class Sidebar < Base
          # Groups open by default even when they don't hold the current page.
          ALWAYS_OPEN = %i[monitor tracing].freeze

          # @param groups [Array<Hash>] :id, :label, :items
          # @param current [Symbol, nil] key of the active item
          # @param brand [String] wordmark
          # @param subtitle [String] small caps line under the wordmark
          # @param meta [String, nil] version / environment line
          def initialize(groups:, current: nil, brand: "RAAF", subtitle: "Console",
                         brand_href: "#", meta: nil, class: nil, **attrs)
            @groups = groups
            @current = current
            @brand = brand
            @subtitle = subtitle
            @brand_href = brand_href
            @meta = meta
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            aside(class: tokens("raaf-sidebar", @class), **@attrs) do
              brand_link

              nav(class: "raaf-nav", "aria-label": "Console") do
                @groups.each do |group|
                  render Molecules::NavGroup.new(
                    label: group[:label], items: group[:items], current: @current,
                    open: ALWAYS_OPEN.include?(group[:id])
                  )
                end
              end

              footer_block if @meta
            end
          end

          private

          def brand_link
            a(href: @brand_href, class: "raaf-brand") do
              span(class: "raaf-brand-mark") do
                img(src: Ui::Logo.data_uri, alt: "", width: 30, height: 30, class: "raaf-brand-logo")
              end
              span(class: "raaf-brand-text") do
                span(class: "raaf-brand-name") { @brand }
                span(class: "raaf-brand-sub") { @subtitle }
              end
            end
          end

          def footer_block
            div(class: "raaf-sidebar-foot") do
              div(class: "raaf-sidebar-meta") { @meta }
            end
          end
        end
      end
    end
  end
end
