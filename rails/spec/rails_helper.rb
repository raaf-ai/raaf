# frozen_string_literal: true

require_relative "spec_helper"

# The engine is isolated, so its own url_helpers generate paths relative to the
# engine root. Telling them where the dummy application mounted it makes
# `continuous_policies_path` produce the same string a browser would ask for.
RAAF::Rails::Engine.routes.default_url_options[:script_name] = "/raaf"

# The specs address engine routes by their own names -- `continuous_policies_path`
# reads in a spec the way it reads in a controller -- rather than through the
# `raaf_rails.` mount proxy, so the engine's helpers are included directly.
module EngineRouteHelpers
  include RAAF::Rails::Engine.routes.url_helpers
end

# The continuous evaluation tables belong to raaf-eval. The specs name them the
# way the screens talk about them, which is shorter than the class names.
EvaluationPolicy = RAAF::Eval::Models::EvaluationPolicy unless defined?(EvaluationPolicy)
EvaluationQueue = RAAF::Eval::Models::EvaluationQueueItem unless defined?(EvaluationQueue)
EvaluationResult = RAAF::Eval::Models::ContinuousEvaluationResult unless defined?(EvaluationResult)
EvaluationMetric = RAAF::Eval::Models::EvaluationMetric unless defined?(EvaluationMetric)

RSpec.configure do |config|
  config.include EngineRouteHelpers
end
