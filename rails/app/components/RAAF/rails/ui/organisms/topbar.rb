# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # Topbar — the thin strip above the content column.
        #
        # Carries the mobile navigation toggle, the breadcrumb, and a right-hand
        # slot for live status and page-level controls.
        #
        class Topbar < Base
          # @param breadcrumb [Array<Hash>, nil] items for Molecules::Breadcrumb
          # @param meta [String, nil] monospace caption on the right
          def initialize(breadcrumb: nil, meta: nil, class: nil, **attrs)
            @breadcrumb = breadcrumb
            @meta = meta
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            header(class: tokens("raaf-topbar", @class), **@attrs) do
              nav_toggle
              render Molecules::Breadcrumb.new(items: @breadcrumb) if @breadcrumb&.any?
              div(class: "raaf-topbar-spacer")
              span(class: "raaf-topbar-meta") { @meta } if @meta
              yield if block
            end
          end

          private

          def nav_toggle
            button(type: "button",
                   class: "raaf-button raaf-button--icon raaf-sidebar-toggle",
                   "aria-label": "Toggle navigation",
                   data: { action: "click->app-shell#toggleNav" }) do
              render Atoms::Icon.new("list")
            end
          end
        end
      end
    end
  end
end
