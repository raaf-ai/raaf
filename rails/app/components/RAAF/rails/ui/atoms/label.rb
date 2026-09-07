# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Label — a form field label, with an optional "optional" chip.
        #
        class Label < Base
          def initialize(content = nil, for_id: nil, optional: false, class: nil, **attrs)
            @content = content
            @for_id = for_id
            @optional = optional
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            label(for: @for_id, class: tokens("raaf-label", @class), **@attrs) do
              slot(@content, &block)
              span(class: "raaf-label-optional") { "optional" } if @optional
            end
          end
        end
      end
    end
  end
end
