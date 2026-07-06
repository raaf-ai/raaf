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
          @datasets = Dataset.active.latest_versions.recent
          @datasets = @datasets.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::DatasetList.new(datasets: @datasets)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Datasets") { render component }
              render layout
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
                dataset: @dataset, items: @items, experiments: @experiments
              )
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: @dataset.name) { render component }
              render layout
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
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "New Dataset") { render component }
              render layout
            end
          end
        end

        # GET /raaf/eval/datasets/:id/edit
        def edit
          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::DatasetForm.new(dataset: @dataset)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Edit #{@dataset.name}") { render component }
              render layout
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
            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "New Dataset") { render component }
            render layout, status: :unprocessable_entity
          end
        end

        # PATCH /raaf/eval/datasets/:id
        def update
          if @dataset.update(dataset_params)
            redirect_to eval_dataset_path(@dataset), notice: "Dataset updated."
          else
            component = RAAF::Rails::Eval::DatasetForm.new(dataset: @dataset)
            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Edit #{@dataset.name}") { render component }
            render layout, status: :unprocessable_entity
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
