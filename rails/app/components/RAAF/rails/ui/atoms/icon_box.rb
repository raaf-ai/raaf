# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # IconBox — a tinted square behind an icon. Used in card headers and
        # empty states where a bare glyph would read as too small.
        #
        class IconBox < Base
          TONES = %i[accent success warning danger].freeze
          SIZES = %i[lg].freeze

          def initialize(name, tone: nil, size: nil, label: nil, class: nil, **attrs)
            @name = name
            @tone = tone
            @size = size
            @label = label
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            span(class: css, **@attrs) do
              render Icon.new(@name, label: @label)
            end
          end

          private

          def css
            tokens(
              "raaf-icon-box",
              modifier("raaf-icon-box", @tone, TONES),
              modifier("raaf-icon-box", @size, SIZES),
              @class
            )
          end
        end
      end
    end
  end
end
