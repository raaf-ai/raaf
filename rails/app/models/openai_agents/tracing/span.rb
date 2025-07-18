# frozen_string_literal: true

module RAAF
  module Tracing
    # ActiveRecord model for storing span data
    #
    # A span represents a single operation within a trace. Each span captures:
    #
    # - Operation timing and duration
    # - Status and error information
    # - Attributes and events
    # - Parent-child relationships
    # - Operation-specific metadata
    #
    # ## Usage
    #
    # Spans are typically created automatically by the ActiveRecordProcessor.
    # They can be queried for analysis and debugging:
    #
    # @example Find slow spans
    #   RAAF::Tracing::Span.slow(threshold: 1000) # > 1 second
    #
    # @example Find error spans
    #   RAAF::Tracing::Span.errors.recent
    #
    # @example Find spans by operation type
    #   RAAF::Tracing::Span.by_kind('llm')
    #
    # @example Get span performance metrics
    #   RAAF::Tracing::Span.performance_metrics('tool')
    class SpanRecord < ActiveRecord::Base
      self.table_name = "raaf_tracing_spans"

      # Associations
      belongs_to :trace, primary_key: :trace_id, foreign_key: :trace_id,
                         class_name: "RAAF::Tracing::TraceRecord", optional: true
      belongs_to :parent_span, class_name: "RAAF::Tracing::SpanRecord",
                               primary_key: :span_id, foreign_key: :parent_id, optional: true
      has_many :children, class_name: "RAAF::Tracing::SpanRecord",
                          primary_key: :span_id, foreign_key: :parent_id

      # Validations
      validates :span_id, presence: true, uniqueness: true,
                          format: {
                            with: /\Aspan_[a-zA-Z0-9]{24}\z/,
                            message: "must be in format 'span_<24_alphanumeric>'"
                          }
      validates :trace_id, presence: true,
                           format: {
                             with: /\Atrace_[a-zA-Z0-9]{32}\z/,
                             message: "must be in format 'trace_<32_alphanumeric>'"
                           }
      validates :name, presence: true, length: { maximum: 255 }
      validates :kind, inclusion: {
        in: %w[agent llm tool handoff guardrail mcp_list_tools response
               speech_group speech transcription custom internal trace]
      }
      validates :status, inclusion: { in: %w[ok error cancelled] }

      # Callbacks
      before_validation :ensure_span_id
      before_validation :set_defaults
      after_save :update_trace_status
      after_destroy :update_trace_status

      # Scopes
      scope :recent, -> { order(start_time: :desc) }
      scope :by_kind, ->(kind) { where(kind: kind) }
      scope :by_status, ->(status) { where(status: status) }
      scope :errors, -> { where(status: "error") }
      scope :successful, -> { where(status: "ok") }
      scope :slow, ->(threshold_ms = 1000) { where("duration_ms > ?", threshold_ms) }
      scope :within_timeframe, lambda { |start_time, end_time|
        where(start_time: start_time..end_time)
      }
      scope :root_spans, -> { where(parent_id: nil) }
      scope :child_spans, -> { where.not(parent_id: nil) }

      # JSON serialization for complex fields
      serialize :span_attributes, coder: JSON if respond_to?(:serialize)
      serialize :events, coder: JSON if respond_to?(:serialize)

      # Class methods for analytics
      class << self
        # Get performance metrics for spans of a specific kind
        #
        # @param kind [String, nil] Span kind to analyze
        # @param timeframe [Range, nil] Time range to analyze
        # @return [Hash] Performance statistics
        def performance_metrics(kind: nil, timeframe: nil)
          query = all.reorder(nil)
          query = query.by_kind(kind) if kind
          query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe

          {
            total_spans: query.count,
            successful_spans: query.successful.count,
            error_spans: query.errors.count,
            avg_duration_ms: query.average(:duration_ms)&.round(2),
            p95_duration_ms: query.percentile(:duration_ms, 0.95)&.round(2),
            p99_duration_ms: query.percentile(:duration_ms, 0.99)&.round(2),
            success_rate: query.any? ? (query.successful.count.to_f / query.count * 100).round(2) : 0
          }
        end

        # Calculate percentile for a given column
        # Note: This is PostgreSQL-specific. For other databases, you might need different syntax.
        #
        # @param column [Symbol] Column to calculate percentile for
        # @param percentile [Float] Percentile to calculate (0.0 to 1.0)
        # @return [Float, nil] Percentile value
        def percentile(column, percentile)
          return nil if count == 0

          # PostgreSQL syntax - adjust for other databases as needed
          if connection.adapter_name.downcase.include?("postgresql")
            # Use unscope to remove any ordering/grouping that might conflict
            unscope(:order, :group, :select)
              .select("PERCENTILE_CONT(#{percentile}) WITHIN GROUP (ORDER BY #{column}) as percentile_value")
              .first&.percentile_value
          else
            # Fallback for other databases
            ordered_values = order(column).pluck(column).compact
            return nil if ordered_values.empty?

            index = (percentile * (ordered_values.length - 1)).round
            ordered_values[index]
          end
        end

        # Get error analysis
        #
        # @param timeframe [Range, nil] Time range to analyze
        # @return [Hash] Error statistics
        def error_analysis(timeframe: nil)
          query = errors.reorder(nil)
          query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe

          error_spans = query.includes(:trace)

          # Get errors by workflow using a PostgreSQL-compatible approach
          errors_by_workflow = {}
          if error_spans.any?
            # Use pluck to get the raw data, then group and count in Ruby
            workflow_data = error_spans.joins(:trace)
                                       .pluck("raaf_tracing_traces.workflow_name", "raaf_tracing_spans.id") # rubocop:disable Layout/LineLength

            # Group by workflow name and count unique span IDs
            workflow_data.group_by(&:first).each do |workflow_name, entries|
              errors_by_workflow[workflow_name] = entries.map(&:last).uniq.count
            end
          end

          {
            total_errors: error_spans.count,
            errors_by_kind: error_spans.reorder(nil).group(:kind).count,
            errors_by_workflow: errors_by_workflow,
            recent_errors: error_spans.reorder(start_time: :desc).limit(10).map(&:error_summary)
          }
        end

        # Get cost analysis for LLM spans
        #
        # @param timeframe [Range, nil] Time range to analyze
        # @return [Hash] Cost analysis
        def cost_analysis(timeframe: nil)
          query = by_kind("llm").unscope(:order)
          query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe

          # Force evaluation to array to avoid any ordering/grouping issues
          llm_spans = query.select(:id, :span_attributes).to_a

          total_input_tokens = llm_spans.sum do |span|
            span.span_attributes.dig("llm", "usage", "input_tokens").to_i
          end

          total_output_tokens = llm_spans.sum do |span|
            span.span_attributes.dig("llm", "usage", "output_tokens").to_i
          end

          models_usage = llm_spans.group_by do |span|
            span.span_attributes.dig("llm", "request", "model")
          end.transform_values(&:count)

          {
            total_llm_calls: llm_spans.count,
            total_input_tokens: total_input_tokens,
            total_output_tokens: total_output_tokens,
            total_tokens: total_input_tokens + total_output_tokens,
            models_usage: models_usage,
            avg_tokens_per_call: if llm_spans.any?
                                   ((total_input_tokens + total_output_tokens).to_f / llm_spans.count).round(2)
                                 else
                                   0
                                 end
          }
        end

        # Clean up old spans based on retention policy
        #
        # @param older_than [ActiveSupport::Duration] Delete spans older than this
        # @return [Integer] Number of spans deleted
        def cleanup_old_spans(older_than: 30.days)
          where("start_time < ?", older_than.ago).delete_all
        end
      end

      # Instance methods

      # Check if span has errors
      #
      # @return [Boolean] True if span status is error
      def error?
        status == "error"
      end

      # Check if span completed successfully
      #
      # @return [Boolean] True if span status is ok
      def successful?
        status == "ok"
      end

      # Get span duration in seconds
      #
      # @return [Float, nil] Duration or nil if not available
      def duration_seconds
        duration_ms&./(1000.0)
      end

      # Check if this is a root span (no parent)
      #
      # @return [Boolean] True if no parent span
      def root_span?
        parent_id.nil?
      end

      # Get all child span IDs
      #
      # @return [Array<String>] Array of child span IDs
      def child_span_ids
        children.pluck(:span_id)
      end

      # Get span depth in the hierarchy
      #
      # @return [Integer] Depth level (0 for root spans)
      def depth
        return 0 if root_span?

        parent_span&.depth&.+(1) || 1
      end

      # Get error details if span failed
      #
      # @return [Hash, nil] Error information
      def error_details
        return nil unless error?

        {
          status_description: span_attributes&.dig("status", "description"),
          exception_type: events&.find { |e| e["name"] == "exception" }&.dig("attributes", "exception.type"),
          exception_message: events&.find { |e| e["name"] == "exception" }&.dig("attributes", "exception.message"),
          exception_stacktrace: events&.find { |e| e["name"] == "exception" }&.dig("attributes", "exception.stacktrace")
        }.compact
      end

      # Get summary of span for error reporting
      #
      # @return [Hash] Span summary
      def error_summary
        {
          span_id: span_id,
          trace_id: trace_id,
          name: name,
          kind: kind,
          start_time: start_time,
          duration_ms: duration_ms,
          error_details: error_details
        }
      end

      # Get operation-specific details based on span kind
      #
      # @return [Hash] Kind-specific attributes
      def operation_details
        case kind
        when "llm"
          {
            model: span_attributes&.dig("llm", "request", "model"),
            input_tokens: span_attributes&.dig("llm", "usage", "input_tokens"),
            output_tokens: span_attributes&.dig("llm", "usage", "output_tokens"),
            messages: span_attributes&.dig("llm", "request", "messages")
          }
        when "tool"
          {
            function_name: span_attributes&.dig("function", "name"),
            input: span_attributes&.dig("function", "input"),
            output: span_attributes&.dig("function", "output")
          }
        when "agent"
          {
            agent_name: span_attributes&.dig("agent", "name"),
            tools: span_attributes&.dig("agent", "tools"),
            handoffs: span_attributes&.dig("agent", "handoffs")
          }
        when "handoff"
          {
            from_agent: span_attributes&.dig("handoff", "from"),
            to_agent: span_attributes&.dig("handoff", "to")
          }
        else
          span_attributes&.slice("name", "data") || {}
        end.compact
      end

      # Get all events of a specific type
      #
      # @param event_name [String] Name of event to filter by
      # @return [Array<Hash>] Matching events
      def events_by_name(event_name)
        (events || []).select { |e| e["name"] == event_name }
      end

      # Get timeline of events within this span
      #
      # @return [Array<Hash>] Chronological list of events
      def event_timeline
        (events || []).sort_by { |e| e["timestamp"] }
      end

      private

      # Ensure span_id is set
      def ensure_span_id
        return if span_id.present?

        self.span_id = "span_#{SecureRandom.hex(12)}" # 24 character hex
      end

      # Set default values
      def set_defaults
        self.status = "ok" if status.blank?
        self.kind = "internal" if kind.blank?
        self.span_attributes = {} if span_attributes.blank?
        self.events = [] if events.blank?
      end

      # Update associated trace status after span changes
      def update_trace_status
        trace&.update_trace_status
      rescue StandardError => e
        ::Rails.logger.warn "[Ruby AI Agents Factory Tracing] Failed to update trace status: #{e.message}"
      end
    end
  end
end
