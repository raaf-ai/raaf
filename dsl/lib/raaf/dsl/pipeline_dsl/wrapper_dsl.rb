# frozen_string_literal: true

module RAAF
  module DSL
    module PipelineDSL
      # Shared DSL methods for all pipeline wrapper classes
      #
      # This module provides common DSL configuration methods that can be chained
      # on any wrapper class (RemappedAgent, ConfiguredAgent, IteratingAgent, etc.)
      #
      # @example Usage in a wrapper class
      #   class MyWrapper
      #     include WrapperDSL
      #
      #     def create_wrapper(**new_options)
      #       MyWrapper.new(@agent_class, **@options.merge(new_options))
      #     end
      #   end
      #
      module WrapperDSL
        # Wrap this component in a batched executor
        #
        # @param chunk_size [Integer] Number of items to process per batch
        # @param opts [Hash] Additional batching options (input_field, output_field, etc.)
        # @return [BatchedAgent] Batched wrapper around this component
        def in_chunks_of(chunk_size, **opts)
          BatchedAgent.new(self, chunk_size, **opts)
        end

        # Set timeout for this component
        #
        # @param seconds [Integer] Timeout in seconds
        # @return [Wrapper] New wrapper instance with timeout configured
        def timeout(seconds)
          create_wrapper(timeout: seconds)
        end

        # Set retry count for this component
        #
        # @param times [Integer] Number of retry attempts
        # @return [Wrapper] New wrapper instance with retry configured
        def retry(times)
          create_wrapper(retry: times)
        end

        # Set limit for this component
        #
        # @param count [Integer] Maximum number of items to process
        # @return [Wrapper] New wrapper instance with limit configured
        def limit(count)
          create_wrapper(limit: count)
        end

        # Chain this component with another
        #
        # @param next_agent [Class, Agent, Service] Next component in chain
        # @return [ChainedAgent] Chained wrapper
        def >>(next_agent)
          ChainedAgent.new(self, next_agent)
        end

        # Run this component in parallel with another
        #
        # @param other_agent [Class, Agent, Service] Component to run in parallel
        # @return [ParallelAgents] Parallel wrapper
        def |(other_agent)
          ParallelAgents.new([self, other_agent])
        end

        # Abstract method that must be implemented by including class
        # Should return a new instance of the wrapper with merged options
        #
        # @param new_options [Hash] Options to merge
        # @return [Wrapper] New wrapper instance
        def create_wrapper(**new_options)
          raise NotImplementedError, "#{self.class} must implement #create_wrapper"
        end
      end
    end
  end
end
