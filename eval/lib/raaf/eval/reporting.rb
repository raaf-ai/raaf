# frozen_string_literal: true

# RAAF Eval Reporting Module
#
# Provides consistency reporting and analysis for multi-run evaluations.
#
# @example Basic usage
#   require 'raaf/eval'
#   require 'raaf/eval/reporting'
#
#   # Run multiple evaluations
#   results = 3.times.map { Eval::Prospect::Scoring.evaluate_agent_run(agent) }
#
#   # Generate consistency report
#   report = RAAF::Eval::Reporting::ConsistencyReport.new(results, tolerance: 12)
#   report.generate
#
# @example JSON export
#   report = RAAF::Eval::Reporting::ConsistencyReport.new(results)
#   json_data = report.to_json
#   File.write('consistency_report.json', json_data)
#
# @example CSV export
#   report = RAAF::Eval::Reporting::ConsistencyReport.new(results)
#   csv_data = report.to_csv
#   File.write('consistency_report.csv', csv_data)
#
module RAAF
  module Eval
    module Reporting
      # Load reporting components
      require_relative 'reporting/multi_run_aggregator'
      require_relative 'reporting/consistency_analyzer'
      require_relative 'reporting/console_reporter'
      require_relative 'reporting/consistency_report'

      # Load domain-specific output reporting (for prospect scoring, etc.)
      require_relative 'reporting/domain_output_aggregator'
      require_relative 'reporting/domain_output_reporter'
    end
  end
end
