#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyze current test coverage without requiring all files

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

  puts "\n🔍 Files needing test coverage:"
  uncovered_files.each do |file|
    size = File.size(file)
    puts "  - #{file} (#{size} bytes)"
  end

  # Analyze core components
  puts "\n🎯 Core Component Analysis:"
  core_components = {
    'Agent' => source_files.select { |f| f.include?('agent') },
    'Pipeline' => source_files.select { |f| f.include?('pipeline') },
    'Context' => source_files.select { |f| f.include?('context') },
    'Prompts' => source_files.select { |f| f.include?('prompt') },
    'Tools' => source_files.select { |f| f.include?('tools') },
    'Builders' => source_files.select { |f| f.include?('builders') },
    'Schema' => source_files.select { |f| f.include?('schema') },
    'Core' => source_files.select { |f| f.include?('core/') }
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
    status = component_coverage >= 75 ? "✅" : component_coverage >= 50 ? "⚠️" : "❌"
    puts "  #{status} #{component}: #{tested_files.length}/#{files.length} files (#{component_coverage}%)"

    if component_coverage < 75
      untested = files - tested_files
      untested.first(3).each do |file|
        puts "    📝 Missing: #{file}"
      end
    end
  end

  puts "\n📈 To reach 75% coverage:"
  if coverage_percentage < 75
    needed_files = ((source_files.length * 0.75) - covered_files.length).ceil
    puts "  - Need to add tests for #{needed_files} more files"
    puts "  - Current file coverage: #{coverage_percentage}%"
    puts "  - Target: 75%"
  else
    puts "  - File coverage looks good! Focus on line coverage within tests"
  end

  # Line count analysis
  puts "\n📏 Source file size analysis:"
  large_files = source_files.map { |f| [f, File.size(f)] }
                           .sort_by { |_, size| -size }
                           .first(10)

  large_files.each do |file, size|
    has_test = covered_files.include?(file)
    status = has_test ? "✅" : "❌"
    puts "  #{status} #{file} (#{size} bytes)"
  end

  # Specific recommendations
  puts "\n🎯 Priority areas for 75% coverage:"

  priority_files = uncovered_files.select do |file|
    file.include?('agent.rb') ||
    file.include?('pipeline') ||
    file.include?('context') ||
    file.include?('prompts') ||
    File.size(file) > 1000
  end.sort_by { |f| -File.size(f) }

  if priority_files.any?
    puts "  High-impact files to test:"
    priority_files.first(5).each do |file|
      size = File.size(file)
      puts "    📝 #{file} (#{size} bytes)"
    end
  end

  # Test quality analysis
  puts "\n📋 Test file analysis:"
  large_test_files = test_files.map { |f| [f, File.size(f)] }
                              .sort_by { |_, size| -size }
                              .first(5)

  puts "  Largest test files (likely comprehensive):"
  large_test_files.each do |file, size|
    puts "    ✅ #{file} (#{size} bytes)"
  end

  # Coverage goal calculation
  total_source_lines = source_files.sum { |f| File.readlines(f).count rescue 0 }
  puts "\n📊 Line coverage estimation:"
  puts "  Total source lines: ~#{total_source_lines}"
  puts "  Lines needed for 75%: ~#{(total_source_lines * 0.75).to_i}"
  puts "  Current coverage: 14.34% (640 lines)"
  puts "  Lines to cover: ~#{(total_source_lines * 0.75).to_i - 640}"
end

analyze_coverage_potential

puts "\n✅ Coverage analysis complete!"
puts "🚨 Note: Syntax error in declarative_pipeline.rb prevents full testing"