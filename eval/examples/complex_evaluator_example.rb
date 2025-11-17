# frozen_string_literal: true

# Example: Complex Evaluator with Multiple Fields and History
#
# This example demonstrates advanced features of the EvaluatorDefinition module
# including multiple field selections, complex evaluation logic, progress callbacks,
# and historical tracking.

require 'raaf/eval'

class ComprehensiveQualityEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  # Select multiple fields
  select 'output', as: :output
  select 'usage.total_tokens', as: :tokens
  select 'usage.prompt_tokens', as: :prompt_tokens

  # Define evaluation for output field with combined criteria
  evaluate_field :output do
    evaluate_with :semantic_similarity, threshold: 0.85
    evaluate_with :no_regression
    combine_with :and  # Both criteria must pass
  end

  # Define evaluation for token usage
  evaluate_field :tokens do
    evaluate_with :token_efficiency, max_increase_pct: 15
  end

  # Register progress callback for monitoring
  on_progress do |event|
    puts "[#{Time.now}] #{event.status}: #{event.progress}%"
  end

  # Configure historical tracking
  history auto_save: true, retention_count: 100, retention_days: 90
end

# Usage Example
evaluator = ComprehensiveQualityEvaluator.evaluator
puts "Evaluator created: #{evaluator.class.name}"

# Configuration inspection
config = ComprehensiveQualityEvaluator.instance_variable_get(:@_evaluator_config)
puts "\nConfiguration:"
puts "- Fields selected: #{config[:selections].map { |s| s[:as] }.join(', ')}"
puts "- Fields evaluated: #{config[:field_evaluations].keys.join(', ')}"
puts "- Progress callback: #{config[:progress_callback] ? 'Yes' : 'No'}"
puts "- History enabled: #{config[:history_options][:auto_save]}"

# The evaluator can now be used to evaluate spans
# result = evaluator.evaluate(span)
