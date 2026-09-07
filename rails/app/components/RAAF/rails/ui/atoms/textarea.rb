# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Textarea — a multi-line control sharing the Input shape.
        #
        class Textarea < Base
          def initialize(name: nil, value: nil, surface: :glass, rows: 6,
                         mono: false, invalid: false, class: nil, **attrs)
            @name = name
            @value = value
            @surface = surface
            @rows = rows
            @mono = mono
            @invalid = invalid
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            textarea(name: @name, rows: @rows, class: css,
                     "aria-invalid": (@invalid ? "true" : nil), **@attrs) do
              plain(@value.to_s)
            end
          end

          private

          def css
            tokens(
              "raaf-input",
              "raaf-textarea",
              modifier("raaf-input", @surface, Input::SURFACES),
              { "raaf-input--mono" => @mono, "raaf-input--invalid" => @invalid },
              @class
            )
          end
        end
      end
    end
  end
end
