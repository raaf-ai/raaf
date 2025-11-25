# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Controller for browsing evaluation results
      class ResultsController < BaseController
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
            passed: all_results.where(status: 'passed').count,
            failed: all_results.where(status: 'failed').count,
            warning: all_results.where(status: 'warning').count
          }

          # Filter options
          @agents = EvaluationResult.distinct.pluck(:agent_name).compact.sort
          @environments = EvaluationResult.distinct.pluck(:environment).compact.sort
          @evaluators = EvaluationResult.distinct.pluck(:evaluator_name).compact.sort
        end

        # GET /raaf/rails/continuous/results/:id
        def show
          @result = EvaluationResult.find(params[:id])
          @span = RAAF::Rails::Tracing::SpanRecord.find_by(span_id: @result.span_id)
          @other_results = EvaluationResult.where(span_id: @result.span_id).where.not(id: @result.id)
        end
      end
    end
  end
end
