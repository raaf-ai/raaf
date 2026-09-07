# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Divider — a 1px rule, horizontal or vertical.
        #
        class Divider < Base
          def initialize(axis: :x, class: nil, **attrs)
            @axis = axis
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            hr(class: tokens("raaf-divider", { "raaf-divider--y" => @axis == :y }, @class), **@attrs)
          end
        end
      end
    end
  end
end
