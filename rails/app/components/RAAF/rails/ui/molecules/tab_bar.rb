# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # TabBar — underline tabs inside a panel, or pill tabs for a whole view.
        #
        # Tabs are links by default so each view is addressable.
        #
        class TabBar < Base
          VARIANTS = %i[pill].freeze

          # @param tabs [Array<Hash>] :label, :href, :active, :count, :icon
          # @param variant [Symbol, nil] :pill
          def initialize(tabs:, variant: nil, class: nil, **attrs)
            @tabs = tabs
            @variant = variant
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            nav(class: tokens("raaf-tabbar", modifier("raaf-tabbar", @variant, VARIANTS), @class),
                role: "tablist", **@attrs) do
              @tabs.each { |tab| tab(tab) }
            end
          end

          private

          def tab(tab)
            attributes = {
              class: tokens("raaf-tabbar-tab", { "is-active" => tab[:active] }),
              role: "tab",
              "aria-selected": tab[:active] ? "true" : "false"
            }

            if tab[:href]
              a(href: tab[:href], **attributes) { contents(tab) }
            else
              button(type: "button", **attributes) { contents(tab) }
            end
          end

          def contents(tab)
            render Atoms::Icon.new(tab[:icon], size: :sm) if tab[:icon]
            span { tab[:label] }
            span(class: "raaf-tabbar-count") { tab[:count].to_s } if tab[:count]
          end
        end
      end
    end
  end
end
