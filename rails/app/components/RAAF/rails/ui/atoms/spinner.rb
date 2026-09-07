# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Spinner — an indeterminate busy indicator.
        #
        class Spinner < Base
          SIZES = %i[md lg].freeze

          def initialize(size: nil, label: "Loading", class: nil, **attrs)
            @size = size
            @label = label
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            span(class: css, role: "status", "aria-label": @label, **@attrs)
          end

          private

          def css
            tokens("raaf-spinner", modifier("raaf-spinner", @size, SIZES), @class)
          end
        end
      end
    end
  end
end
