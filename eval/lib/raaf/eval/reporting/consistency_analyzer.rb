# frozen_string_literal: true

module RAAF
  module Eval
    module Reporting
      # Analyzes consistency of evaluation results across multiple runs
      #
      # @example
      #   aggregator = MultiRunAggregator.new(results)
      #   analyzer = ConsistencyAnalyzer.new(aggregator, tolerance: 12)
      #   analysis = analyzer.analyze_field(:individual_scores)
      #   # => { mean: 79.0, min: 78, max: 80, range: 2, std_dev: 0.8, variance_status: :perfect }
      #
      class ConsistencyAnalyzer
        # Variance status thresholds
        VARIANCE_THRESHOLDS = {
          perfect: 0,
          acceptable: 12,  # Default tolerance
          high_variance: Float::INFINITY
        }.freeze

        attr_reader :aggregator, :tolerance

        # Initialize analyzer with aggregator and tolerance
        #
        # @param aggregator [MultiRunAggregator] Result aggregator
        # @param tolerance [Integer] Maximum acceptable variance (default: 12)
        def initialize(aggregator, tolerance: 12)
          @aggregator = aggregator
          @tolerance = tolerance
        end

        # Analyze consistency for a specific field
        #
        # @param field_name [Symbol, String] Field name to analyze
        # @return [Hash] Analysis results with mean, min, max, range, std_dev, variance_status
        def analyze_field(field_name)
          values = @aggregator.field_values(field_name)

          return nil_analysis if values.empty?

          {
            field_name: field_name.to_sym,
            mean: calculate_mean(values),
            min: values.min,
            max: values.max,
            range: values.max - values.min,
            std_dev: calculate_std_dev(values),
            variance_status: variance_status(values.max - values.min),
            sample_size: values.size
          }
        end

        # Analyze all fields for consistency
        #
        # @return [Hash<Symbol, Hash>] Analysis results for all fields
        def analyze_all_fields
          @aggregator.results_by_field.transform_values do |field_results|
            # Extract field name from first result
            field_name = field_results.first&.keys&.first
            analyze_field(field_name) if field_name
          end.compact
        end

        # Get variance status for a given range
        #
        # @param range [Numeric] Score range
        # @return [Symbol] :perfect, :acceptable, or :high_variance
        def variance_status(range)
          case range
          when 0
            :perfect
          when 1..@tolerance
            :acceptable
          else
            :high_variance
          end
        end

        private

        # Calculate mean of values
        #
        # @param values [Array<Numeric>] Values to analyze
        # @return [Float] Mean value
        def calculate_mean(values)
          return 0.0 if values.empty?
          values.sum.to_f / values.size
        end

        # Calculate standard deviation
        #
        # @param values [Array<Numeric>] Values to analyze
        # @return [Float] Standard deviation
        def calculate_std_dev(values)
          return 0.0 if values.size < 2

          mean = calculate_mean(values)
          variance = values.sum { |v| (v - mean)**2 } / values.size.to_f
          Math.sqrt(variance)
        end

        # Return nil analysis for empty values
        #
        # @return [Hash] Nil analysis structure
        def nil_analysis
          {
            mean: 0.0,
            min: 0,
            max: 0,
            range: 0,
            std_dev: 0.0,
            variance_status: :unknown,
            sample_size: 0
          }
        end
      end
    end
  end
end
