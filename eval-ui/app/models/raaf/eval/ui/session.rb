# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Represents an evaluation session in the UI
      #
      # A session captures a complete evaluation workflow, including:
      # - The baseline span being evaluated
      # - One or more configurations to test
      # - Results from evaluation execution
      # - Session metadata and status
      #
      # @example Create a new session
      #   session = Session.create!(
      #     name: "Temperature comparison",
      #     baseline_span_id: span.id,
      #     session_type: "draft"
      #   )
      #
      class Session < ApplicationRecord
        self.table_name = "raaf_eval_ui_sessions"

        # Associations
        # Note: User association is optional and polymorphic to support different auth systems
        belongs_to :user, optional: true, class_name: "::User"

        has_many :configurations,
                 class_name: "RAAF::Eval::UI::SessionConfiguration",
                 foreign_key: :raaf_eval_ui_session_id,
                 dependent: :destroy,
                 inverse_of: :session

        has_many :results,
                 class_name: "RAAF::Eval::UI::SessionResult",
                 foreign_key: :raaf_eval_ui_session_id,
                 dependent: :destroy,
                 inverse_of: :session

        # Validations
        validates :name, presence: true, length: { maximum: 255 }
        validates :session_type, inclusion: { in: %w[draft saved archived] }
        validates :status, inclusion: { in: %w[pending running completed failed cancelled] }

        # Scopes
        scope :recent, -> { order(updated_at: :desc).limit(10) }
        scope :saved, -> { where(session_type: "saved") }
        scope :drafts, -> { where(session_type: "draft") }
        scope :archived, -> { where(session_type: "archived") }
        scope :completed, -> { where(status: "completed") }
        scope :running, -> { where(status: "running") }
        scope :failed, -> { where(status: "failed") }

        # Instance methods
        def baseline_span
          # This would connect to Phase 1's span model
          # For now, return a stub or nil
          nil
        end

        def running?
          status == "running"
        end

        def completed?
          status == "completed"
        end

        def failed?
          status == "failed"
        end

        def pending?
          status == "pending"
        end

        def draft?
          session_type == "draft"
        end

        def saved?
          session_type == "saved"
        end

        def archived?
          session_type == "archived"
        end

        # Mark session as running
        def mark_running!
          update!(status: "running", started_at: Time.current)
        end

        # Mark session as completed
        def mark_completed!
          update!(status: "completed", completed_at: Time.current)
        end

        # Mark session as failed with error details
        def mark_failed!(error)
          update!(
            status: "failed",
            error_message: error.message,
            error_backtrace: error.backtrace&.join("\n"),
            completed_at: Time.current
          )
        end

        # Cancel a running session
        def cancel!
          return unless running?

          update!(status: "cancelled", completed_at: Time.current)
        end

        # Archive this session
        def archive!
          update!(session_type: "archived")
        end

        # Progress percentage (0-100)
        def progress_percentage
          return 0 if results.empty?
          return 100 if completed?

          completed_count = results.where(status: "completed").count
          (completed_count.to_f / results.count * 100).round
        end

        # Current execution step (for progress display)
        def current_step
          return nil unless running?

          metadata&.dig("current_step")
        end

        # Estimated time remaining in seconds
        def estimated_time_remaining
          return nil unless running? || pending?
          return nil unless started_at

          elapsed_seconds = Time.current - started_at
          completed_ratio = progress_percentage / 100.0

          return nil if completed_ratio.zero?

          total_estimated_seconds = elapsed_seconds / completed_ratio
          remaining_seconds = total_estimated_seconds - elapsed_seconds

          [remaining_seconds.round, 0].max
        end

        # Duration of evaluation in milliseconds
        def duration_ms
          return nil unless completed_at && started_at

          ((completed_at - started_at) * 1000).round
        end

        # Partial metrics available during execution
        def partial_metrics
          return {} unless running?

          metadata&.dig("partial_metrics") || {}
        end

        # Retry count for failed evaluations
        def retry_count
          metadata&.dig("retry_count") || 0
        end

        # Increment retry count
        def increment_retry_count!
          current_count = retry_count
          new_metadata = (metadata || {}).merge("retry_count" => current_count + 1)
          update!(metadata: new_metadata)
        end

        # Update progress with current step
        def update_progress!(step:, partial_metrics: nil)
          new_metadata = (metadata || {}).merge("current_step" => step)
          new_metadata["partial_metrics"] = partial_metrics if partial_metrics
          update!(metadata: new_metadata)
        end
      end
    end
  end
end
