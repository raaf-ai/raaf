# frozen_string_literal: true

module OpenAIAgents
  module Tracing
    class AlertEngine
      DEFAULT_RULES = [
        {
          name: "high_error_rate",
          description: "Triggers when error rate exceeds threshold",
          condition: "error_rate > threshold",
          threshold: 10.0,
          severity: "critical",
          window_minutes: 10,
          enabled: true
        },
        {
          name: "elevated_error_rate",
          description: "Triggers when error rate is elevated",
          condition: "error_rate > threshold",
          threshold: 5.0,
          severity: "warning",
          window_minutes: 15,
          enabled: true
        },
        {
          name: "high_latency",
          description: "Triggers when P95 latency exceeds threshold",
          condition: "p95_duration_ms > threshold",
          threshold: 30_000, # 30 seconds
          severity: "warning",
          window_minutes: 10,
          enabled: true
        },
        {
          name: "cost_spike",
          description: "Triggers when cost per hour exceeds budget",
          condition: "cost_per_hour > threshold",
          threshold: 100.0, # $100/hour
          severity: "warning",
          window_minutes: 60,
          enabled: true
        },
        {
          name: "trace_volume_spike",
          description: "Triggers when trace volume increases dramatically",
          condition: "traces_per_minute > baseline * multiplier",
          threshold: 3.0, # 3x normal volume
          severity: "warning",
          window_minutes: 5,
          enabled: true
        },
        {
          name: "no_traces",
          description: "Triggers when no traces are received",
          condition: "traces_count == 0",
          threshold: 0,
          severity: "critical",
          window_minutes: 30,
          enabled: true
        }
      ].freeze

      def initialize(config = {})
        @rules = load_rules(config[:rules] || [])
        @alert_handlers = []
        @state = {}
        @last_check = {}
        @suppression_cache = {}

        setup_default_handlers(config)
      end

      def add_alert_handler(handler)
        @alert_handlers << handler
      end

      def add_rule(rule)
        @rules << normalize_rule(rule)
      end

      def remove_rule(rule_name)
        @rules.reject! { |rule| rule[:name] == rule_name }
      end

      def update_rule(rule_name, updates)
        rule = @rules.find { |r| r[:name] == rule_name }
        return false unless rule

        rule.merge!(updates)
        true
      end

      def check_all_rules
        results = []

        @rules.select { |rule| rule[:enabled] }.each do |rule|
          result = check_rule(rule)
          if result[:triggered]
            results << result
            handle_alert(result) unless suppressed?(result)
          end
        rescue StandardError => e
          Rails.logger.error "Alert rule check failed for #{rule[:name]}: #{e.message}"
        end

        cleanup_suppression_cache
        results
      end

      def check_rule(rule)
        now = Time.current
        window_start = now - rule[:window_minutes].minutes

        metrics = calculate_metrics(window_start, now, rule)
        triggered = evaluate_condition(rule, metrics)

        result = {
          rule_name: rule[:name],
          triggered: triggered,
          severity: rule[:severity],
          description: rule[:description],
          metrics: metrics,
          threshold: rule[:threshold],
          window_start: window_start,
          window_end: now,
          checked_at: now
        }

        if triggered
          result[:message] = generate_alert_message(rule, metrics)
          result[:runbook_url] = generate_runbook_url(rule[:name])
        end

        @last_check[rule[:name]] = result
        result
      end

      def get_rule_status(rule_name = nil)
        if rule_name
          @last_check[rule_name] || { status: "never_checked" }
        else
          @last_check
        end
      end

      def list_rules
        @rules.map do |rule|
          rule.merge(
            last_checked: @last_check[rule[:name]]&.dig(:checked_at),
            last_triggered: @last_check[rule[:name]]&.dig(:triggered) ? @last_check[rule[:name]][:checked_at] : nil
          )
        end
      end

      def suppress_alert(rule_name, duration_minutes = 60)
        @suppression_cache[rule_name] = Time.current + duration_minutes.minutes
      end

      def clear_suppression(rule_name = nil)
        if rule_name
          @suppression_cache.delete(rule_name)
        else
          @suppression_cache.clear
        end
      end

      private

      def load_rules(custom_rules)
        rules = DEFAULT_RULES.dup
        custom_rules.each { |rule| rules << normalize_rule(rule) }
        rules
      end

      def normalize_rule(rule)
        {
          name: rule[:name] || rule["name"],
          description: rule[:description] || rule["description"],
          condition: rule[:condition] || rule["condition"],
          threshold: rule[:threshold] || rule["threshold"] || 0,
          severity: rule[:severity] || rule["severity"] || "warning",
          window_minutes: rule[:window_minutes] || rule["window_minutes"] || 10,
          enabled: rule[:enabled].nil? || rule[:enabled]
        }
      end

      def setup_default_handlers(config)
        # Add console logger handler
        add_alert_handler(ConsoleAlertHandler.new)

        # Add Rails logger handler
        add_alert_handler(RailsLoggerHandler.new)

        # Add ActionCable broadcaster (if available)
        add_alert_handler(ActionCableHandler.new) if defined?(ActionCable)

        # Add custom handlers from config
        return unless config[:handlers]

        config[:handlers].each { |handler| add_alert_handler(handler) }
      end

      def calculate_metrics(window_start, window_end, rule)
        case rule[:name]
        when "high_error_rate", "elevated_error_rate"
          calculate_error_rate_metrics(window_start, window_end)
        when "high_latency"
          calculate_latency_metrics(window_start, window_end)
        when "cost_spike"
          calculate_cost_metrics(window_start, window_end)
        when "trace_volume_spike"
          calculate_volume_metrics(window_start, window_end)
        when "no_traces"
          calculate_trace_count_metrics(window_start, window_end)
        else
          calculate_general_metrics(window_start, window_end)
        end
      end

      def calculate_error_rate_metrics(window_start, window_end)
        traces = Trace.within_timeframe(window_start, window_end)
        total_traces = traces.count
        failed_traces = traces.failed.count

        error_rate = total_traces > 0 ? (failed_traces.to_f / total_traces * 100) : 0

        {
          total_traces: total_traces,
          failed_traces: failed_traces,
          error_rate: error_rate.round(2)
        }
      end

      def calculate_latency_metrics(window_start, window_end)
        durations = Trace.within_timeframe(window_start, window_end)
                         .where.not(ended_at: nil)
                         .pluck("EXTRACT(EPOCH FROM (ended_at - started_at)) * 1000")
                         .sort

        return { p95_duration_ms: 0, p99_duration_ms: 0, avg_duration_ms: 0, trace_count: 0 } if durations.empty?

        {
          p95_duration_ms: percentile(durations, 95).round(2),
          p99_duration_ms: percentile(durations, 99).round(2),
          avg_duration_ms: (durations.sum / durations.size).round(2),
          trace_count: durations.size
        }
      end

      def calculate_cost_metrics(window_start, window_end)
        spans = Span.joins(:trace)
                    .where(openai_agents_tracing_traces: { started_at: window_start..window_end })
                    .where(kind: "llm")

        total_input_tokens = 0
        total_output_tokens = 0
        total_cost = 0.0

        spans.find_each do |span|
          if span.attributes&.dig("llm", "usage")
            usage = span.attributes["llm"]["usage"]
            input_tokens = usage["prompt_tokens"] || 0
            output_tokens = usage["completion_tokens"] || 0

            total_input_tokens += input_tokens
            total_output_tokens += output_tokens

            # Estimate cost (simplified - should use actual model pricing)
            model = span.attributes.dig("llm", "request", "model") || "gpt-4"
            total_cost += estimate_cost(model, input_tokens, output_tokens)
          end
        end

        window_hours = (window_end - window_start) / 1.hour
        cost_per_hour = window_hours > 0 ? total_cost / window_hours : 0

        {
          total_input_tokens: total_input_tokens,
          total_output_tokens: total_output_tokens,
          total_cost: total_cost.round(4),
          cost_per_hour: cost_per_hour.round(2),
          llm_spans: spans.count
        }
      end

      def calculate_volume_metrics(window_start, window_end)
        current_traces = Trace.within_timeframe(window_start, window_end).count
        window_minutes = (window_end - window_start) / 1.minute
        traces_per_minute = window_minutes > 0 ? current_traces / window_minutes : 0

        # Calculate baseline from previous period
        baseline_start = window_start - (window_end - window_start)
        baseline_end = window_start
        baseline_traces = Trace.within_timeframe(baseline_start, baseline_end).count
        baseline_per_minute = window_minutes > 0 ? baseline_traces / window_minutes : 0

        {
          current_traces: current_traces,
          traces_per_minute: traces_per_minute.round(2),
          baseline_traces: baseline_traces,
          baseline_per_minute: baseline_per_minute.round(2),
          multiplier: baseline_per_minute > 0 ? (traces_per_minute / baseline_per_minute).round(2) : 0
        }
      end

      def calculate_trace_count_metrics(window_start, window_end)
        traces_count = Trace.within_timeframe(window_start, window_end).count

        {
          traces_count: traces_count,
          window_minutes: ((window_end - window_start) / 1.minute).round
        }
      end

      def calculate_general_metrics(window_start, window_end)
        {
          window_start: window_start,
          window_end: window_end,
          window_minutes: ((window_end - window_start) / 1.minute).round
        }
      end

      def evaluate_condition(rule, metrics)
        case rule[:condition]
        when "error_rate > threshold"
          metrics[:error_rate] > rule[:threshold]
        when "p95_duration_ms > threshold"
          metrics[:p95_duration_ms] > rule[:threshold]
        when "cost_per_hour > threshold"
          metrics[:cost_per_hour] > rule[:threshold]
        when "traces_per_minute > baseline * multiplier"
          metrics[:traces_per_minute] > (metrics[:baseline_per_minute] * rule[:threshold])
        when "traces_count == 0"
          metrics[:traces_count] == 0
        else
          false
        end
      end

      def generate_alert_message(rule, metrics)
        case rule[:name]
        when "high_error_rate", "elevated_error_rate"
          "Error rate is #{metrics[:error_rate]}% (#{metrics[:failed_traces]}/#{metrics[:total_traces]} traces failed)"
        when "high_latency"
          "P95 latency is #{metrics[:p95_duration_ms]}ms (threshold: #{rule[:threshold]}ms)"
        when "cost_spike"
          "Cost per hour is $#{metrics[:cost_per_hour]} (threshold: $#{rule[:threshold]})"
        when "trace_volume_spike"
          "Trace volume is #{metrics[:multiplier]}x baseline " \
          "(#{metrics[:traces_per_minute]} vs #{metrics[:baseline_per_minute]} per minute)"
        when "no_traces"
          "No traces received in the last #{metrics[:window_minutes]} minutes"
        else
          "Alert condition met for #{rule[:name]}"
        end
      end

      def generate_runbook_url(rule_name)
        base_url = begin
          Rails.application.routes.url_helpers.root_url
        rescue StandardError
          "http://localhost:3000"
        end
        "#{base_url}tracing/runbooks/#{rule_name}"
      end

      def handle_alert(alert)
        @alert_handlers.each do |handler|
          handler.handle(alert)
        rescue StandardError => e
          Rails.logger.error "Alert handler failed: #{e.message}"
        end
      end

      def suppressed?(alert)
        suppression_until = @suppression_cache[alert[:rule_name]]
        suppression_until && Time.current < suppression_until
      end

      def cleanup_suppression_cache
        @suppression_cache.delete_if { |_, until_time| Time.current >= until_time }
      end

      def percentile(sorted_array, percentile)
        return 0 if sorted_array.empty?

        index = (percentile / 100.0 * (sorted_array.length - 1)).round
        sorted_array[index]
      end

      def estimate_cost(model, input_tokens, output_tokens)
        # Simplified cost estimation - should be replaced with actual pricing
        pricing = {
          "gpt-4" => { input: 0.00003, output: 0.00006 },
          "gpt-4o" => { input: 0.000005, output: 0.000015 },
          "gpt-3.5-turbo" => { input: 0.0000015, output: 0.000002 }
        }

        rates = pricing[model] || pricing["gpt-4"]
        (input_tokens * rates[:input]) + (output_tokens * rates[:output])
      end

      # Alert Handler Classes
      class ConsoleAlertHandler
        def handle(alert)
          puts "\n🚨 ALERT: #{alert[:rule_name]} (#{alert[:severity]})"
          puts "   Message: #{alert[:message]}"
          puts "   Runbook: #{alert[:runbook_url]}"
          puts "   Time: #{alert[:checked_at]}"
        end
      end

      class RailsLoggerHandler
        def handle(alert)
          level = alert[:severity] == "critical" ? :error : :warn
          Rails.logger.send(level, "ALERT: #{alert[:rule_name]} - #{alert[:message]} [#{alert[:runbook_url]}]")
        end
      end

      class ActionCableHandler
        def handle(alert)
          ActionCable.server.broadcast("traces_updates", {
                                         type: "alert",
                                         alert: {
                                           title: alert[:rule_name].humanize,
                                           message: alert[:message],
                                           severity: alert[:severity],
                                           runbook_url: alert[:runbook_url],
                                           timestamp: alert[:checked_at].iso8601
                                         }
                                       })
        end
      end

      # Custom alert handlers can be added by implementing #handle(alert)
      class WebhookHandler
        def initialize(webhook_url, secret = nil)
          @webhook_url = webhook_url
          @secret = secret
        end

        def handle(alert)
          payload = {
            alert: alert[:rule_name],
            severity: alert[:severity],
            message: alert[:message],
            runbook: alert[:runbook_url],
            timestamp: alert[:checked_at].iso8601,
            metrics: alert[:metrics]
          }

          headers = { "Content-Type" => "application/json" }
          headers["X-Alert-Signature"] = generate_signature(payload.to_json) if @secret

          Net::HTTP.post(
            URI(@webhook_url),
            payload.to_json,
            headers
          )
        end

        private

        def generate_signature(payload)
          OpenSSL::HMAC.hexdigest("SHA256", @secret, payload)
        end
      end

      class SlackHandler
        def initialize(webhook_url, channel = nil)
          @webhook_url = webhook_url
          @channel = channel
        end

        def handle(alert)
          color = alert[:severity] == "critical" ? "danger" : "warning"

          payload = {
            text: "🚨 Alert: #{alert[:rule_name].humanize}",
            channel: @channel,
            attachments: [{
              color: color,
              fields: [
                { title: "Severity", value: alert[:severity].upcase, short: true },
                { title: "Message", value: alert[:message], short: false },
                { title: "Runbook", value: alert[:runbook_url], short: false }
              ],
              footer: "OpenAI Agents Tracing",
              ts: alert[:checked_at].to_i
            }]
          }

          Net::HTTP.post(
            URI(@webhook_url),
            payload.to_json,
            { "Content-Type" => "application/json" }
          )
        end
      end

      class EmailHandler
        def initialize(recipients, smtp_config = nil)
          @recipients = recipients
          @smtp_config = smtp_config || Rails.application.config.action_mailer.smtp_settings
        end

        def handle(alert)
          subject = "🚨 #{alert[:severity].upcase}: #{alert[:rule_name].humanize}"
          body = generate_email_body(alert)

          @recipients.each do |recipient|
            AlertMailer.alert_notification(recipient, subject, body).deliver_now
          rescue StandardError => e
            Rails.logger.error "Failed to send alert email: #{e.message}"
          end
        end

        private

        def generate_email_body(alert)
          <<~BODY
            Alert Details:
            - Rule: #{alert[:rule_name]}
            - Severity: #{alert[:severity].upcase}
            - Message: #{alert[:message]}
            - Time: #{alert[:checked_at]}
            - Runbook: #{alert[:runbook_url]}

            Metrics:
            #{alert[:metrics].map { |k, v| "- #{k}: #{v}" }.join("\n")}

            --
            OpenAI Agents Tracing Alert System
          BODY
        end
      end
    end
  end
end
