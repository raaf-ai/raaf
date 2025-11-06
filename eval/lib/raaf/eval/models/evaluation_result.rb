# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # EvaluationResult stores evaluation execution results with comprehensive metrics.
      class EvaluationResult < ActiveRecord::Base
        self.table_name = "evaluation_results"

        # Associations
        belongs_to :evaluation_run, class_name: "RAAF::Eval::Models::EvaluationRun"
        belongs_to :evaluation_configuration, class_name: "RAAF::Eval::Models::EvaluationConfiguration"

        # Validations
        validates :result_span_id, presence: true
        validates :status, presence: true, inclusion: { in: %w[pending running completed failed] }

        # Scopes
        scope :completed, -> { where(status: "completed") }
        scope :failed, -> { where(status: "failed") }
        scope :with_ai_comparison, -> { where(ai_comparison_status: "completed") }
        scope :with_regressions, -> { where("baseline_comparison ->> 'regression_detected' = 'true'") }

        ##
        # Mark result as started
        def start!
          update!(status: "running", started_at: Time.current)
        end

        ##
        # Mark result as completed
        def complete!
          update!(status: "completed", completed_at: Time.current)
        end

        ##
        # Mark result as failed
        # @param error [String, Exception] Error message or exception
        def fail!(error)
          message = error.is_a?(Exception) ? error.message : error
          backtrace = error.is_a?(Exception) ? error.backtrace&.join("\n") : nil

          update!(
            status: "failed",
            completed_at: Time.current,
            error_message: message,
            error_backtrace: backtrace
          )
        end

        ##
        # Calculate duration in seconds
        # @return [Float, nil]
        def duration
          return nil unless started_at && completed_at
          completed_at - started_at
        end

        ##
        # Check if result has regression
        # @return [Boolean]
        def regression_detected?
          baseline_comparison&.dig("regression_detected") == true
        end

        ##
        # Get quality change status
        # @return [String, nil] "improved", "degraded", or "unchanged"
        def quality_change
          baseline_comparison&.dig("quality_change")
        end

        ##
        # Get token delta
        # @return [Hash, nil] Hash with :absolute and :percentage keys
        def token_delta
          baseline_comparison&.dig("token_delta")
        end

        ##
        # Get latency delta
        # @return [Hash, nil] Hash with :absolute_ms and :percentage keys
        def latency_delta
          baseline_comparison&.dig("latency_delta")
        end

        ##
        # Check if AI comparison is complete
        # @return [Boolean]
        def ai_comparison_complete?
          ai_comparison_status == "completed"
        end

        ##
        # Get semantic similarity score from AI comparison
        # @return [Float, nil]
        def semantic_similarity
          ai_comparison&.dig("semantic_similarity_score")
        end

        ##
        # Get coherence score from AI comparison
        # @return [Float, nil]
        def coherence_score
          ai_comparison&.dig("coherence_score")
        end

        ##
        # Check if hallucination was detected
        # @return [Boolean]
        def hallucination_detected?
          ai_comparison&.dig("hallucination_detected") == true
        end

        ##
        # Get bias detection results
        # @return [Hash, nil]
        def bias_detected
          ai_comparison&.dig("bias_detected")
        end

        ##
        # Get comparison reasoning from AI
        # @return [String, nil]
        def comparison_reasoning
          ai_comparison&.dig("comparison_reasoning")
        end
      end
    end
  end
end
