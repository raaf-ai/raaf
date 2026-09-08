# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for managing evaluation datasets
      class DatasetsController < BaseController
        Dataset = RAAF::Eval::Models::Dataset

        before_action :set_dataset, only: %i[show edit update destroy new_version archive]

        # GET /raaf/eval/datasets
        def index
          @datasets = listed_datasets

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::DatasetList.new(
                datasets: @datasets,
                experiment_counts: experiment_counts(@datasets),
                params: params
              )
              render_in_layout component, title: "Datasets", crumb: "Evaluate", current: :datasets
            end
            format.json { render json: @datasets }
          end
        end

        # GET /raaf/eval/datasets/:id
        def show
          @items = @dataset.dataset_items.recent.limit(50)
          @experiments = @dataset.experiments.recent.limit(10)

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::DatasetShow.new(
                dataset: @dataset, items: @items, experiments: @experiments,
                imported_count: @dataset.dataset_items.where.not(source_span_id: nil).count,
                experiments_count: @dataset.experiments.count
              )
              render_in_layout component, title: @dataset.name, crumb: "Evaluate", current: :datasets
            end
            format.json { render json: @dataset.as_json(include: :dataset_items) }
          end
        end

        # GET /raaf/eval/datasets/new
        def new
          @dataset = Dataset.new
          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::DatasetForm.new(dataset: @dataset)
              render_in_layout component, title: "New Dataset"
            end
          end
        end

        # GET /raaf/eval/datasets/:id/edit
        def edit
          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::DatasetForm.new(dataset: @dataset)
              render_in_layout component, title: "Edit #{@dataset.name}"
            end
          end
        end

        # POST /raaf/eval/datasets
        def create
          @dataset = Dataset.new(dataset_params)
          if @dataset.save
            redirect_to eval_dataset_path(@dataset), notice: "Dataset created."
          else
            component = RAAF::Rails::Eval::DatasetForm.new(dataset: @dataset)
            render_in_layout component, title: "New Dataset", status: :unprocessable_content
          end
        end

        # PATCH /raaf/eval/datasets/:id
        def update
          if @dataset.update(dataset_params)
            redirect_to eval_dataset_path(@dataset), notice: "Dataset updated."
          else
            component = RAAF::Rails::Eval::DatasetForm.new(dataset: @dataset)
            render_in_layout component, title: "Edit #{@dataset.name}", status: :unprocessable_content
          end
        end

        # DELETE /raaf/eval/datasets/:id
        def destroy
          @dataset.destroy
          redirect_to eval_datasets_path, notice: "Dataset deleted."
        end

        # POST /raaf/eval/datasets/:id/new_version
        def new_version
          new_dataset = @dataset.create_new_version!(created_by: current_user_name)
          redirect_to eval_dataset_path(new_dataset), notice: "Version #{new_dataset.version} created."
        end

        # POST /raaf/eval/datasets/:id/archive
        def archive
          @dataset.archive!
          redirect_to eval_datasets_path, notice: "Dataset archived."
        end

        private

        # The screen opens on the active sets, which is what it has always
        # listed; Archived and All are the design's other two filters, and an
        # unrecognised value falls back to Active rather than listing nothing.
        def listed_datasets
          scope = Dataset.latest_versions.recent
          scope = scope.where(status: status_filter) unless status_filter == "all"
          scope = scope.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?
          scope
        end

        def status_filter
          value = params[:status].to_s
          %w[active archived all].include?(value) ? value : "active"
        end

        # One query for the whole page rather than one per row.
        def experiment_counts(datasets)
          RAAF::Eval::Models::Experiment.where(dataset_id: datasets.map(&:id))
                                        .group(:dataset_id).count
        end

        def set_dataset
          @dataset = Dataset.find(params[:id])
        end

        def dataset_params
          params.require(:dataset).permit(:name, :description, :created_by, schema_definition: {}, metadata: {})
        end

        def current_user_name
          respond_to?(:current_user) && current_user&.respond_to?(:name) ? current_user.name : "system"
        end
      end
    end
  end
end
