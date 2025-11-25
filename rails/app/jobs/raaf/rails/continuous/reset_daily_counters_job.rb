# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # ResetDailyCountersJob resets the daily evaluation counters for all policies.
      # Runs daily at midnight to reset today_evaluation_count to 0.
      #
      # This enables policies to enforce max_daily_evaluations limits without
      # manual intervention. The counter tracks how many evaluations have been
      # performed today and prevents exceeding the configured limit.
      #
      # Schedule: Daily at midnight (0 0 * * *)
      class ResetDailyCountersJob < RAAF::Rails::ApplicationJob
        queue_as :raaf_evaluations_low

        # Don't retry counter resets aggressively
        retry_on StandardError, wait: 5.minutes, attempts: 3

        ##
        # Reset daily counters for all policies
        def perform
          policies_count = 0
          failed_count = 0

          RAAF::Eval::Models::EvaluationPolicy.find_each do |policy|
            reset_policy_counter(policy)
            policies_count += 1
          rescue => e
            failed_count += 1
            log_error("Failed to reset counter for policy #{policy.id}", e)
          end

          log_info("Reset daily counters", {
            policies_count: policies_count,
            failed_count: failed_count,
            reset_date: Date.current
          })
        end

        private

        ##
        # Reset counter for a single policy
        # @param policy [RAAF::Eval::Models::EvaluationPolicy]
        def reset_policy_counter(policy)
          policy.reset_daily_counter!
        end

        def log_info(message, data = {})
          RAAF::Rails.logger.info(
            "[ResetDailyCountersJob] #{message}: #{data.inspect}"
          )
        end

        def log_error(message, error)
          RAAF::Rails.logger.error(
            "[ResetDailyCountersJob] #{message}: #{error.class} - #{error.message}"
          )
        end
      end
    end
  end
end
