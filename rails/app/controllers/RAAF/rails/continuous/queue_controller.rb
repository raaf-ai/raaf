# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Controller for monitoring and managing the evaluation queue
      class QueueController < BaseController
        before_action :set_queue_item, only: %i[show retry cancel]

        # GET /raaf/rails/continuous/queue
        def index
          @queue_items = EvaluationQueue.order(created_at: :desc)
          @queue_items = @queue_items.where(status: params[:status]) if params[:status].present?
          @queue_items = @queue_items.where(evaluation_policy_id: params[:policy_id]) if params[:policy_id].present?
          @queue_items = @queue_items.page(params[:page]).per(50)

          @stats = {
            pending: EvaluationQueue.where(status: 'pending').count,
            running: EvaluationQueue.where(status: 'running').count,
            failed: EvaluationQueue.where(status: 'failed').count,
            completed_1h: EvaluationQueue.where(status: 'completed').where('completed_at > ?', 1.hour.ago).count
          }
        end

        # GET /raaf/rails/continuous/queue/:id
        def show
          @results = @queue_item.evaluation_results.order(created_at: :desc)
        end

        # POST /raaf/rails/continuous/queue/:id/retry
        def retry
          @queue_item.update!(status: 'pending', attempts: 0, error_message: nil)
          RAAF::Eval::Continuous::EvaluationJob.perform_later(
            span_id: @queue_item.span_id,
            policy_id: @queue_item.evaluation_policy_id
          )
          redirect_to continuous_queue_index_path, notice: 'Evaluation requeued.'
        end

        # POST /raaf/rails/continuous/queue/:id/cancel
        def cancel
          @queue_item.update!(status: 'cancelled')
          redirect_to continuous_queue_index_path, notice: 'Evaluation cancelled.'
        end

        # POST /raaf/rails/continuous/queue/retry_failed
        def retry_failed
          failed_items = EvaluationQueue.where(status: 'failed')
          count = failed_items.count
          failed_items.find_each do |item|
            item.update!(status: 'pending', attempts: 0, error_message: nil)
            RAAF::Eval::Continuous::EvaluationJob.perform_later(
              span_id: item.span_id,
              policy_id: item.evaluation_policy_id
            )
          end
          redirect_to continuous_queue_index_path, notice: "#{count} evaluations requeued."
        end

        # DELETE /raaf/rails/continuous/queue/clear_completed
        def clear_completed
          count = EvaluationQueue.where(status: %w[completed cancelled]).delete_all
          redirect_to continuous_queue_index_path, notice: "#{count} completed items cleared."
        end

        private

        def set_queue_item
          @queue_item = EvaluationQueue.find(params[:id])
        end
      end
    end
  end
end
