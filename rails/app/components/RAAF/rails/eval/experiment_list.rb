# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # The experiment listing, from the Experiments screen in
      # RAAF Eval.dc.html: a status rail with the count opposite it, and one
      # table where a row is an experiment, its dataset, its model, how it
      # ended and what it scored.
      #
      # This screen was still the original Tailwind markup — a white card on a
      # grey page inside a console that is dark everywhere else. It now sits on
      # the same library as the Tracing and Continuous screens.
      #
      # The design spends no column on progress; the run's own screen carries
      # that. A running experiment still needs it here, so it goes on the
      # second line under the name where the agent already is.
      #
      class ExperimentList < RAAF::Rails::Tracing::BaseComponent
        # Columns and fr weights taken from RAAF Eval.dc.html.
        COLUMNS = [
          { label: "Experiment", span: 2 },
          { label: "Dataset", span: 1.4 },
          { label: "Model", span: 1.1 },
          { label: "Status", span: 0.9, align: :right },
          { label: "Score", span: 0.7, align: :right },
          { label: "Spend", span: 0.8, align: :right },
          { label: "Run", span: 0.8, align: :right }
        ].freeze

        STATUSES = [
          { label: "All", value: nil },
          { label: "Completed", value: "completed" },
          { label: "Running", value: "running" },
          { label: "Pending", value: "pending" },
          { label: "Failed", value: "failed" }
        ].freeze

        # @param experiments [Enumerable<Experiment>] the rows to draw
        # @param agents [Array<String>] every agent an experiment names, for
        #   the strip's scope filter
        # @param filters [Hash] :status and :agent, as the controller read them
        def initialize(experiments:, agents: [], filters: {})
          @experiments = experiments
          @agents = agents || []
          @filters = filters || {}
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
            render Atoms::Link.new(sort_label, href: sort_path, mono: true)
            render Atoms::Mono.new(count_label, tone: :muted)
            render Atoms::Button.new(label: "New experiment", icon: "plus-lg", size: :sm,
                                     href: "#{eval_experiments_path}/new")
          end
        end

        def agent_filter
          Molecules::ScopeFilter.new(
            name: "agent", value: @filters[:agent], options: @agents,
            action: eval_experiments_path, prefix: "agent",
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
          path_with(status: status, sort: @filters[:sort])
        end

        # Dearest first is how the list is read when two runs scored alike and
        # the question is what each of them cost. Newest first is how it is
        # read the rest of the time, so that stays the default.
        def sort_label
          by_spend? ? "dearest first · show newest first" : "newest first · show dearest first"
        end

        def sort_path
          path_with(status: @filters[:status], sort: by_spend? ? nil : "spend")
        end

        def by_spend?
          @filters[:sort].to_s == "spend"
        end

        def path_with(params)
          carried = { agent: @filters[:agent] }.merge(params)
          eval_experiments_path(carried.compact.reject { |_, value| value.to_s.empty? })
        end

        def count_label
          pluralize(@experiments.size, "experiment")
        end

        def table
          render(Organisms::Card.new(flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "eyedropper", title: "No experiments",
                              text: "Nothing has been run against a dataset yet." }
                   )) do |grid|
              @experiments.each { |experiment| row(grid, experiment) }
            end
          end
        end

        def row(grid, experiment)
          score = score_for(experiment)

          grid.row(href: eval_experiment_path(experiment), cells: [
                     { value: Molecules::TitleMeta.new(experiment.name, subtitle_for(experiment)) },
                     { value: Atoms::Mono.new(dataset_for(experiment), tone: :muted) },
                     # Muted, not the default: the row is an anchor, so an
                     # untoned value takes the link colour and reads as
                     # something you can click on its own.
                     { value: Atoms::Mono.new(experiment.model.presence || "—", tone: :muted) },
                     { value: Atoms::StatusBadge.new(experiment.status), align: :right },
                     { value: Atoms::Mono.new(score_text(score), tone: score_tone(score)),
                       align: :right },
                     { value: Atoms::Mono.new(money(experiment_spend(experiment), places: 4),
                                              tone: :muted), align: :right },
                     { value: Atoms::Mono.new(time_ago(run_at(experiment)), tone: :muted),
                       align: :right }
                   ])
        end

        # The second line: which agent was run, and — while it is still
        # running — how far through the dataset it is.
        def subtitle_for(experiment)
          [experiment.agent_name.presence || "no agent", progress_for(experiment)]
            .compact.join(" · ")
        end

        def progress_for(experiment)
          return nil unless experiment.in_progress? && experiment.total_items.to_i.positive?

          "#{experiment.progress_percentage.round}% of #{experiment.total_items}"
        end

        # Reading the dataset through the association is why the controller
        # preloads it; without that this is one query per row.
        def dataset_for(experiment)
          experiment.dataset&.name.presence || "—"
        end

        # `aggregate_metrics` is written once when the run completes, so the
        # column costs nothing to draw. Averaging the per-dimension averages
        # matches how a single result computes its own overall score.
        def score_for(experiment)
          scores = experiment.aggregate_metrics.is_a?(Hash) ? experiment.aggregate_metrics["scores"] : nil
          return nil unless scores.is_a?(Hash)

          values = scores.values.filter_map { |stats| stats["avg"]&.to_f if stats.is_a?(Hash) }
          return nil if values.empty?

          values.sum / values.size
        end

        # When the run happened — the end of it, or its start while it is
        # still going, and otherwise when it was created.
        def run_at(experiment)
          experiment.completed_at || experiment.started_at || experiment.created_at
        end
      end
    end
  end
end
