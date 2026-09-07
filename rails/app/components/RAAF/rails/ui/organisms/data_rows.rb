# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # DataRows — the container that stacks DataRow children and draws the
        # hairlines between them.
        #
        class DataRows < Base
          def initialize(class: nil, **attrs)
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-rows", @class), **@attrs) { yield if block }
          end
        end
      end
    end
  end
end
