# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # Represents a single evaluation run
    #
    # This class encapsulates the execution of an evaluation, including configuration,
    # baseline span, and result collection.
    class EvaluationRun
      attr_reader :id, :span, :configurations, :results, :metadata

      ##
      # Creates a new evaluation run
      #
      # @param span [Hash] the baseline span
      # @param configurations [Hash] map of configuration names to settings
      # @param metadata [Hash] additional metadata about the evaluation
      def initialize(span:, configurations: {}, metadata: {})
        @id = SecureRandom.uuid
        @span = span
        @configurations = configurations
        @results = {}
        @metadata = metadata
        @executed = false
      end

      ##
      # Executes all configurations
      #
      # @param async [Boolean] whether to run asynchronously
      # @return [Hash] results mapped by configuration name
      def execute(async: false)
        return @results if @executed

        if async && configurations.size > 1
          execute_async
        else
          execute_sync
        end

        @executed = true
        @results
      end

      ##
      # Checks if evaluation has been executed
      #
      # @return [Boolean]
      def executed?
        @executed
      end

      ##
      # Gets result for a specific configuration
      #
      # @param config_name [Symbol, String] configuration name
      # @return [Hash] the result
      def result_for(config_name)
        @results[config_name.to_sym]
      end

      private

      def execute_sync
        configurations.each do |name, config|
          engine = Engine.new(span: span, configuration_overrides: config)
          @results[name.to_sym] = engine.execute
        end
      end

      def execute_async
        threads = configurations.map do |name, config|
          Thread.new do
            engine = Engine.new(span: span, configuration_overrides: config)
            [name.to_sym, engine.execute]
          end
        end

        threads.each do |thread|
          name, result = thread.value
          @results[name] = result
        end
      end
    end
  end
end
