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
        # Every figure and every control on this screen reads the one source.
        # They did not: the cards counted SolidQueue rows and the buttons
        # beside them moved RAAF's, so "failed" meant two populations on one
        # screen and requeueing did not act on what the card had listed.
        # `EvaluationQueueItem` is still RAAF's audit trail, and the item
        # screen still reads it — it drives nothing here.
        def index
          @queue = RAAF::Rails::Continuous::JobQueue.new(window: 24.hours)

          respond_to do |format|
            format.html do
              queue_list = RAAF::Rails::Continuous::QueueList.new(queue: @queue)
              render_in_layout queue_list, title: "Queue", crumb: "Continuous", current: :queue
            end
            format.json { render json: queue_json }
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
              render_in_layout queue_show, title: "Queue item", crumb: "Continuous"
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
        # Puts back exactly the jobs the Failed card lists.
        def retry_failed
          count = job_queue.retry_failed
          redirect_to continuous_queue_index_path,
                      notice: "#{helpers.pluralize(count, 'failed job')} requeued."
        end

        # DELETE /raaf/rails/continuous/queue/discard_failed
        # The other half of what the Failed card promises. It replaces a
        # "Clear completed" that deleted `EvaluationQueueItem` rows: completed
        # evaluations are not on this screen, so the button emptied a table
        # nobody was looking at, out of the source the rest of the screen had
        # stopped reading.
        def discard_failed
          count = job_queue.discard_failed
          redirect_to continuous_queue_index_path,
                      notice: "#{helpers.pluralize(count, 'failed job')} discarded."
        end

        private

        def job_queue
          @job_queue ||= RAAF::Rails::Continuous::JobQueue.new(window: 24.hours)
        end

        def set_queue_item
          @queue_item = EvaluationQueue.find(params[:id])
        end

        # The same four figures and three lists the screen draws, from the same
        # source it draws them from.
        def queue_json
          { available: RAAF::Rails::Continuous::JobQueue.available?,
            counts: { waiting: @queue.waiting_count, in_flight: @queue.in_flight_count,
                      scheduled: @queue.scheduled_count, failed: @queue.failed_count },
            in_flight: @queue.in_flight,
            waiting: @queue.waiting,
            failed: @queue.failed }
        end
      end
    end
  end
end
