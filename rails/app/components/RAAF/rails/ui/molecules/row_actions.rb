# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # RowActions — the small controls at the end of a table row.
        #
        # A `:method` makes one a `button_to`, which emits its own form; that is
        # why a row carrying these cannot itself be a link.
        #
        # @example
        #   render Molecules::RowActions.new(actions: [
        #     { label: "Retry", href: retry_path(item), method: :post },
        #     { label: "Cancel", href: cancel_path(item), method: :post,
        #       tone: :danger, confirm: "Cancel this evaluation?" }
        #   ])
        #
        class RowActions < Base
          # The only component in the library that needs a Rails helper:
          # a state-changing action has to POST, and `button_to` is what
          # carries the CSRF token.
          include Phlex::Rails::Helpers::ButtonTo

          # @param actions [Array<Hash>] :label, :href, :method, :tone, :confirm
          def initialize(actions: [], class: nil, **attrs)
            @actions = Array(actions)
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            return if @actions.empty?

            div(class: tokens("raaf-row-actions", @class), **@attrs) do
              @actions.each { |action| render_action(action) }
            end
          end

          private

          def render_action(action)
            if action[:method]
              button_to(action[:label], action[:href], method: action[:method],
                                                       form_class: "raaf-inline-form",
                                                       class: css_for(action),
                                                       data: confirm_data(action))
            else
              a(href: action[:href], class: css_for(action)) { action[:label] }
            end
          end

          def css_for(action)
            tokens("raaf-button", "raaf-button--sm",
                   action[:tone] == :danger ? "raaf-button--danger" : "raaf-button--secondary")
          end

          def confirm_data(action)
            action[:confirm] ? { confirm: action[:confirm] } : {}
          end
        end
      end
    end
  end
end
