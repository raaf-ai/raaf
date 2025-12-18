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
                      :max_concurrent_evaluations, :hook_enabled,
                      :backpressure_active, :backpressure_threshold,
                      :register_built_in_evaluators, :evaluator_paths

        def initialize
          @enabled = true                           # Opt-out: enabled by default
          @default_queue_name = "raaf_evaluations"
          @default_priority = 50
          @max_concurrent_evaluations = 10
          @hook_enabled = true                      # Span hooks enabled by default
          @backpressure_active = false              # Set by BackpressureMonitorJob
          @backpressure_threshold = 1000            # Queue depth threshold
          @register_built_in_evaluators = false     # Only use application-defined evaluators by default
          @evaluator_paths = []                     # Paths to directories containing custom evaluator files
        end

        ##
        # Add a path to the list of evaluator paths.
        # Files in these directories will be loaded on first evaluator discovery.
        # @param path [String, Pathname] Path to evaluator directory
        def add_evaluator_path(path)
          @evaluator_paths << path.to_s unless @evaluator_paths.include?(path.to_s)
        end
      end
    end
  end
end

require_relative "continuous/evaluator_discovery"
require_relative "continuous/policy_matcher"
