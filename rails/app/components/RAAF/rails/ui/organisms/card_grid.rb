# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # CardGrid — a responsive grid of cards that reflows without breakpoints.
        #
        class CardGrid < Base
          VARIANTS = %i[wide].freeze

          # @param variant [Symbol, nil] :wide raises the minimum column width
          def initialize(variant: nil, class: nil, **attrs)
            @variant = variant
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-card-grid", modifier("raaf-card-grid", @variant, VARIANTS), @class),
                **@attrs) { yield if block }
          end
        end
      end
    end
  end
end
