# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # WaterfallRow — one span in the trace waterfall.
        #
        # A kind chip, the span name, its tokens and duration, and beneath them
        # a track showing where the span sat in the trace. Offset, width and
        # nesting depth all travel as custom properties, so the row's markup
        # carries no layout arithmetic and the same row works at any depth.
        #
        # @example
        #   render Molecules::WaterfallRow.new(
        #     kind: "tool", name: "crm_upsert", duration: "4.0s",
        #     offset: 62, width: 35, level: 2, tone: :bad, href: span_path(span)
        #   )
        #
        class WaterfallRow < Base
          TONES = %i[ok warn bad idle].freeze

          # @param kind [String] span kind, rendered as a KindBadge
          # @param name [String]
          # @param duration [String, nil] preformatted, e.g. "4.0s"
          # @param tokens [String, nil]
          # @param offset [Numeric] 0–100, where the span starts in the trace
          # @param width [Numeric] 0–100, how much of the trace it spans
          # @param level [Integer] nesting depth
          # @param tone [Symbol, nil] :bad for a failure, :idle for a skip
          # @param selected [Boolean] the row the inspector is showing
          # @param href [String, nil] makes the row a link
          def initialize(kind:, name:, duration: nil, tokens: nil, offset: 0, width: 0,
                         level: 0, tone: nil, selected: false, href: nil, class: nil, **attrs)
            @kind = kind
            @name = name
            @duration = duration
            @tokens = tokens
            @offset = offset.to_f.clamp(0, 100)
            @width = width.to_f.clamp(0, 100)
            @level = level.to_i
            @tone = tone
            @selected = selected
            @href = href
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            if @href
              a(href: @href, class: css, style: vars, **@attrs) { contents }
            else
              div(class: css, style: vars, **@attrs) { contents }
            end
          end

          private

          def css
            tokens(
              "raaf-wfrow",
              modifier("raaf-wfrow", @tone, TONES),
              { "is-selected" => @selected },
              @class
            )
          end

          # The bar's geometry and the indent, as custom properties.
          def vars
            "--raaf-tree-level: #{@level}; --raaf-bar-off: #{@offset.round(2)}%; " \
              "--raaf-bar-w: #{@width.round(2)}%"
          end

          def contents
            div(class: "raaf-wfrow-head") do
              render Atoms::KindBadge.new(@kind)
              span(class: "raaf-wfrow-name") { @name }
              render Atoms::Mono.new(@tokens, tone: :muted) if @tokens
              render Atoms::Mono.new(@duration, class: "raaf-wfrow-dur") if @duration
            end
            div(class: "raaf-wfrow-track") do
              div(class: "raaf-wfrow-bar")
            end
          end
        end
      end
    end
  end
end
