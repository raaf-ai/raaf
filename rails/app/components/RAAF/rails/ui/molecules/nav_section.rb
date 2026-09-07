# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # NavSection — the uppercase caption separating groups of nav items.
        #
        class NavSection < Base
          def initialize(content = nil, class: nil, **attrs)
            @content = content
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-nav-section", @class), **@attrs) { slot(@content, &block) }
          end
        end
      end
    end
  end
end
