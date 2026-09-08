# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # ExperimentResult stores the result of running an experiment against a single dataset item.
      # Contains the agent's output, evaluation scores, and performance metrics.
      #
      # @example Accessing results
      #   result = experiment.experiment_results.first
      #   puts result.output           # Agent's response
      #   puts result.scores           # { "relevance" => 0.9, "accuracy" => 0.85 }
      #   puts result.overall_score    # Average of all scores
      #   puts result.token_metrics    # { "total_tokens" => 150, ... }
      class ExperimentResult < ActiveRecord::Base
        self.table_name = "raaf_experiment_results"

        # Associations
        belongs_to :experiment,
                   class_name: "RAAF::Eval::Models::Experiment"
        belongs_to :dataset_item,
                   class_name: "RAAF::Eval::Models::DatasetItem"

        # Validations
        validates :status, presence: true, inclusion: { in: %w[pending running completed failed] }

        # Scopes
        scope :completed, -> { where(status: "completed") }
        scope :failed, -> { where(status: "failed") }
        scope :pending, -> { where(status: "pending") }
        scope :recent, -> { order(created_at: :desc) }

        # Worst first, which is the order a run is read in when the question is
        # what it got wrong. A row without a score sorts last either way: it has
        # no verdict to rank, and putting it at the top would bury the failures
        # under cases nobody measured.
        #
        # Both fall back to doing nothing where the column has not been
        # migrated in. RAAF's migrations are copied into a host application by
        # hand, so a console running ahead of its database asks for an ordering
        # it cannot have — and a results page that 500s until somebody notices
        # is a worse answer than one that is merely not sorted.
        scope :worst_first, lambda {
          overall_score_stored? ? order(Arel.sql("overall_score ASC NULLS LAST")) : recent
        }
        scope :scoring_below, lambda { |threshold|
          overall_score_stored? ? where(overall_score: ...threshold.to_f) : none
        }

        ##
        # @return [Boolean] whether this database carries the score column
        def self.overall_score_stored?
          column_names.include?("overall_score")
        rescue ActiveRecord::ActiveRecordError
          false
        end

        # Kept in step with the hash it summarises, so the table can order and
        # filter by it in SQL over the whole run rather than over the page it
        # already loaded.
        before_save :cache_overall_score

        ##
        # The mean of the score dimensions.
        #
        # Read off the column where one has been written, and averaged out of
        # the hash where it has not — a row saved before the column existed is
        # still scored, and reading it as unscored would lose it from every
        # screen at once.
        #
        # @return [Float, nil]
        def overall_score
          stored = self[:overall_score] if has_attribute?(:overall_score)
          return stored unless stored.nil?

          computed_overall_score
        end

        ##
        # @return [Float, nil] the mean of the numeric dimensions, or nil where
        #   nothing numeric was recorded
        def computed_overall_score
          return nil if scores.blank?

          values = scores.values.select { |v| v.is_a?(Numeric) }
          return nil if values.empty?

          values.sum / values.size.to_f
        end

        ##
        # Get a specific score
        # @param name [String, Symbol] Score dimension name
        # @return [Float, nil]
        def score(name)
          scores[name.to_s]
        end

        ##
        # Check if this result passed a threshold
        # @param threshold [Float] Minimum acceptable score
        # @param score_name [String, Symbol, nil] Specific score to check, or overall
        # @return [Boolean]
        def passed?(threshold: 0.7, score_name: nil)
          if score_name
            (score(score_name) || 0) >= threshold
          else
            (overall_score || 0) >= threshold
          end
        end

        ##
        # Calculate duration in seconds
        # @return [Float, nil]
        def duration
          return duration_seconds if duration_seconds
          return nil unless started_at && completed_at

          completed_at - started_at
        end

        ##
        # Check if this result has an error
        # @return [Boolean]
        def error?
          status == "failed"
        end

        ##
        # Check if completed successfully
        # @return [Boolean]
        def success?
          status == "completed"
        end

        private

        # Skipped where the column is not there yet, so a host that has not run
        # the migration saves results as it always did.
        def cache_overall_score
          return unless has_attribute?(:overall_score)

          self[:overall_score] = computed_overall_score
        end
      end
    end
  end
end
