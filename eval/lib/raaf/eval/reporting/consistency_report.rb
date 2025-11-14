# frozen_string_literal: true

require 'json'

module RAAF
  module Eval
    module Reporting
      # Unified interface for consistency reporting
      #
      # Provides a high-level API for generating consistency reports from
      # multiple evaluation runs with support for different output formats.
      #
      # @example Basic usage
      #   results = 3.times.map { agent.run }
      #   report = ConsistencyReport.new(results)
      #   report.generate  # Prints formatted console output
      #
      # @example JSON export
      #   report = ConsistencyReport.new(results)
      #   json_data = report.to_json
      #   File.write('report.json', json_data)
      #
      # @example Custom tolerance
      #   report = ConsistencyReport.new(results, tolerance: 15)
      #   report.generate
      #
      class ConsistencyReport
        attr_reader :aggregator, :analyzer, :reporter

        # Initialize consistency report
        #
        # @param evaluation_results [Array<Hash>] Array of evaluation run results
        # @param tolerance [Integer] Maximum acceptable variance (default: 12)
        # @param reporter [Symbol] Reporter type (:console, :json, :csv)
        def initialize(evaluation_results, tolerance: 12, reporter: :console)
          @aggregator = MultiRunAggregator.new(evaluation_results)
          @analyzer = ConsistencyAnalyzer.new(@aggregator, tolerance: tolerance)
          @reporter = create_reporter(reporter)
        end

        # Generate formatted report
        #
        # @return [void] Prints report to stdout (for console reporter)
        def generate
          @reporter.generate
        end

        # Export report data as JSON
        #
        # @return [String] JSON representation of report data
        def to_json(*_args)
          {
            metadata: {
              total_runs: @aggregator.runs.size,
              tolerance: @analyzer.tolerance,
              generated_at: Time.now.iso8601
            },
            consistency_analysis: @analyzer.analyze_all_fields,
            performance_summary: @aggregator.performance_summary
          }.to_json
        end

        # Export report data as CSV
        #
        # @return [String] CSV representation of consistency analysis
        def to_csv
          require 'csv'

          CSV.generate do |csv|
            # Header row
            csv << %w[field_name mean min max range std_dev variance_status sample_size]

            # Data rows
            @analyzer.analyze_all_fields.each do |field_name, analysis|
              csv << [
                field_name,
                analysis[:mean].round(2),
                analysis[:min],
                analysis[:max],
                analysis[:range],
                analysis[:std_dev].round(2),
                analysis[:variance_status],
                analysis[:sample_size]
              ]
            end
          end
        end

        # Get analysis summary
        #
        # @return [Hash] Summary of consistency analysis
        def summary
          {
            total_runs: @aggregator.runs.size,
            success_rate: @aggregator.performance_summary[:success_rate],
            fields_analyzed: @analyzer.analyze_all_fields.size,
            high_variance_fields: high_variance_fields_count
          }
        end

        private

        # Create appropriate reporter based on type
        #
        # @param type [Symbol] Reporter type
        # @return [Object] Reporter instance
        def create_reporter(type)
          case type
          when :console
            ConsoleReporter.new(@aggregator, @analyzer)
          when :json
            # JSON reporter would be implemented here
            # For now, use console as fallback
            ConsoleReporter.new(@aggregator, @analyzer)
          when :csv
            # CSV reporter would be implemented here
            # For now, use console as fallback
            ConsoleReporter.new(@aggregator, @analyzer)
          else
            ConsoleReporter.new(@aggregator, @analyzer)
          end
        end

        # Count fields with high variance
        #
        # @return [Integer] Number of fields with high variance
        def high_variance_fields_count
          @analyzer.analyze_all_fields.count do |_field_name, analysis|
            analysis[:variance_status] == :high_variance
          end
        end
      end
    end
  end
end
