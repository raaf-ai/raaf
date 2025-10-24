# frozen_string_literal: true

require_relative "../core/context_variables"

module RAAF
  module DSL
    module IntelligentStreaming
      # Custom error class for executor errors
      class ExecutorError < StandardError; end

      # Executes streaming scopes within a pipeline
      #
      # The PipelineStreamExecutor is responsible for:
      # - Splitting arrays into configured stream sizes
      # - Executing each stream through the agent chain
      # - Managing state (skip_if, load_existing, persist)
      # - Firing progress hooks (on_stream_start, on_stream_complete, on_stream_error)
      # - Merging results from all streams
      #
      # @example Basic execution
      #   executor = Executor.new(scope: scope, context: context, config: config)
      #   results = executor.execute(agent_chain)
      #
      # @example With state management
      #   config.skip_if { |record| record[:processed] }
      #   config.load_existing { |record| cache[record[:id]] }
      #   executor = Executor.new(scope: scope, context: context, config: config)
      #   results = executor.execute(agent_chain)
      class Executor
        include RAAF::Logger if defined?(RAAF::Logger)

        attr_reader :scope, :context, :config
        attr_reader :accumulated_results, :execution_stats

        # Initialize a new executor
        #
        # @param scope [Scope] The streaming scope to execute
        # @param context [ContextVariables] The pipeline context
        # @param config [Config] The streaming configuration
        def initialize(scope:, context:, config:)
          @scope = scope
          @context = context
          @config = config
          @accumulated_results = []
          @execution_stats = {
            total_streams: 0,
            successful_streams: 0,
            failed_streams: 0,
            total_items: 0,
            processed_items: 0,
            skipped_items: 0,
            start_time: nil,
            end_time: nil
          }
        end

        # Execute the streaming scope
        #
        # @param agent_chain [Array<Agent>] The agents to execute for each stream
        # @return [Array, Hash] Merged results from all streams
        # @raise [ExecutorError] if array field is missing or invalid
        def execute(agent_chain)
          @execution_stats[:start_time] = Time.now

          # Extract array to stream
          array_field = determine_array_field
          items = extract_array(array_field)

          @execution_stats[:total_items] = items.size

          return [] if items.empty?

          # Split into streams
          streams = split_into_streams(items)
          @execution_stats[:total_streams] = streams.size

          # Execute each stream
          all_results = []
          streams.each_with_index do |stream_items, index|
            stream_num = index + 1

            begin
              stream_result = execute_stream(
                stream_items: stream_items,
                stream_num: stream_num,
                total_streams: streams.size,
                agent_chain: agent_chain
              )

              all_results << stream_result
              @accumulated_results << stream_result
              @execution_stats[:successful_streams] += 1
            rescue StandardError => e
              @execution_stats[:failed_streams] += 1
              handle_stream_error(stream_num, streams.size, stream_items, e)

              # Continue with next stream unless configured to stop
              next unless config.blocks[:stop_on_error]

              raise e
            end
          end

          @execution_stats[:end_time] = Time.now

          # Fire on_stream_complete for non-incremental mode
          if !config.incremental && config.blocks[:on_stream_complete]
            merged = merge_results(all_results)
            fire_complete_hook_non_incremental(merged)
          end

          # Merge and return results
          merge_results(all_results)
        end

        private

        def determine_array_field
          # Use configured field or detect from scope
          if config.array_field
            config.array_field
          elsif scope.array_field
            scope.array_field
          else
            detect_array_field_from_context
          end
        end

        def detect_array_field_from_context
          # Find first array field in context
          context_hash = context.respond_to?(:to_h) ? context.to_h : context
          array_fields = context_hash.select { |_k, v| v.is_a?(Array) }.keys

          if array_fields.empty?
            raise ExecutorError, "No array fields found in context"
          elsif array_fields.size > 1
            raise ExecutorError, "Multiple array fields found: #{array_fields.join(', ')}. " \
                                 "Please specify which field to stream using 'over: :field_name'"
          else
            array_fields.first
          end
        end

        def extract_array(array_field)
          # Handle both ContextVariables and plain Hash
          value = if context.respond_to?(:get)
                    context.get(array_field)
                  elsif context.respond_to?(:[])
                    context[array_field]
                  else
                    nil
                  end

          unless value
            raise ExecutorError, "No array field '#{array_field}' found in context"
          end

          unless value.is_a?(Array)
            raise ExecutorError, "Field '#{array_field}' does not contain an array, got: #{value.class}"
          end

          value
        end

        def split_into_streams(items)
          items.each_slice(config.stream_size).to_a
        end

        def execute_stream(stream_items:, stream_num:, total_streams:, agent_chain:)
          stream_results = []

          # Fire on_stream_start hook
          if config.blocks[:on_stream_start]
            config.blocks[:on_stream_start].call(stream_num, total_streams, stream_items)
          end

          # Process each record in stream
          stream_items.each do |record|
            if should_skip_record?(record)
              @execution_stats[:skipped_items] += 1

              # Load cached result if available
              if config.blocks[:load_existing]
                context_hash = context.respond_to?(:to_h) ? context.to_h : context
                result = config.blocks[:load_existing].call(record, context_hash)
                stream_results << result if result
              end
            else
              @execution_stats[:processed_items] += 1

              # Execute through agent chain
              result = execute_record_through_agents(record, agent_chain)
              stream_results << result if result
            end
          end

          # Persist stream results if configured
          if config.blocks[:persist_each_stream] && stream_results.any?
            context_hash = context.respond_to?(:to_h) ? context.to_h : context
            config.blocks[:persist_each_stream].call(stream_results, context_hash)
          end

          # Fire on_stream_complete hook for incremental mode
          if config.incremental && config.blocks[:on_stream_complete]
            fire_complete_hook_incremental(stream_num, total_streams, stream_items, stream_results)
          end

          stream_results
        end

        def should_skip_record?(record)
          return false unless config.blocks[:skip_if]

          context_hash = context.respond_to?(:to_h) ? context.to_h : context
          config.blocks[:skip_if].call(record, context_hash)
        end

        def execute_record_through_agents(record, agent_chain)
          # Create a new context for this record
          record_context = if context.is_a?(RAAF::DSL::ContextVariables)
                             context.dup
                           else
                             RAAF::DSL::ContextVariables.new(context)
                           end

          # Set the current record
          if record_context.respond_to?(:set)
            record_context = record_context.set(:current_record, record)
          else
            record_context[:current_record] = record
          end

          # Execute through all agents in chain
          agent_chain.each do |agent|
            agent_context = record_context.respond_to?(:to_h) ? record_context.to_h : record_context
            agent_result = agent.run(context: agent_context)

            # Merge agent result back into context
            if agent_result.is_a?(Hash)
              if record_context.is_a?(RAAF::DSL::ContextVariables)
                record_context = RAAF::DSL::ContextVariables.new(record_context.to_h.merge(agent_result))
              else
                record_context = agent_context.merge(agent_result)
              end
            else
              record_context = RAAF::DSL::ContextVariables.new(agent_result)
            end
          end

          record_context.respond_to?(:to_h) ? record_context.to_h : record_context
        end

        def fire_complete_hook_incremental(stream_num, total_streams, stream_data, stream_results)
          # Incremental mode: 4 parameters
          config.blocks[:on_stream_complete].call(stream_num, total_streams, stream_data, stream_results)
        end

        def fire_complete_hook_non_incremental(all_results)
          # Non-incremental mode: 1 parameter
          config.blocks[:on_stream_complete].call(all_results)
        end

        def handle_stream_error(stream_num, total_streams, stream_items, error)
          log_error("Stream #{stream_num}/#{total_streams} failed: #{error.message}") if respond_to?(:log_error)

          # Fire error hook if configured
          if config.blocks[:on_stream_error]
            config.blocks[:on_stream_error].call(stream_num, total_streams, stream_items, error)
          end
        end

        def merge_results(all_results)
          return [] if all_results.empty?
          return all_results.first if all_results.size == 1

          # Flatten arrays of arrays into single array
          # Each stream returns an array of processed items, so we concatenate them all
          flattened = all_results.flatten(1)

          # Return the flattened array of all processed items
          # NOTE: We DO NOT merge individual processed records into a single hash
          # That would lose all the individual item data
          flattened
        end

        def deep_merge(hash1, hash2)
          return hash2 unless hash1.is_a?(Hash) && hash2.is_a?(Hash)

          hash1.merge(hash2) do |_key, old_val, new_val|
            if old_val.is_a?(Hash) && new_val.is_a?(Hash)
              deep_merge(old_val, new_val)
            else
              new_val
            end
          end
        end

        def log_error(message)
          return unless defined?(Rails) && Rails.logger

          Rails.logger.error "[IntelligentStreaming::Executor] #{message}"
        end

        def warn(message)
          return unless defined?(Rails) && Rails.logger

          Rails.logger.warn "[IntelligentStreaming::Executor] #{message}"
        end
      end
    end
  end
end