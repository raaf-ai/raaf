# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # EvaluationMetric stores pre-aggregated metrics for fast dashboard queries.
      # Supports hourly, daily, and weekly aggregation periods.
      class EvaluationMetric < ActiveRecord::Base
        self.table_name = "raaf_evaluation_metrics"

        # Validations
        validates :agent_name, presence: true
        validates :period_type, presence: true, inclusion: { in: %w[hourly daily weekly] }
        validates :period_start, presence: true
        validates :agent_name, uniqueness: {
          scope: [:environment, :model, :evaluator_name, :period_type, :period_start],
          message: "already has metrics for this period"
        }

        # Scopes
        scope :for_agent, ->(name) { where(agent_name: name) }
        scope :for_environment, ->(env) { where(environment: env) }
        scope :for_model, ->(model) { where(model: model) }
        scope :for_evaluator, ->(name) { where(evaluator_name: name) }
        scope :hourly, -> { where(period_type: "hourly") }
        scope :daily, -> { where(period_type: "daily") }
        scope :weekly, -> { where(period_type: "weekly") }
        scope :in_period_range, ->(start_date, end_date) { where(period_start: start_date..end_date) }
        scope :recent, -> { order(period_start: :desc) }

        ##
        # Calculate pass rate (passed + warning / total)
        # @return [Float] Rate between 0 and 1
        def pass_rate
          return 0 if total_evaluations.zero?
          success_count.to_f / total_evaluations
        end

        ##
        # Calculate fail rate (failed + error / total)
        # @return [Float] Rate between 0 and 1
        def fail_rate
          return 0 if total_evaluations.zero?
          failure_count.to_f / total_evaluations
        end

        ##
        # Get count of successful evaluations (passed + warning)
        # @return [Integer]
        def success_count
          (passed_count || 0) + (warning_count || 0)
        end

        ##
        # Get count of failed evaluations (failed + error)
        # @return [Integer]
        def failure_count
          (failed_count || 0) + (error_count || 0)
        end

        class << self
          ##
          # Upsert metrics for a period
          # @param dimensions [Hash] Dimension columns for lookup
          # @param metrics [Hash] Metric values to set
          # @return [EvaluationMetric]
          def upsert_for_period(dimensions, metrics)
            record = find_or_initialize_by(dimensions)
            record.assign_attributes(metrics)
            record.save!
            record
          end

          ##
          # Increment metrics for a period
          # @param dimensions [Hash] Dimension columns for lookup
          # @param increments [Hash] Values to increment
          # @return [EvaluationMetric]
          def increment_for_period(dimensions, increments)
            record = find_or_create_by!(dimensions)
            increments.each do |key, value|
              record.increment!(key, value)
            end
            record.reload
          end

          ##
          # Aggregate metrics from evaluation results
          # @param results [ActiveRecord::Relation] Results to aggregate
          # @param dimensions [Hash] Dimension values for the metric
          # @return [EvaluationMetric]
          def aggregate_from_results(results, **dimensions)
            scores = results.where.not(score: nil).pluck(:score)

            metrics = {
              total_evaluations: results.count,
              passed_count: results.where(status: "passed").count,
              failed_count: results.where(status: "failed").count,
              warning_count: results.where(status: "warning").count,
              error_count: results.where(status: "error").count,
              avg_score: scores.any? ? scores.sum / scores.size : nil,
              min_score: scores.min,
              max_score: scores.max,
              stddev_score: calculate_stddev(scores),
              avg_evaluation_duration_ms: results.average(:evaluation_duration_ms),
              score_distribution: build_score_distribution(results)
            }

            # Add percentiles
            percentiles = calculate_percentiles(results)
            metrics.merge!(
              p50_score: percentiles[:p50],
              p90_score: percentiles[:p90],
              p95_score: percentiles[:p95]
            )

            upsert_for_period(dimensions, metrics)
          end

          ##
          # Calculate percentiles from results
          # @param results [ActiveRecord::Relation]
          # @return [Hash]
          def calculate_percentiles(results)
            scores = results.where.not(score: nil).order(:score).pluck(:score)
            return { p50: nil, p90: nil, p95: nil } if scores.empty?

            {
              p50: percentile(scores, 50),
              p90: percentile(scores, 90),
              p95: percentile(scores, 95)
            }
          end

          ##
          # Build score distribution histogram
          # @param results [ActiveRecord::Relation]
          # @return [Hash]
          def build_score_distribution(results)
            buckets = (0..9).map { |i| ["#{i / 10.0}-#{(i + 1) / 10.0}", 0] }.to_h

            results.where.not(score: nil).pluck(:score).each do |score|
              bucket_index = [(score * 10).floor, 9].min
              bucket_key = "#{bucket_index / 10.0}-#{(bucket_index + 1) / 10.0}"
              buckets[bucket_key] += 1
            end

            buckets
          end

          private

          def percentile(sorted_array, percent)
            return nil if sorted_array.empty?

            k = (percent / 100.0) * (sorted_array.size - 1)
            f = k.floor
            c = k.ceil

            return sorted_array[k.round] if f == c

            sorted_array[f] * (c - k) + sorted_array[c] * (k - f)
          end

          def calculate_stddev(values)
            return nil if values.empty? || values.size < 2

            mean = values.sum / values.size
            variance = values.sum { |v| (v - mean) ** 2 } / (values.size - 1)
            Math.sqrt(variance)
          end
        end
      end
    end
  end
end
