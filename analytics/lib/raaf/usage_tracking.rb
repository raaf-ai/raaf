# frozen_string_literal: true

require "json"
require "time"
require "digest"

module RubyAIAgentsFactory
  ##
  # UsageTracking - Comprehensive resource monitoring and analytics system
  #
  # Provides detailed tracking of agent usage, API calls, token consumption, costs,
  # performance metrics, and user interactions. Supports real-time monitoring,
  # analytics dashboards, and automated reporting.
  #
  # == Features
  #
  # * API usage and token tracking
  # * Cost monitoring and billing analytics
  # * Performance metrics and benchmarking
  # * User interaction analytics
  # * Resource utilization monitoring
  # * Custom metrics and events
  # * Export and reporting capabilities
  # * Real-time dashboards
  #
  # == Basic Usage
  #
  #   # Create usage tracker
  #   tracker = RubyAIAgentsFactory::UsageTracking::UsageTracker.new
  #
  #   # Track API usage
  #   tracker.track_api_call(
  #     provider: "openai",
  #     model: "gpt-4",
  #     tokens_used: 1500,
  #     cost: 0.045
  #   )
  #
  #   # Get usage analytics
  #   analytics = tracker.analytics
  #   puts "Total cost: $#{analytics[:total_cost]}"
  #
  # == Advanced Tracking
  #
  #   # Track with custom metrics
  #   tracker.track_agent_interaction(
  #     agent_name: "CustomerSupport",
  #     user_id: "user123",
  #     session_id: "session456",
  #     duration: 45.2,
  #     satisfaction_score: 4.5,
  #     custom_metrics: {
  #       issue_resolved: true,
  #       escalation_needed: false
  #     }
  #   )
  #
  # == Real-time Monitoring
  #
  #   # Set up monitoring alerts
  #   tracker.add_alert(:high_cost) do |usage|
  #     usage[:total_cost] > 100.0
  #   end
  #
  #   tracker.add_alert(:token_limit) do |usage|
  #     usage[:tokens_today] > 1_000_000
  #   end
  #
  # @author OpenAI Agents Ruby Team
  # @since 0.1.0
  module UsageTracking
    ##
    # UsageTracker - Main usage tracking and analytics engine
    #
    # Central component for collecting, storing, and analyzing usage data across
    # all OpenAI Agents operations.
    class UsageTracker
      attr_reader :storage, :alerts, :custom_metrics

      ##
      # Creates a new UsageTracker instance
      #
      # @param storage [StorageAdapter] storage backend for usage data
      # @param enable_real_time [Boolean] enable real-time monitoring (default: true)
      # @param retention_days [Integer] days to retain usage data (default: 90)
      #
      # @example Create with default settings
      #   tracker = RubyAIAgentsFactory::UsageTracking::UsageTracker.new
      #
      # @example Create with custom storage
      #   storage = RubyAIAgentsFactory::UsageTracking::DatabaseStorage.new(connection)
      #   tracker = RubyAIAgentsFactory::UsageTracking::UsageTracker.new(storage: storage)
      def initialize(storage: nil, enable_real_time: true, retention_days: 90)
        @storage = storage || MemoryStorage.new
        @enable_real_time = enable_real_time
        @retention_days = retention_days
        @alerts = {}
        @custom_metrics = {}
        @session_cache = {}

        # Start background cleanup if real-time monitoring is enabled
        start_cleanup_thread if @enable_real_time
      end

      ##
      # Tracks an API call with usage metrics
      #
      # @param provider [String] API provider (e.g., "openai", "anthropic")
      # @param model [String] model used for the call
      # @param tokens_used [Hash] token usage breakdown
      # @param cost [Float] cost of the API call
      # @param duration [Float] call duration in seconds
      # @param metadata [Hash] additional metadata
      # @return [String] usage event ID
      #
      # @example Track OpenAI API call
      #   tracker.track_api_call(
      #     provider: "openai",
      #     model: "gpt-4",
      #     tokens_used: {
      #       prompt_tokens: 150,
      #       completion_tokens: 75,
      #       total_tokens: 225
      #     },
      #     cost: 0.0135,
      #     duration: 2.3,
      #     metadata: {
      #       agent: "CustomerSupport",
      #       user_id: "user123"
      #     }
      #   )
      def track_api_call(provider:, model:, tokens_used:, cost:, duration: nil, metadata: {})
        event = {
          id: generate_event_id,
          type: :api_call,
          timestamp: Time.now.utc,
          provider: provider,
          model: model,
          tokens_used: normalize_token_usage(tokens_used),
          cost: cost.to_f,
          duration: duration&.to_f,
          metadata: metadata
        }

        store_event(event)
        check_alerts if @enable_real_time

        event[:id]
      end

      ##
      # Tracks an agent interaction session
      #
      # @param agent_name [String] name of the agent
      # @param user_id [String] user identifier
      # @param session_id [String] session identifier
      # @param duration [Float] interaction duration in seconds
      # @param message_count [Integer] number of messages in conversation
      # @param satisfaction_score [Float, nil] user satisfaction rating (1-5)
      # @param outcome [Symbol] interaction outcome (:resolved, :escalated, :abandoned)
      # @param custom_metrics [Hash] custom tracking metrics
      # @return [String] usage event ID
      #
      # @example Track customer service interaction
      #   tracker.track_agent_interaction(
      #     agent_name: "CustomerSupport",
      #     user_id: "user123",
      #     session_id: "cs_session_456",
      #     duration: 180.5,
      #     message_count: 12,
      #     satisfaction_score: 4.2,
      #     outcome: :resolved,
      #     custom_metrics: {
      #       issue_category: "billing",
      #       resolution_time: 120,
      #       escalation_count: 0
      #     }
      #   )
      def track_agent_interaction(agent_name:, user_id:, session_id:, duration:,
                                  message_count:, satisfaction_score: nil, outcome: nil,
                                  custom_metrics: {})
        event = {
          id: generate_event_id,
          type: :agent_interaction,
          timestamp: Time.now.utc,
          agent_name: agent_name,
          user_id: user_id,
          session_id: session_id,
          duration: duration.to_f,
          message_count: message_count.to_i,
          satisfaction_score: satisfaction_score&.to_f,
          outcome: outcome,
          custom_metrics: custom_metrics
        }

        store_event(event)
        update_session_cache(session_id, event)
        check_alerts if @enable_real_time

        event[:id]
      end

      ##
      # Tracks tool usage
      #
      # @param tool_name [String] name of the tool used
      # @param agent_name [String] agent that used the tool
      # @param execution_time [Float] tool execution time in seconds
      # @param success [Boolean] whether tool execution succeeded
      # @param input_size [Integer] size of tool input data
      # @param output_size [Integer] size of tool output data
      # @param metadata [Hash] additional metadata
      # @return [String] usage event ID
      #
      # @example Track file search tool usage
      #   tracker.track_tool_usage(
      #     tool_name: "file_search",
      #     agent_name: "DevAssistant",
      #     execution_time: 1.2,
      #     success: true,
      #     input_size: 256,
      #     output_size: 1024,
      #     metadata: {
      #       search_query: "configuration",
      #       files_found: 5
      #     }
      #   )
      def track_tool_usage(tool_name:, agent_name:, execution_time:, success:,
                           input_size: 0, output_size: 0, metadata: {})
        event = {
          id: generate_event_id,
          type: :tool_usage,
          timestamp: Time.now.utc,
          tool_name: tool_name,
          agent_name: agent_name,
          execution_time: execution_time.to_f,
          success: success,
          input_size: input_size.to_i,
          output_size: output_size.to_i,
          metadata: metadata
        }

        store_event(event)
        check_alerts if @enable_real_time

        event[:id]
      end

      ##
      # Tracks custom events and metrics
      #
      # @param event_type [Symbol] type of custom event
      # @param data [Hash] event data
      # @param metadata [Hash] additional metadata
      # @return [String] usage event ID
      #
      # @example Track custom business metric
      #   tracker.track_custom_event(
      #     :user_conversion,
      #     {
      #       user_id: "user123",
      #       conversion_type: "trial_to_paid",
      #       revenue: 29.99
      #     }
      #   )
      def track_custom_event(event_type, data, metadata: {})
        event = {
          id: generate_event_id,
          type: :custom_event,
          event_type: event_type,
          timestamp: Time.now.utc,
          data: data,
          metadata: metadata
        }

        store_event(event)
        update_custom_metrics(event_type, data)
        check_alerts if @enable_real_time

        event[:id]
      end

      ##
      # Gets comprehensive usage analytics
      #
      # @param period [Symbol] time period (:today, :week, :month, :all)
      # @param group_by [Symbol] grouping dimension (:provider, :agent, :user, :day)
      # @return [Hash] analytics data
      #
      # @example Get today's analytics
      #   analytics = tracker.analytics(:today)
      #   puts "API calls: #{analytics[:api_calls][:count]}"
      #   puts "Total cost: $#{analytics[:costs][:total]}"
      #
      # @example Get weekly analytics grouped by agent
      #   analytics = tracker.analytics(:week, group_by: :agent)
      #   analytics[:agent_usage].each do |agent, stats|
      #     puts "#{agent}: #{stats[:interactions]} interactions"
      #   end
      def analytics(period = :all, group_by: nil)
        events = get_events_for_period(period)

        analytics = {
          period: period,
          total_events: events.length,
          api_calls: analyze_api_calls(events),
          agent_interactions: analyze_agent_interactions(events),
          tool_usage: analyze_tool_usage(events),
          costs: analyze_costs(events),
          performance: analyze_performance(events),
          custom_metrics: analyze_custom_metrics(events)
        }

        analytics[:grouped_data] = group_analytics(events, group_by) if group_by

        analytics
      end

      ##
      # Gets real-time usage dashboard data
      #
      # @return [Hash] dashboard data for real-time monitoring
      #
      # @example Get dashboard data
      #   dashboard = tracker.dashboard_data
      #   puts "Current API rate: #{dashboard[:current_api_rate]} calls/min"
      #   puts "Active sessions: #{dashboard[:active_sessions]}"
      def dashboard_data
        current_time = Time.now.utc

        # Get events from last hour for rate calculations
        hour_ago = current_time - 3600
        recent_events = @storage.get_events(since: hour_ago)

        {
          timestamp: current_time,
          current_api_rate: calculate_api_rate(recent_events),
          active_sessions: count_active_sessions,
          total_cost_today: calculate_daily_cost,
          tokens_used_today: calculate_daily_tokens,
          error_rate: calculate_error_rate(recent_events),
          average_response_time: calculate_average_response_time(recent_events),
          top_agents: get_top_agents_by_usage(recent_events),
          alert_status: alert_status
        }
      end

      ##
      # Adds a usage alert condition
      #
      # @param name [Symbol] alert name
      # @yield [Hash] alert condition block that receives current usage data
      # @return [void]
      #
      # @example Add cost threshold alert
      #   tracker.add_alert(:daily_cost_limit) do |usage|
      #     usage[:total_cost_today] > 50.0
      #   end
      #
      # @example Add token usage alert
      #   tracker.add_alert(:token_burst) do |usage|
      #     usage[:current_api_rate] > 100  # > 100 calls per minute
      #   end
      def add_alert(name, &condition)
        @alerts[name] = {
          condition: condition,
          triggered: false,
          last_check: nil
        }
      end

      ##
      # Removes a usage alert
      #
      # @param name [Symbol] alert name
      # @return [Boolean] true if alert was removed
      def remove_alert(name)
        !!@alerts.delete(name)
      end

      ##
      # Exports usage data in various formats
      #
      # @param format [Symbol] export format (:json, :csv, :excel)
      # @param period [Symbol] time period to export
      # @param file_path [String, nil] output file path (auto-generated if nil)
      # @return [String] path to exported file
      #
      # @example Export monthly data as JSON
      #   file_path = tracker.export_data(:json, :month)
      #   puts "Data exported to: #{file_path}"
      #
      # @example Export all data as CSV
      #   tracker.export_data(:csv, :all, "usage_report.csv")
      def export_data(format, period = :all, file_path = nil)
        events = get_events_for_period(period)
        file_path ||= generate_export_filename(format, period)

        case format
        when :json
          export_json(events, file_path)
        when :csv
          export_csv(events, file_path)
        when :excel
          export_excel(events, file_path)
        else
          raise ArgumentError, "Unsupported export format: #{format}"
        end

        file_path
      end

      ##
      # Generates usage report
      #
      # @param period [Symbol] reporting period
      # @param include_charts [Boolean] whether to include charts in report
      # @return [UsageReport] comprehensive usage report
      #
      # @example Generate monthly report
      #   report = tracker.generate_report(:month, include_charts: true)
      #   puts report.summary
      #   report.save_to_file("monthly_report.html")
      def generate_report(period = :month, include_charts: false)
        analytics = analytics(period)
        UsageReport.new(analytics, period, include_charts)
      end

      ##
      # Clears old usage data based on retention policy
      #
      # @return [Integer] number of events cleaned up
      def cleanup_old_data
        cutoff_date = Time.now.utc - (@retention_days * 24 * 3600)
        @storage.delete_events_before(cutoff_date)
      end

      private

      def generate_event_id
        "#{Time.now.utc.strftime("%Y%m%d_%H%M%S")}_#{SecureRandom.hex(4)}"
      end

      def normalize_token_usage(tokens)
        case tokens
        when Hash
          tokens
        when Integer
          { total_tokens: tokens }
        else
          { total_tokens: 0 }
        end
      end

      def store_event(event)
        @storage.store_event(event)
      end

      def get_events_for_period(period)
        case period
        when :today
          now = Time.now.utc
          start_time = Time.utc(now.year, now.month, now.day)
        when :week
          now = Time.now.utc
          start_time = Time.utc(now.year, now.month, now.day) - ((now.wday - 1) * 24 * 60 * 60)
        when :month
          now = Time.now.utc
          start_time = Time.utc(now.year, now.month, 1)
        when :all
          start_time = nil
        else
          start_time = Time.now.utc - period if period.is_a?(Integer)
        end

        @storage.get_events(since: start_time)
      end

      def analyze_api_calls(events)
        api_events = events.select { |e| e[:type] == :api_call }

        {
          count: api_events.length,
          total_tokens: api_events.sum { |e| e[:tokens_used][:total_tokens] || 0 },
          by_provider: api_events.group_by { |e| e[:provider] }.transform_values(&:length),
          by_model: api_events.group_by { |e| e[:model] }.transform_values(&:length),
          average_duration: calculate_average(api_events, :duration)
        }
      end

      def analyze_agent_interactions(events)
        interaction_events = events.select { |e| e[:type] == :agent_interaction }

        {
          count: interaction_events.length,
          total_duration: interaction_events.sum { |e| e[:duration] },
          average_duration: calculate_average(interaction_events, :duration),
          average_satisfaction: calculate_average(interaction_events, :satisfaction_score),
          by_agent: interaction_events.group_by { |e| e[:agent_name] }.transform_values(&:length),
          by_outcome: interaction_events.group_by { |e| e[:outcome] }.transform_values(&:length)
        }
      end

      def analyze_tool_usage(events)
        tool_events = events.select { |e| e[:type] == :tool_usage }

        {
          count: tool_events.length,
          success_rate: calculate_success_rate(tool_events),
          average_execution_time: calculate_average(tool_events, :execution_time),
          by_tool: tool_events.group_by { |e| e[:tool_name] }.transform_values(&:length),
          by_agent: tool_events.group_by { |e| e[:agent_name] }.transform_values(&:length)
        }
      end

      def analyze_costs(events)
        api_events = events.select { |e| e[:type] == :api_call && e[:cost] }

        {
          total: api_events.sum { |e| e[:cost] },
          by_provider: api_events.group_by { |e| e[:provider] }
                                 .transform_values { |evs| evs.sum { |e| e[:cost] } },
          by_model: api_events.group_by { |e| e[:model] }
                              .transform_values { |evs| evs.sum { |e| e[:cost] } },
          average_per_call: calculate_average(api_events, :cost)
        }
      end

      def analyze_performance(events)
        {
          total_events: events.length,
          events_per_hour: calculate_events_per_hour(events),
          peak_hour: find_peak_hour(events),
          response_times: analyze_response_times(events)
        }
      end

      def analyze_custom_metrics(events)
        custom_events = events.select { |e| e[:type] == :custom_event }

        custom_events.group_by { |e| e[:event_type] }
                     .transform_values { |evs| { count: evs.length, latest: evs.last } }
      end

      def calculate_events_per_hour(events)
        return 0 if events.empty?

        # Group events by hour
        now = Time.now.utc
        hours_ago = now - (24 * 60 * 60) # Last 24 hours
        recent_events = events.select { |e| e[:timestamp] && e[:timestamp] > hours_ago }

        return 0 if recent_events.empty?

        # Calculate events per hour over the last 24 hours
        recent_events.length / 24.0
      end

      def find_peak_hour(events)
        return nil if events.empty?

        # Group events by hour of day
        hourly_counts = events.group_by { |e| e[:timestamp]&.hour || 0 }
                              .transform_values(&:length)

        return nil if hourly_counts.empty?

        peak_hour, max_count = hourly_counts.max_by { |_hour, count| count }
        { hour: peak_hour, count: max_count }
      end

      def analyze_response_times(events)
        api_events = events.select { |e| e[:type] == :api_call && e[:duration] }
        return { average: 0, min: 0, max: 0, count: 0 } if api_events.empty?

        durations = api_events.map { |e| e[:duration] }
        {
          average: durations.sum.to_f / durations.length,
          min: durations.min,
          max: durations.max,
          count: durations.length
        }
      end

      def group_analytics(events, group_by)
        return {} unless events.is_a?(Array) && group_by

        case group_by
        when :agent
          group_by_agent(events)
        when :provider
          group_by_provider(events)
        when :model
          group_by_model(events)
        when :hour
          group_by_hour(events)
        else
          {}
        end
      end

      def group_by_agent(events)
        events.group_by { |e| e.dig(:metadata, :agent) || "unknown" }
              .transform_values do |agent_events|
                {
                  interactions: agent_events.count,
                  total_tokens: agent_events.sum { |e| e.dig(:tokens_used, :total_tokens) || 0 },
                  total_cost: agent_events.sum { |e| e[:cost] || 0 },
                  avg_duration: calculate_average(agent_events, :duration)
                }
              end
      end

      def group_by_provider(events)
        events.group_by { |e| e[:provider] || "unknown" }
              .transform_values do |provider_events|
                {
                  api_calls: provider_events.count,
                  total_tokens: provider_events.sum { |e| e.dig(:tokens_used, :total_tokens) || 0 },
                  total_cost: provider_events.sum { |e| e[:cost] || 0 }
                }
              end
      end

      def group_by_model(events)
        events.group_by { |e| e[:model] || "unknown" }
              .transform_values do |model_events|
                {
                  api_calls: model_events.count,
                  total_tokens: model_events.sum { |e| e.dig(:tokens_used, :total_tokens) || 0 }
                }
              end
      end

      def group_by_hour(events)
        events.group_by { |e| e[:timestamp]&.hour || 0 }
              .transform_values { |hour_events| { count: hour_events.length } }
      end

      def calculate_average(events, field)
        values = events.map { |e| e[field] }.compact
        return 0 if values.empty?

        values.sum.to_f / values.length
      end

      def calculate_success_rate(events)
        return 0 if events.empty?

        successful = events.count { |e| e[:success] }
        (successful.to_f / events.length * 100).round(2)
      end

      def calculate_api_rate(events)
        api_events = events.select { |e| e[:type] == :api_call }
        return 0 if api_events.empty?

        # Calculate calls per minute
        time_span = 60 # 1 minute
        (api_events.length.to_f / time_span * 60).round(2)
      end

      def count_active_sessions
        @session_cache.length
      end

      def calculate_daily_cost
        today_events = get_events_for_period(:today)
        api_events = today_events.select { |e| e[:type] == :api_call && e[:cost] }
        api_events.sum { |e| e[:cost] }
      end

      def calculate_daily_tokens
        today_events = get_events_for_period(:today)
        api_events = today_events.select { |e| e[:type] == :api_call }
        api_events.sum { |e| e[:tokens_used][:total_tokens] || 0 }
      end

      def calculate_error_rate(events)
        tool_events = events.select { |e| e[:type] == :tool_usage }
        return 0 if tool_events.empty?

        failed = tool_events.count { |e| !e[:success] }
        (failed.to_f / tool_events.length * 100).round(2)
      end

      def calculate_average_response_time(events)
        api_events = events.select { |e| e[:type] == :api_call && e[:duration] }
        calculate_average(api_events, :duration)
      end

      def get_top_agents_by_usage(events)
        agent_events = events.select { |e| e[:agent_name] }
        agent_events.group_by { |e| e[:agent_name] }
                    .transform_values(&:length)
                    .sort_by { |_, count| -count }
                    .first(5)
                    .to_h
      end

      def check_alerts
        return unless @enable_real_time

        data = dashboard_data

        @alerts.each do |name, alert|
          triggered = alert[:condition].call(data)

          if triggered && !alert[:triggered]
            handle_alert_triggered(name, data)
            alert[:triggered] = true
          elsif !triggered && alert[:triggered]
            alert[:triggered] = false
          end

          alert[:last_check] = Time.now.utc
        rescue StandardError => e
          warn "Alert '#{name}' check failed: #{e.message}"
        end
      end

      def handle_alert_triggered(name, _data)
        # In a real implementation, this would send notifications
        warn "USAGE ALERT: #{name} triggered at #{Time.now}"
      end

      def alert_status
        {
          total_alerts: @alerts.length,
          active_alerts: @alerts.count { |_, alert| alert[:triggered] },
          last_check: @alerts.values.map { |alert| alert[:last_check] }.compact.max
        }
      end

      def update_session_cache(session_id, event)
        @session_cache[session_id] = {
          last_activity: event[:timestamp],
          event_count: (@session_cache[session_id]&.dig(:event_count) || 0) + 1
        }

        # Clean up old sessions (older than 1 hour)
        cutoff = Time.now.utc - 3600
        @session_cache.delete_if { |_, data| data[:last_activity] < cutoff }
      end

      def update_custom_metrics(event_type, data)
        @custom_metrics[event_type] ||= { count: 0, last_value: nil }
        @custom_metrics[event_type][:count] += 1
        @custom_metrics[event_type][:last_value] = data
      end

      def start_cleanup_thread
        Thread.new do
          loop do
            sleep(24 * 3600) # Run daily
            begin
              cleanup_old_data
            rescue StandardError => e
              warn "Cleanup failed: #{e.message}"
            end
          end
        end
      end

      def export_json(events, file_path)
        File.write(file_path, JSON.pretty_generate(events))
      end

      def export_csv(events, file_path)
        require "csv"

        CSV.open(file_path, "w") do |csv|
          if events.any?
            # Write header
            csv << events.first.keys

            # Write data
            events.each { |event| csv << event.values }
          end
        end
      end

      def export_excel(events, file_path)
        # Simplified Excel export - in production, use a proper Excel gem
        export_csv(events, file_path.gsub(".xlsx", ".csv"))
      end

      def generate_export_filename(format, period)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        "usage_data_#{period}_#{timestamp}.#{format}"
      end
    end

    ##
    # MemoryStorage - In-memory storage adapter for usage data
    class MemoryStorage
      def initialize
        @events = []
      end

      def store_event(event)
        @events << event
      end

      def get_events(since: nil)
        events = @events

        events = events.select { |e| e[:timestamp] >= since } if since

        events
      end

      def delete_events_before(cutoff_date)
        initial_count = @events.length
        @events.reject! { |e| e[:timestamp] < cutoff_date }
        initial_count - @events.length
      end
    end

    ##
    # UsageReport - Comprehensive usage report generator
    class UsageReport
      attr_reader :analytics, :period

      # rubocop:disable Style/OptionalBooleanParameter
      def initialize(analytics, period, include_charts = false)
        # rubocop:enable Style/OptionalBooleanParameter
        @analytics = analytics
        @period = period
        @include_charts = include_charts
      end

      def summary
        <<~SUMMARY
          Usage Report - #{@period.to_s.capitalize}
          =====================================

          API Calls: #{@analytics[:api_calls][:count]}
          Total Tokens: #{format_number(@analytics[:api_calls][:total_tokens])}
          Total Cost: $#{@analytics[:costs][:total].round(2)}

          Agent Interactions: #{@analytics[:agent_interactions][:count]}
          Average Satisfaction: #{@analytics[:agent_interactions][:average_satisfaction]&.round(2) || "N/A"}

          Tool Usage: #{@analytics[:tool_usage][:count]}
          Tool Success Rate: #{@analytics[:tool_usage][:success_rate]}%
        SUMMARY
      end

      def save_to_file(file_path)
        content = generate_html_report
        File.write(file_path, content)
      end

      private

      def generate_html_report
        # Simplified HTML report - in production, use a template engine
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>Usage Report - #{@period}</title>
            <style>
              body { font-family: Arial, sans-serif; margin: 20px; }
              .metric { padding: 10px; margin: 10px 0; border: 1px solid #ddd; }
              .chart { height: 300px; margin: 20px 0; background: #f5f5f5; }
            </style>
          </head>
          <body>
            <h1>Usage Report - #{@period.to_s.capitalize}</h1>
          #{"  "}
            <div class="metric">
              <h3>API Usage</h3>
              <p>Total Calls: #{@analytics[:api_calls][:count]}</p>
              <p>Total Tokens: #{format_number(@analytics[:api_calls][:total_tokens])}</p>
              <p>Average Duration: #{@analytics[:api_calls][:average_duration]&.round(2)}s</p>
            </div>
          #{"  "}
            <div class="metric">
              <h3>Costs</h3>
              <p>Total Cost: $#{@analytics[:costs][:total].round(2)}</p>
              <p>Average per Call: $#{@analytics[:costs][:average_per_call]&.round(4)}</p>
            </div>
          #{"  "}
            <div class="metric">
              <h3>Agent Interactions</h3>
              <p>Total Interactions: #{@analytics[:agent_interactions][:count]}</p>
              <p>Average Duration: #{@analytics[:agent_interactions][:average_duration]&.round(1)}s</p>
              <p>Average Satisfaction: #{@analytics[:agent_interactions][:average_satisfaction]&.round(2)}/5.0</p>
            </div>
          #{"  "}
            #{generate_charts_html if @include_charts}
          #{"  "}
            <p><em>Generated at #{Time.now}</em></p>
          </body>
          </html>
        HTML
      end

      def generate_charts_html
        # Placeholder for chart generation
        '<div class="chart">Charts would be rendered here with a charting library</div>'
      end

      def format_number(number)
        return "N/A" unless number

        number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end
    end
  end
end
