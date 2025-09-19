# frozen_string_literal: true

require 'timeout'
require 'active_support/core_ext/hash/keys'
require 'active_support/hash_with_indifferent_access'

module RAAF
  module DSL
    module PipelineDSL
      # Wrapper for agents with input and output parameter remapping
      #
      # This class allows agents to be used in pipelines even when their expected
      # parameter names don't match what they receive from previous agents, and
      # when their output field names need to be transformed for downstream agents.
      #
      # @example Input remapping only
      #   Company::GenericEnrichment.with_mapping(company: :prospect)
      #
      # @example Input and output remapping
      #   Company::GenericEnrichment.with_mapping(
      #     input: { company: :prospect },
      #     output: { enriched_company: :enriched_prospect }
      #   )
      #
      class RemappedAgent
        attr_reader :agent_class, :input_mapping, :output_mapping, :options

        def initialize(agent_class, input_mapping: {}, output_mapping: {}, **options)
          @agent_class = agent_class
          @input_mapping = normalize_mapping(input_mapping)
          @output_mapping = normalize_mapping(output_mapping)
          @options = options
        end

        # DSL operators for chaining and parallel execution
        def >>(next_agent)
          ChainedAgent.new(self, next_agent)
        end

        def |(other_agent)
          ParallelAgents.new([self, other_agent])
        end

        # Additional DSL configuration methods
        def timeout(seconds)
          RemappedAgent.new(@agent_class,
            input_mapping: @input_mapping,
            output_mapping: @output_mapping,
            **@options.merge(timeout: seconds)
          )
        end

        def retry(times)
          RemappedAgent.new(@agent_class,
            input_mapping: @input_mapping,
            output_mapping: @output_mapping,
            **@options.merge(retry: times)
          )
        end

        def limit(count)
          RemappedAgent.new(@agent_class,
            input_mapping: @input_mapping,
            output_mapping: @output_mapping,
            **@options.merge(limit: count)
          )
        end

        # Delegate metadata methods to the wrapped agent
        def required_fields
          # Return the mapped required fields (what we expect from the pipeline)
          agent_required = @agent_class.respond_to?(:required_fields) ? @agent_class.required_fields : []

          # Map agent requirements to pipeline context field names
          agent_required.map do |field|
            # If this field is mapped from another name, use the source name
            source_field = @input_mapping[field] || field
            source_field
          end.uniq
        end

        def provided_fields
          # Return the mapped provided fields (what downstream agents will see)
          agent_provided = @agent_class.respond_to?(:provided_fields) ? @agent_class.provided_fields : []

          # Map agent outputs to pipeline field names
          agent_provided.map do |field|
            # If this field is mapped to another name, use the target name
            @output_mapping[field] || field
          end.uniq
        end

        def requirements_met?(context)
          # Check if requirements are met after input mapping is applied
          remapped_context = apply_input_mapping_to_context(context)
          @agent_class.respond_to?(:requirements_met?) ?
            @agent_class.requirements_met?(remapped_context) : true
        end

        # Execute with input/output remapping
        def execute(context, agent_results = [])
          timeout_value = @options[:timeout] || get_agent_config(:timeout) || 30
          retry_count = @options[:retry] || get_agent_config(:retry) || 1

          Timeout.timeout(timeout_value) do
            attempts = 0
            begin
              attempts += 1

              # Apply input mapping to context
              remapped_context = apply_input_mapping_to_context(context)

              # Convert context for agent initialization (no options merging needed!)
              context_hash = remapped_context.is_a?(RAAF::DSL::ContextVariables) ?
                remapped_context.to_h : remapped_context
              agent = @agent_class.new(**context_hash)
              result = agent.run

              # Apply output mapping to result
              remapped_result = apply_output_mapping_to_result(result)

              # Update original context with remapped results
              updated_context = update_context_with_result(context, remapped_result)

              # Add result to agent_results collection if provided
              agent_results << remapped_result if agent_results && remapped_result.is_a?(Hash)

              updated_context
            rescue => e
              if attempts < retry_count
                sleep_time = 2 ** (attempts - 1) # Exponential backoff
                RAAF.logger.warn "Retrying #{@agent_class.name} after #{sleep_time}s (attempt #{attempts}/#{retry_count})"
                sleep(sleep_time)
                retry
              else
                raise e
              end
            end
          end
        rescue Timeout::Error => e
          RAAF.logger.error "#{@agent_class.name} timed out after #{timeout_value} seconds"
          raise e
        end

        private

        # Extract configuration value from the wrapped agent class
        # This allows pipeline wrappers to access DSL configurations like timeout, max_turns, etc.
        def get_agent_config(key)
          return nil unless @agent_class.respond_to?(:_context_config)

          @agent_class._context_config[key.to_sym]
        end

        # Normalize mapping to ensure consistent symbol keys
        def normalize_mapping(mapping)
          return {} if mapping.nil? || mapping.empty?

          case mapping
          when Hash
            # Convert to symbol keys for consistency
            normalized = {}
            mapping.each do |key, value|
              normalized[key.to_sym] = value.to_sym
            end
            normalized
          else
            {}
          end
        end

        # Apply input mapping to context before agent execution
        def apply_input_mapping_to_context(context)
          return context if @input_mapping.empty?

          # Start with the original context
          remapped = case context
                    when RAAF::DSL::ContextVariables
                      context.dup
                    when Hash
                      ActiveSupport::HashWithIndifferentAccess.new(context.dup)
                    else
                      ActiveSupport::HashWithIndifferentAccess.new
                    end

          # Apply input mappings: target_field: source_field
          @input_mapping.each do |target_field, source_field|
            if has_field?(context, source_field)
              value = get_field_value(context, source_field)

              # Set the mapped field in the context
              if remapped.is_a?(RAAF::DSL::ContextVariables)
                remapped = remapped.set(target_field, value)
              else
                remapped[target_field] = value
              end
            else
              RAAF.logger.warn "Input mapping failed: source field '#{source_field}' not found in context"
            end
          end

          remapped
        end

        # Apply output mapping to agent result
        def apply_output_mapping_to_result(result)
          return result if @output_mapping.empty? || !result.is_a?(Hash)

          # Start with the original result
          remapped = ActiveSupport::HashWithIndifferentAccess.new(result.dup)

          # Apply output mappings: source_field: target_field
          @output_mapping.each do |source_field, target_field|
            if remapped.key?(source_field)
              value = remapped.delete(source_field)
              remapped[target_field] = value
            end
          end

          remapped
        end

        # Update the pipeline context with remapped result fields
        def update_context_with_result(context, result)
          return context unless result.is_a?(Hash)

          # Update context with result fields
          case context
          when RAAF::DSL::ContextVariables
            result.each do |key, value|
              # Skip internal control fields
              unless key.to_s.match?(/^(success|error|errors|status|metadata)$/i)
                context = context.set(key, value)
              end
            end
            context
          when Hash
            result.each do |key, value|
              unless key.to_s.match?(/^(success|error|errors|status|metadata)$/i)
                context[key] = value
              end
            end
            context
          else
            context
          end
        end

        # Check if context has a specific field (handles different context types)
        def has_field?(context, field)
          case context
          when RAAF::DSL::ContextVariables
            context.respond_to?(field) || !context.get(field).nil?
          when Hash
            context.key?(field) || context.key?(field.to_s) || context.key?(field.to_sym)
          else
            false
          end
        end

        # Get field value from context (handles different context types)
        def get_field_value(context, field)
          case context
          when RAAF::DSL::ContextVariables
            context.get(field)
          when Hash
            context[field] || context[field.to_s] || context[field.to_sym]
          else
            nil
          end
        end
      end
    end
  end
end