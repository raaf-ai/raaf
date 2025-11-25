# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # Continuous evaluation module for database-driven automatic evaluation.
    # Provides policy-based span evaluation with configurable sampling.
    module Continuous
      class << self
        ##
        # Check if continuous evaluation is enabled
        # @return [Boolean]
        def enabled?
          configuration.enabled
        end

        ##
        # Enable continuous evaluation
        def enable!
          configuration.enabled = true
        end

        ##
        # Disable continuous evaluation
        def disable!
          configuration.enabled = false
        end

        ##
        # Configuration object for continuous evaluation
        # @return [Configuration]
        def configuration
          @configuration ||= Configuration.new
        end

        ##
        # Configure continuous evaluation
        # @yield [Configuration]
        def configure
          yield(configuration) if block_given?
        end
      end

      ##
      # Configuration for continuous evaluation
      class Configuration
        attr_accessor :enabled, :default_queue_name, :default_priority,
                      :max_concurrent_evaluations, :hook_enabled

        def initialize
          @enabled = true
          @default_queue_name = "raaf_evaluations"
          @default_priority = 50
          @max_concurrent_evaluations = 10
          @hook_enabled = true
        end
      end
    end
  end
end

require_relative "continuous/evaluator_discovery"
require_relative "continuous/policy_matcher"
