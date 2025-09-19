# frozen_string_literal: true

require 'simplecov'

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/examples/'
  add_filter '/vendor/'

  # Coverage groups
  add_group 'Core', 'lib/raaf/dsl/core'
  add_group 'Agents', 'lib/raaf/dsl/agent'
  add_group 'Pipeline DSL', 'lib/raaf/dsl/pipeline'
  add_group 'Prompts', 'lib/raaf/dsl/prompts'
  add_group 'Tools', 'lib/raaf/dsl/tools'
  add_group 'Builders', 'lib/raaf/dsl/builders'
  add_group 'Context', ['lib/raaf/dsl/context', 'lib/raaf/dsl/core/context']
  add_group 'Debugging', 'lib/raaf/dsl/debugging'
  add_group 'Hooks', 'lib/raaf/dsl/hooks'
  add_group 'Main', 'lib/raaf-dsl.rb'

  # Coverage thresholds
  minimum_coverage 75
  minimum_coverage_by_file 60

  # Output formats
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter
  ])
end

puts "SimpleCov configured with 75% minimum coverage target"