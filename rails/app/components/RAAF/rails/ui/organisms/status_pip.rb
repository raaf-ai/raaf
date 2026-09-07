# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # StatusPip — the live-connection indicator in the top bar.
        #
        # @example
        #   render Organisms::StatusPip.new(label: "Live", state: :live)
        #
        class StatusPip < Base
          STATES = %i[live error].freeze

          def initialize(label:, state: nil, class: nil, **attrs)
            @label = label
            @state = state
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            span(class: tokens("raaf-status-pip", modifier("raaf-status-pip", @state, STATES), @class),
                 **@attrs) { @label }
          end
        end
      end
    end
  end
end
