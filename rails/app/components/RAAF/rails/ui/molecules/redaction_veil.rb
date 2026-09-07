# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # RedactionVeil — the cover over a payload that holds customer data.
        #
        # The veil is a `<label>` driving a checkbox rather than a button with
        # a handler, so revealing works with no JavaScript at all — which
        # matters here, because a payload that stays blurred when a script
        # fails to load is a payload nobody can read.
        #
        # `PayloadBlock` wires the pair up; use this directly only when
        # covering something else with the same affordance.
        #
        # @example
        #   render Molecules::RedactionVeil.new(for_id: "reveal-42")
        #
        class RedactionVeil < Base
          # @param for_id [String] id of the checkbox this veil toggles
          # @param reason [String] why the payload is covered
          # @param note [String, nil] the fine print under the reason
          # @param icon [String] Bootstrap icon name
          def initialize(for_id:, reason: "Contains customer data — click to reveal",
                         note: "access is logged", icon: "eye-slash", class: nil, **attrs)
            @for_id = for_id
            @reason = reason
            @note = note
            @icon = icon
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            label(for: @for_id, class: tokens("raaf-veil", @class), **@attrs) do
              render Atoms::Icon.new(@icon)
              span(class: "raaf-veil-reason") { @reason }
              span(class: "raaf-veil-note") { @note } if @note
            end
          end
        end
      end
    end
  end
end
