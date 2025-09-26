# frozen_string_literal: true

require_relative "base_collector"

module RAAF
  module Tracing
    module SpanCollectors
      # Specialized collector for Pipeline components that captures multi-agent
      # orchestration details, flow structure, and execution context. This collector
      # provides visibility into complex agent workflows and their coordination patterns.
      #
      # @example Basic usage with RAAF pipeline
      #   class DataProcessingPipeline < RAAF::Pipeline
      #     flow DataAnalyzer >> ReportGenerator
      #     context do
      #       required :input_data
      #       optional format_type: "json"
      #     end
      #   end
      #
      #   pipeline = DataProcessingPipeline.new(input_data: "sales data")
      #   collector = PipelineCollector.new
      #   attributes = collector.collect_attributes(pipeline)
      #   result_attrs = collector.collect_result(pipeline, execution_result)
      #
      # @example Captured pipeline information
      #   # Pipeline identification and structure
      #   attributes["pipeline.name"]  # => "DataProcessingPipeline"
      #   attributes["pipeline.flow_structure"]  # => "DataAnalyzer >> ReportGenerator"
      #   attributes["pipeline.agent_count"]  # => 2
      #
      #   # Context and configuration
      #   attributes["pipeline.context_fields"]  # => ["input_data", "format_type"]
      #
      #   # Execution results
      #   result_attrs["result.execution_status"]  # => "success"
      #
      # @example Integration with tracing system
      #   tracer = RAAF::Tracing::SpanTracer.new
      #   pipeline = DataProcessingPipeline.new(data: raw_data)
      #   result = pipeline.run
      #   # Pipeline orchestration automatically traced with flow visibility
      #
      # @note Flow structures capture the agent chaining patterns (>> for sequential, | for parallel)
      # @note Agent counting helps understand pipeline complexity
      # @note Context fields show the data requirements for pipeline execution
      # @note Execution status provides high-level success/failure information
      #
      # @see BaseCollector For DSL methods and common attribute handling
      # @see AgentCollector For individual agent tracing within pipelines
      # @see RAAF::Pipeline The component type this collector specializes in tracing
      #
      # @since 1.0.0
      # @author RAAF Team
      class PipelineCollector < BaseCollector
        # Pipeline identification and naming
        span name: ->(comp) { comp.respond_to?(:pipeline_name) ? comp.pipeline_name : comp.class.name }

        # Flow structure and agent composition analysis
        span flow_structure: ->(comp) do
          if comp.respond_to?(:flow_structure_description) && comp.instance_variable_get(:@flow)
            comp.flow_structure_description(comp.instance_variable_get(:@flow))
          end
        end
        span agent_count: ->(comp) do
          if comp.respond_to?(:count_agents_in_flow) && comp.instance_variable_get(:@flow)
            comp.count_agents_in_flow(comp.instance_variable_get(:@flow))
          end
        end

        # Context requirements and configuration
        span context_fields: ->(comp) { comp.class.respond_to?(:context_fields) ? comp.class.context_fields : [] }

        # ============================================================================
        # PIPELINE EXECUTION RESULTS
        # These attributes capture pipeline execution outcomes and status information.
        # ============================================================================

        # High-level execution status based on result analysis
        # @return [String] "success" or "failure" based on result structure
        result execution_status: ->(result, comp) { result.is_a?(Hash) && result[:success] ? "success" : "failure" }
      end
    end
  end
end
