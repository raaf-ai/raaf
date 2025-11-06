# frozen_string_literal: true

module RAAF
  module Eval
    module Metrics
      ##
      # CustomMetric base class for domain-specific metrics
      class CustomMetric
        # @return [String] Metric name
        attr_reader :name

        ##
        # Initialize custom metric
        # @param name [String] Metric name
        def initialize(name)
          @name = name
        end

        ##
        # Calculate metric (to be overridden)
        # @param baseline_span [Object] Baseline span
        # @param result_span [Object] Result span
        # @return [Hash] Metric results
        def calculate(baseline_span, result_span)
          raise NotImplementedError, "Subclasses must implement calculate method"
        end

        ##
        # Whether metric calculation is asynchronous
        # @return [Boolean]
        def async?
          false
        end

        ##
        # Registry for custom metrics
        class Registry
          @metrics = {}
          @mutex = Mutex.new

          class << self
            ##
            # Register a custom metric
            # @param metric [CustomMetric] Metric instance
            def register(metric)
              @mutex.synchronize do
                @metrics[metric.name] = metric
              end
            end

            ##
            # Get registered metric by name
            # @param name [String] Metric name
            # @return [CustomMetric, nil]
            def get(name)
              @mutex.synchronize do
                @metrics[name]
              end
            end

            ##
            # Get all registered metrics
            # @return [Hash<String, CustomMetric>]
            def all
              @mutex.synchronize do
                @metrics.dup
              end
            end

            ##
            # Clear all registered metrics (for testing)
            def clear!
              @mutex.synchronize do
                @metrics.clear
              end
            end
          end
        end
      end
    end
  end
end
