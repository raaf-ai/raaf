# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # How long a set of spans was running, counting a moment once.
      #
      # Summing durations answers a different question, and answers it wrongly
      # for anything that fans out: ten spans of one second that ran side by
      # side sum to ten seconds although only one second passed, and a span
      # nested inside another is counted twice, once on itself and once inside
      # its parent. On a run that fans out the sum can exceed the elapsed time
      # by a wide margin, so a share taken over it is not a share of anything a
      # clock measured.
      #
      # The union is: sort by start, merge every interval that overlaps or
      # touches the one before it, and total what is left. Intervals that merge
      # contribute the stretch they cover between them, not their lengths.
      #
      module BusyTime
        module_function

        # @param intervals [Array<Array(Time, Time)>] start and finish pairs,
        #   in any order. A pair missing either end, or finishing before it
        #   starts, describes no stretch of time and is dropped.
        # @return [Float] milliseconds during which at least one interval ran
        def total_ms(intervals)
          merge(intervals).sum { |from, to| (to - from) * 1000.0 }
        end

        # @param intervals [Array<Array(Time, Time)>]
        # @return [Array<Array(Time, Time)>] disjoint intervals, earliest first
        def merge(intervals)
          usable(intervals).each_with_object([]) do |(from, to), merged|
            previous = merged.last

            if previous && from <= previous[1]
              previous[1] = to if to > previous[1]
            else
              merged << [from, to]
            end
          end
        end

        def usable(intervals)
          intervals.filter_map do |from, to|
            [from, to] if from && to && to > from
          end.sort_by(&:first)
        end
      end
    end
  end
end
