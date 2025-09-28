# frozen_string_literal: true

require 'date'
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
        # ============================================================================
        # PIPELINE IDENTIFICATION AND STRUCTURE
        # ============================================================================

        span name: ->(comp) { comp.respond_to?(:pipeline_name) ? comp.pipeline_name : comp.class.name }
        span class: ->(comp) { comp.class.name }

        # Flow structure and agent composition analysis
        span flow_structure: ->(comp) do
          if comp.respond_to?(:flow_structure_description) && comp.instance_variable_get(:@flow)
            comp.flow_structure_description(comp.instance_variable_get(:@flow))
          end
        end

        span total_agents: ->(comp) do
          if comp.respond_to?(:count_agents_in_flow) && comp.instance_variable_get(:@flow)
            comp.count_agents_in_flow(comp.instance_variable_get(:@flow))
          end
        end

        span execution_mode: ->(comp) do
          if comp.respond_to?(:detect_execution_mode) && comp.instance_variable_get(:@flow)
            comp.detect_execution_mode(comp.instance_variable_get(:@flow))
          end
        end

        # ============================================================================
        # PIPELINE CONTEXT AND DATA FLOW
        # ============================================================================

        # Initial context provided to the pipeline
        span initial_context: ->(comp) do
          context = comp.instance_variable_get(:@context)
          if context
            context_data = context.respond_to?(:to_h) ? context.to_h : context
            sanitized_data = sanitize_data(context_data)
            redact_sensitive_data(sanitized_data)
          else
            {}
          end
        end

        # Context field requirements
        span context_fields: ->(comp) { comp.class.respond_to?(:context_fields) ? comp.class.context_fields : [] }

        # ============================================================================
        # PIPELINE EXECUTION FLOW AND METRICS
        # ============================================================================

        # Agent execution sequence with detailed step information
        span execution_flow: ->(comp) do
          agent_results = comp.instance_variable_get(:@agent_results)
          next [] unless agent_results && agent_results.any?

          agent_results.map.with_index do |agent_result, index|
            sanitized_result = sanitize_data(agent_result)
            {
              "step_number" => index + 1,
              "agent_name" => sanitized_result[:agent_name] || "Agent #{index + 1}",
              "agent_class" => sanitized_result[:agent_class]&.to_s,
              "status" => sanitized_result[:success] ? "completed" : "failed",
              "execution_time_ms" => sanitized_result[:execution_time_ms],
              "input_summary" => sanitized_result[:input_summary],
              "output_summary" => sanitized_result[:output_summary]
            }.compact
          end
        end

        # Execution metrics and performance data
        span metrics: ->(comp) do
          agent_results = comp.instance_variable_get(:@agent_results)
          next {} unless agent_results && agent_results.any?

          total_execution_time = 0
          successful_agents = 0
          failed_agents = 0

          agent_results.each do |result|
            total_execution_time += result[:execution_time_ms] || 0
            if result[:success]
              successful_agents += 1
            else
              failed_agents += 1
            end
          end

          {
            "total_agents_executed" => agent_results.size,
            "successful_agents" => successful_agents,
            "failed_agents" => failed_agents,
            "total_execution_time_ms" => total_execution_time,
            "average_agent_time_ms" => agent_results.any? ? (total_execution_time / agent_results.size) : 0
          }
        end

        # Overall pipeline status
        span status: ->(comp) do
          agent_results = comp.instance_variable_get(:@agent_results)
          next "unknown" unless agent_results && agent_results.any?

          if agent_results.all? { |result| result[:success] }
            "completed"
          elsif agent_results.any? { |result| result[:success] }
            "partial_success"
          else
            "failed"
          end
        end

        # ============================================================================
        # PIPELINE EXECUTION RESULTS
        # ============================================================================

        # Final merged result from all agents
        result final_result: ->(result, comp) do
          if result.is_a?(Hash)
            sanitized_data = sanitize_data(result)
            redacted = redact_sensitive_data(sanitized_data)
            redacted
          else
            {}
          end
        end

        # High-level execution status based on result analysis
        result execution_status: ->(result, comp) { result.is_a?(Hash) && result[:success] ? "success" : "failure" }

        private

        # Sanitize data using Rails' built-in serializable_hash for ActiveRecord objects
        # This leverages Rails' battle-tested implementation for handling ActiveRecord serialization
        def self.sanitize_data(data)
          case data
          when defined?(ActiveRecord::Base) && ActiveRecord::Base
            # Use Rails' built-in method - it handles circular references automatically
            data.serializable_hash
          when Hash
            # Recursively sanitize hash values
            data.transform_values { |v| sanitize_data(v) }
          when Array
            # Recursively sanitize array items
            data.map { |item| sanitize_data(item) }
          when Time, Date, DateTime
            # Convert time objects to ISO strings
            data.respond_to?(:iso8601) ? data.iso8601 : data.to_s
          else
            # Basic types pass through unchanged
            data
          end
        rescue => e
          # Fallback if sanitization fails
          "[Sanitization error: #{e.message}]"
        end

        # Redact sensitive data from context/results
        def self.redact_sensitive_data(data)
          return data unless data.is_a?(Hash)

          redacted = {}
          data.each do |key, value|
            key_str = key.to_s.downcase
            if sensitive_key?(key_str)
              redacted[key] = "[REDACTED]"
            elsif value.is_a?(Hash)
              redacted[key] = redact_sensitive_data(value)
            elsif value.is_a?(Array) && value.any? { |v| v.is_a?(Hash) }
              redacted[key] = value.map { |v| v.is_a?(Hash) ? redact_sensitive_data(v) : v }
            else
              redacted[key] = value
            end
          end
          redacted
        end

        # Check if key contains sensitive information
        def self.sensitive_key?(key)
          sensitive_patterns = %w[
            password token secret key api_key auth credential
            email phone ssn social_security credit_card
          ]
          sensitive_patterns.any? { |pattern| key.include?(pattern) }
        end
      end
    end
  end
end
