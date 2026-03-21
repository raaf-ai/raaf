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

        ##
        # Calculate overall score as average of all score dimensions
        # @return [Float, nil]
        def overall_score
          return nil if scores.blank? || scores.empty?
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
      end
    end
  end
end
