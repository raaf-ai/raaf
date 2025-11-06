# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # EvaluationSpan stores complete serialized span data for baseline and evaluation runs.
      class EvaluationSpan < ActiveRecord::Base
        self.table_name = "evaluation_spans"

        # Associations
        belongs_to :evaluation_run, optional: true, class_name: "RAAF::Eval::Models::EvaluationRun"

        # Validations
        validates :span_id, presence: true, uniqueness: true
        validates :trace_id, presence: true
        validates :span_type, presence: true, inclusion: { in: %w[agent response tool handoff] }
        validates :span_data, presence: true
        validates :source, presence: true, inclusion: { in: %w[production_trace evaluation_run manual_upload] }

        # Scopes
        scope :by_type, ->(type) { where(span_type: type) }
        scope :by_source, ->(source) { where(source: source) }
        scope :by_trace, ->(trace_id) { where(trace_id: trace_id) }
        scope :production_spans, -> { where(source: "production_trace") }
        scope :evaluation_spans, -> { where(source: "evaluation_run") }

        ##
        # Get agent name from span data
        # @return [String, nil]
        def agent_name
          span_data&.dig("agent_name")
        end

        ##
        # Get model from span data
        # @return [String, nil]
        def model
          span_data&.dig("model")
        end

        ##
        # Get input messages from span data
        # @return [Array<Hash>]
        def input_messages
          span_data&.dig("input_messages") || []
        end

        ##
        # Get output messages from span data
        # @return [Array<Hash>]
        def output_messages
          span_data&.dig("output_messages") || []
        end

        ##
        # Get token count from metadata
        # @return [Integer, nil]
        def total_tokens
          span_data&.dig("metadata", "tokens")
        end

        ##
        # Get latency from metadata
        # @return [Integer, nil]
        def latency_ms
          span_data&.dig("metadata", "latency_ms")
        end
      end
    end
  end
end
