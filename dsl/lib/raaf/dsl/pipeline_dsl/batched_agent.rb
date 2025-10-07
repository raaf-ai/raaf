# frozen_string_literal: true

module RAAF
  module DSL
    module PipelineDSL
      # Wraps any pipeline component to execute in chunks over an array field
      #
      # Supports field name transformation when input and output field names differ.
      # This is useful when an agent reads from one field (e.g., :company_list) but
      # outputs to a different field (e.g., :prospects) as defined in its schema.
      #
      # @example Basic usage with auto-detection
      #   flow CompanyDiscovery >> QuickFitAnalyzer.in_chunks_of(50)
      #
      # @example Explicit array field (same input/output)
      #   flow DataLoader >> Analyzer.in_chunks_of(100, array_field: :companies)
      #
      # @example Field name transformation (different input/output)
      #   flow CompanyDiscovery >>
      #        QuickFitAnalyzer.in_chunks_of(50, input_field: :company_list, output_field: :prospects) >>
      #        DeepIntelligence.in_chunks_of(30, array_field: :prospects)
      #
      # @example Multiple batched stages with field transformation
      #   flow CompanyDiscovery >>
      #        QuickFitAnalyzer.in_chunks_of(50, input_field: :company_list, output_field: :prospects) >>
      #        DeepIntelligence.in_chunks_of(30, array_field: :prospects) >>
      #        Scoring.in_chunks_of(50, array_field: :prospects)
      class BatchedAgent
        include RAAF::Logger

        attr_reader :wrapped_component, :chunk_size, :input_field, :output_field

        # Initialize a new BatchedAgent wrapper
        #
        # @param wrapped_component [Class, Agent, Service] Component to execute in chunks
        # @param chunk_size [Integer] Size of each chunk to process
        # @param array_field [Symbol, nil] Field for both input and output (legacy, backward compatible)
        # @param input_field [Symbol, nil] Explicit input field name (reads from this context field)
        # @param output_field [Symbol, nil] Explicit output field name (writes to this context field)
        #
        # @note Field Resolution Logic
        #   Priority order for determining input field:
        #   1. explicit input_field parameter
        #   2. array_field parameter (backward compatibility)
        #   3. auto-detection from agent's required fields
        #
        #   Priority order for determining output field:
        #   1. explicit output_field parameter
        #   2. array_field parameter (backward compatibility)
        #   3. input_field parameter (if no output_field specified)
        #   4. auto-detection from agent's provided fields
        #
        # @example Backward compatible usage
        #   BatchedAgent.new(MyAgent, 50, array_field: :items)
        #   # Same as: input_field: :items, output_field: :items
        #
        # @example Field transformation usage
        #   BatchedAgent.new(MyAgent, 50, input_field: :raw_data, output_field: :processed_data)
        #   # Reads from context[:raw_data], writes to context[:processed_data]
        def initialize(wrapped_component, chunk_size, array_field: nil, input_field: nil, output_field: nil)
          @wrapped_component = wrapped_component
          @chunk_size = chunk_size

          # Resolve input and output fields with backward compatibility
          # Priority: explicit params > array_field > auto-detection
          @input_field = input_field || array_field
          @output_field = output_field || array_field || input_field

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

          log_info "🔄 [#{wrapped_agent_name}] Processing #{full_array.size} items in chunks of #{chunk_size}"

          # Split into chunks
          chunks = full_array.each_slice(chunk_size).to_a

          # Process each chunk
          accumulated_results = []
          chunks.each_with_index do |chunk, index|
            log_debug "📦 [#{wrapped_agent_name}] Processing chunk #{index + 1}/#{chunks.size} (#{chunk.size} items)"

            # Create chunk context with this chunk
            chunk_context = context.set(field_to_batch, chunk)

            # Execute wrapped component on chunk
            chunk_result = execute_wrapped_component(chunk_context, agent_results)

            # CRITICAL FIX: Use output_field for extraction when field transformation is configured
            # When input_field != output_field, the agent returns data under the output field name
            extraction_field = @output_field || field_to_batch
            extracted_data = extract_result_data(chunk_result, extraction_field)
            accumulated_results << extracted_data if extracted_data

            log_debug "✅ [#{wrapped_agent_name}] Chunk #{index + 1} completed (#{extracted_data&.size || 0} results)"
          end

          # Merge all chunk results (use same extraction field for consistency)
          extraction_field = @output_field || field_to_batch
          merged_result = merge_chunk_results(accumulated_results, extraction_field)

          log_info "✅ [#{wrapped_agent_name}] Completed processing #{chunks.size} chunks, #{merged_result.size} total results"

          # Determine output field (supports field transformation)
          # Use explicit output_field if set, otherwise fall back to input field (backward compatible)
          output_field_name = @output_field || field_to_batch

          # Log field transformation if input and output differ
          if output_field_name != field_to_batch
            log_info "🔄 [#{wrapped_agent_name}] Field transformation: #{field_to_batch} → #{output_field_name}"
          end

          # Return updated context with merged results written to output field
          context.set(output_field_name, merged_result)
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

        # Extract the actual agent name from the wrapped component
        def wrapped_agent_name
          case @wrapped_component
          when Class
            # Agent class - try to get configured name or use class name
            if @wrapped_component.respond_to?(:_context_config)
              @wrapped_component._context_config[:name] || @wrapped_component.name.split("::").last
            else
              @wrapped_component.name.split("::").last
            end
          else
            # Agent instance or other wrapper - try agent_name method
            if @wrapped_component.respond_to?(:agent_name)
              @wrapped_component.agent_name
            elsif @wrapped_component.respond_to?(:wrapped_component)
              # Nested wrapper - recurse
              @wrapped_component.respond_to?(:wrapped_agent_name) ?
                @wrapped_component.wrapped_agent_name :
                @wrapped_component.class.name.split("::").last
            else
              @wrapped_component.class.name.split("::").last
            end
          end
        end

        # Detect which array field to batch over (INPUT field)
        #
        # This determines which context field contains the array to be batched.
        # Separate from output field which determines where merged results are written.
        #
        # Priority order:
        # 1. Explicit input_field parameter (NEW - supports field transformation)
        # 2. Explicit array_field parameter (backward compatibility)
        # 3. Single array in context (automatic detection)
        # 4. Infer from component's provided_fields
        # 5. Error if ambiguous
        def detect_array_field(context)
          # Priority 1: Explicit input_field (NEW - highest priority for field transformation)
          return input_field if input_field

          # Priority 2: Single array in context
          array_fields = context.to_h.select { |_k, v| v.is_a?(Array) }.keys

          if array_fields.size == 1
            log_debug "🔍 [#{wrapped_agent_name}] Auto-detected array field: #{array_fields.first}"
            return array_fields.first
          end

          # Priority 3: Infer from provided_fields
          if @wrapped_component.respond_to?(:provided_fields)
            provided = @wrapped_component.provided_fields
            array_candidates = array_fields & provided

            if array_candidates.size == 1
              log_debug "🔍 [#{wrapped_agent_name}] Inferred array field from provided_fields: #{array_candidates.first}"
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

          log_warn "⚠️ [#{wrapped_agent_name}] Could not extract #{field_name} from result of type #{result.class}"
          nil
        end

        # Merge results from all chunks
        # Simple flattening for MVP - can enhance with deep merge if needed
        def merge_chunk_results(chunk_results, field_name)
          # Filter out nils and flatten
          valid_results = chunk_results.compact

          if valid_results.empty?
            log_warn "⚠️ [#{wrapped_agent_name}] No valid results to merge"
            return []
          end

          # Flatten all arrays into single result array
          merged = valid_results.flatten

          log_debug "🔀 [#{wrapped_agent_name}] Merged #{valid_results.size} chunks into #{merged.size} total items"

          merged
        end
      end
    end
  end
end
