# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for managing experiments
      class ExperimentsController < BaseController
        Experiment = RAAF::Eval::Models::Experiment
        Dataset = RAAF::Eval::Models::Dataset

        before_action :set_experiment, only: %i[show edit update destroy run cancel]

        # GET /raaf/eval/experiments
        def index
          @experiments = Experiment.recent
          @experiments = @experiments.for_agent(params[:agent]) if params[:agent].present?
          @experiments = @experiments.for_model(params[:model]) if params[:model].present?
          @experiments = @experiments.by_status(params[:status]) if params[:status].present?

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::ExperimentList.new(experiments: @experiments)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Experiments") { render component }
              render layout
            end
            format.json { render json: @experiments }
          end
        end

        # GET /raaf/eval/experiments/:id
        def show
          @results = @experiment.experiment_results.includes(:dataset_item).recent.limit(100)

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::ExperimentShow.new(
                experiment: @experiment, results: @results
              )
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: @experiment.name) { render component }
              render layout
            end
            format.json { render json: @experiment.as_json(include: :aggregate_metrics) }
          end
        end

        # GET /raaf/eval/experiments/new
        def new
          @experiment = Experiment.new
          @datasets = Dataset.active.latest_versions.recent

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::ExperimentForm.new(experiment: @experiment, datasets: @datasets)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "New Experiment") { render component }
              render layout
            end
          end
        end

        # POST /raaf/eval/experiments
        def create
          @experiment = Experiment.new(experiment_params)
          if @experiment.save
            redirect_to eval_experiment_path(@experiment), notice: "Experiment created."
          else
            @datasets = Dataset.active.latest_versions.recent
            component = RAAF::Rails::Eval::ExperimentForm.new(experiment: @experiment, datasets: @datasets)
            layout = RAAF::Rails::Tracing::BaseLayout.new(title: "New Experiment") { render component }
            render layout, status: :unprocessable_entity
          end
        end

        # POST /raaf/eval/experiments/:id/run
        def run
          engine = RAAF::Eval::ExperimentEngine.new
          engine.run_experiment(@experiment)
          redirect_to eval_experiment_path(@experiment), notice: "Experiment completed."
        rescue StandardError => e
          redirect_to eval_experiment_path(@experiment), alert: "Experiment failed: #{e.message}"
        end

        # POST /raaf/eval/experiments/:id/cancel
        def cancel
          @experiment.cancel!
          redirect_to eval_experiment_path(@experiment), notice: "Experiment cancelled."
        end

        # DELETE /raaf/eval/experiments/:id
        def destroy
          @experiment.destroy
          redirect_to eval_experiments_path, notice: "Experiment deleted."
        end

        private

        def set_experiment
          @experiment = Experiment.find(params[:id])
        end

        def experiment_params
          params.require(:experiment).permit(
            :name, :description, :dataset_id, :agent_name, :model, :provider,
            :created_by, configuration: {}, metadata: {}
          )
        end
      end
    end
  end
end
