# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      class ResultsList < RAAF::Rails::Tracing::BaseComponent
        COLUMNS = [
          { label: "Agent", span: 1.3 },
          { label: "Evaluator", span: 1.5 },
          { label: "Field", span: 1.1 },
          { label: "Status", span: 0.7, align: :right },
          { label: "Score", span: 0.6, align: :right },
          { label: "Span", span: 0.8, align: :right },
          { label: "Created", span: 0.8, align: :right }
        ].freeze

        STATUSES = [
          { label: "All", value: nil },
          { label: "Good", value: "good" },
          { label: "Average", value: "average" },
          { label: "Bad", value: "bad" },
          { label: "Error", value: "error" }
        ].freeze

        # @param agents [Array<String>] every agent that has produced a result,
        #   for the strip's filter
        # @param summary [Hash] counts per status over the whole set
        def initialize(results:, page: 1, per_page: 50, filters: {}, agents: [], summary: {})
          @results = results
          @page = page
          @per_page = per_page
          @filters = filters || {}
          @agents = agents || []
          @summary = summary || {}
        end

        def view_template
          div(class: "raaf-page") do
            filters
            table
          end
        end

        private

        def filters
          render(Molecules::FilterBar.new(chips: status_chips, panel: true,
                                          lead: agent_filter)) do
            render Atoms::Mono.new(count_label, tone: :muted)
          end
        end

        def agent_filter
          Molecules::ScopeFilter.new(
            name: "agent", value: @filters[:agent], options: @agents,
            action: continuous_results_path, prefix: "agent",
            carry: { "status" => @filters[:status] }
          )
        end

        def status_chips
          STATUSES.map do |status|
            { label: status[:label],
              active: @filters[:status].presence == status[:value],
              href: filtered_path(status[:value]) }
          end
        end

        def filtered_path(status)
          carried = { agent: @filters[:agent], status: status }
          continuous_results_path(carried.compact.reject { |_, v| v.to_s.empty? })
        end

        def count_label
          total = @summary[:total] ||
                  (@results.respond_to?(:total_count) ? @results.total_count : @results.size)
          pluralize(total, "result")
        end

        def table
          render(Organisms::Card.new(flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "graph-up", title: "No results",
                              text: "Nothing matches the current filters." }
                   )) do |grid|
              @results.each { |result| row(grid, result) }
            end

            pagination if paginated?
          end
        end

        def row(grid, result)
          grid.row(href: continuous_result_path(result), cells: [
                     { value: Atoms::Mono.new(result.agent_name.presence || "unknown", tone: :muted) },
                     { value: Molecules::TitleMeta.new(result.evaluator_name.to_s,
                                                       result.evaluator_type.to_s, mono: true) },
                     { value: Atoms::Mono.new(field_for(result), tone: :muted) },
                     { value: Atoms::StatusBadge.new(result.status), align: :right },
                     { value: Atoms::Mono.new(format_score(result.score),
                                              tone: score_tone(result.score)), align: :right },
                     { value: Atoms::Mono.new(truncate_id(result.span_id), tone: :accent),
                       align: :right },
                     { value: Atoms::Mono.new(time_ago(result.created_at), tone: :muted),
                       align: :right }
                   ])
        end

        def field_for(result)
          result.metadata&.dig("field_name").presence ||
            result.metadata&.dig(:field_name).presence || "—"
        end

        def score_tone(score)
          return nil if score.nil?

          case score.to_f
          when 0.8.. then :ok
          when 0.5...0.8 then :warn
          else :bad
          end
        end

        def paginated?
          @results.respond_to?(:total_pages) && @results.total_pages > 1
        end

        def pagination
          render Molecules::Pagination.new(
            page: @results.current_page, total_pages: @results.total_pages,
            total_count: @results.total_count, per_page: @per_page,
            href: ->(n) { continuous_results_path(@filters.to_h.merge(page: n).compact) }
          )
        end

        def format_score(score)
          return "—" if score.nil?

          "%.2f" % score.to_f
        end

        def truncate_id(id)
          id.to_s.delete_prefix("span_").first(8)
        end
      end
    end
  end
end
