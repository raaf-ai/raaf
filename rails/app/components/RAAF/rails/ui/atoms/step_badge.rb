# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # StepBadge — a circular number, for wizards and ordered lists.
        #
        # @example
        #   render Atoms::StepBadge.new(2, state: :active)
        #
        class StepBadge < Base
          STATES = %i[default active completed].freeze
          SIZES = %i[md lg].freeze

          # @param value [String, Integer] the number or short glyph shown
          # @param state [Symbol] :default, :active or :completed
          # @param size [Symbol, nil] :md or :lg
          def initialize(value, state: :default, size: nil, class: nil, **attrs)
            @value = value
            @state = state
            @size = size
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            span(class: css, **@attrs) { @value.to_s }
          end

          private

          def css
            tokens(
              "raaf-badge-step",
              modifier("raaf-badge-step", @state, STATES),
              modifier("raaf-badge-step", @size, SIZES),
              @class
            )
          end
        end
      end
    end
  end
end
