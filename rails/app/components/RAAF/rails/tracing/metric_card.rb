# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # A single metric tile.
      #
      # Kept as a thin adapter over the library's MetricCard so the existing
      # `color:`/`link:` call sites keep working; new code should render
      # Ui::Molecules::MetricCard directly.
      #
      class MetricCard < BaseComponent
        TONES = { green: :success, red: :danger, yellow: :warning, gray: nil, blue: :accent }.freeze

        ICONS = {
          green: "check-circle",
          red: "x-circle",
          yellow: "exclamation-circle",
          gray: "clock",
          blue: "bar-chart"
        }.freeze

        def initialize(value:, label:, color: :blue, link: nil)
          @value = value
          @label = label
          @color = color.to_sym
          @link = link
        end

        def view_template
          render Ui::Molecules::MetricCard.new(
            label: @label,
            value: @value,
            icon: ICONS.fetch(@color, ICONS[:blue]),
            tone: TONES[@color],
            href: @link
          )
        end
      end
    end
  end
end
