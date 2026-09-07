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
        # The screen reads the job backend, not `EvaluationQueueItem`. That
        # table records what RAAF decided to run; SolidQueue decides what a
        # worker will actually pick up, and the two part company the moment a
        # worker dies mid-run — which is why `StaleJobCleanupJob` exists.
        #
        # The JSON branch still answers with the RAAF rows. It is what the
        # existing `show`, `retry` and `cancel` actions operate on, and
        # changing its shape would break any caller of this endpoint.
        def index
          @queue = RAAF::Rails::Continuous::JobQueue.new(window: 24.hours)

          respond_to do |format|
            format.html do
              queue_list = RAAF::Rails::Continuous::QueueList.new(queue: @queue)
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Queue", crumb: "Continuous",
                                                            current: :queue) do
                render queue_list
              end
              render layout
            end
            format.json { render json: queue_items_for_json }
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
              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Queue item", crumb: "Continuous") do
                render queue_show
              end
              render layout
            end
            format.json { render json: @queue_item }
          end
        end

        # POST /raaf/rails/continuous/queue/:id/retry
        def retry
          @queue_item.update!(status: "pending", attempts: 0, error_message: nil)
          RAAF::Rails::Continuous::EvaluationJob.perform_later(
            span_id: @queue_item.span_id,
            policy_id: @queue_item.evaluation_policy_id
          )
          redirect_to continuous_queue_index_path, notice: "Evaluation requeued."
        end

        # POST /raaf/rails/continuous/queue/:id/cancel
        def cancel
          @queue_item.update!(status: "cancelled")
          redirect_to continuous_queue_index_path, notice: "Evaluation cancelled."
        end

        # POST /raaf/rails/continuous/queue/retry_failed
        def retry_failed
          failed_items = EvaluationQueue.where(status: "failed")
          count = failed_items.count
          failed_items.find_each do |item|
            item.update!(status: "pending", attempts: 0, error_message: nil)
            RAAF::Rails::Continuous::EvaluationJob.perform_later(
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

        def queue_items_for_json
          items = EvaluationQueue.order(created_at: :desc)
          items = items.where(status: params[:status]) if params[:status].present?
          items = items.where(evaluation_policy_id: params[:policy_id]) if params[:policy_id].present?
          items.limit(50)
        end
      end
    end
  end
end
