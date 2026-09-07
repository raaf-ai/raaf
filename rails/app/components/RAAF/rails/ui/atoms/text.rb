# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Text — every piece of prose in the dashboard.
        #
        # Size and tone are named roles rather than raw values, so a page never
        # has to know that "body small" is 13px or that muted is gray-400.
        #
        # @example
        #   render Atoms::Text.new("No spans recorded yet", tone: :muted)
        #   render(Atoms::Text.new(size: :h5, weight: :semibold)) { agent.name }
        #
        class Text < Base
          SIZES = %i[xs sm body-sm body body-lg h6 h5 h4 h3 h2 h1].freeze
          WEIGHTS = %i[regular medium semibold bold].freeze
          TONES = %i[primary secondary muted link accent success warning danger info].freeze

          # @param content [String, nil]
          # @param as [Symbol] the element to render: :p, :span, :h1..:h6, :div
          # @param size [Symbol, nil] see SIZES
          # @param weight [Symbol, nil] see WEIGHTS
          # @param tone [Symbol, nil] see TONES
          # @param mono [Boolean] monospace with tabular figures
          # @param truncate [Boolean] single line with an ellipsis
          # @param wrap [Boolean] preserve newlines and break long words
          def initialize(content = nil, as: :p, size: nil, weight: nil, tone: nil,
                         mono: false, truncate: false, wrap: false, class: nil, **attrs)
            @content = content
            @as = as
            @size = size
            @weight = weight
            @tone = tone
            @mono = mono
            @truncate = truncate
            @wrap = wrap
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            send(@as, class: css, **@attrs) { slot(@content, &block) }
          end

          private

          def css
            tokens(
              "raaf-text",
              modifier("raaf-text", @size, SIZES),
              modifier("raaf-text", @weight, WEIGHTS),
              modifier("raaf-text", @tone, TONES),
              {
                "raaf-text--mono" => @mono,
                "raaf-text--truncate" => @truncate,
                "raaf-text--wrap" => @wrap
              },
              @class
            )
          end
        end
      end
    end
  end
end
