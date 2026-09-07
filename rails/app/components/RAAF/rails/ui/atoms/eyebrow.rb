# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Eyebrow — the small uppercase kicker that sits above a title.
        #
        class Eyebrow < Base
          def initialize(content = nil, class: nil, **attrs)
            @content = content
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            p(class: tokens("raaf-eyebrow", @class), **@attrs) { slot(@content, &block) }
          end
        end
      end
    end
  end
end
