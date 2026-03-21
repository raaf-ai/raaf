# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      class FeedbackStatistics < RAAF::Rails::Tracing::BaseComponent
        def initialize(stats:, distribution:)
          @stats = stats
          @distribution = distribution
        end

        def view_template
          div(class: "p-6") do
            h1(class: "text-2xl font-bold text-gray-900 mb-6") { "Feedback Score Statistics" }
            render_numerical_stats
            render_category_distribution
          end
        end

        private

        def render_numerical_stats
          div(class: "mb-6") do
            h2(class: "text-lg font-semibold text-gray-900 mb-3") { "Numerical Scores" }
            if @stats.any?
              div(class: "grid grid-cols-2 md:grid-cols-5 gap-4") do
                render_metric_card(title: "Count", value: @stats[:count], color: "blue")
                render_metric_card(title: "Average", value: @stats[:avg]&.round(3), color: "green")
                render_metric_card(title: "Min", value: @stats[:min]&.round(3), color: "yellow")
                render_metric_card(title: "Max", value: @stats[:max]&.round(3), color: "purple")
                render_metric_card(title: "Median", value: @stats[:median]&.round(3), color: "blue")
              end
            else
              div(class: "bg-white shadow rounded-lg p-6 text-center text-gray-500") { "No numerical scores recorded." }
            end
          end
        end

        def render_category_distribution
          div do
            h2(class: "text-lg font-semibold text-gray-900 mb-3") { "Category Distribution" }
            if @distribution.any?
              div(class: "bg-white shadow rounded-lg p-6") do
                @distribution.each do |category, count|
                  div(class: "flex justify-between items-center py-2 border-b border-gray-100") do
                    span(class: "text-sm font-medium text-gray-700") { category }
                    span(class: "px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm font-medium") { count.to_s }
                  end
                end
              end
            else
              div(class: "bg-white shadow rounded-lg p-6 text-center text-gray-500") { "No categorical scores recorded." }
            end
          end
        end
      end
    end
  end
end
