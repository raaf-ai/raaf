# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Caret — a disclosure chevron that rotates when open.
        #
        class Caret < Base
          def initialize(open: false, class: nil, **attrs)
            @open = open
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            i(class: tokens("bi bi-chevron-right raaf-caret", { "is-open" => @open }, @class),
              "aria-hidden": "true", **@attrs)
          end
        end
      end
    end
  end
end
