# frozen_string_literal: true

require_relative "intelligent_streaming"
require "concurrent"

module RAAF
  module DSL
    # Module containing intelligent streaming methods for Agent class
    # This is mixed into Agent to provide streaming functionality
    module AgentStreamingMethods
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Configure intelligent streaming for this agent to process large arrays efficiently
        #
        # Intelligent streaming enables pipeline-level processing of large arrays by splitting
        # them into configurable streams and executing all scope agents for each stream
        # sequentially. This provides memory efficiency, state management, and incremental
        # result delivery.
        #
        # @param stream_size [Integer] Number of items to process per stream (required, must be positive)
        # @param over [Symbol, nil] Field name containing the array to stream (optional, auto-detected if nil)
        # @param incremental [Boolean] Enable per-stream callbacks for incremental delivery (default: false)
        # @param override [Boolean] Allow overriding existing configuration (default: false)
        # @yield [Config] Configuration block for state management and progress hooks
        #
        # @raise [ArgumentError] if stream_size is not a positive integer
        # @raise [ConfigurationError] if already configured without override: true
        #
        # @return [void]
        #
        # @example Basic streaming - process 100 items at a time
        #   class MyAgent < RAAF::DSL::Agent
        #     intelligent_streaming stream_size: 100, over: :companies
        #   end
        #
        # @example With state management - skip processed, load cached, persist progress
        #   class MyAgent < RAAF::DSL::Agent
        #     intelligent_streaming stream_size: 100, over: :items do
        #       # Skip already processed records
        #       skip_if { |record| ProcessedRecords.exists?(id: record[:id]) }
        #
        #       # Load existing results from cache
        #       load_existing { |record| Rails.cache.read("item_#{record[:id]}") }
        #
        #       # Save results after each stream
        #       persist_each_stream { |results| BulkInsert.insert_all(results) }
        #     end
        #   end
        #
        # @example With incremental delivery and progress tracking
        #   class MyAgent < RAAF::DSL::Agent
        #     intelligent_streaming stream_size: 50, incremental: true do
        #       on_stream_start { |num, total, data|
        #         Rails.logger.info "Starting stream #{num}/#{total}"
        #       }
        #
        #       on_stream_complete { |num, total, data, results|
        #         Rails.logger.info "Completed stream #{num}/#{total}"
        #         BackgroundJob.enqueue(results)  # Process immediately
        #       }
        #
        #       on_stream_error { |num, total, data, error|
        #         Rails.logger.error "Stream #{num} failed: #{error}"
        #         ErrorTracker.report(error)
        #       }
        #     end
        #   end
        #
        # @example Cost optimization with filtering
        #   class FilterAgent < RAAF::DSL::Agent
        #     model "gpt-4o-mini"  # Cheap model for filtering
        #
        #     intelligent_streaming stream_size: 200 do
        #       on_stream_complete { |num, total, data, results|
        #         # Only send good candidates to expensive analysis
        #         good = results.select { |r| r[:score] > 70 }
        #         ExpensiveAnalyzer.process(good)
        #       }
        #     end
        #   end
        #
        # @see IntelligentStreaming::Config Configuration object methods
        # @see INTELLIGENT_STREAMING_API.md Complete API documentation
        def intelligent_streaming(stream_size:, over: nil, incremental: false, override: false, &block)
          # Check if already configured
          if @_intelligent_streaming_config && !override
            raise IntelligentStreaming::ConfigurationError,
                  "intelligent_streaming already configured for #{name}. Use override: true to reconfigure."
          end

          # Create configuration
          config = IntelligentStreaming::Config.new(
            stream_size: stream_size,
            over: over,
            incremental: incremental
          )

          # Apply configuration block if provided
          if block_given?
            config.instance_eval(&block)
          end

          # Store configuration
          @_intelligent_streaming_config = config

          nil
        end

        # Check if this agent triggers streaming in a pipeline
        #
        # Agents that trigger streaming will cause the pipeline to create streaming scopes
        # and process data in streams rather than all at once.
        #
        # @return [Boolean] true if intelligent_streaming is configured for this agent
        #
        # @example Check if agent triggers streaming
        #   if MyAgent.streaming_trigger?
        #     puts "MyAgent will trigger streaming in pipelines"
        #   end
        def streaming_trigger?
          !@_intelligent_streaming_config.nil?
        end

        # Check if streaming is configured for this agent
        #
        # Alias for streaming_trigger? for better readability in some contexts.
        #
        # @return [Boolean] true if intelligent_streaming is configured
        #
        # @example Guard clause usage
        #   return unless MyAgent.streaming_config?
        def streaming_config?
          !@_intelligent_streaming_config.nil?
        end

        # Get the streaming configuration object
        #
        # Returns the configuration object that contains stream_size, array_field,
        # incremental setting, and all configured blocks (skip_if, load_existing, etc.).
        #
        # @return [IntelligentStreaming::Config, nil] The configuration object or nil if not configured
        #
        # @example Access configuration settings
        #   config = MyAgent.streaming_config
        #   if config
        #     puts "Stream size: #{config.stream_size}"
        #     puts "Array field: #{config.array_field}"
        #     puts "Incremental: #{config.incremental?}"
        #     puts "Has state management: #{config.has_state_management?}"
        #   end
        def streaming_config
          @_intelligent_streaming_config
        end

        # Find agents with streaming configuration in a collection
        #
        # Utility method to filter a collection of agent classes to find only those
        # that have intelligent streaming configured. Useful for pipeline introspection.
        #
        # @param agents [Array<Class>] Array of agent classes to filter
        # @return [Array<Class>] Agent classes that have streaming configured
        #
        # @example Find streaming agents in a pipeline
        #   agents = [Agent1, Agent2, Agent3]
        #   streaming_agents = Agent.with_streaming_in(agents)
        #   puts "#{streaming_agents.count} agents have streaming configured"
        def with_streaming_in(agents)
          agents.select { |agent| agent.respond_to?(:streaming_trigger?) && agent.streaming_trigger? }
        end
      end
    end

    # Configuration error for intelligent streaming
    module IntelligentStreaming
      class ConfigurationError < StandardError; end
    end
  end
end