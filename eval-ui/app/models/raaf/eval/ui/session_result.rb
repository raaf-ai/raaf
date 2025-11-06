# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Represents the result of evaluating a specific configuration
      #
      # Stores the output, metrics, and status of running an evaluation
      # with a particular configuration.
      #
      # @example Create a result
      #   result = SessionResult.create!(
      #     session: session,
      #     configuration: config,
      #     status: "completed",
      #     result_data: { output: "...", tokens: 150 },
      #     metrics: { latency_ms: 1200, cost: 0.003 }
      #   )
      #
      class SessionResult < ApplicationRecord
        self.table_name = "raaf_eval_ui_session_results"

        # Associations
        belongs_to :session,
                   class_name: "RAAF::Eval::UI::Session",
                   foreign_key: :raaf_eval_ui_session_id,
                   inverse_of: :results

        belongs_to :configuration,
                   class_name: "RAAF::Eval::UI::SessionConfiguration",
                   foreign_key: :raaf_eval_ui_session_configuration_id,
                   inverse_of: :results

        # Validations
        validates :status, inclusion: { in: %w[pending running completed failed] }

        # Scopes
        scope :completed, -> { where(status: "completed") }
        scope :running, -> { where(status: "running") }
        scope :failed, -> { where(status: "failed") }
        scope :pending, -> { where(status: "pending") }

        # Instance methods
        def completed?
          status == "completed"
        end

        def running?
          status == "running"
        end

        def failed?
          status == "failed"
        end

        def pending?
          status == "pending"
        end

        # Get output from result data
        def output
          result_data["output"] || result_data[:output]
        end

        # Get token usage
        def tokens
          result_data["tokens"] || result_data[:tokens] || 0
        end

        # Get cost
        def cost
          metrics["cost"] || metrics[:cost] || 0.0
        end

        # Get latency in milliseconds
        def latency_ms
          metrics["latency_ms"] || metrics[:latency_ms] || 0
        end

        # Mark result as running
        def mark_running!
          update!(status: "running")
        end

        # Mark result as completed with data
        def mark_completed!(data, metrics_data)
          update!(
            status: "completed",
            result_data: data,
            metrics: metrics_data
          )
        end

        # Mark result as failed
        def mark_failed!
          update!(status: "failed")
        end
      end
    end
  end
end
