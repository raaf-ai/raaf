# frozen_string_literal: true

require_relative "evaluation_run"
require "active_support/core_ext/hash/indifferent_access"

module RAAF
  module Eval
    module Storage
      # Query builder for filtering evaluation runs
      # Supports filtering by evaluator name, configuration, date range, and tags
      class QueryBuilder
        # Initialize query builder with filters
        # @param filters [Hash] Query filters
        # @option filters [String] :evaluator_name Filter by evaluator name
        # @option filters [String, Symbol] :configuration_name Filter by configuration
        # @option filters [Time] :start_date Filter by start date (inclusive)
        # @option filters [Time] :end_date Filter by end date (inclusive)
        # @option filters [Hash] :tags Filter by tags (all must match)
        def initialize(filters)
          @filters = filters.with_indifferent_access
        end

        # Execute the query
        # @return [Array<EvaluationRun>] Filtered results sorted by created_at desc
        def execute
          results = EvaluationRun.all

          results = filter_by_evaluator_name(results) if @filters[:evaluator_name]
          results = filter_by_configuration_name(results) if @filters[:configuration_name]
          results = filter_by_date_range(results) if @filters[:start_date] || @filters[:end_date]
          results = filter_by_tags(results) if @filters[:tags]

          # Sort by created_at descending (most recent first)
          results.sort_by(&:created_at).reverse
        end

        private

        # Filter by evaluator name
        # @param results [Array<EvaluationRun>] Current results
        # @return [Array<EvaluationRun>] Filtered results
        def filter_by_evaluator_name(results)
          results.select { |r| r.evaluator_name == @filters[:evaluator_name] }
        end

        # Filter by configuration name
        # @param results [Array<EvaluationRun>] Current results
        # @return [Array<EvaluationRun>] Filtered results
        def filter_by_configuration_name(results)
          config_name = @filters[:configuration_name].to_s
          results.select { |r| r.configuration_name == config_name }
        end

        # Filter by date range
        # @param results [Array<EvaluationRun>] Current results
        # @return [Array<EvaluationRun>] Filtered results
        def filter_by_date_range(results)
          results.select do |run|
            within_start = @filters[:start_date].nil? || run.created_at >= @filters[:start_date]
            within_end = @filters[:end_date].nil? || run.created_at <= @filters[:end_date]
            within_start && within_end
          end
        end

        # Filter by tags (all specified tags must match)
        # @param results [Array<EvaluationRun>] Current results
        # @return [Array<EvaluationRun>] Filtered results
        def filter_by_tags(results)
          tag_filters = @filters[:tags].with_indifferent_access

          results.select do |run|
            # Skip runs with nil tags
            next false if run.tags.nil?

            run_tags = run.tags.with_indifferent_access
            # All filter tags must match
            tag_filters.all? { |key, value| run_tags[key] == value }
          end
        end
      end
    end
  end
end
