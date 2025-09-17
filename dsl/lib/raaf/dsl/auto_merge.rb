# frozen_string_literal: true

require_relative 'merge_strategy'

module RAAF
  module DSL
    # Automatic merging integration for RAAF agents
    #
    # This module provides automatic merging of AI agent results with existing pipeline context
    # by overriding the run method to apply merge strategies after AI execution. It eliminates
    # the need for manual `process_*_from_data` methods in agents.
    #
    # The auto-merge system:
    # 1. Runs the AI agent normally
    # 2. Detects merge strategies for each field in the result
    # 3. Merges AI results with existing context data
    # 4. Updates the context with merged results
    # 5. Returns the final merged results
    #
    # @example Agent with automatic merging
    #   class MarketAnalysis < RAAF::DSL::Agent
    #     include RAAF::DSL::AutoMerge
    #
    #     agent_name "MarketAnalysis"
    #     model "gpt-4o"
    #
    #     # No manual merge methods needed!
    #     # Results automatically merge with pipeline context
    #   end
    #
    module AutoMerge
      # Override the run method to add automatic merging
      def run(context: nil, input_context_variables: nil, stop_checker: nil, skip_retries: false, previous_result: nil)
        # Call the original run method
        ai_result = super(context: context, input_context_variables: input_context_variables, stop_checker: stop_checker, skip_retries: skip_retries, previous_result: previous_result)

        # Only apply automatic merging if enabled for this agent class and successful
        if self.class.respond_to?(:auto_merge_enabled?) && self.class.auto_merge_enabled? &&
           ai_result && ai_result[:success] != false && ai_result[:results]
          merged_result = auto_merge_with_context(ai_result, context || input_context_variables)
          update_context_with_merged_data(merged_result, context || input_context_variables)
          merged_result
        else
          # Return original result if auto_merge is disabled, failed, or no results
          ai_result
        end
      end

      private

      # Performs automatic merging of AI results with pipeline context
      #
      # @param ai_result [Hash] The result from the AI agent
      # @param pipeline_context [Object] The pipeline context (ContextVariables or Hash)
      # @return [Hash] The result with merged data
      def auto_merge_with_context(ai_result, pipeline_context)
        return ai_result unless ai_result[:results].respond_to?(:each)

        # Get the current context data
        context_data = extract_context_data(pipeline_context)

        # Create a copy of the AI result to avoid mutation
        merged_result = ai_result.dup
        merged_results = {}

        # Merge each field in the AI results
        ai_result[:results].each do |field, new_value|
          existing_value = context_data[field] || context_data[field.to_s]

          if present?(existing_value)
            # Merge with existing data using strategy detection
            merged_value = MergeStrategy.merge(field, existing_value, new_value)
            merged_results[field] = merged_value
          else
            # No existing data, use new value as-is
            merged_results[field] = new_value
          end
        end

        # Update the result with merged data
        merged_result[:results] = merged_results
        merged_result
      end

      # Updates the pipeline context with merged data
      #
      # @param merged_result [Hash] The result with merged data
      # @param pipeline_context [Object] The pipeline context to update
      def update_context_with_merged_data(merged_result, pipeline_context)
        return unless merged_result[:results]

        if pipeline_context.respond_to?(:set)
          # ContextVariables object
          merged_result[:results].each do |field, value|
            pipeline_context.set(field, value)
          end
        elsif pipeline_context.respond_to?(:[]=)
          # Hash-like object
          merged_result[:results].each do |field, value|
            pipeline_context[field] = value
          end
        end
      end

      # Extracts context data from various context types
      #
      # @param pipeline_context [Object] The pipeline context
      # @return [Hash] The context data as a hash
      def extract_context_data(pipeline_context)
        return {} if pipeline_context.nil?

        if pipeline_context.respond_to?(:to_h)
          pipeline_context.to_h
        elsif pipeline_context.is_a?(Hash)
          pipeline_context
        elsif pipeline_context.respond_to?(:get)
          # ContextVariables - extract all data by accessing the instance variable
          pipeline_context.instance_variable_get(:@variables) || {}
        else
          {}
        end
      end

      # Check if a value is present (not nil and not empty)
      def present?(value)
        !value.nil? && (value != "" && (!value.respond_to?(:empty?) || !value.empty?))
      end
    end
  end
end