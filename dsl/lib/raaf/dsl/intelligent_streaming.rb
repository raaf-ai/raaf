# frozen_string_literal: true

require_relative "intelligent_streaming/config"
require_relative "intelligent_streaming/scope"
require_relative "intelligent_streaming/manager"
require_relative "intelligent_streaming/progress_context"
require_relative "intelligent_streaming/executor"

module RAAF
  module DSL
    # Intelligent Streaming module for RAAF Pipeline DSL
    #
    # Provides pipeline-level streaming with optional state management
    # and incremental result delivery. This module enables agents to
    # process large datasets in manageable streams while maintaining
    # state and providing progress updates.
    #
    # @example Basic streaming
    #   class MyAgent < RAAF::DSL::Agent
    #     intelligent_streaming stream_size: 100, over: :items
    #   end
    #
    # @example With state management
    #   class MyAgent < RAAF::DSL::Agent
    #     intelligent_streaming stream_size: 100, over: :items do
    #       skip_if { |record| record[:processed] }
    #       load_existing { |record| cache[record[:id]] }
    #       persist_each_stream { |results| save_to_db(results) }
    #     end
    #   end
    module IntelligentStreaming
      # Module method to configure intelligent streaming on an agent class
      #
      # @param agent_class [Class] The agent class to configure
      # @param stream_size [Integer] Number of items per stream
      # @param over [Symbol, nil] Field containing array to stream
      # @param incremental [Boolean] Enable incremental delivery
      # @param block [Proc] Configuration block
      def self.configure(agent_class, stream_size:, over: nil, incremental: false, &block)
        config = Config.new(
          stream_size: stream_size,
          over: over,
          incremental: incremental
        )

        # Apply configuration block if provided
        if block_given?
          config.instance_eval(&block)
        end

        # Store configuration on the agent class
        agent_class.instance_variable_set(:@_intelligent_streaming_config, config)

        # Define helper methods on the agent class
        agent_class.define_singleton_method(:streaming_config) do
          @_intelligent_streaming_config
        end

        agent_class.define_singleton_method(:streaming_trigger?) do
          !@_intelligent_streaming_config.nil?
        end

        agent_class.define_singleton_method(:streaming_config?) do
          !@_intelligent_streaming_config.nil?
        end

        config
      end
    end
  end
end