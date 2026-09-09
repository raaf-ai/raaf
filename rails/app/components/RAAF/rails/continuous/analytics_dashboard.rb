# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class AnalyticsDashboard < RAAF::Rails::Tracing::BaseComponent
        MODEL_COLUMNS = [
          { label: "Model", span: 1.8 },
          { label: "Evaluations", span: 0.8, align: :right },
          { label: "Good rate", span: 0.8, align: :right },
          { label: "Avg score", span: 0.7, align: :right },
          { label: "Avg cost", span: 0.7, align: :right },
          { label: "Avg duration", span: 0.9, align: :right }
        ].freeze

        def initialize(stats: {}, filters: {}, agents: [], environments: [])
          @stats = stats || {}
          @filters = filters || {}
          @agents = agents || []
          @environments = environments || []
        end

        # The two chart panels that used to sit here were placeholders — a
        # `d3-chart` Stimulus controller that is registered nowhere, behind the
        # words "Chart will be rendered with D3.js". They are gone rather than
        # restyled: a promise the console cannot keep is worse dark than light.
        def view_template
          div(class: "raaf-page") do
            filters
            headline
            model_comparison
          end
        end

        private

        def filters
          render(Molecules::FilterBar.new(panel: true, lead: agent_filter)) do
            render environment_filter
          end
        end

        def agent_filter
          Molecules::ScopeFilter.new(
            name: "agent", value: @filters[:agent], options: @agents,
            action: continuous_analytics_path, prefix: "agent",
            carry: { "environment" => @filters[:environment] }
          )
        end

        def environment_filter
          render Molecules::ScopeFilter.new(
            name: "environment", value: @filters[:environment], options: @environments,
            action: continuous_analytics_path, prefix: "env",
            carry: { "agent" => @filters[:agent] }
          )
        end

        def headline
          render Organisms::StatGrid.new(layout: :leading, stats: [
                                           { label: "Evaluations", value: number(@stats[:total_evaluations]),
                                             icon: "graph-up", note: "in the selected scope" },
                                           { label: "Good rate", value: format_percentage(@stats[:good_rate] || @stats[:pass_rate]),
                                             icon: "check-circle", tone: :success, note: "came back good" },
                                           { label: "Avg score", value: score_text(@stats[:avg_score]),
                                             icon: "star", note: "across every check" },
                                           { label: "Total cost", value: format_cost(@stats[:total_cost]),
                                             icon: "cash-stack", note: "what evaluating cost" }
                                         ])
        end

        def model_comparison
          render(Organisms::Card.new(title: "By model", flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: MODEL_COLUMNS,
                     empty: { icon: "cpu", title: "No model data",
                              text: "This appears once evaluations have run." }
                   )) do |grid|
              Array(@stats[:model_comparison]).each { |row| model_row(grid, row) }
            end
          end
        end

        def model_row(grid, stat)
          grid.row(cells: [
                     { value: Atoms::Mono.new(stat[:model_name].to_s) },
                     { value: Atoms::Mono.new(number(stat[:count]), tone: :muted), align: :right },
                     { value: Atoms::Mono.new(format_percentage(stat[:good_rate] || stat[:pass_rate])),
                       align: :right },
                     { value: Atoms::Mono.new(score_text(stat[:avg_score])), align: :right },
                     { value: Atoms::Mono.new(format_cost(stat[:avg_cost]), tone: :muted),
                       align: :right },
                     { value: Atoms::Mono.new(format_duration(stat[:avg_duration_ms]), tone: :muted),
                       align: :right }
                   ])
        end

        def number(value)
          value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end

        def format_percentage(value)
          return "—" if value.nil?

          "#{value.to_f.round(1)}%"
        end

        def format_cost(cost)
          return "—" if cost.nil? || cost.to_f.zero?

          "$#{'%.4f' % cost.to_f}"
        end

        def format_duration(ms)
          return "—" if ms.nil?

          ms.to_f < 1000 ? "#{ms.to_i}ms" : "#{'%.1f' % (ms.to_f / 1000)}s"
        end
      end
    end
  end
end
