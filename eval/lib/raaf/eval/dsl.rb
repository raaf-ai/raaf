# frozen_string_literal: true

module RAAF
  module Eval
    # DSL module for the RAAF Eval API
    module DSL
      # Autoload DSL components
      autoload :Builder, "raaf/eval/dsl/builder"
      autoload :FieldContext, "raaf/eval/dsl/field_context"
      autoload :FieldSelector, "raaf/eval/dsl/field_selector"
      autoload :EvaluatorConfig, "raaf/eval/dsl/evaluator_config"
      autoload :EvaluatorDefinition, "raaf/eval/dsl/evaluator_definition"
      autoload :EvaluationResult, "raaf/eval/dsl/evaluation_result"
    end
  end
end

# Require the core DSL components
require_relative "dsl/builder"
require_relative "dsl/field_context"
require_relative "dsl/field_selector"
require_relative "dsl/evaluator_config"
require_relative "dsl/evaluator_definition"
require_relative "dsl/evaluation_result"
