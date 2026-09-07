# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # NavItem — one row in the sidebar.
        #
        # An item without an href renders as a "soon" placeholder rather than a
        # dead link, which is how the design represents screens that do not
        # exist yet.
        #
        class NavItem < Base
          # @param label [String]
          # @param href [String, nil] omit for a not-yet-built screen
          # @param icon [String, nil] Bootstrap Icons name, with or without `bi-`
          # @param active [Boolean]
          # @param badge [String, Integer, nil] danger-toned count, e.g. errors
          def initialize(label:, href: nil, icon: nil, active: false, badge: nil,
                         key: nil, class: nil, **attrs)
            @label = label
            @href = href
            @icon = icon
            @active = active
            @badge = badge
            @key = key
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            return pending unless @href

            a(href: @href, class: css, "aria-current": (@active ? "page" : nil), **@attrs) do
              glyph
              span(class: "raaf-nav-item-label") { @label }
              span(class: "raaf-nav-item-badge") { @badge.to_s } if @badge
            end
          end

          private

          def css
            tokens("raaf-nav-item", { "is-active" => @active }, @class)
          end

          def pending
            div(class: tokens("raaf-nav-item", "raaf-nav-item--pending", @class), **@attrs) do
              glyph
              span(class: "raaf-nav-item-label") { @label }
              span(class: "raaf-nav-item-soon") { "soon" }
            end
          end

          def glyph
            return unless @icon

            render Atoms::Icon.new(@icon.to_s.delete_prefix("bi-"), size: :sm)
          end
        end
      end
    end
  end
end
