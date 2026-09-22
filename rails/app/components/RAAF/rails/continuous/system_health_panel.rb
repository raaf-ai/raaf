# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # System status: what the queue is doing, what has alerted, and the
      # configuration in force.
      #
      # It rendered in the light theme, and it was in no menu — which is how
      # it came to raise `NoMethodError` on every request for a long time
      # without anybody noticing. It is in the Continuous group now, so it
      # gets looked at.
      #
      class SystemHealthPanel < RAAF::Rails::Tracing::BaseComponent
        def initialize(health_data: {}, alerts: [], config: {})
          @health_data = health_data || {}
          @alerts = Array(alerts)
          @config = config || {}
        end

        def view_template
          div(class: "raaf-page") do
            header
            metrics
            backpressure_notice if @health_data[:backpressure_active]
            alerts_card
            configuration_card
          end
        end

        # Molecules::Alert's own vocabulary, which is not the tone vocabulary
        # the KPI tiles use.
        SEVERITY_TONES = { "critical" => :error, "warning" => :warning }.freeze

        private

        def header
          render Organisms::RecordHead.new(
            title: "System status",
            description: "What the continuous evaluation queue is doing right now, " \
                         "and the configuration it is doing it under.",
            status: status_word.downcase,
            meta: "queue #{delimited(@health_data[:queue_depth].to_i)} deep"
          )
        end

        def metrics
          render Organisms::StatGrid.new(stats: [
                                           { label: "Status", value: status_word, icon: "activity",
                                             tone: status_tone, note: status_note },
                                           { label: "Queue depth",
                                             value: delimited(@health_data[:queue_depth].to_i),
                                             icon: "list-task", tone: queue_tone,
                                             note: queue_note },
                                           { label: "Processing rate",
                                             value: "#{(@health_data[:processing_rate] || 0).round(1)}/min",
                                             icon: "speedometer2", tone: :accent,
                                             note: "evaluations finished" },
                                           { label: "Active alerts", value: active_alerts.size.to_s,
                                             icon: "bell", tone: alerts_tone,
                                             note: alerts_note }
                                         ])
        end

        def backpressure_notice
          render(Molecules::Alert.new(:warning, title: "Backpressure is on")) do
            plain "New evaluations are being skipped so the queue can drain. " \
                  "The threshold is #{delimited(@config[:backpressure_threshold].to_i)}."
          end
        end

        # ── Queue ─────────────────────────────────────────────────────────

        def queue_note
          "#{delimited(@health_data[:pending_count].to_i)} pending · " \
            "#{delimited(@health_data[:running_count].to_i)} running"
        end

        # ── Alerts ────────────────────────────────────────────────────────

        def alerts_card
          render(Organisms::Card.new(title: "Recent alerts", subtitle: alerts_subtitle)) do
            if @alerts.empty?
              render Molecules::EmptyState.new(icon: "check-circle", title: "Nothing has alerted",
                                               text: "The system is operating normally.")
            else
              @alerts.first(5).each { |alert| alert_row(alert) }
            end
          end
        end

        def alerts_subtitle
          return nil if @alerts.empty?

          "#{pluralize(@alerts.size, 'alert')}, newest first"
        end

        def alert_row(alert)
          render(Molecules::Alert.new(SEVERITY_TONES.fetch(alert[:severity].to_s, :info),
                                      title: alert[:title].to_s)) do
            plain alert[:message].to_s
            div(class: "raaf-cluster") do
              render Atoms::StatusBadge.new(alert[:status].to_s)
              render Atoms::Mono.new(alert_meta(alert), tone: :muted)
            end
          end
        end

        # How many times it has fired matters as much as when: one occurrence
        # is an incident, forty is a condition.
        def alert_meta(alert)
          occurrences = alert[:occurrence_count].to_i

          [format_time(alert[:triggered_at]),
           (pluralize(occurrences, "occurrence") if occurrences > 1)].compact.join(" · ")
        end

        # ── Configuration ─────────────────────────────────────────────────

        def configuration_card
          render(Organisms::Card.new(title: "Configuration", flush: true)) do
            render Molecules::KeyValueList.new(pairs: config_pairs, layout: :rows,
                                               mono: true, flush: true)
          end
        end

        def config_pairs
          {
            "Continuous evaluation" => @config[:enabled] ? "on" : "off",
            "Span hooks" => @config[:hook_enabled] ? "on" : "off",
            "Default queue" => (@config[:default_queue_name] || "raaf_evaluations").to_s,
            "Max concurrent" => (@config[:max_concurrent_evaluations] || 10).to_s,
            "Backpressure threshold" => delimited((@config[:backpressure_threshold] || 1000).to_i)
          }
        end

        # ── Status ────────────────────────────────────────────────────────

        def active_alerts
          @active_alerts ||= @alerts.select { |alert| alert[:status].to_s == "active" }
        end

        def critical?
          active_alerts.any? { |alert| alert[:severity].to_s == "critical" }
        end

        def status_word
          return "Off" unless @config[:enabled]
          return "Backpressure" if @health_data[:backpressure_active]
          return "Degraded" if critical?

          "Healthy"
        end

        def status_tone
          return :idle unless @config[:enabled]
          return :warning if @health_data[:backpressure_active]
          return :danger if critical?
          return :warning if active_alerts.any?

          :success
        end

        # A disabled system is not a healthy one, and the two used to look
        # alike but for the colour.
        def status_note
          return "nothing is being evaluated" unless @config[:enabled]
          return "shedding load" if @health_data[:backpressure_active]

          active_alerts.any? ? "alerting" : "evaluating normally"
        end

        def queue_tone
          depth = @health_data[:queue_depth].to_i
          threshold = (@config[:backpressure_threshold] || 1000).to_i
          return :danger if depth > threshold
          return :warning if depth > threshold * 0.7

          :success
        end

        def alerts_tone
          return :danger if critical?
          return :warning if active_alerts.any?

          :success
        end

        def alerts_note
          return "nothing active" if active_alerts.empty?

          critical? ? "one or more critical" : "none critical"
        end

        def format_time(time)
          return "unknown" unless time

          time = Time.zone.parse(time) if time.is_a?(String)
          time.strftime("%Y-%m-%d %H:%M:%S")
        rescue StandardError
          "unknown"
        end
      end
    end
  end
end
