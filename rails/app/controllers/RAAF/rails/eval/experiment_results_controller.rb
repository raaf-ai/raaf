# frozen_string_literal: true

module RAAF
  module Rails
    module Eval
      # Controller for experiment results
      class ExperimentResultsController < BaseController
        before_action :set_experiment

        # GET /raaf/eval/experiments/:experiment_id/results
        def index
          scope = @experiment.experiment_results.includes(:dataset_item)
          scope = params[:sort] == "worst" ? scope.worst_first : scope.recent
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.scoring_below(threshold) if params[:below].present?

          @results = scope.page(params[:page]).per(50)
          @counts = @experiment.experiment_results.group(:status).count

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::ExperimentResultList.new(
                experiment: @experiment, results: @results, counts: @counts,
                below_count: below_count,
                filters: { status: params[:status], sort: params[:sort], below: params[:below] }
              )
              render_in_layout component, title: "#{@experiment.name} · results", crumb: "Evaluate",
                                          current: :experiments
            end
            format.json { render json: @results }
          end
        end

        # GET /raaf/eval/experiments/:experiment_id/results/:id
        def show
          @result = @experiment.experiment_results.includes(:dataset_item).find(params[:id])

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Eval::ExperimentResultShow.new(
                experiment: @experiment, result: @result,
                neighbours: neighbours(@result)
              )
              render_in_layout component, title: "Result ##{@result.dataset_item_id}", crumb: "Evaluate",
                                          current: :experiments
            end
            format.json { render json: @result }
          end
        end

        private

        # The results either side of this one, so a run can be read straight
        # through rather than by going back to the table between every case.
        # In the order the run produced them, which is not the table's order —
        # that lists newest first. Stepping through a run backwards is the
        # stranger of the two, and the table is one click away either way.
        def neighbours(result)
          scope = @experiment.experiment_results
          { previous: scope.where("id < ?", result.id).order(id: :desc).first,
            next: scope.where("id > ?", result.id).order(:id).first }
        end

        def set_experiment
          @experiment = RAAF::Eval::Models::Experiment.find(params[:experiment_id])
        end

        # The line the run itself was given, where somebody set one. Falling
        # back to the console's own tier rather than to a number invented here,
        # so a case is called failing against the same bar everywhere.
        def threshold
          @experiment.schedule[:alert_below] ||
            RAAF::Rails::Tracing::BaseComponent::POOR_SCORE
        end

        # Counted over the whole run rather than the page, which is the point of
        # the column: "eleven cases below the line" is a fact about the run, and
        # "eleven of the fifty I loaded" is not.
        #
        # Zero without the column, so the chip stays off a console whose
        # database has not caught up rather than offering a filter that cannot
        # answer.
        def below_count
          return 0 unless RAAF::Eval::Models::ExperimentResult.overall_score_stored?

          @experiment.experiment_results.scoring_below(threshold).count
        end
      end
    end
  end
end
