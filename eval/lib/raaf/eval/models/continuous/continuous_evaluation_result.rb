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
                                   inclusion: { in: %w[rule_based statistical llm_judge custom] }
        validates :agent_name, presence: true
        validates :status, presence: true,
                           inclusion: { in: %w[good average bad error] }
        # "automated" is a policy sampling production traffic. "manual" is a
        # sweep somebody ran by hand against a span they chose -- the same
        # verdict, from a population nobody sampled, so it is shown in the
        # console and left out of the metrics MetricsAggregationJob rolls up.
        validates :evaluation_type, inclusion: { in: %w[automated manual] }
        validates :score, numericality: { in: 0..1 }, allow_nil: true

        # Scopes - using quality labels: good, average, bad, error
        scope :good_quality, -> { where(status: "good") }
        scope :average_quality, -> { where(status: "average") }
        scope :bad_quality, -> { where(status: "bad") }
        scope :errored, -> { where(status: "error") }
        scope :acceptable, -> { where(status: %w[good average]) }
        scope :unacceptable, -> { where(status: %w[bad error]) }
        scope :for_agent, ->(name) { where(agent_name: name) }
        scope :for_evaluator, ->(name) { where(evaluator_name: name) }
        scope :for_environment, ->(env) { where(environment: env) }
        scope :automated, -> { where(evaluation_type: "automated") }
        scope :manual, -> { where(evaluation_type: "manual") }
        scope :for_model, ->(model) { where(model: model) }
        scope :in_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }
        scope :recent, -> { order(created_at: :desc) }

        # One check's own history. A check is `field:evaluator`, and a row is
        # one check's answer about one span.
        scope :for_check, ->(key) { where(check_key: key.to_s) }

        # Rows written before a result was recorded per check. Their score is
        # several evaluators' verdicts combined, and cannot be split after the
        # fact -- the parts were never written down. The screens say so rather
        # than crediting the figure to whichever evaluator is being read.
        scope :combined, -> { where(check_key: nil) }

        ##
        # @return [Boolean] whether this database carries the check column.
        #   RAAF's migrations are copied into a host application by hand, so a
        #   console can run ahead of its database; a screen that 500s until
        #   somebody notices is worse than one that is merely not split.
        def self.check_key_stored?
          column_names.include?("check_key")
        rescue ActiveRecord::ActiveRecordError
          false
        end

        ##
        # @return [Boolean] whether this database carries the provenance
        #   columns -- the policy's name and its retention, copied onto the row
        #   so neither depends on the policy still existing.
        #
        #   Guarded the same way as check_key_stored? and for the same reason:
        #   RAAF's migrations are copied into a host application by hand, so a
        #   console can run ahead of its database, and a writer that insists on
        #   the column would stop grading rather than grade without it.
        def self.policy_provenance_stored?
          (%w[policy_name retention_days] - column_names).empty?
        rescue ActiveRecord::ActiveRecordError
          false
        end

        ##
        # How long this row is worth keeping, in days.
        #
        # Its own value when it has one, and the policy's while the backfill has
        # not reached it. Nil means neither is available -- a row whose policy
        # is already gone -- and the caller's default applies.
        #
        # @return [Integer, nil]
        def keep_for_days
          own = self.class.policy_provenance_stored? ? self[:retention_days] : nil
          own || evaluation_policy&.retention_days
        end

        ##
        # The policy that produced this row, by name.
        #
        # Read from the row itself, so it survives the policy being deleted --
        # which is the whole reason the column exists. Falls back to the
        # association for rows written before the backfill.
        #
        # @return [String, nil]
        def producing_policy_name
          own = self.class.policy_provenance_stored? ? self[:policy_name] : nil
          own || evaluation_policy&.name
        end

        ##
        # @return [Boolean] whether the score is one evaluator's own verdict
        def per_check?
          self.class.check_key_stored? && self[:check_key].present?
        end

        ##
        # Check if the evaluation judged the span good
        # @return [Boolean]
        def good?
          status == "good"
        end

        ##
        # Check if the evaluation judged the span average
        # @return [Boolean]
        def average?
          status == "average"
        end

        ##
        # Check if the evaluation judged the span bad
        # @return [Boolean]
        def bad?
          status == "bad"
        end

        ##
        # Check if evaluation had an error
        # @return [Boolean]
        def error?
          status == "error"
        end

        ##
        # Check if the verdict is one a reader can act on (good or average)
        # @return [Boolean]
        def success?
          %w[good average].include?(status)
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
          # Calculate the share of verdicts that were good or average
          # @return [Float] Rate between 0 and 1
          def pass_rate
            total = count
            return 0 if total.zero?

            acceptable.count.to_f / total
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
              "COUNT(CASE WHEN status IN ('good', 'average') THEN 1 END) as passed",
              "COUNT(CASE WHEN status IN ('bad', 'error') THEN 1 END) as failed",
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
