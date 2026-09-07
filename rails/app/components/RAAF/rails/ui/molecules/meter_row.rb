# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # MeterRow — a name, its figure, and a bar showing its share.
        #
        # One component for cost-by-model, cost-by-workflow, pipeline heat and
        # eval scores. The inventory is explicit that this should not be forked
        # per screen, so the two shapes those screens need are variants here:
        # the default stacks the bar under the name, and `inline: true` puts
        # name, bar and figure on one line for a dense list of steps.
        #
        # @example Cost by model
        #   render Molecules::MeterRow.new(name: "gpt-4o", value: "$182.40",
        #                                  pct: 68, sub: "4.1M tokens")
        #
        # @example A pipeline step, with its index and kind ahead of the name
        #   render(Molecules::MeterRow.new(name: "crm_upsert", value: "4.0s",
        #                                  pct: 33, meta: "8.1%", tone: :bad,
        #                                  inline: true)) do
        #     render Atoms::KindBadge.new("tool")
        #   end
        #
        # `tip:` puts a readout on the bar itself. What the fill is a share
        # *of* differs per screen — spend against the largest row, coverage
        # against what a policy could have graded — and only the caller knows
        # which, so the row states nothing about the bar it was not told.
        # Assistive technology already has the figure: the bar underneath is a
        # `progressbar` carrying `aria-valuenow`.
        #
        class MeterRow < Base
          # @param name [String]
          # @param value [String] the figure on the right
          # @param pct [Numeric] 0–100, the bar's fill
          # @param sub [String, nil] caption under the bar
          # @param meta [String, nil] a second figure after the value
          # @param tone [Symbol, nil] bar tone
          # @param value_tone [Symbol, nil] tone for the figure; defaults to `tone`
          # @param inline [Boolean] name, bar and figure on one line
          # @param tip [String, nil] hover readout on the bar
          def initialize(name:, value:, pct: 0, sub: nil, meta: nil, tone: nil,
                         value_tone: nil, inline: false, tip: nil, class: nil, **attrs)
            @name = name
            @value = value
            @pct = pct
            @sub = sub
            @meta = meta
            @tone = tone
            @value_tone = value_tone
            @inline = inline
            @tip = tip
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          # A block is rendered ahead of the name — the step index and kind chip
          # on the pipeline screen. Phlex routes it into `view_template`, so it
          # arrives here rather than through the constructor.
          def view_template(&block)
            div(class: css, **@attrs) do
              div(class: "raaf-meter-lead", &block) if block
              span(class: "raaf-meter-name") { @name }
              render Atoms::Mono.new(@value, tone: @value_tone || @tone)
              div(class: tokens("raaf-meter-bar", @tip.present? && "raaf-tooltip")) do
                render Atoms::Bar.new(pct: @pct, tone: @tone, label: "#{@name}: #{@value}")
                span(class: "raaf-tooltip-content", role: "tooltip") { @tip } if @tip.present?
              end
              render Atoms::Mono.new(@meta, tone: :muted, class: "raaf-meter-meta") if @meta
              div(class: "raaf-meter-sub") { @sub } if @sub
            end
          end

          private

          def css
            tokens("raaf-meter", { "raaf-meter--inline" => @inline }, @class)
          end
        end
      end
    end
  end
end
