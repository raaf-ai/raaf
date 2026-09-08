# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # KeyValueList — a set of KeyValue pairs, as columns or as stacked rows.
        #
        # Pass a hash for the common case; pass a block when some values need
        # to be components rather than strings.
        #
        # @example Hash
        #   render Molecules::KeyValueList.new(pairs: {
        #     "Model" => span.model, "Duration" => span.duration_ms
        #   })
        #
        # @example Block
        #   render(Molecules::KeyValueList.new(layout: :rows)) do
        #     render Molecules::KeyValue.new("Status") { render Atoms::Badge.for_status(span.status) }
        #   end
        #
        class KeyValueList < Base
          LAYOUTS = %i[cols rows].freeze

          # @param pairs [Hash, nil] label => value
          # @param layout [Symbol] :cols for a responsive grid, :rows for a list
          # @param mono [Boolean] applies to every pair built from `pairs`
          # @param flush [Boolean] the list runs to a flush card's edges, so each
          #   row carries the padding the card body would have given it
          def initialize(pairs: nil, layout: :cols, mono: false, flush: false, class: nil, **attrs)
            @pairs = pairs
            @layout = layout
            @mono = mono
            @flush = flush
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: css, **@attrs) do
              if block
                yield
              else
                @pairs.to_h.each { |key, value| render KeyValue.new(key, value, mono: @mono) }
              end
            end
          end

          private

          def css
            tokens("raaf-kv-list", modifier("raaf-kv-list", @layout, LAYOUTS),
                   { "raaf-kv-list--flush" => @flush }, @class)
          end
        end
      end
    end
  end
end
