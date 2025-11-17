# frozen_string_literal: true

# Example: Simple Evaluator using EvaluatorDefinition module
#
# This example demonstrates the clean, declarative syntax for defining
# evaluators using the RAAF::Eval::DSL::EvaluatorDefinition module.

require 'raaf/eval'

class SimpleOutputEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  # Select fields for evaluation
  select 'output', as: :output

  # Define evaluation criteria for output field
  evaluate_field :output do
    evaluate_with :semantic_similarity, threshold: 0.85
  end
end

# Usage
evaluator = SimpleOutputEvaluator.evaluator

# Evaluator is automatically cached
evaluator2 = SimpleOutputEvaluator.evaluator
puts evaluator.object_id == evaluator2.object_id  # => true

# Reset cache for testing
SimpleOutputEvaluator.reset_evaluator!
evaluator3 = SimpleOutputEvaluator.evaluator
puts evaluator3.object_id == evaluator.object_id  # => false (rebuilt)
