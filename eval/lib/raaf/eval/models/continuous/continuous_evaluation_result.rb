# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # ContinuousEvaluationResult stores results from automated continuous evaluation.
      # Includes full metrics, scores, reasoning, and provenance tracking.
      class ContinuousEvaluationResult < ActiveRecord::Base
        self.table_name = "raaf_evaluation_results"

        # Associations
        belongs_to :evaluation_policy,
                   class_name: "RAAF::Eval::Models::EvaluationPolicy",
                   optional: true
        belongs_to :evaluation_queue_item,
                   class_name: "RAAF::Eval::Models::EvaluationQueueItem",
                   foreign_key: :queue_item_id,
                   optional: true

        # Validations
        validates :span_id, presence: true
        validates :trace_id, presence: true
        validates :evaluator_name, presence: true
        validates :evaluator_type, presence: true,
                  inclusion: { in: %w[rule_based statistical llm_judge] }
        validates :agent_name, presence: true
        validates :status, presence: true,
                  inclusion: { in: %w[passed failed warning error] }
        validates :evaluation_type, inclusion: { in: %w[automated] }
        validates :score, numericality: { in: 0..1 }, allow_nil: true

        # Scopes
        scope :passed, -> { where(status: "passed") }
        scope :failed, -> { where(status: "failed") }
        scope :warning, -> { where(status: "warning") }
        scope :errored, -> { where(status: "error") }
        scope :successful, -> { where(status: %w[passed warning]) }
        scope :unsuccessful, -> { where(status: %w[failed error]) }
        scope :for_agent, ->(name) { where(agent_name: name) }
        scope :for_evaluator, ->(name) { where(evaluator_name: name) }
        scope :for_environment, ->(env) { where(environment: env) }
        scope :for_model, ->(model) { where(model: model) }
        scope :in_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }
        scope :recent, -> { order(created_at: :desc) }

        ##
        # Check if evaluation passed
        # @return [Boolean]
        def passed?
          status == "passed"
        end

        ##
        # Check if evaluation failed
        # @return [Boolean]
        def failed?
          status == "failed"
        end

        ##
        # Check if evaluation had a warning
        # @return [Boolean]
        def warning?
          status == "warning"
        end

        ##
        # Check if evaluation had an error
        # @return [Boolean]
        def error?
          status == "error"
        end

        ##
        # Check if evaluation was successful (passed or warning)
        # @return [Boolean]
        def success?
          %w[passed warning].include?(status)
        end

        ##
        # Get label based on score thresholds
        # @param good_threshold [Float] Threshold for "good" (default 0.8)
        # @param average_threshold [Float] Threshold for "average" (default 0.6)
        # @return [String] "good", "average", "bad", or "unknown"
        def label(good_threshold: 0.8, average_threshold: 0.6)
          return "unknown" if score.nil?
          return "good" if score >= good_threshold
          return "average" if score >= average_threshold
          "bad"
        end

        ##
        # Get duration in seconds
        # @return [Float, nil]
        def duration
          return nil if evaluation_duration_ms.nil?
          evaluation_duration_ms / 1000.0
        end

        class << self
          ##
          # Get counts by status
          # @return [Hash<String, Integer>]
          def aggregate_by_status
            group(:status).count
          end

          ##
          # Calculate pass rate (including warnings as success)
          # @return [Float] Rate between 0 and 1
          def pass_rate
            total = count
            return 0 if total.zero?

            successful.count.to_f / total
          end

          ##
          # Calculate average score
          # @return [Float, nil]
          def average_score
            average(:score)
          end

          ##
          # Calculate score statistics
          # @return [Hash]
          def score_statistics
            {
              avg: average(:score),
              min: minimum(:score),
              max: maximum(:score),
              count: where.not(score: nil).count
            }
          end

          ##
          # Get results grouped by evaluator with counts
          # @return [Hash<String, Hash>]
          def by_evaluator_with_stats
            select(
              :evaluator_name,
              "COUNT(*) as total",
              "COUNT(CASE WHEN status = 'passed' THEN 1 END) as passed",
              "COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed",
              "AVG(score) as avg_score"
            ).group(:evaluator_name).to_a.map do |row|
              [row.evaluator_name, {
                total: row.total,
                passed: row.passed,
                failed: row.failed,
                avg_score: row.avg_score
              }]
            end.to_h
          end
        end
      end
    end
  end
end
