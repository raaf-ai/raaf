# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Controller for browsing evaluation results
      class ResultsController < BaseController
        # Alias the models for cleaner code
        EvaluationResult = RAAF::Eval::Models::ContinuousEvaluationResult

        # GET /raaf/rails/continuous/results
        def index
          @results = EvaluationResult.order(created_at: :desc)

          # Filtering
          @results = @results.where(agent_name: params[:agent]) if params[:agent].present?
          @results = @results.where(environment: params[:environment]) if params[:environment].present?
          @results = @results.where(status: params[:status]) if params[:status].present?
          @results = @results.where(evaluator_name: params[:evaluator]) if params[:evaluator].present?
          @results = @results.where('created_at >= ?', params[:from].to_date) if params[:from].present?
          @results = @results.where('created_at <= ?', params[:to].to_date.end_of_day) if params[:to].present?

          @results = @results.page(params[:page]).per(50)

          # Summary stats
          all_results = EvaluationResult.all
          @summary = {
            total: @results.total_count,
            good: all_results.where(status: 'good').count,
            average: all_results.where(status: 'average').count,
            bad: all_results.where(status: 'bad').count,
            error: all_results.where(status: 'error').count
          }

          # Filter options
          @agents = EvaluationResult.distinct.pluck(:agent_name).compact.sort
          @environments = EvaluationResult.distinct.pluck(:environment).compact.sort
          @evaluators = EvaluationResult.distinct.pluck(:evaluator_name).compact.sort

          respond_to do |format|
            format.html do
              results_list = RAAF::Rails::Continuous::ResultsList.new(
                results: @results,
                filters: params.permit(:agent, :environment, :status, :evaluator, :from, :to).to_h
              )
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Evaluation Results") do
                render results_list
              end
              render layout
            end
            format.json { render json: @results }
          end
        end

        # GET /raaf/rails/continuous/results/:id
        def show
          @result = EvaluationResult.find(params[:id])
          @span = RAAF::Rails::Tracing::SpanRecord.find_by(span_id: @result.span_id)
          @other_results = EvaluationResult.where(span_id: @result.span_id).where.not(id: @result.id)

          respond_to do |format|
            format.html do
              result_show = RAAF::Rails::Continuous::ResultShow.new(result: @result)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Evaluation Result") do
                render result_show
              end
              render layout
            end
            format.json { render json: @result }
          end
        end
      end
    end
  end
end
