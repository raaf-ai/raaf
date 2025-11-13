# frozen_string_literal: true

require_relative "evaluation_run"

module RAAF
  module Eval
    module Storage
      # Retention policy implementation with OR logic
      # Keeps evaluation runs if they satisfy EITHER time-based OR count-based retention
      class RetentionPolicy
        # Initialize retention policy
        # @param retention_days [Integer, nil] Keep runs within this many days
        # @param retention_count [Integer, nil] Keep this many most recent runs
        def initialize(retention_days, retention_count)
          @retention_days = retention_days
          @retention_count = retention_count
        end

        # Execute retention cleanup
        # Deletes runs that are BOTH outside retention_days AND outside retention_count
        # @return [Integer] Number of runs deleted
        def cleanup
          return 0 if @retention_days.nil? && @retention_count.nil?

          runs_to_keep = identify_runs_to_keep
          runs_to_delete = EvaluationRun.all - runs_to_keep

          runs_to_delete.each(&:destroy)
          runs_to_delete.size
        end

        private

        # Identify runs to keep based on OR logic
        # Keep if (within days) OR (within count)
        # @return [Array<EvaluationRun>] Runs that should be kept
        def identify_runs_to_keep
          runs_within_days = runs_within_retention_days
          runs_within_count = runs_within_retention_count

          # Convert relation to array if needed, then combine and remove duplicates
          days_array = runs_within_days.respond_to?(:to_a) ? runs_within_days.to_a : runs_within_days
          count_array = runs_within_count.respond_to?(:to_a) ? runs_within_count.to_a : runs_within_count

          # OR logic: combine both sets and remove duplicates
          (days_array + count_array).uniq
        end

        # Get runs within retention_days threshold
        # @return [Array<EvaluationRun>] Runs within time threshold
        def runs_within_retention_days
          return [] if @retention_days.nil?

          # Calculate cutoff with 1-second tolerance to handle timing precision
          # Runs created exactly at the threshold should be kept
          cutoff_date = Time.now - (@retention_days * 24 * 60 * 60) - 1
          EvaluationRun.all.select { |run| run.created_at >= cutoff_date }
        end

        # Get runs within retention_count threshold (most recent N runs)
        # Note: "Most recent" means most recently inserted into the database,
        # not necessarily the newest created_at timestamp (which can be manually set)
        # @return [Array<EvaluationRun>] Most recent N runs by insertion order
        def runs_within_retention_count
          return [] if @retention_count.nil?

          # Sort by insertion_order (not created_at) to get truly most recently added runs
          all_runs = EvaluationRun.all.sort_by(&:insertion_order).reverse
          all_runs.first(@retention_count)
        end
      end
    end
  end
end
