# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # TagList — a wrapping row of small mono tags.
        #
        # For a cell holding several short names that are read, not clicked —
        # the scorers a policy runs, say. Filter chips are `Atoms::Chip`; these
        # are labels.
        #
        # @example
        #   render Molecules::TagList.new(%w[quality pii latency])
        #
        class TagList < Base
          # @param tags [Array<String>]
          # @param limit [Integer, nil] show at most this many, then a `+n`
          def initialize(tags, limit: nil, class: nil, **attrs)
            @tags = Array(tags).compact
            @limit = limit
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-taglist", @class), **@attrs) do
              shown.each { |tag| span(class: "raaf-tag") { tag.to_s } }
              span(class: "raaf-tag raaf-tag--more") { "+#{@tags.size - shown.size}" } if truncated?
            end
          end

          private

          def shown
            @shown ||= @limit ? @tags.first(@limit) : @tags
          end

          def truncated?
            @tags.size > shown.size
          end
        end
      end
    end
  end
end
