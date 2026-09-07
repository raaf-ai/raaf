# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Mono — a tabular monospace value: durations, counts, ids, money.
        #
        # Tabular figures matter in tables, where a column of numbers that
        # jitters is much harder to scan.
        #
        class Mono < Base
          TONES = %i[muted ok warn bad accent].freeze
          SIZES = %i[lg].freeze

          def initialize(value = nil, tone: nil, size: nil, align: nil, class: nil, **attrs)
            @value = value
            @tone = tone
            @size = size
            @align = align
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            span(class: css, **@attrs) { slot(@value, &block) }
          end

          private

          def css
            tokens(
              "raaf-mono",
              modifier("raaf-mono", @tone, TONES),
              modifier("raaf-mono", @size, SIZES),
              { "raaf-mono--right" => @align == :right },
              @class
            )
          end
        end
      end
    end
  end
end
