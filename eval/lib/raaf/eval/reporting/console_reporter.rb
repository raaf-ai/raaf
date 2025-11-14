# frozen_string_literal: true

module RAAF
  module Eval
    module Reporting
      # Generates formatted console output for consistency reports
      #
      # @example
      #   aggregator = MultiRunAggregator.new(results)
      #   analyzer = ConsistencyAnalyzer.new(aggregator)
      #   reporter = ConsoleReporter.new(aggregator, analyzer)
      #   reporter.generate
      #
      class ConsoleReporter
        # Emoji indicators for status
        EMOJI = {
          perfect: "✅",
          acceptable: "⚠️",
          high_variance: "❌",
          success: "✅",
          failure: "❌",
          info: "📊"
        }.freeze

        attr_reader :aggregator, :analyzer

        # Initialize reporter with aggregator and analyzer
        #
        # @param aggregator [MultiRunAggregator] Result aggregator
        # @param analyzer [ConsistencyAnalyzer] Consistency analyzer
        def initialize(aggregator, analyzer)
          @aggregator = aggregator
          @analyzer = analyzer
        end

        # Generate complete consistency report
        #
        # @return [void] Prints formatted report to stdout
        def generate
          print_header
          print_consistency_analysis
          print_performance_summary
          print_overall_assessment
        end

        private

        # Print report header
        def print_header
          puts "=" * 80
          puts "CONSISTENCY ANALYSIS (Across #{@aggregator.runs.size} runs)"
          puts "=" * 80
          puts ""
        end

        # Print consistency analysis for all fields
        def print_consistency_analysis
          @analyzer.analyze_all_fields.each do |field_name, analysis|
            next unless analysis

            status_emoji = EMOJI[analysis[:variance_status]] || "❓"

            puts "#{status_emoji} #{field_name}"
            puts "  Score Range: #{analysis[:min]}-#{analysis[:max]} (std dev: #{analysis[:std_dev].round(1)})"
            puts "  Average: #{analysis[:mean].round(1)}"

            case analysis[:variance_status]
            when :perfect
              puts "  ✨ Perfect consistency across all runs"
            when :acceptable
              puts "  #{EMOJI[:info]} Good consistency (variance ≤#{@analyzer.tolerance})"
            when :high_variance
              puts "  ⚠️ High variance detected (>#{@analyzer.tolerance} points)"
            end
            puts ""
          end
        end

        # Print performance summary
        def print_performance_summary
          summary = @aggregator.performance_summary
          latencies = summary[:latencies]
          tokens = summary[:tokens]

          puts "Performance Summary:"
          puts "-" * 80

          if latencies.any?
            avg_latency = latencies.sum / latencies.size
            puts "Latency: avg #{avg_latency}ms, min #{latencies.min}ms, max #{latencies.max}ms"
          else
            puts "Latency: No data available"
          end

          if tokens.any?
            avg_tokens = tokens.sum / tokens.size
            puts "Tokens: avg #{avg_tokens}, min #{tokens.min}, max #{tokens.max}"
          else
            puts "Tokens: No data available (incremental processing)"
          end

          puts "Success Rate: #{(summary[:success_rate] * 100).round}%"
          puts ""
        end

        # Print overall assessment
        def print_overall_assessment
          summary = @aggregator.performance_summary
          all_passed = summary[:success_rate] == 1.0
          status_emoji = all_passed ? EMOJI[:success] : EMOJI[:failure]

          puts "=" * 80
          puts "Overall: #{status_emoji} #{all_passed ? 'ALL RUNS PASSED' : 'SOME RUNS FAILED'}"
          puts "=" * 80
        end
      end
    end
  end
end
