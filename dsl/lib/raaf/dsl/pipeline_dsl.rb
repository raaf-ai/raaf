# frozen_string_literal: true

require_relative "pipelineable"
require_relative "pipeline_dsl/wrapper_dsl"
require_relative "pipeline_dsl/chained_agent"
require_relative "pipeline_dsl/parallel_agents"
require_relative "pipeline_dsl/configured_agent"
require_relative "pipeline_dsl/field_mismatch_error"
require_relative "pipeline_dsl/pipeline"

module RAAF
  module DSL
    # Pipeline DSL for elegant agent chaining
    # Enables syntax like: Market::Analysis >> Market::Scoring >> Company::Search
    module PipelineDSL
      VERSION = "1.0.0"
    end
  end
end