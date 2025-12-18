# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # SystemHealthPanel displays system health metrics and alerts for the
      # continuous evaluation system.
      #
      # Shows:
      # - Queue status (pending, running, backlog)
      # - Recent alerts
      # - Backpressure status
      # - Processing rate
      # - System configuration
      class SystemHealthPanel < RAAF::Rails::Tracing::BaseComponent
        def initialize(health_data: {}, alerts: [], config: {})
          @health_data = health_data
          @alerts = alerts
          @config = config
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_status_overview
            render_queue_metrics
            render_alerts_section
            render_configuration_section
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6 pb-4 border-b border-gray-200") do
            div do
              h1(class: "text-2xl font-bold text-gray-900") { "System Health" }
              p(class: "mt-1 text-sm text-gray-500") { "Continuous evaluation system status and alerts" }
            end

            div(class: "mt-4 sm:mt-0 flex gap-2") do
              render_preline_button(
                text: "Refresh",
                href: "javascript:window.location.reload();",
                variant: "secondary",
                icon: "bi-arrow-clockwise"
              )
            end
          end
        end

        def render_status_overview
          div(class: "grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4 mb-6") do
            render_status_card(
              "System Status",
              system_status_text,
              system_status_icon,
              system_status_color
            )
            render_stat_card(
              "Queue Depth",
              @health_data[:queue_depth] || 0,
              "bi-list-task",
              queue_depth_color
            )
            render_stat_card(
              "Processing Rate",
              "#{(@health_data[:processing_rate] || 0).round(1)}/min",
              "bi-speedometer2",
              "blue"
            )
            render_stat_card(
              "Active Alerts",
              @alerts.count { |a| a[:status] == 'active' },
              "bi-bell",
              active_alerts_color
            )
          end
        end

        def render_status_card(label, value, icon, color)
          border_color = "border-#{color}-500"
          text_color = "text-#{color}-600"
          icon_bg = "text-#{color}-200"

          div(class: "bg-white shadow rounded-lg overflow-hidden border-l-4 #{border_color}") do
            div(class: "px-4 py-5 sm:p-6") do
              div(class: "flex justify-between items-center") do
                div do
                  div(class: "text-2xl font-bold #{text_color}") { value }
                  p(class: "text-sm text-gray-500") { label }
                end
                i(class: "bi #{icon} text-4xl #{icon_bg}")
              end
            end
          end
        end

        def render_stat_card(label, value, icon, color)
          render_status_card(label, value.to_s, icon, color)
        end

        def render_queue_metrics
          div(class: "bg-white shadow rounded-lg overflow-hidden mb-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "Queue Metrics" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              div(class: "grid grid-cols-2 sm:grid-cols-4 gap-4") do
                render_metric_item("Pending", @health_data[:pending_count] || 0, "text-yellow-600")
                render_metric_item("Running", @health_data[:running_count] || 0, "text-blue-600")
                render_metric_item("Completed (1h)", @health_data[:completed_1h] || 0, "text-green-600")
                render_metric_item("Failed (1h)", @health_data[:failed_1h] || 0, "text-red-600")
              end

              # Backpressure indicator
              if @health_data[:backpressure_active]
                div(class: "mt-4 p-4 bg-yellow-50 border border-yellow-200 rounded-md") do
                  div(class: "flex") do
                    i(class: "bi bi-exclamation-triangle text-yellow-400 mr-3")
                    div do
                      h4(class: "text-sm font-medium text-yellow-800") { "Backpressure Active" }
                      p(class: "mt-1 text-sm text-yellow-700") do
                        "New evaluations are being skipped to allow the queue to drain. " \
                        "Threshold: #{@health_data[:backpressure_threshold] || 'N/A'}"
                      end
                    end
                  end
                end
              end
            end
          end
        end

        def render_metric_item(label, value, color_class)
          div(class: "text-center") do
            div(class: "text-3xl font-bold #{color_class}") { value.to_s }
            p(class: "text-sm text-gray-500") { label }
          end
        end

        def render_alerts_section
          div(class: "bg-white shadow rounded-lg overflow-hidden mb-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200 flex justify-between items-center") do
              h3(class: "text-lg font-medium text-gray-900") { "Recent Alerts" }
              if @alerts.any?
                span(class: "text-sm text-gray-500") { "#{@alerts.count} alerts" }
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              if @alerts.any?
                div(class: "space-y-4") do
                  @alerts.first(5).each do |alert|
                    render_alert_item(alert)
                  end
                end
              else
                render_empty_alerts
              end
            end
          end
        end

        def render_alert_item(alert)
          severity_classes = case alert[:severity]
                             when 'critical' then 'bg-red-50 border-red-200'
                             when 'warning' then 'bg-yellow-50 border-yellow-200'
                             else 'bg-blue-50 border-blue-200'
                             end

          severity_icon = case alert[:severity]
                          when 'critical' then 'bi-x-circle text-red-500'
                          when 'warning' then 'bi-exclamation-triangle text-yellow-500'
                          else 'bi-info-circle text-blue-500'
                          end

          status_badge = case alert[:status]
                         when 'active' then 'bg-red-100 text-red-800'
                         when 'acknowledged' then 'bg-yellow-100 text-yellow-800'
                         when 'resolved' then 'bg-green-100 text-green-800'
                         else 'bg-gray-100 text-gray-800'
                         end

          div(class: "p-4 border rounded-md #{severity_classes}") do
            div(class: "flex items-start") do
              i(class: "bi #{severity_icon} mt-0.5 mr-3")
              div(class: "flex-1") do
                div(class: "flex items-center justify-between") do
                  h4(class: "text-sm font-medium text-gray-900") { alert[:title] }
                  span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{status_badge}") do
                    alert[:status]
                  end
                end
                p(class: "mt-1 text-sm text-gray-600") { alert[:message] }
                div(class: "mt-2 text-xs text-gray-500") do
                  span { "Triggered: #{format_time(alert[:triggered_at])}" }
                  if alert[:occurrence_count] && alert[:occurrence_count] > 1
                    span(class: "ml-4") { "Occurrences: #{alert[:occurrence_count]}" }
                  end
                end
              end
            end
          end
        end

        def render_empty_alerts
          div(class: "flex flex-col items-center justify-center py-12") do
            i(class: "bi bi-check-circle text-5xl text-green-400")
            h3(class: "mt-4 text-lg font-medium text-gray-900") { "No active alerts" }
            p(class: "mt-1 text-sm text-gray-500") { "System is operating normally" }
          end
        end

        def render_configuration_section
          div(class: "bg-white shadow rounded-lg overflow-hidden") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-medium text-gray-900") { "System Configuration" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              dl(class: "grid grid-cols-1 gap-4 sm:grid-cols-2") do
                render_config_item("Continuous Evaluation", @config[:enabled] ? "Enabled" : "Disabled")
                render_config_item("Span Hooks", @config[:hook_enabled] ? "Enabled" : "Disabled")
                render_config_item("Default Queue", @config[:default_queue_name] || "raaf_evaluations")
                render_config_item("Max Concurrent", @config[:max_concurrent_evaluations] || 10)
                render_config_item("Backpressure Threshold", @config[:backpressure_threshold] || 1000)
              end
            end
          end
        end

        def render_config_item(label, value)
          div(class: "py-2 sm:py-3") do
            dt(class: "text-sm font-medium text-gray-500") { label }
            dd(class: "mt-1 text-sm text-gray-900") { value.to_s }
          end
        end

        # Helper methods

        def system_status_text
          return "Disabled" unless @config[:enabled]
          return "Backpressure" if @health_data[:backpressure_active]
          return "Degraded" if @alerts.any? { |a| a[:status] == 'active' && a[:severity] == 'critical' }
          "Healthy"
        end

        def system_status_icon
          return "bi-x-circle" unless @config[:enabled]
          return "bi-pause-circle" if @health_data[:backpressure_active]
          return "bi-exclamation-circle" if @alerts.any? { |a| a[:status] == 'active' }
          "bi-check-circle"
        end

        def system_status_color
          return "gray" unless @config[:enabled]
          return "yellow" if @health_data[:backpressure_active]
          return "red" if @alerts.any? { |a| a[:status] == 'active' && a[:severity] == 'critical' }
          return "yellow" if @alerts.any? { |a| a[:status] == 'active' }
          "green"
        end

        def queue_depth_color
          depth = @health_data[:queue_depth] || 0
          threshold = @config[:backpressure_threshold] || 1000
          return "red" if depth > threshold
          return "yellow" if depth > threshold * 0.7
          "green"
        end

        def active_alerts_color
          active = @alerts.count { |a| a[:status] == 'active' }
          return "red" if active > 0 && @alerts.any? { |a| a[:status] == 'active' && a[:severity] == 'critical' }
          return "yellow" if active > 0
          "green"
        end

        def format_time(time)
          return "Unknown" unless time
          time = Time.parse(time) if time.is_a?(String)
          time.strftime("%Y-%m-%d %H:%M:%S")
        rescue
          "Unknown"
        end
      end
    end
  end
end
