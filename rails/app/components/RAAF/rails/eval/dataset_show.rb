# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # One dataset, from the `isDataset` screen in RAAF Eval.dc.html: the
      # header panel carrying the name, what it holds and its three figures;
      # the items; and the experiments that have run against it.
      #
      # The version and archive controls are not in the canvas — a dataset
      # there is a thing you read — so they sit in `.raaf-page-actions` above
      # the header rather than inside it, which is where the Tracing screens
      # put the actions their banner used to carry.
      #
      class DatasetShow < RAAF::Rails::Tracing::BaseComponent
        # Columns and fr weights taken from RAAF Eval.dc.html.
        ITEM_COLUMNS = [
          { label: "ID", span: 0.5 },
          { label: "Input", span: 2.2 },
          { label: "Expected output", span: 1.7 },
          { label: "Source", span: 0.7, align: :right }
        ].freeze

        EXPERIMENT_COLUMNS = [
          { label: "Experiment", span: 2.0 },
          { label: "Model", span: 1.0 },
          { label: "Score", span: 0.6, align: :right },
          { label: "Status", span: 0.8, align: :right }
        ].freeze

        # Above this a score is healthy, below the lower bound it is failing.
        # The same two bounds the policy screen reads by.

        # @param dataset [RAAF::Eval::Models::Dataset]
        # @param items [Enumerable<DatasetItem>] the page being shown
        # @param experiments [Enumerable<Experiment>] most recent first
        # @param imported_count [Integer] items promoted from production spans
        # @param experiments_count [Integer] every experiment, not just the page
        def initialize(dataset:, items:, experiments:, imported_count: 0, experiments_count: nil)
          @dataset = dataset
          @items = items
          @experiments = experiments
          @imported_count = imported_count.to_i
          @experiments_count = experiments_count || experiments.size
        end

        def view_template
          div(class: "raaf-page") do
            actions
            header_panel
            items
            experiments
          end
        end

        private

        def actions
          render Molecules::RowActions.new(class: "raaf-page-actions", actions: [
            { label: "New version", href: new_version_eval_dataset_path(@dataset), method: :post,
              confirm: "Copy every item into a new version of #{@dataset.name}?" },
            (unless archived?
               { label: "Archive", href: archive_eval_dataset_path(@dataset), method: :post,
                 tone: :danger,
                 confirm: "Archive #{@dataset.name} v#{@dataset.version}?" }
             end)
          ].compact)
        end

        def header_panel
          render Organisms::RecordHead.new(
            title: @dataset.name,
            mono: true,
            description: @dataset.description,
            status: @dataset.status,
            meta: head_meta,
            stats: [{ label: "Items", value: @dataset.items_count.to_i.to_s },
                    { label: "Experiments", value: @experiments_count.to_i.to_s },
                    { label: "Version", value: "v#{@dataset.version}" }]
          )
        end

        def head_meta
          created = @dataset.created_at&.strftime("%Y-%m-%d")
          ["version #{@dataset.version}",
           created && "created #{created}",
           @dataset.created_by.presence && "by #{@dataset.created_by}"].compact.join(" · ")
        end

        def archived?
          @dataset.status == "archived"
        end

        # ── Items ─────────────────────────────────────────────────────────

        def items
          render(Organisms::Card.new(title: "Items", subtitle: items_meta, flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: ITEM_COLUMNS,
                     empty: { icon: "list-check", title: "No items",
                              text: "Add cases directly, or import a production span from its " \
                                    "trace to keep a real failure as a test." }
                   )) do |grid|
              @items.each { |item| item_row(grid, item) }
            end
          end
        end

        # The design's "120 items · 96 imported from spans". Where a dataset is
        # long enough to be paged, the second half says which page is on screen
        # — a table showing fifty of four hundred rows under a heading that
        # only says four hundred is the kind of thing that gets misread.
        def items_meta
          total = @dataset.items_count.to_i
          shown = @items.size

          parts = [pluralize(total, "item")]
          parts << "#{@imported_count} imported from spans" if @imported_count.positive?
          parts << "showing the latest #{shown}" if shown < total

          parts.join(" · ")
        end

        # The row opens the item. dataset_items#show is routed and always was;
        # the row simply carried no href, so a case longer than a sentence —
        # every payload is cut at 160 characters here — could not be read at
        # all from the console.
        def item_row(grid, item)
          grid.row(href: eval_dataset_item_path(@dataset, item), cells: [
                     { value: Atoms::Mono.new("##{item.id}", tone: :muted) },
                     { value: Atoms::Mono.new(preview(item.input)) },
                     { value: Atoms::Mono.new(expected(item), tone: :muted) },
                     { value: source_badge(item), align: :right }
                   ])
        end

        def expected(item)
          item.has_expected_output? ? preview(item.expected_output) : "—"
        end

        # The cell truncates in CSS, so the JSON is only cut here to keep a
        # very large payload out of the document.
        def preview(payload)
          payload.to_json.truncate(160)
        end

        def source_badge(item)
          if item.from_production?
            Atoms::Badge.new("Span", variant: :"tint-cyan", size: :sm)
          else
            Atoms::Badge.new("Manual", variant: :"tint-slate", size: :sm)
          end
        end

        # ── Experiments ───────────────────────────────────────────────────

        def experiments
          render(Organisms::Card.new(title: "Experiments against this dataset",
                                     subtitle: experiments_meta, flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: EXPERIMENT_COLUMNS,
                     empty: { icon: "beaker", title: "Never run",
                              text: "Nothing has been evaluated against this dataset yet." }
                   )) do |grid|
              @experiments.each { |experiment| experiment_row(grid, experiment) }
            end
          end
        end

        def experiments_meta
          return nil if @experiments.size >= @experiments_count.to_i

          "latest #{@experiments.size} of #{@experiments_count}"
        end

        def experiment_row(grid, experiment)
          score = experiment.average_score

          grid.row(href: eval_experiment_path(experiment), cells: [
                     { value: experiment.name, primary: true },
                     { value: Atoms::Mono.new(experiment.model.presence || "—", tone: :muted) },
                     { value: Atoms::Mono.new(score_text(score), tone: score_tone(score)),
                       align: :right },
                     { value: Atoms::StatusBadge.new(experiment.status), align: :right }
                   ])
        end
      end
    end
  end
end
