#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple coverage measurement script to estimate current test coverage

require 'simplecov'
require 'json'

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/examples/'
  add_filter '/vendor/'
end

# Manual require of source files to force loading
lib_dir = File.expand_path('lib', __dir__)
Dir.glob("#{lib_dir}/**/*.rb").each do |file|
  begin
    require_relative file.sub("#{__dir__}/", '')
  rescue LoadError, StandardError => e
    puts "Warning: Could not load #{file}: #{e.message}"
  end
end

# Estimate coverage by analyzing source vs test files
def analyze_coverage_potential
  puts "\n=== RAAF DSL Coverage Analysis ==="

  # Count source files
  source_files = Dir.glob('lib/**/*.rb')
  test_files = Dir.glob('spec/**/*_spec.rb')

  puts "📁 Source files: #{source_files.length}"
  puts "🧪 Test files: #{test_files.length}"

  # Analyze which source files have corresponding tests
  covered_files = []
  uncovered_files = []

  source_files.each do |source_file|
    # Remove lib/ prefix and .rb suffix
    relative_path = source_file.sub('lib/', '').sub('.rb', '')

    # Look for corresponding test file
    possible_test_files = [
      "spec/#{relative_path}_spec.rb",
      "spec/#{relative_path.split('/').last}_spec.rb"
    ]

    has_test = possible_test_files.any? { |test_file| File.exist?(test_file) }

    if has_test
      covered_files << source_file
    else
      uncovered_files << source_file
    end
  end

  coverage_percentage = (covered_files.length.to_f / source_files.length * 100).round(2)

  puts "\n📊 Estimated Coverage by File Presence:"
  puts "✅ Files with tests: #{covered_files.length} (#{coverage_percentage}%)"
  puts "❌ Files without tests: #{uncovered_files.length}"

  puts "\n🔍 Files potentially needing more test coverage:"
  uncovered_files.first(10).each do |file|
    puts "  - #{file}"
  end

  if uncovered_files.length > 10
    puts "  ... and #{uncovered_files.length - 10} more"
  end

  # Analyze core components
  puts "\n🎯 Core Component Analysis:"
  core_components = {
    'Agent' => source_files.select { |f| f.include?('agent') },
    'Pipeline' => source_files.select { |f| f.include?('pipeline') },
    'Context' => source_files.select { |f| f.include?('context') },
    'Prompts' => source_files.select { |f| f.include?('prompt') },
    'Tools' => source_files.select { |f| f.include?('tools') },
    'Builders' => source_files.select { |f| f.include?('builders') }
  }

  core_components.each do |component, files|
    next if files.empty?

    tested_files = files.select do |file|
      relative_path = file.sub('lib/', '').sub('.rb', '')
      possible_tests = [
        "spec/#{relative_path}_spec.rb",
        "spec/#{relative_path.split('/').last}_spec.rb"
      ]
      possible_tests.any? { |test_file| File.exist?(test_file) }
    end

    component_coverage = (tested_files.length.to_f / files.length * 100).round(1)
    puts "  #{component}: #{tested_files.length}/#{files.length} files (#{component_coverage}%)"
  end

  puts "\n📈 Recommendations to reach 75% coverage:"
  if coverage_percentage < 75
    needed_files = ((source_files.length * 0.75) - covered_files.length).ceil
    puts "  - Need to add tests for approximately #{needed_files} more files"
    puts "  - Focus on core components: Agent, Pipeline, Context"
    puts "  - Prioritize large, complex files first"
  else
    puts "  - Current file coverage suggests good test coverage potential!"
    puts "  - Focus on line coverage within existing test files"
  end

  # Recommend specific files to test
  puts "\n🎯 Priority files for testing (large, core functionality):"
  priority_files = uncovered_files.select do |file|
    file.include?('agent.rb') ||
    file.include?('pipeline') ||
    file.include?('context') ||
    file.include?('prompts') ||
    file.size > 1000  # Large files
  end

  priority_files.first(5).each do |file|
    size = File.size(file)
    puts "  - #{file} (#{size} bytes)"
  end
end

analyze_coverage_potential

puts "\n✅ Coverage analysis complete!"
puts "💡 Run individual test files to get actual line coverage with SimpleCov"