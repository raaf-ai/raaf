# frozen_string_literal: true

require_relative 'pipeline_dsl/chained_agent'
require_relative 'pipeline_dsl/parallel_agents'
require_relative 'pipeline_dsl/configured_agent'
require_relative 'pipeline_dsl/iterating_agent'

module RAAF
  module DSL
    # Shared pipeline integration module for Agent and Service classes
    #
    # This module provides unified pipeline DSL functionality that can be shared
    # between RAAF::DSL::Agent and RAAF::DSL::Service classes, ensuring consistent
    # pipeline integration behavior across both AI agents and direct service classes.
    #
    # Features:
    # - DSL operators for chaining (>>) and parallel (|) execution
    # - Configuration methods for timeout, retry, and limit settings
    # - Iterator support via each_over() for processing multiple data entries
    # - Field requirement checking for pipeline validation
    #
    # @example Usage with chaining
    #   class MyPipeline < RAAF::Pipeline
    #     flow AgentA >> ServiceB >> AgentC
    #   end
    #
    # @example Usage with parallel execution
    #   class MyPipeline < RAAF::Pipeline
    #     flow DataLoader >> (ServiceA | ServiceB) >> ResultAggregator
    #   end
    #
    # @example Usage with iteration
    #   class MyPipeline < RAAF::Pipeline
    #     flow DataLoader >> 
    #          ProcessorService.each_over(:items).parallel.timeout(60) >>
    #          ResultCollector
    #   end
    #
    module PipelineIntegration
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Check if agent/service requirements are satisfied
        #
        # Validates that all required fields are present in the provided context
        # or have default values defined in the class configuration.
        #
        # @param context [Hash, Object] Context to validate against requirements
        # @return [Boolean] True if all requirements are met
        def requirements_met?(context)
          required = required_fields
          return true if required.empty?

          # Get defaults if available (from ContextConfiguration module)
          defaults = {}
          if respond_to?(:_agent_config) && _agent_config && _agent_config[:context_rules]
            defaults = _agent_config[:context_rules][:defaults] || {}
          end

          # Check if context has all required fields (or they have defaults)
          if context.is_a?(Hash)
            required.all? { |field| context.key?(field) || defaults.key?(field) }
          elsif context.respond_to?(:keys)
            required.all? { |field| context.keys.include?(field) || defaults.key?(field) }
          else
            # For ContextVariables or other context objects
            required.all? do |field|
              context.respond_to?(field) ||
                (context.respond_to?(:[]) && !context[field].nil?) ||
                defaults.key?(field)
            end
          end
        end

        # DSL operator: Chain this agent/service with the next one
        #
        # Creates a sequential execution chain where the output of this class
        # becomes the input of the next class in the pipeline.
        #
        # @param next_agent [Class] The next agent or service in the chain
        # @return [ChainedAgent] Chained execution wrapper
        def >>(next_agent)
          PipelineDSL::ChainedAgent.new(self, next_agent)
        end

        # DSL operator: Run this agent/service in parallel with another
        #
        # Creates a parallel execution group where both classes execute
        # simultaneously with the same input context.
        #
        # @param parallel_agent [Class] The agent/service to run in parallel
        # @return [ParallelAgents] Parallel execution wrapper
        def |(parallel_agent)
          PipelineDSL::ParallelAgents.new([self, parallel_agent])
        end

        # DSL method: Configure timeout for execution
        #
        # Wraps the agent/service with a timeout configuration that will
        # terminate execution if it exceeds the specified time limit.
        #
        # @param seconds [Integer] Timeout in seconds
        # @return [ConfiguredAgent] Configured execution wrapper
        def timeout(seconds)
          PipelineDSL::ConfiguredAgent.new(self, timeout: seconds)
        end

        # DSL method: Configure retry behavior
        #
        # Wraps the agent/service with retry logic that will automatically
        # retry failed executions up to the specified number of times.
        #
        # @param times [Integer] Number of retry attempts
        # @return [ConfiguredAgent] Configured execution wrapper
        def retry(times)
          PipelineDSL::ConfiguredAgent.new(self, retry: times)
        end

        # DSL method: Configure result limit
        #
        # Wraps the agent/service with a limit configuration that can be
        # used to control the number of results processed or returned.
        #
        # @param count [Integer] Maximum number of items to process
        # @return [ConfiguredAgent] Configured execution wrapper
        def limit(count)
          PipelineDSL::ConfiguredAgent.new(self, limit: count)
        end

        # DSL method: Enable iteration over multiple data entries
        #
        # Creates an iterator wrapper that processes an array of data entries,
        # executing the agent/service once for each entry. Supports both
        # sequential and parallel processing modes with custom output field naming.
        #
        # @example Sequential iteration (default output naming)
        #   ProcessorService.each_over(:items)  # outputs to :processed_items
        #
        # @example Custom output field
        #   ProcessorService.each_over(:items, to: :enriched_items)
        #
        # @example Custom field name for iteration items
        #   ProcessorService.each_over(:search_terms, as: :search_term, to: :companies)
        #
        # @example Full syntax with :from marker
        #   ProcessorService.each_over(:from, :companies, to: :analyzed_companies)
        #
        # @example Parallel iteration with custom output
        #   ProcessorService.each_over(:items, to: :results).parallel.timeout(30)
        #
        # @param args [Array] Variable arguments supporting different syntax patterns
        # @param options [Hash] Optional configuration for the iterator
        # @option options [Symbol] :to Custom output field name
        # @option options [Symbol] :as Custom field name for individual iteration items
        # @return [IteratingAgent] Iterator execution wrapper
        def each_over(*args, **options)
          # Parse argument patterns
          if args.length == 1
            # each_over(:field) - simple syntax
            field = args[0]
          elsif args.length == 2
            if args[0] == :from
              # each_over(:from, :field, to: :output) - :from marker with field and keyword arg
              field = args[1]
              unless options[:to]
                raise ArgumentError, "Invalid syntax: :from marker requires 'to:' keyword argument. Use: each_over(:from, :field, to: :output)"
              end
            else
              # Assume old-style positional arguments for backward compatibility
              field = args[0]
              # If second arg is a Hash, merge it with options; if Symbol, treat as error
              if args[1].is_a?(Hash)
                options = args[1].merge(options)
              else
                raise ArgumentError, "Invalid syntax. Use: each_over(:field, to: :output) or each_over(:from, :field, to: :output)"
              end
            end
          elsif args.length == 3 && args[0] == :from
            # Unsupported - should use keyword args
            raise ArgumentError, "Invalid syntax: too many arguments. Use: each_over(:from, :field, to: :output) with keyword argument"
          else
            raise ArgumentError, "Invalid each_over syntax. Supported patterns:\n" \
                                 "  each_over(:field)\n" \
                                 "  each_over(:field, to: :output)\n" \
                                 "  each_over(:from, :field, to: :output)"
          end
          
          PipelineDSL::IteratingAgent.new(self, field, options)
        end

        # Field introspection methods (can be overridden by including classes)
        # These are used by pipeline validation to ensure field compatibility

        # Extract required fields for pipeline validation
        #
        # Override in subclasses to specify what context fields this class requires.
        # Used by pipeline DSL for automatic field validation and error reporting.
        #
        # @return [Array<Symbol>] Array of required field names
        def required_fields
          # Default implementation - can be overridden
          if respond_to?(:externally_required_fields)
            externally_required_fields
          else
            []
          end
        end

        # Extract provided fields for pipeline validation
        #
        # Override in subclasses to specify what fields this class provides in its output.
        # Used by pipeline DSL for automatic field flow validation.
        #
        # @return [Array<Symbol>] Array of provided field names
        def provided_fields
          # Default implementation - must be overridden by subclasses
          []
        end
      end
    end
  end
end