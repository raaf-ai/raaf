# frozen_string_literal: true

module RAAF
  module Eval
    module RSpec
      ##
      # Configuration for RSpec integration
      #
      # This class manages RSpec-specific configuration separate from the global
      # RAAF::Eval configuration.
      class Configuration
        attr_accessor :llm_judge_model, :llm_judge_temperature, :llm_judge_cache, :llm_judge_timeout,
                      :enable_parallel_execution, :max_parallel_workers, :enable_cost_tracking, :fail_fast, :evaluation_timeout

        def initialize
          @llm_judge_model = RAAF::Eval.configuration.llm_judge_model
          @llm_judge_temperature = RAAF::Eval.configuration.llm_judge_temperature
          @llm_judge_cache = RAAF::Eval.configuration.llm_judge_cache
          @llm_judge_timeout = RAAF::Eval.configuration.llm_judge_timeout
          @enable_parallel_execution = false
          @max_parallel_workers = 4
          @enable_cost_tracking = true
          @fail_fast = false
          @evaluation_timeout = 300 # 5 minutes default
        end
      end
    end
  end
end
