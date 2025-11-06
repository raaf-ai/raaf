# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # ResultStore handles storage and retrieval of evaluation results
    class ResultStore
      ##
      # Store evaluation result with all metrics
      # @param evaluation_result [Models::EvaluationResult] Result to update
      # @param metrics [Hash] Hash containing all metric categories
      def store(evaluation_result, metrics)
        updates = {}

        updates[:token_metrics] = metrics[:token_metrics] if metrics[:token_metrics]
        updates[:latency_metrics] = metrics[:latency_metrics] if metrics[:latency_metrics]
        updates[:accuracy_metrics] = metrics[:accuracy_metrics] if metrics[:accuracy_metrics]
        updates[:structural_metrics] = metrics[:structural_metrics] if metrics[:structural_metrics]
        updates[:ai_comparison] = metrics[:ai_comparison] if metrics[:ai_comparison]
        updates[:statistical_analysis] = metrics[:statistical_analysis] if metrics[:statistical_analysis]
        updates[:custom_metrics] = metrics[:custom_metrics] if metrics[:custom_metrics]
        updates[:baseline_comparison] = metrics[:baseline_comparison] if metrics[:baseline_comparison]

        # Update AI comparison status if present
        if metrics[:ai_comparison]
          updates[:ai_comparison_status] = metrics[:ai_comparison][:status] || "completed"
        end

        evaluation_result.update!(updates)
      rescue StandardError => e
        RAAF::Eval.logger.error("Failed to store evaluation result: #{e.message}")
        raise DatabaseError, "Failed to store result: #{e.message}"
      end

      ##
      # Query results by run
      # @param run [Models::EvaluationRun] Run to query
      # @return [Array<Models::EvaluationResult>]
      def query_by_run(run)
        run.evaluation_results.includes(:evaluation_configuration).order(:created_at)
      end

      ##
      # Query results by configuration type
      # @param run [Models::EvaluationRun] Run to query
      # @param config_type [String] Configuration type
      # @return [Array<Models::EvaluationResult>]
      def query_by_config_type(run, config_type)
        run.evaluation_results
           .joins(:evaluation_configuration)
           .where(evaluation_configurations: { configuration_type: config_type })
           .includes(:evaluation_configuration)
      end

      ##
      # Query results with regressions
      # @param run [Models::EvaluationRun] Run to query
      # @return [Array<Models::EvaluationResult>]
      def query_regressions(run)
        run.evaluation_results.with_regressions.includes(:evaluation_configuration)
      end

      ##
      # Aggregate metrics across results
      # @param results [Array<Models::EvaluationResult>] Results to aggregate
      # @return [Hash] Aggregated metrics
      def aggregate_metrics(results)
        return {} if results.empty?

        {
          count: results.size,
          completed: results.count { |r| r.status == "completed" },
          failed: results.count { |r| r.status == "failed" },
          regressions: results.count(&:regression_detected?),
          avg_token_delta: calculate_average_token_delta(results),
          avg_latency_delta: calculate_average_latency_delta(results),
          quality_distribution: calculate_quality_distribution(results)
        }
      end

      private

      def calculate_average_token_delta(results)
        completed = results.select { |r| r.status == "completed" }
        return 0 if completed.empty?

        total_delta = completed.sum { |r| r.token_delta&.dig(:absolute) || 0 }
        (total_delta.to_f / completed.size).round(2)
      end

      def calculate_average_latency_delta(results)
        completed = results.select { |r| r.status == "completed" }
        return 0 if completed.empty?

        total_delta = completed.sum { |r| r.latency_delta&.dig(:absolute_ms) || 0 }
        (total_delta.to_f / completed.size).round(2)
      end

      def calculate_quality_distribution(results)
        completed = results.select { |r| r.status == "completed" }
        return {} if completed.empty?

        distribution = completed.group_by(&:quality_change)
        distribution.transform_values(&:count)
      end
    end
  end
end
