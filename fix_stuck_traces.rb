#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to fix stuck traces in RAAF Rails tracing system
# Usage: ruby fix_stuck_traces.rb

puts "🔧 RAAF Trace Repair Tool"
puts "=" * 50

# Check if we're in Rails environment
if defined?(Rails)
  puts "✅ Rails environment detected"
else
  puts "⚠️  Loading Rails environment..."
  require_relative '../../config/environment'
end

# Import TraceRecord
require_relative 'rails/app/models/RAAF/rails/tracing/trace_record'
TraceRecord = RAAF::Rails::Tracing::TraceRecord

puts "\n📊 Current trace status summary:"
puts "-" * 30

# Show current status counts
%w[pending running completed failed skipped].each do |status|
  count = TraceRecord.where(status: status).count
  puts "#{status.capitalize.ljust(10)} #{count}"
end

puts "\n🔍 Analyzing stuck traces..."

# Find traces that have been running for more than 5 minutes
stuck_traces = TraceRecord.running.where("started_at < ?", 5.minutes.ago)

if stuck_traces.empty?
  puts "✅ No stuck traces found!"
else
  puts "🚨 Found #{stuck_traces.count} stuck traces:"

  stuck_traces.each do |trace|
    puts "\n  Trace: #{trace.trace_id}"
    puts "    Workflow: #{trace.workflow_name}"
    puts "    Started: #{trace.started_at}"
    puts "    Duration: #{((Time.current - trace.started_at) / 60).round(1)} minutes"
    puts "    Spans: #{trace.spans.count}"

    # Show span statuses
    span_statuses = trace.spans.pluck(:status).tally
    puts "    Span statuses: #{span_statuses}"

    # Check if all spans are in final states
    final_states = %w[ok error cancelled skipped]
    all_final = trace.spans.pluck(:status).all? { |s| final_states.include?(s) }
    puts "    All spans final: #{all_final}"
  end

  puts "\n🔧 Attempting to fix stuck traces..."
  fixed_count = TraceRecord.fix_stuck_traces
  puts "✅ Fixed #{fixed_count} traces"

  if fixed_count > 0
    puts "\n📊 Updated trace status summary:"
    puts "-" * 30
    %w[pending running completed failed skipped].each do |status|
      count = TraceRecord.where(status: status).count
      puts "#{status.capitalize.ljust(10)} #{count}"
    end
  end
end

puts "\n✨ Trace repair complete!"