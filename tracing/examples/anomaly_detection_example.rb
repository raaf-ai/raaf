#!/usr/bin/env ruby
# frozen_string_literal: true

# Anomaly Detection Example
#
# Demonstrates statistical anomaly detection for monitoring agent performance,
# costs, and behavior patterns using multiple algorithms.

require "raaf"

puts "=== Anomaly Detection Example ==="
puts "Demonstrates statistical monitoring and anomaly detection"
puts "-" * 60

# Setup Anomaly Detector
anomaly_detector = RAAF::Tracing::AnomalyDetector.new(
  algorithms: %i[z_score iqr isolation_forest],
  sensitivity: 0.95,
  min_data_points: 10
)

puts "✅ Anomaly Detector configured with #{anomaly_detector.algorithms.length} algorithms"

# Example anomaly detection
performance_data = [
  { timestamp: Time.now - 3600, response_time: 1200, cost: 0.05 },
  { timestamp: Time.now - 1800, response_time: 1100, cost: 0.04 },
  { timestamp: Time.now - 900, response_time: 5500, cost: 0.15 }, # Anomaly
  { timestamp: Time.now, response_time: 1150, cost: 0.05 }
]

puts "\n=== Anomaly Detection Results ==="
anomalies = anomaly_detector.detect_anomalies(performance_data)

if anomalies.any?
  puts "🚨 Anomalies detected:"
  anomalies.each do |anomaly|
    puts "  - #{anomaly[:type]}: #{anomaly[:description]}"
    puts "    Confidence: #{anomaly[:confidence]}%"
  end
else
  puts "✅ No anomalies detected"
end

puts "\n✅ Anomaly Detection example completed"
