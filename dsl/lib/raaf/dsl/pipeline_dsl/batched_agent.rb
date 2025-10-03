# frozen_string_literal: true

module RAAF
  module DSL
    module PipelineDSL
      # Wraps any pipeline component to execute in chunks over an array field
      #
      # @example Basic usage with auto-detection
      #   flow CompanyDiscovery >> QuickFitAnalyzer.in_chunks_of(50)
      #
      # @example Explicit array field
      #   flow DataLoader >> Analyzer.in_chunks_of(100, array_field: :companies)
      #
      # @example Multiple batched stages
      #   flow CompanyDiscovery >>
      #        QuickFitAnalyzer.in_chunks_of(50) >>
      #        DeepIntelligence.in_chunks_of(30) >>
      #        Scoring.in_chunks_of(50)
      class BatchedAgent
        include RAAF::Logger

        attr_reader :wrapped_component, :chunk_size, :array_field

        # Initialize a new BatchedAgent wrapper
        #
        # @param wrapped_component [Class, Agent, Service] Component to execute in chunks
        # @param chunk_size [Integer] Size of each chunk to process
        # @param array_field [Symbol, nil] Explicit array field name (auto-detected if nil)
        def initialize(wrapped_component, chunk_size, array_field: nil)
          @wrapped_component = wrapped_component
          @chunk_size = chunk_size
          @array_field = array_field

          validate_chunk_size!
        end

        # Chain this batched agent with the next component
        # @param next_agent [Class, Agent, Service] Next component in chain
        # @return [ChainedAgent]
        def >>(next_agent)
          ChainedAgent.new(self, next_agent)
        end

        # Run this batched agent in parallel with another
        # @param parallel_agent [Class, Agent, Service] Component to run in parallel
        # @return [ParallelAgents]
        def |(parallel_agent)
          ParallelAgents.new([self, parallel_agent])
        end

        # Execute the wrapped component in chunks
        #
        # @param context [ContextVariables] Pipeline context with array field
        # @param agent_results [Array, nil] Optional results accumulator
        # @return [ContextVariables] Updated context with merged results
        def execute(context, agent_results = nil)
          require 'byebug';debugger
          # Ensure context is ContextVariables
          unless context.respond_to?(:set)
            context = RAAF::DSL::ContextVariables.new(context)
          end

          # Detect which array field to batch over
          field_to_batch = detect_array_field(context)

          # Get the full array to process
          full_array = context.get(field_to_batch)

          unless full_array.is_a?(Array)
            raise ArgumentError, "Field #{field_to_batch} must be an array, got #{full_array.class}"
          end

          log_info "🔄 [BatchedAgent] Processing #{full_array.size} items in chunks of #{chunk_size}"

          # Split into chunks
          chunks = full_array.each_slice(chunk_size).to_a

          # Process each chunk
          accumulated_results = []
          chunks.each_with_index do |chunk, index|
            log_debug "📦 [BatchedAgent] Processing chunk #{index + 1}/#{chunks.size} (#{chunk.size} items)"

            # Create chunk context with this chunk
            chunk_context = context.set(field_to_batch, chunk)

            # Execute wrapped component on chunk
            chunk_result = execute_wrapped_component(chunk_context, agent_results)

            # Extract and accumulate results
            extracted_data = extract_result_data(chunk_result, field_to_batch)
            accumulated_results << extracted_data if extracted_data

            log_debug "✅ [BatchedAgent] Chunk #{index + 1} completed (#{extracted_data&.size || 0} results)"
          end

          # Merge all chunk results
          merged_result = merge_chunk_results(accumulated_results, field_to_batch)

          log_info "✅ [BatchedAgent] Completed processing #{chunks.size} chunks, #{merged_result.size} total results"

          # Return updated context with merged results
          context.set(field_to_batch, merged_result)
        end

        # Delegate required fields to wrapped component
        def required_fields
          return [] unless @wrapped_component.respond_to?(:required_fields)

          @wrapped_component.required_fields
        end

        # Delegate provided fields to wrapped component
        def provided_fields
          return [] unless @wrapped_component.respond_to?(:provided_fields)

          @wrapped_component.provided_fields
        end

        # Delegate requirements check to wrapped component
        def requirements_met?(context)
          return true unless @wrapped_component.respond_to?(:requirements_met?)

          @wrapped_component.requirements_met?(context)
        end

        private

        def validate_chunk_size!
          unless chunk_size.is_a?(Integer) && chunk_size > 0
            raise ArgumentError, "chunk_size must be a positive integer, got #{chunk_size.inspect}"
          end
        end

        # Detect which array field to batch over
        # Priority order:
        # 1. Explicit array_field parameter
        # 2. Single array in context (automatic detection)
        # 3. Infer from component's provided_fields
        # 4. Error if ambiguous
        def detect_array_field(context)
          # Priority 1: Explicit parameter
          return array_field if array_field

          # Priority 2: Single array in context
          array_fields = context.to_h.select { |_k, v| v.is_a?(Array) }.keys

          if array_fields.size == 1
            log_debug "🔍 [BatchedAgent] Auto-detected array field: #{array_fields.first}"
            return array_fields.first
          end

          # Priority 3: Infer from provided_fields
          if @wrapped_component.respond_to?(:provided_fields)
            provided = @wrapped_component.provided_fields
            array_candidates = array_fields & provided

            if array_candidates.size == 1
              log_debug "🔍 [BatchedAgent] Inferred array field from provided_fields: #{array_candidates.first}"
              return array_candidates.first
            end
          end

          # Error: Ambiguous or no array fields
          if array_fields.empty?
            raise ArgumentError, "No array fields found in context. Available fields: #{context.to_h.keys.join(', ')}"
          else
            raise ArgumentError, "Multiple array fields found: #{array_fields.join(', ')}. Please specify array_field parameter."
          end
        end

        # Execute the wrapped component based on its type
        def execute_wrapped_component(chunk_context, agent_results)
          component_name = @wrapped_component.respond_to?(:name) ? @wrapped_component.name : @wrapped_component.class.name

          case @wrapped_component
          when Class
            # Agent or Service class
            execute_class_component(chunk_context, agent_results)
          when ConfiguredAgent, IteratingAgent, RemappedAgent, ChainedAgent, ParallelAgents
            # Other wrapper types
            @wrapped_component.execute(chunk_context, agent_results)
          else
            raise "RAAF Framework Error: Unsupported component type for batching: #{@wrapped_component.class.name}"
          end
        end

        # Execute a class-based component (Agent or Service)
        def execute_class_component(chunk_context, agent_results)
          agent_params = chunk_context.to_h

          # Pass pipeline instance if available
          pipeline_instance = chunk_context.get(:pipeline_instance)
          agent_params[:parent_component] = pipeline_instance if pipeline_instance

          # Convert to symbolized hash for RAAF::DSL::Agent compatibility
          regular_hash = agent_params.to_h
          symbolized_params = regular_hash.transform_keys(&:to_sym)

          # Instantiate and execute
          component_instance = @wrapped_component.new(**symbolized_params)

          if component_instance.respond_to?(:call) && component_instance.class.superclass.name == 'RAAF::DSL::Service'
            component_instance.call
          else
            component_instance.run
          end
        end

        # Extract result data from chunk execution
        # Handles both hash-based and object-based results
        def extract_result_data(result, field_name)
          return nil unless result

          # Hash-like result (most common)
          if result.is_a?(Hash)
            # Try symbol and string keys
            return result[field_name] || result[field_name.to_s]
          end

          # Object-based result (OpenStruct, etc.)
          if result.respond_to?(field_name)
            return result.send(field_name)
          end

          log_warn "⚠️ [BatchedAgent] Could not extract #{field_name} from result of type #{result.class}"
          nil
        end

        # Merge results from all chunks
        # Simple flattening for MVP - can enhance with deep merge if needed
        def merge_chunk_results(chunk_results, field_name)
          # Filter out nils and flatten
          valid_results = chunk_results.compact

          if valid_results.empty?
            log_warn "⚠️ [BatchedAgent] No valid results to merge"
            return []
          end

          # Flatten all arrays into single result array
          merged = valid_results.flatten

          log_debug "🔀 [BatchedAgent] Merged #{valid_results.size} chunks into #{merged.size} total items"

          merged
        end
      end
    end
  end
end
