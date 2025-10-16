# frozen_string_literal: true

module RAAF
  module DSL
    module PipelineDSL
      # Shared DSL methods for all pipeline wrapper classes
      #
      # This module provides common DSL configuration methods that can be chained
      # on any wrapper class (RemappedAgent, ConfiguredAgent, IteratingAgent, etc.)
      #
      # It also provides universal before_execute/after_execute hook support for
      # all wrapper types, enabling consistent preprocessing and postprocessing
      # across the entire pipeline DSL.
      #
      # @example Usage in a wrapper class
      #   class MyWrapper
      #     include WrapperDSL
      #
      #     def execute(context, agent_results = nil)
      #       execute_with_hooks(context, :my_wrapper, config: @config) do
      #         # Actual wrapper execution logic
      #         perform_work(context)
      #       end
      #     end
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

        # Execute wrapped logic with before_execute/after_execute hooks
        #
        # This method provides universal hook support for all pipeline wrappers.
        # It executes before_execute hooks from the agent class (if defined),
        # runs the provided execution block, then executes after_execute hooks.
        #
        # Timing information and wrapper context are automatically passed to hooks,
        # enabling agents to implement wrapper-aware preprocessing and postprocessing
        # logic that works consistently across all wrapper types.
        #
        # @param context [ContextVariables] Pipeline context (mutable, can be modified by hooks)
        # @param wrapper_type [Symbol] Type of wrapper executing (:batched, :chained, :parallel, :remapped, :configured, :iterating)
        # @param wrapper_config [Hash] Wrapper-specific configuration data passed to hooks
        # @yield Block containing the actual wrapper execution logic
        # @return [Object] Result from the wrapper execution block
        #
        # @example Basic usage in BatchedAgent
        #   def execute(context, agent_results = nil)
        #     execute_with_hooks(context, :batched, chunk_size: @chunk_size) do
        #       perform_batched_execution(context, agent_results)
        #     end
        #   end
        #
        # @example With rich wrapper config in RemappedAgent
        #   def execute(context, agent_results = nil)
        #     execute_with_hooks(context, :remapped, input_mapping: @input_mapping, output_mapping: @output_mapping) do
        #       perform_field_remapping(context, agent_results)
        #     end
        #   end
        #
        def execute_with_hooks(context, wrapper_type, wrapper_config = {})
          # Start timing for duration calculation
          start_time = Time.current

          # Extract agent class from wrapped component
          agent_class = extract_agent_class

          # BEFORE_EXECUTE HOOKS
          # Execute any before_execute hooks defined on the agent class
          if agent_class.respond_to?(:get_agent_hooks)
            execute_hooks(
              agent_class.get_agent_hooks(:before_execute),
              context: context,
              wrapper_type: wrapper_type,
              wrapper_config: wrapper_config,
              timestamp: Time.current
            )
          end

          # EXECUTE WRAPPER LOGIC
          # Run the actual wrapper execution logic provided by the block
          result = yield

          # Calculate execution duration
          duration_ms = ((Time.current - start_time) * 1000).round(2)

          # AFTER_EXECUTE HOOKS
          # Execute any after_execute hooks defined on the agent class
          # Pass result as context so hook modifications persist in the returned result
          if agent_class.respond_to?(:get_agent_hooks)
            execute_hooks(
              agent_class.get_agent_hooks(:after_execute),
              context: result,
              result: result,
              wrapper_type: wrapper_type,
              wrapper_config: wrapper_config,
              duration_ms: duration_ms,
              timestamp: Time.current
            )
          end

          # Return the wrapper result
          result
        end

        private

        # Execute a list of hooks with given parameters
        #
        # Handles both Proc-based hooks (blocks) and Symbol-based hooks (method names).
        # Silently skips execution if hooks array is nil or empty.
        #
        # @param hooks [Array<Proc, Symbol>] List of hooks to execute
        # @param params [Hash] Keyword arguments to pass to each hook
        # @return [void]
        #
        def execute_hooks(hooks, **params)
          return if hooks.nil? || hooks.empty?

          hooks.each do |hook|
            if hook.is_a?(Proc)
              # Block-based hook: call with keyword arguments
              hook.call(**params)
            elsif hook.is_a?(Symbol)
              # Method name hook: call as class method on agent class
              agent_class = extract_agent_class
              agent_class.send(hook, **params) if agent_class.respond_to?(hook)
            end
          end
        end

        # Extract the agent class from the wrapped component
        #
        # Handles various wrapper nesting scenarios (BatchedAgent wrapping RemappedAgent
        # wrapping ConfiguredAgent, etc.) to find the actual agent class at the core.
        #
        # This method knows about all 6 wrapper types:
        # - ChainedAgent (@first, @second)
        # - ParallelAgents (@agents array)
        # - RemappedAgent, ConfiguredAgent, IteratingAgent, BatchedAgent (@agent_class)
        #
        # @return [Class] The agent class being wrapped
        #
        def extract_agent_class
          # Handle different wrapper types
          if instance_variable_defined?(:@agent_class)
            # RemappedAgent, ConfiguredAgent, IteratingAgent, BatchedAgent
            component = @agent_class
          elsif instance_variable_defined?(:@first)
            # ChainedAgent - use the first agent
            component = @first
          elsif instance_variable_defined?(:@agents)
            # ParallelAgents - use the first agent in the array
            component = @agents.first
          else
            # Fallback to wrapped_component if available
            component = respond_to?(:wrapped_component) ? @wrapped_component : self
          end

          # Recursively extract from nested wrappers
          if component.respond_to?(:extract_agent_class)
            # Nested wrapper - recursively extract
            component.extract_agent_class
          elsif component.respond_to?(:agent_class)
            # Wrapper with agent_class method
            component.agent_class
          elsif component.is_a?(Class)
            # Already a class
            component
          else
            # Instance - get its class
            component.class
          end
        end
      end
    end
  end
end
