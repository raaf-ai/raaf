# frozen_string_literal: true

require "active_record"
require "json"
require "matrix"

# Load raaf-core and raaf-tracing if not already loaded
begin
  require "raaf-core"
rescue LoadError
  # Try relative path for mono-repo development
  require_relative "../../core/lib/raaf-core"
end

begin
  require "raaf-tracing"
rescue LoadError
  # Try relative path for mono-repo development
  require_relative "../../tracing/lib/raaf-tracing"
end

# Load version first
require_relative "raaf/eval/version"

# Load core utilities and configuration
require_relative "raaf/eval/errors"
require_relative "raaf/eval/configuration"

# Load database models
require_relative "raaf/eval/models/evaluation_run"
require_relative "raaf/eval/models/evaluation_span"
require_relative "raaf/eval/models/evaluation_configuration"
require_relative "raaf/eval/models/evaluation_result"

# Load serialization components
require_relative "raaf/eval/span_serializer"
require_relative "raaf/eval/span_deserializer"
require_relative "raaf/eval/span_accessor"

# Load evaluation engine
require_relative "raaf/eval/evaluation_engine"

# Load metrics system
require_relative "raaf/eval/metrics/token_metrics"
require_relative "raaf/eval/metrics/latency_metrics"
require_relative "raaf/eval/metrics/accuracy_metrics"
require_relative "raaf/eval/metrics/structural_metrics"
require_relative "raaf/eval/metrics/ai_comparator"
require_relative "raaf/eval/metrics/statistical_analyzer"
require_relative "raaf/eval/metrics/custom_metric"

# Load comparison and storage
require_relative "raaf/eval/baseline_comparator"
require_relative "raaf/eval/result_store"

##
# RAAF Eval - AI agent evaluation and testing framework
#
# This gem provides comprehensive evaluation capabilities for RAAF agents,
# enabling systematic testing and validation of agent behavior across
# different LLM configurations, parameters, and prompts.
#
# == Core Features
#
# * Span serialization and deserialization for test reproduction
# * Evaluation engine for re-executing agents with modified configurations
# * Quantitative metrics (tokens, latency, accuracy, structural)
# * Qualitative AI-powered comparison (semantic similarity, bias, hallucinations)
# * Statistical analysis (confidence intervals, significance testing, effect size)
# * Baseline comparison and regression detection
# * Custom metrics interface for domain-specific KPIs
#
# == Quick Start
#
#   require 'raaf-eval'
#
#   # Initialize database connection
#   RAAF::Eval.configure do |config|
#     config.database_url = ENV['DATABASE_URL']
#   end
#
#   # Serialize a span from production
#   span_accessor = RAAF::Eval::SpanAccessor.new
#   baseline_span = span_accessor.find_by_id("span_123")
#   serialized = RAAF::Eval::SpanSerializer.serialize(baseline_span)
#
#   # Create evaluation run with different configurations
#   engine = RAAF::Eval::EvaluationEngine.new
#   run = engine.create_run(
#     name: "Model Comparison Test",
#     baseline_span: serialized,
#     configurations: [
#       { name: "GPT-4", changes: { model: "gpt-4o" } },
#       { name: "Claude", changes: { model: "claude-3-5-sonnet-20241022", provider: "anthropic" } }
#     ]
#   )
#
#   # Execute evaluations
#   results = engine.execute_run(run)
#
#   # Access metrics and comparison
#   results.each do |result|
#     puts "#{result.configuration.name}: #{result.token_metrics[:total_tokens]} tokens"
#     puts "Quality change: #{result.baseline_comparison[:quality_change]}"
#     puts "Regression detected: #{result.baseline_comparison[:regression_detected]}"
#   end
#
# @author RAAF Eval Team
# @since 0.1.0
module RAAF
  module Eval

    # Eval gem version
    EVAL_VERSION = VERSION

    class << self
      # @return [RAAF::Eval::Configuration] The global configuration
      attr_writer :configuration

      ##
      # Get the global configuration instance
      #
      # @return [RAAF::Eval::Configuration]
      def configuration
        @configuration ||= Configuration.new
      end

      ##
      # Configure RAAF Eval with a block
      #
      # @yield [config] Configuration block
      # @yieldparam config [RAAF::Eval::Configuration]
      #
      # @example
      #   RAAF::Eval.configure do |config|
      #     config.database_url = ENV['DATABASE_URL']
      #     config.ai_comparator_model = "gpt-4o"
      #   end
      def configure
        yield(configuration)
      end

      ##
      # Get the logger instance
      #
      # @return [Logger]
      def logger
        configuration.logger
      end
    end
  end
end
