# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # EvaluationRun represents a single evaluation execution that may include
      # multiple configuration variants.
      class EvaluationRun < ActiveRecord::Base
        self.table_name = "evaluation_runs"

        # Associations
        has_many :evaluation_configurations, dependent: :destroy, class_name: "RAAF::Eval::Models::EvaluationConfiguration"
        has_many :evaluation_results, dependent: :destroy, class_name: "RAAF::Eval::Models::EvaluationResult"
        has_many :evaluation_spans, dependent: :nullify, class_name: "RAAF::Eval::Models::EvaluationSpan"

        # Validations
        validates :name, presence: true
        validates :baseline_span_id, presence: true
        validates :status, presence: true, inclusion: { in: %w[pending running completed failed cancelled] }

        # Scopes
        scope :recent, -> { order(created_at: :desc) }
        scope :by_status, ->(status) { where(status: status) }
        scope :completed, -> { where(status: "completed") }
        scope :failed, -> { where(status: "failed") }

        ##
        # Mark run as started
        def start!
          update!(status: "running", started_at: Time.current)
        end

        ##
        # Mark run as completed
        def complete!
          update!(status: "completed", completed_at: Time.current)
        end

        ##
        # Mark run as failed
        # @param error_message [String] Error description
        def fail!(error_message = nil)
          update!(status: "failed", completed_at: Time.current)
          RAAF::Eval.logger.error("Evaluation run failed: #{error_message}") if error_message
        end

        ##
        # Calculate duration in seconds
        # @return [Float, nil] Duration or nil if not completed
        def duration
          return nil unless started_at && completed_at
          completed_at - started_at
        end

        ##
        # Check if run is in progress
        # @return [Boolean]
        def in_progress?
          status == "running"
        end

        ##
        # Check if run is finished (completed, failed, or cancelled)
        # @return [Boolean]
        def finished?
          %w[completed failed cancelled].include?(status)
        end
      end
    end
  end
end
