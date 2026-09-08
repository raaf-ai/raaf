# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # Every case an experiment scored, as its own screen.
      #
      # The Experiment screen in RAAF Eval.dc.html draws this table inside the
      # experiment, capped at a hundred rows. That is the right length beside
      # four metric cards and the aggregate scores; it is not a way to read a
      # run of four hundred cases. This is the same table, paginated, with the
      # experiment's identity at the top so it is still obvious what is being
      # read.
      #
      # The canvas's filter strip offers All / Failed / Low score. "Low score"
      # used to be unanswerable: a result's score was the mean of a jsonb hash
      # computed in Ruby, so it could be asked of the fifty rows already loaded
      # or of nothing at all, and "low among these fifty" is a different
      # question wearing the same label. The score is a column now, so the chip
      # is a query over the whole run, and worst-first is an ordering rather
      # than a re-sort of the page.
      #
      class ExperimentResultList < RAAF::Rails::Tracing::BaseComponent
        # Columns and fr weights taken from RAAF Eval.dc.html.
        COLUMNS = [
          { label: "Item", span: 0.55 },
          { label: "Status", span: 0.9 },
          { label: "Score", span: 0.6, align: :right },
          { label: "Output", span: 2.6 }
        ].freeze

        STATUSES = [
          { label: "All", value: nil },
          { label: "Completed", value: "completed" },
          { label: "Failed", value: "failed" },
          { label: "Running", value: "running" },
          { label: "Pending", value: "pending" }
        ].freeze

        # @param counts [Hash] status => how many the run recorded, over the
        #   whole experiment rather than the page
        # @param below_count [Integer] how many cases scored under the run's
        #   own line, over the whole experiment
        def initialize(experiment:, results:, counts: {}, filters: {}, per_page: 50, below_count: 0)
          @experiment = experiment
          @results = results
          @counts = counts || {}
          @filters = filters || {}
          @per_page = per_page
          @below_count = below_count.to_i
        end

        def view_template
          div(class: "raaf-page") do
            breadcrumb
            filters
            table
          end
        end

        private

        def breadcrumb
          render Molecules::Breadcrumb.new(items: [
                                             { label: "Experiments", href: eval_experiments_path },
                                             { label: @experiment.name,
                                               href: eval_experiment_path(@experiment) },
                                             { label: "Results" }
                                           ])
        end

        # ── Filters ───────────────────────────────────────────────────────

        # A status nothing was recorded under is left out rather than offered
        # as a chip that empties the table.
        def filters
          render(Molecules::FilterBar.new(chips: chips, panel: true)) do
            render Atoms::Link.new(sort_label, href: sort_path, mono: true)
            render Atoms::Mono.new(count_label, tone: :muted)
          end
        end

        def chips
          status_chips + below_chip
        end

        def status_chips
          STATUSES.filter_map do |status|
            count = status[:value].nil? ? total : @counts[status[:value]].to_i
            next if status[:value] && count.zero?

            { label: status[:label], count: count,
              active: @filters[:status].presence == status[:value] && !below?,
              href: filtered_path(status: status[:value]) }
          end
        end

        # The cases the run itself calls failing, counted over the whole run.
        # Absent where nothing falls below the line: a chip reading zero is a
        # question with one answer.
        def below_chip
          return [] if @below_count.zero?

          [{ label: "Below the line", count: @below_count, active: below?,
             href: filtered_path(status: @filters[:status], below: "1") }]
        end

        def below?
          @filters[:below].present?
        end

        # Worst first is how a run is read when the question is what it got
        # wrong; newest first is how it is read while it is still going.
        def sort_label
          worst? ? "worst first · show newest first" : "newest first · show worst first"
        end

        def sort_path
          filtered_path(status: @filters[:status], below: @filters[:below],
                        sort: worst? ? nil : "worst")
        end

        def worst?
          @filters[:sort].to_s == "worst"
        end

        def filtered_path(params)
          eval_experiment_results_path(@experiment, params.compact.reject { |_, v| v.to_s.empty? })
        end

        def count_label
          shown = total_count
          return pluralize(shown, "result") if total.zero? || total <= shown

          "#{shown} of #{total} results"
        end

        def total
          @total ||= @counts.values.sum
        end

        def total_count
          @results.respond_to?(:total_count) ? @results.total_count : @results.size
        end

        # ── Table ─────────────────────────────────────────────────────────

        def table
          render(Organisms::Card.new(flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "list-check", title: "No results",
                              text: "Nothing matches the current filter." }
                   )) do |grid|
              @results.each { |result| result_row(grid, result) }
            end

            pagination if paginated?
          end
        end

        def result_row(grid, result)
          score = result.overall_score

          grid.row(href: eval_experiment_result_path(@experiment, result), cells: [
                     { value: Atoms::Mono.new("##{result.dataset_item_id}", tone: :muted) },
                     { value: Atoms::StatusBadge.new(result.status) },
                     { value: Atoms::Mono.new(score_text(score), tone: score_tone(score)),
                       align: :right },
                     { value: Atoms::Mono.new(output_preview(result), tone: :muted,
                                                                      class: "raaf-cell-indent") }
                   ])
        end

        # A failed result has no output worth printing; what went wrong is the
        # only thing the row can say.
        def output_preview(result)
          return result.error_message.to_s.truncate(160) if result.error_message.present?

          output = result.output
          text = output.is_a?(Hash) || output.is_a?(Array) ? output.to_json : output.to_s
          text.presence&.truncate(160) || "—"
        end

        def paginated?
          @results.respond_to?(:total_pages) && @results.total_pages > 1
        end

        def pagination
          render Molecules::Pagination.new(
            page: @results.current_page, total_pages: @results.total_pages,
            total_count: @results.total_count, per_page: @per_page,
            href: lambda { |n|
              filtered_path(status: @filters[:status], below: @filters[:below],
                            sort: @filters[:sort], page: n)
            }
          )
        end
      end
    end
  end
end
