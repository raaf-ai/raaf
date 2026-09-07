# frozen_string_literal: true

module RAAF
  module Rails
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
      class TraceRecord < ActiveRecord::Base
        self.table_name = "raaf_tracing_traces"
        self.primary_key = "trace_id"

        # Associations
        has_many :spans, primary_key: :trace_id, foreign_key: :trace_id,
                         class_name: "RAAF::Rails::Tracing::SpanRecord", dependent: :destroy

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

        # JSON columns are natively serialized in Rails 8+
        # No need for explicit serialization

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
          # Reports the 95th percentile duration alongside the mean, because the
          # Overview's agent tiles label what they show as p95 and a mean hides
          # exactly the runs that tile exists to surface.
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
                p95_duration: percentile_of(durations.sort, 0.95),
                error_count: error_count,
                success_rate: traces.any? ? ((traces.size - error_count).to_f / traces.size * 100).round(2) : 0
              }
            end

            # Sort and limit
            workflow_stats.sort_by { |w| -w[:trace_count] }.first(limit)
          end

          # Linear-interpolated percentile of an already sorted array, nil where
          # there is nothing to take a percentile of.
          def percentile_of(sorted, fraction)
            return nil if sorted.empty?
            return sorted.first.round(2) if sorted.one?

            position = fraction * (sorted.length - 1)
            lower = sorted[position.floor]
            upper = sorted[position.ceil]

            (lower + ((upper - lower) * (position - position.floor))).round(2)
          end

          # Clean up old traces based on retention policy
          #
          # @param older_than [ActiveSupport::Duration] Delete traces older than this
          # @return [Integer] Number of traces deleted
          def cleanup_old_traces(older_than: 30.days)
            where(started_at: ...older_than.ago).delete_all
          end

          # Fix stuck traces that should be completed but are still marked as running
          #
          # @param older_than [ActiveSupport::Duration] Only fix traces older than this
          # @return [Integer] Number of traces fixed
          def fix_stuck_traces(older_than: 5.minutes)
            stuck_traces = running.where("started_at < ?", older_than.ago)

            fixed_count = 0
            stuck_traces.find_each do |trace|
              old_status = trace.status
              trace.update_trace_status
              if trace.status != old_status
                Rails.logger.info "Fixed stuck trace #{trace.trace_id}: #{old_status} -> #{trace.status}"
                fixed_count += 1
              end
            end

            fixed_count
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

        # Token and cost totals for many traces in one query.
        #
        # The per-trace instance methods load every span and re-read its payload,
        # which is right for a detail page and ruinous for a listing — a page of
        # 25 traces would be 25 span loads carrying their full JSON attributes.
        # This reads the native token columns instead and groups in SQL, so a
        # listing costs one query however many traces it shows.
        #
        # The trade-off is that it sees only what has been copied into the
        # columns: spans written before those columns existed report nothing
        # until +raaf:tracing:backfill_token_columns+ has been run.
        #
        # @param trace_ids [Array<String>] Traces to total
        # @return [Hash] +trace_id => { tokens:, cost: }+, cost nil when unpriced
        def self.token_totals_for(trace_ids)
          trace_ids = Array(trace_ids).uniq
          return {} if trace_ids.empty?

          rows = SpanRecord.where(trace_id: trace_ids)
                           .unscope(:order)
                           .group(:trace_id, :agent_model)
                           .pluck(
                             :trace_id,
                             :agent_model,
                             Arel.sql("SUM(COALESCE(input_tokens, 0))"),
                             Arel.sql("SUM(COALESCE(output_tokens, 0))"),
                             Arel.sql("SUM(COALESCE(total_tokens, COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0)))")
                           )

          rows.each_with_object({}) do |(trace_id, model, input, output, total), totals|
            next if total.to_i.zero?

            entry = totals[trace_id] ||= { tokens: 0, cost: nil }
            entry[:tokens] += total.to_i

            cost = ::RAAF::Tracing::SpanUsage.cost(
              { input: input.to_i, output: output.to_i, total: total.to_i, model: model }
            )
            entry[:cost] = entry[:cost].to_f + cost if cost
          end
        end

        # Token usage recorded across this trace, per span that recorded any.
        #
        # @return [Array<Hash>] +{ input:, output:, total:, model: }+ per span
        def span_usages
          @span_usages ||= spans.map(&:token_usage)
                                .select { |usage| ::RAAF::Tracing::SpanUsage.total_tokens(usage) }
        end

        # Tokens this trace consumed, counted the way the provider bills.
        #
        # @return [Integer, nil] Token count, or nil when no span recorded usage
        def total_tokens
          return nil if span_usages.empty?

          span_usages.sum { |usage| ::RAAF::Tracing::SpanUsage.total_tokens(usage).to_i }
        end

        # Input tokens this trace consumed.
        #
        # @return [Integer] Token count, zero when no span recorded usage
        def total_input_tokens
          span_usages.sum { |usage| usage[:input].to_i }
        end

        # Output tokens this trace consumed, as reported.
        #
        # Excludes tokens a provider bills but does not itemise — see
        # {RAAF::Tracing::SpanUsage.billable_output}, which is what {total_cost}
        # charges for.
        #
        # @return [Integer] Token count, zero when no span recorded usage
        def total_output_tokens
          span_usages.sum { |usage| usage[:output].to_i }
        end

        # Cost in USD of everything this trace consumed.
        #
        # Nil rather than zero when nothing could be priced, so a dashboard can
        # tell "this trace was free" apart from "nobody knows what this cost" —
        # a trace on a model with no pricing entry is the second, and rendering
        # it as $0.00 quietly understates the bill.
        #
        # @return [Float, nil] Cost, or nil when no span could be priced
        def total_cost
          priced = span_usages.filter_map { |usage| ::RAAF::Tracing::SpanUsage.cost(usage) }
          return nil if priced.empty?

          priced.sum.round(6)
        end

        # Get cost analysis for this trace
        #
        # @return [Hash] Cost breakdown
        def cost_analysis
          {
            total_input_tokens: total_input_tokens,
            total_output_tokens: total_output_tokens,
            total_tokens: total_tokens.to_i,
            total_cost: total_cost,
            llm_calls: span_usages.count,
            models_used: span_usages.filter_map { |usage| usage[:model] }.uniq
          }
        end

        # Get skip reasons from any skipped spans in this trace
        #
        # @return [String, nil] Skip reasons from skipped spans, or nil if none
        def skip_reasons_summary
          # Reload spans to ensure we have the latest data
          spans.reload if spans.respond_to?(:reload)

          # Find all skipped or cancelled spans
          skipped_spans = spans.select { |span| %w[cancelled skipped].include?(span.status) }

          return nil if skipped_spans.empty?

          # Extract skip reasons from all skipped spans
          reasons = skipped_spans.map do |span|
            reason = span.span_attributes&.dig("agent.skip_reason") ||
                     span.span_attributes&.dig("skip_reason") ||
                     span.span_attributes&.dig("cancelled_reason") ||
                     "No reason provided"

            # Include span name for context if multiple spans are skipped
            if skipped_spans.count > 1
              span_name = begin
                span.display_name
              rescue StandardError
                span.name
              end
              "#{span_name}: #{reason}"
            else
              reason
            end
          end.compact

          reasons.join("; ")
        end

        # Update trace status based on span states
        def update_trace_status
          return unless persisted?

          span_statuses = spans.pluck(:status)

          new_status = if span_statuses.empty?
                         "pending"
                       elsif span_statuses.include?("error")
                         "failed"
                       elsif span_statuses.all? { |s| %w[ok error cancelled skipped].include?(s) }
                         # All spans are in final states - determine overall status
                         if span_statuses.any? { |s| s == "error" }
                           "failed"
                         else
                           "completed"
                         end
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
end
