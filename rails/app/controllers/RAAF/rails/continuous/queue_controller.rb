# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      # Controller for monitoring and managing the evaluation queue
      class QueueController < BaseController
        # Alias the models for cleaner code
        EvaluationQueue = RAAF::Eval::Models::EvaluationQueueItem

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

          respond_to do |format|
            format.html do
              queue_list = RAAF::Rails::Continuous::QueueList.new(
                queue_items: @queue_items,
                filters: params.permit(:status, :policy_id).to_h
              )
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Evaluation Queue") do
                render queue_list
              end
              render layout
            end
            format.json { render json: @queue_items }
          end
        end

        # GET /raaf/rails/continuous/queue/:id
        def show
          @results = @queue_item.continuous_evaluation_results.order(created_at: :desc)

          respond_to do |format|
            format.html do
              queue_show = RAAF::Rails::Continuous::QueueShow.new(
                queue_item: @queue_item,
                results: @results
              )
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Queue Item Details") do
                render queue_show
              end
              render layout
            end
            format.json { render json: @queue_item }
          end
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
