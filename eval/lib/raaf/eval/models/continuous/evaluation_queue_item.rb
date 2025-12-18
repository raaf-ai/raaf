# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # EvaluationQueueItem tracks pending and in-progress evaluations.
      # Provides visibility into queue status and supports retry logic.
      class EvaluationQueueItem < ActiveRecord::Base
        self.table_name = "raaf_evaluation_queue"

        # Associations
        belongs_to :evaluation_policy,
                   class_name: "RAAF::Eval::Models::EvaluationPolicy",
                   optional: true
        has_many :continuous_evaluation_results,
                 class_name: "RAAF::Eval::Models::ContinuousEvaluationResult",
                 foreign_key: :queue_item_id,
                 dependent: :nullify

        # Validations
        validates :span_id, presence: true
        validates :trace_id, presence: true
        validates :status, presence: true, inclusion: { in: %w[pending running completed partial failed cancelled] }

        # Scopes
        scope :pending, -> { where(status: "pending") }
        scope :running, -> { where(status: "running") }
        scope :completed, -> { where(status: "completed") }
        scope :partial, -> { where(status: "partial") }
        scope :failed, -> { where(status: "failed") }
        scope :cancelled, -> { where(status: "cancelled") }
        scope :finished_successfully, -> { where(status: %w[completed partial]) }
        scope :processable, -> { pending.where("scheduled_at <= ? OR scheduled_at IS NULL", Time.current).order(priority: :desc, scheduled_at: :asc) }
        scope :retryable, -> { pending.where.not(next_retry_at: nil).where("next_retry_at <= ?", Time.current) }

        # Base backoff time in seconds for retry calculation
        RETRY_BASE_DELAY = 60

        ##
        # Start processing this queue item
        # @raise [InvalidStateTransition] if not in pending state
        def start!
          raise RAAF::Eval::InvalidStateTransition, "Cannot start item in #{status} state" unless status == "pending"

          update!(status: "running", started_at: Time.current)
        end

        ##
        # Mark this item as completed
        # @raise [InvalidStateTransition] if not in running state
        def complete!
          raise RAAF::Eval::InvalidStateTransition, "Cannot complete item in #{status} state" unless status == "running"

          update!(status: "completed", completed_at: Time.current)
        end

        ##
        # Mark this item as completed with partial failures
        # Some evaluators succeeded, some failed
        # @param error_summary [String] Summary of failures
        # @raise [InvalidStateTransition] if not in running state
        def complete_partial!(error_summary = nil)
          raise RAAF::Eval::InvalidStateTransition, "Cannot complete item in #{status} state" unless status == "running"

          update!(
            status: "partial",
            completed_at: Time.current,
            error_message: error_summary
          )
        end

        ##
        # Mark this item as failed
        # @param error_message [String] Error description
        # @param error_class [String] Error class name
        def fail!(error_message = nil, error_class = nil)
          increment_attempts!

          if can_retry?
            schedule_retry!
            update!(
              status: "pending",
              error_message: error_message,
              error_class: error_class
            )
          else
            update!(
              status: "failed",
              completed_at: Time.current,
              error_message: error_message,
              error_class: error_class
            )
          end
        end

        ##
        # Cancel this item
        def cancel!
          update!(status: "cancelled", completed_at: Time.current)
        end

        ##
        # Retry a failed item
        def retry!
          update!(
            status: "pending",
            attempts: 0,
            error_message: nil,
            error_class: nil,
            next_retry_at: nil,
            started_at: nil,
            completed_at: nil
          )
        end

        ##
        # Increment the attempts counter
        def increment_attempts!
          increment!(:attempts)
        end

        ##
        # Check if retry is allowed
        # @return [Boolean]
        def can_retry?
          attempts < max_attempts
        end

        ##
        # Schedule next retry with exponential backoff
        def schedule_retry!
          # Exponential backoff: 1min, 4min, 9min, etc.
          delay = RETRY_BASE_DELAY * (attempts ** 2)
          update!(next_retry_at: Time.current + delay.seconds)
        end

        ##
        # Calculate processing duration
        # @return [Float, nil] Duration in seconds or nil
        def duration
          return nil unless started_at && completed_at
          completed_at - started_at
        end

        ##
        # Check if item is currently being processed
        # @return [Boolean]
        def processing?
          status == "running"
        end

        ##
        # Check if item has finished (completed, partial, failed, or cancelled)
        # @return [Boolean]
        def finished?
          %w[completed partial failed cancelled].include?(status)
        end

        ##
        # Check if item completed with at least some success
        # @return [Boolean]
        def successful?
          %w[completed partial].include?(status)
        end

        ##
        # Check if item is waiting for retry
        # @return [Boolean]
        def awaiting_retry?
          status == "pending" && next_retry_at.present? && next_retry_at > Time.current
        end
      end
    end
  end
end
