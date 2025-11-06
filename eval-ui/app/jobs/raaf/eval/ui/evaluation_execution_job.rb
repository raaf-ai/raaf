# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Background job for executing evaluations asynchronously
      #
      # Executes an evaluation session by:
      # 1. Loading the baseline span
      # 2. Running each configuration against the span
      # 3. Calculating metrics for each result
      # 4. Storing results and updating session status
      #
      # @example Queue a job
      #   EvaluationExecutionJob.perform_later(session.id)
      #
      class EvaluationExecutionJob < ApplicationJob
        queue_as :raaf_eval_ui

        # Execute the evaluation session
        # @param session_id [Integer] ID of the session to execute
        def perform(session_id)
          session = Session.find(session_id)
          session.mark_running!

          begin
            execute_session(session)
            session.mark_completed!
          rescue StandardError => e
            Rails.logger.error("Evaluation execution failed: #{e.message}")
            Rails.logger.error(e.backtrace.join("\n"))
            session.mark_failed!(e)
          end
        end

        private

        # Execute all configurations in the session
        def execute_session(session)
          baseline_span = session.baseline_span

          session.configurations.each do |config|
            result = session.results.create!(
              configuration: config,
              status: "running"
            )

            begin
              # This would integrate with Phase 1's evaluation engine
              # For now, create stub results
              execution_result = execute_configuration(baseline_span, config)

              result.mark_completed!(
                {
                  output: execution_result[:output],
                  tokens: execution_result[:tokens],
                  messages: execution_result[:messages]
                },
                {
                  latency_ms: execution_result[:latency_ms],
                  cost: execution_result[:cost],
                  token_usage: execution_result[:token_usage]
                }
              )
            rescue StandardError => e
              Rails.logger.error("Configuration execution failed: #{e.message}")
              result.mark_failed!
            end
          end
        end

        # Execute a single configuration against the baseline
        # This would integrate with Phase 1's RAAF::Eval::EvaluationEngine
        def execute_configuration(baseline_span, configuration)
          # Stub implementation - Phase 1 integration point
          {
            output: "Evaluation output for #{configuration.name}",
            tokens: 150,
            messages: [],
            latency_ms: 1200,
            cost: 0.003,
            token_usage: {
              prompt_tokens: 50,
              completion_tokens: 100,
              total_tokens: 150
            }
          }
        end
      end
    end
  end
end
