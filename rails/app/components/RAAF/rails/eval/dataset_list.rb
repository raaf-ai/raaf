# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      ##
      # The dataset listing, from the `isDatasets` screen in RAAF Eval.dc.html:
      # a rail of status filters with the population opposite it, and the
      # table.
      #
      # This screen was still the original Tailwind markup — a white card on a
      # grey page, in a console that is dark everywhere else — which is what
      # the whole Evaluate section looked like until now.
      #
      # The design has no New dataset button, because the canvas gives no
      # screen one; the button lives in `.raaf-page-actions`, where the Tracing
      # screens put the controls their banner used to carry.
      #
      class DatasetList < RAAF::Rails::Tracing::BaseComponent
        # Columns and fr weights taken from RAAF Eval.dc.html.
        COLUMNS = [
          { label: "Dataset", span: 2.4 },
          { label: "Version", span: 0.6, align: :right },
          { label: "Items", span: 0.7, align: :right },
          { label: "Experiments", span: 0.9, align: :right },
          { label: "Status", span: 0.85, align: :right },
          { label: "Updated", span: 0.85, align: :right }
        ].freeze

        FILTERS = [
          { label: "Active", value: "active" },
          { label: "Archived", value: "archived" },
          { label: "All", value: "all" }
        ].freeze

        # @param datasets [Enumerable<Dataset>] the versions being listed
        # @param experiment_counts [Hash] dataset id => experiments run against it
        # @param params [Hash] the request's own params, for the filter rail
        def initialize(datasets:, experiment_counts: {}, params: {})
          @datasets = datasets
          @experiment_counts = experiment_counts || {}
          @params = params
        end

        def view_template
          div(class: "raaf-page") do
            actions
            filters
            table
          end
        end

        private

        def actions
          div(class: "raaf-page-actions") do
            render Atoms::Button.new(label: "New dataset", icon: "plus-lg",
                                     href: new_eval_dataset_path)
          end
        end

        # Plain pills on the page — the design gives this rail neither a
        # container nor an outline, the same treatment the policy filters get.
        def filters
          render(Molecules::FilterBar.new(chips: filter_chips, grouped: false)) do
            render Atoms::Mono.new(population, tone: :muted)
          end
        end

        def filter_chips
          FILTERS.map do |filter|
            { label: filter[:label],
              active: selected_status == filter[:value],
              href: filter[:value] == "active" ? eval_datasets_path : eval_datasets_path(status: filter[:value]) }
          end
        end

        # No status is the Active list, which is what this screen has always
        # opened on.
        def selected_status
          value = @params[:status].to_s
          FILTERS.any? { |filter| filter[:value] == value } ? value : "active"
        end

        # "6 datasets · 1,842 items" — the design's line, and the only place
        # the screen says how much material there is to test against.
        def population
          rows = @datasets.to_a
          items = rows.sum { |dataset| dataset.items_count.to_i }

          "#{pluralize(rows.size, 'dataset')} · #{pluralize(items, 'item')}"
        end

        def table
          render(Organisms::Card.new(flush: true)) do
            render(Organisms::DataGrid.new(
                     columns: COLUMNS,
                     empty: { icon: "collection", title: "No datasets",
                              text: "A dataset is the set of cases an experiment runs against. " \
                                    "Create one, or promote a production span into one from a trace." }
                   )) do |grid|
              @datasets.each { |dataset| row(grid, dataset) }
            end
          end
        end

        def row(grid, dataset)
          grid.row(href: eval_dataset_path(dataset), cells: [
                     { value: Molecules::TitleMeta.new(dataset.name, dataset.description.presence,
                                                       mono: true) },
                     { value: Atoms::Mono.new("v#{dataset.version}", tone: :muted), align: :right },
                     { value: Atoms::Mono.new(dataset.items_count.to_i.to_s), align: :right },
                     { value: Atoms::Mono.new(experiments_for(dataset)), align: :right },
                     { value: Atoms::StatusBadge.new(dataset.status), align: :right },
                     { value: Atoms::Mono.new(time_ago(dataset.updated_at), tone: :muted),
                       align: :right }
                   ])
        end

        # A dataset nothing has run against reads "—" rather than a zero: the
        # column is about which sets are in use, and a column of noughts says
        # that less clearly than a column of gaps.
        def experiments_for(dataset)
          count = @experiment_counts[dataset.id].to_i
          count.zero? ? "—" : count.to_s
        end
      end
    end
  end
end
