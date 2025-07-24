#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

# Run RSpec to generate coverage report
puts "Running RSpec to generate coverage report..."
system("bundle exec rspec --format progress > /dev/null 2>&1")

# Read SimpleCov result
coverage_file = File.join(Dir.pwd, "coverage", ".resultset.json")

unless File.exist?(coverage_file)
  puts "Coverage file not found. Please run tests first."
  exit 1
end

coverage_data = JSON.parse(File.read(coverage_file))
files_coverage = coverage_data.dig("RSpec", "coverage") || {}

# Calculate coverage percentages
file_stats = []

files_coverage.each do |file_path, lines|
  next unless file_path.include?("lib/raaf")
  next if file_path.include?("spec/")

  total_lines = 0
  covered_lines = 0

  lines.each do |line_coverage|
    next if line_coverage.nil? # Skip non-executable lines

    total_lines += 1
    covered_lines += 1 if line_coverage.is_a?(Integer) && line_coverage.positive?
  end

  next if total_lines.zero?

  coverage_percentage = (covered_lines.to_f / total_lines * 100).round(2)
  relative_path = file_path.gsub("#{Dir.pwd}/", "")

  file_stats << {
    file: relative_path,
    total_lines: total_lines,
    covered_lines: covered_lines,
    coverage: coverage_percentage
  }
end

# Sort by coverage percentage (lowest first)
file_stats.sort_by! { |stat| stat[:coverage] }

puts "\n=== FILES WITH LOWEST TEST COVERAGE ==="
puts "#{file_stats.length} files analyzed\n"

# Show bottom 20 files
file_stats.first(20).each_with_index do |stat, index|
  puts format("%<index>2d. %<file>-60s %<coverage>6.2f%% (%<covered>d/%<total>d lines)",
              index: index + 1,
              file: stat[:file],
              coverage: stat[:coverage],
              covered: stat[:covered_lines],
              total: stat[:total_lines])
end

# Summary statistics
if file_stats.length.positive?
  avg_coverage = file_stats.map { |s| s[:coverage] }.sum / file_stats.length
  zero_coverage_count = file_stats.count { |s| s[:coverage] == 0.0 }

  puts "\n=== SUMMARY ==="
  puts "Average coverage: #{avg_coverage.round(2)}%"
  puts "Files with 0% coverage: #{zero_coverage_count}"
  puts "Files with < 10% coverage: #{file_stats.count { |s| s[:coverage] < 10.0 }}"
  puts "Files with < 50% coverage: #{file_stats.count { |s| s[:coverage] < 50.0 }}"
end
