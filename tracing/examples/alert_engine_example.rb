#!/usr/bin/env ruby
# frozen_string_literal: true

# Alert Engine Example
#
# Demonstrates comprehensive alerting system with multiple handlers for
# automated notifications when issues occur in agent workflows.

require_relative "../raaf/lib/raaf"

puts "=== Alert Engine Example ==="
puts "Demonstrates automated alerting and notification system"
puts "-" * 60

# Setup Alert Engine
alert_engine = RAAF::Tracing::AlertEngine.new

# Configure alert handlers
alert_engine.add_handler(:console, RAAF::Tracing::AlertHandlers::Console.new)
alert_engine.add_handler(:slack, RAAF::Tracing::AlertHandlers::Slack.new(
  webhook_url: "https://hooks.slack.com/demo",
  channel: "#ai-agents-alerts"
))

puts "✅ Alert Engine configured with #{alert_engine.handlers.length} handlers"

# Setup alert rules
alert_rules = [
  {
    name: "high_cost",
    condition: ->(data) { data[:cost] > 0.10 },
    severity: :warning,
    message: "High cost operation detected: $%{cost}"
  },
  {
    name: "slow_response",
    condition: ->(data) { data[:duration] > 5000 },
    severity: :critical,
    message: "Slow response time: %{duration}ms"
  },
  {
    name: "error_rate",
    condition: ->(data) { data[:error_rate] > 0.05 },
    severity: :error,
    message: "High error rate: %{error_rate}%"
  }
]

alert_rules.each { |rule| alert_engine.add_rule(rule) }
puts "📋 Added #{alert_rules.length} alert rules"

# Simulate alert triggers
test_events = [
  { cost: 0.15, duration: 1200, error_rate: 0.02 },  # High cost alert
  { cost: 0.05, duration: 7500, error_rate: 0.01 },  # Slow response alert
  { cost: 0.03, duration: 800, error_rate: 0.08 }    # High error rate alert
]

puts "\n=== Alert Testing ==="
test_events.each_with_index do |event, i|
  puts "Event #{i+1}: Cost=$#{event[:cost]}, Duration=#{event[:duration]}ms, Errors=#{event[:error_rate]}%"
  
  triggered_alerts = alert_engine.process_event(event)
  if triggered_alerts.any?
    triggered_alerts.each do |alert|
      puts "  🚨 #{alert[:severity].upcase}: #{alert[:message]}"
    end
  else
    puts "  ✅ No alerts triggered"
  end
end

puts "\n✅ Alert Engine example completed"