# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # Sparkbars — a bare bar chart for an agent tile.
        #
        # Values are normalised against the series maximum, so a tile reads
        # correctly whatever the absolute numbers are. Heights travel as a
        # custom property rather than inline geometry.
        #
        # Each bar sits in a full-height cell rather than standing on the
        # baseline itself. The cell is what carries the hover readout, and it
        # is also what makes a one-pixel bucket hoverable at all — a bar drawn
        # 2% tall is not a hit target anybody can find.
        #
        # `tips:` is index-aligned with `values:` and reuses the console's
        # tooltip molecule. A bucket with no tip draws as a plain bar, so a
        # caller with nothing to say about a bucket says nothing.
        #
        # @example
        #   render Molecules::Sparkbars.new(
        #     values: [3, 5, 2, 9, 4], tones: { 3 => :bad },
        #     tips: ["09:00 · 3 runs", "10:00 · 5 runs", "11:00 · 2 runs",
        #            "12:00 · 9 runs · 2 failed", "13:00 · 4 runs"]
        #   )
        #
        class Sparkbars < Base
          MIN_HEIGHT = 12

          # @param values [Array<Numeric>]
          # @param tones [Hash{Integer=>Symbol}] index => :ok/:warn/:bad
          # @param tips [Array<String>] hover readout per bucket, index-aligned
          # @param label [String, nil] accessible summary of the series
          def initialize(values:, tones: {}, tips: [], label: nil, class: nil, **attrs)
            @values = Array(values)
            @tones = tones
            @tips = Array(tips)
            @label = label
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-sparkbars", @class), role: "img",
                "aria-label": aria_label, **@attrs) do
              @values.each_with_index { |value, index| cell(value, index) }
            end
          end

          private

          # `role="img"` makes the bars presentational, so the readouts are
          # invisible to a screen reader however they are marked up. The peak
          # bucket is the one a reader would have gone looking for, so it is
          # folded into the label rather than left only to the mouse.
          def aria_label
            base = @label || "Recent activity"
            peak = @tips[peak_index].to_s if peak_index

            peak.present? ? "#{base}. Peak: #{peak}" : base
          end

          def peak_index
            return nil if @values.empty? || peak <= 0

            @values.each_with_index.max_by { |value, _| value.to_f }.last
          end

          def cell(value, index)
            tip = @tips[index].to_s

            div(class: tokens("raaf-sparkbar-cell", tip.present? && "raaf-tooltip")) do
              div(class: bar_css(index), style: "--raaf-spark-h: #{height(value)}%")
              span(class: "raaf-tooltip-content", role: "tooltip") { tip } if tip.present?
            end
          end

          def peak
            @peak ||= @values.map(&:to_f).max.to_f
          end

          def height(value)
            return MIN_HEIGHT if peak <= 0

            [(value.to_f / peak * 100).round, MIN_HEIGHT].max
          end

          def bar_css(index)
            tokens("raaf-sparkbar", @tones[index] && "raaf-sparkbar--#{@tones[index]}")
          end
        end
      end
    end
  end
end
