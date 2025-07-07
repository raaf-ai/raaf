# frozen_string_literal: true

module OpenAIAgents
  module Tracing
    class MetricCard < Phlex::HTML
      include Components::Preline

      def initialize(value:, label:, color: :blue, link: nil)
        @value = value
        @label = label
        @color = color
        @link = link
      end

      def template
        if @link
          preline_link(@link, class: "metric-card hover:scale-105 transition-transform") do
            render_card_content
          end
        else
          render_card_content
        end
      end

      private

      def render_card_content
        Card(class: "metric-card") do |card|
          card.body(class: "flex items-center") do
            Avatar(
              size: :lg,
              variant: @color,
              class: "inline-flex items-center justify-center flex-shrink-0"
            ) do
              # Icon content would go here
              plain icon_name
            end

            Container(class: "ms-3") do
              Typography(@value, variant: :heading, size: :xl)
              Typography(@label, variant: :muted, size: :sm)
            end
          end
        end
      end

      def icon_name
        case @color
        when :green
          "check-circle"
        when :red
          "x-circle"
        when :yellow
          "exclamation-circle"
        when :gray
          "clock"
        else # blue
          "chart-bar"
        end
      end
    end
  end
end