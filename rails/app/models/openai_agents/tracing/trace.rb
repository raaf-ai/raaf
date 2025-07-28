# frozen_string_literal: true

module RAAF
  module Tracing
    # ActiveRecord model for storing trace data
    #
    # A trace represents a complete workflow execution containing multiple
    # related spans. Each trace captures:
    #
    # - Workflow identification and metadata
    # - Overall execution timing
    # - Status and outcome
    # - Associated spans and relationships
    #
    # ## Usage
    #
    # Traces are typically created automatically by the ActiveRecordProcessor
    # when spans are saved to the database. However, they can also be queried
    # and analyzed directly:
    #
    # @example Find recent traces
    #   RAAF::Tracing::Trace.recent.limit(10)
    #
    # @example Find traces by workflow
    #   RAAF::Tracing::Trace.by_workflow("Order Processing")
    #
    # @example Find failed traces
    #   RAAF::Tracing::Trace.failed
    #
    # @example Get trace performance summary
    #   trace = RAAF::Tracing::Trace.find_by(trace_id: "trace_abc123")
    #   trace.performance_summary
    class TraceRecord < ApplicationRecord
      self.table_name = "raaf_tracing_traces"

      # Associations
      has_many :spans, primary_key: :trace_id, foreign_key: :trace_id,
                       class_name: "RAAF::Tracing::SpanRecord", dependent: :destroy

      # Validations
      validates :trace_id, presence: true, uniqueness: true,
                           format: {
                             with: /\Atrace_[a-zA-Z0-9]{32}\z/,
                             message: "must be in format 'trace_<32_alphanumeric>'"
                           }
      validates :workflow_name, presence: true, length: { maximum: 255 }
      validates :status, inclusion: { in: %w[pending running completed failed] }

      # Callbacks
      before_validation :ensure_trace_id
      before_validation :set_default_status
      after_create :update_trace_status

      # Scopes
      scope :recent, -> { order(started_at: :desc) }
      scope :by_workflow, ->(name) { where(workflow_name: name) }
      scope :by_status, ->(status) { where(status: status) }
      scope :completed, -> { where(status: "completed") }
      scope :failed, -> { where(status: "failed") }
      scope :running, -> { where(status: "running") }
      scope :within_timeframe, lambda { |start_time, end_time|
        where(started_at: start_time..end_time)
      }
      scope :long_running, lambda { |threshold_seconds = 30|
        where("EXTRACT(EPOCH FROM (ended_at - started_at)) > ?", threshold_seconds)
      }

      # JSON serialization for metadata
      serialize :metadata, coder: JSON if respond_to?(:serialize)

      # Class methods for analytics and reporting
      class << self
        # Get workflow performance statistics
        #
        # @param workflow_name [String, nil] Specific workflow or all workflows
        # @param timeframe [Range, nil] Time range to analyze
        # @return [Hash] Performance statistics
        def performance_stats(workflow_name: nil, timeframe: nil)
          query = reorder(nil)
          query = query.by_workflow(workflow_name) if workflow_name
          query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe

          {
            total_traces: query.count,
            completed_traces: query.completed.count,
            failed_traces: query.failed.count,
            avg_duration: query.where.not(ended_at: nil).average(
              "EXTRACT(EPOCH FROM (ended_at - started_at))"
            ),
            success_rate: query.any? ? (query.completed.count.to_f / query.count * 100).round(2) : 0
          }
        end

        # Get top workflows by volume
        #
        # @param limit [Integer] Number of workflows to return
        # @param timeframe [Range, nil] Time range to analyze
        # @return [Array<Hash>] Workflow statistics
        def top_workflows(limit: 10, timeframe: nil)
          query = reorder(nil)
          query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe

          # Get raw data to avoid GROUP BY issues
          trace_data = query.pluck(:workflow_name, :status, :started_at, :ended_at)

          # Process in Ruby
          workflow_stats = trace_data.group_by(&:first).map do |workflow_name, traces|
            error_count = traces.count { |_, status, _, _| status == "failed" }
            durations = traces.map do |_, _, started_at, ended_at|
              (ended_at - started_at).to_f if started_at && ended_at
            end.compact

            {
              workflow_name: workflow_name,
              trace_count: traces.size,
              avg_duration: durations.any? ? (durations.sum / durations.size).round(2) : 0,
              error_count: error_count,
              success_rate: traces.any? ? ((traces.size - error_count).to_f / traces.size * 100).round(2) : 0
            }
          end

          # Sort and limit
          workflow_stats.sort_by { |w| -w[:trace_count] }.first(limit)
        end

        # Clean up old traces based on retention policy
        #
        # @param older_than [ActiveSupport::Duration] Delete traces older than this
        # @return [Integer] Number of traces deleted
        def cleanup_old_traces(older_than: 30.days)
          where(started_at: ...older_than.ago).delete_all
        end
      end

      # Instance methods

      # Calculate trace duration in seconds
      #
      # @return [Float, nil] Duration or nil if not completed
      def duration_seconds
        return nil unless started_at && ended_at

        (ended_at - started_at).to_f
      end

      # Calculate trace duration in milliseconds
      #
      # @return [Float, nil] Duration or nil if not completed
      def duration_ms
        duration_seconds&.*(1000)
      end

      # Check if trace is currently running
      #
      # @return [Boolean] True if trace is still running
      def running?
        status == "running" && ended_at.nil?
      end

      # Check if trace completed successfully
      #
      # @return [Boolean] True if trace completed without errors
      def successful?
        status == "completed"
      end

      # Get root spans (spans without parent)
      #
      # @return [ActiveRecord::Relation] Root spans for this trace
      def root_spans
        spans.where(parent_id: nil)
      end

      # Get span hierarchy as nested structure
      #
      # @return [Array<Hash>] Nested span hierarchy
      def span_hierarchy
        span_map = spans.includes(:children).index_by(&:span_id)

        root_spans.map do |root_span|
          build_span_tree(root_span, span_map)
        end
      end

      # Get performance summary for this trace
      #
      # @return [Hash] Performance metrics
      def performance_summary
        # Use pluck to avoid the GROUP BY issue
        span_data = spans.pluck(:kind, :status, :duration_ms)

        # Group and calculate statistics in Ruby
        span_stats = span_data.group_by(&:first).transform_values do |group_spans|
          durations = group_spans.map { |_, _, duration| duration }.compact
          error_count = group_spans.count { |_, status, _| status == "error" }

          {
            count: group_spans.size,
            avg_duration: durations.any? ? (durations.sum.to_f / durations.size).round(2) : 0,
            max_duration: durations.max&.round(2) || 0,
            error_count: error_count
          }
        end

        {
          trace_id: trace_id,
          workflow_name: workflow_name,
          total_duration_ms: duration_ms,
          total_spans: spans.count,
          span_breakdown: span_stats,
          status: status,
          success_rate: if spans.any?
                          ((spans.count - spans.where(status: "error").count).to_f / spans.count * 100).round(2)
                        else
                          0
                        end
        }
      end

      # Get cost analysis for this trace (if cost data is available)
      #
      # @return [Hash] Cost breakdown
      def cost_analysis
        llm_spans = spans.where(kind: "llm")

        total_input_tokens = llm_spans.sum do |span|
          span.attributes.dig("llm", "usage", "input_tokens").to_i
        end

        total_output_tokens = llm_spans.sum do |span|
          span.attributes.dig("llm", "usage", "output_tokens").to_i
        end

        {
          total_input_tokens: total_input_tokens,
          total_output_tokens: total_output_tokens,
          total_tokens: total_input_tokens + total_output_tokens,
          llm_calls: llm_spans.count,
          models_used: llm_spans.map { |s| s.attributes.dig("llm", "request", "model") }.uniq.compact
        }
      end

      # Update trace status based on span states
      def update_trace_status
        return unless persisted?

        span_statuses = spans.pluck(:status)

        new_status = if span_statuses.empty?
                       "pending"
                     elsif span_statuses.include?("error")
                       "failed"
                     elsif span_statuses.all? { |s| s == "ok" }
                       "completed"
                     else
                       "running"
                     end

        update_column(:status, new_status) unless status == new_status

        # Update ended_at if all spans are complete
        return unless %w[completed failed].include?(new_status) && ended_at.nil?

        last_span_end = spans.maximum(:end_time)
        update_column(:ended_at, last_span_end || Time.current)
      end

      private

      # Ensure trace_id is set
      def ensure_trace_id
        return if trace_id.present?

        self.trace_id = "trace_#{SecureRandom.alphanumeric(32)}"
      end

      # Set default status
      def set_default_status
        self.status = "pending" if status.blank?
      end

      # Build nested span tree structure
      def build_span_tree(span, span_map)
        {
          span: span,
          children: span.child_span_ids.map do |child_id|
            child_span = span_map[child_id]
            child_span ? build_span_tree(child_span, span_map) : nil
          end.compact
        }
      end
    end
  end
end
