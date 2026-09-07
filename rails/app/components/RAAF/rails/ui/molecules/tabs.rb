# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # Tabs — a segmented pill group, or an underlined strip inside a card.
        #
        # Tabs are links by default so a dashboard section is addressable; pass
        # a `:target` instead of an `:href` for client-side panels driven by the
        # tabs Stimulus controller.
        #
        # @example
        #   render Molecules::Tabs.new(variant: :underline, items: [
        #     { label: "Overview", href: span_path(span), active: true },
        #     { label: "Payload", href: span_path(span, tab: "payload"), count: 12 }
        #   ])
        #
        class Tabs < Base
          VARIANTS = %i[underline].freeze

          # @param items [Array<Hash>] :label, :href or :target, :active, :count, :icon
          # @param variant [Symbol, nil] :underline for in-card tabs
          def initialize(items:, variant: nil, class: nil, **attrs)
            @items = items
            @variant = variant
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            nav(class: css, role: "tablist", **@attrs) do
              @items.each { |item| tab(item) }
            end
          end

          private

          def css
            tokens("raaf-tabs", modifier("raaf-tabs", @variant, VARIANTS), @class)
          end

          def tab(item)
            attributes = {
              class: tokens("raaf-tab", { "is-active" => item[:active] }),
              role: "tab",
              "aria-selected": item[:active] ? "true" : "false"
            }

            if item[:href]
              a(href: item[:href], **attributes) { tab_label(item) }
            else
              button(type: "button", **attributes, **(item[:data] ? { data: item[:data] } : {})) { tab_label(item) }
            end
          end

          def tab_label(item)
            render Atoms::Icon.new(item[:icon], size: :sm) if item[:icon]
            span { item[:label] }
            span(class: "raaf-tab-count") { item[:count].to_s } if item[:count]
          end
        end
      end
    end
  end
end
