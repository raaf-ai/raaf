# frozen_string_literal: true

module RAAF
  module Eval
    module Reporting
      # Extends MultiRunAggregator to handle domain-specific output structures
      #
      # This aggregator supports analyzing domain outputs (like prospect criterion scores)
      # that aren't directly in evaluation.field_results but exist in the agent output.
      #
      # @example Prospect Scoring Consistency
      #   results = 3.times.map { run_prospect_scoring }
      #   aggregator = DomainOutputAggregator.new(
      #     results,
      #     output_path: 'prospect_evaluations.*.criterion_scores',
      #     group_by: 'criterion_code'  # Group by criterion type (industry, geography, etc.)
      #   )
      #   aggregator.grouped_field_values(:score) # => { industry: [90, 92, 91], geography: [85, 87, 86] }
      #
      class DomainOutputAggregator < MultiRunAggregator
        attr_reader :output_path, :group_by

        # Initialize with domain-specific configuration
        #
        # @param evaluation_results [Array<Hash>] Evaluation run results
        # @param output_path [String] JSONPath to domain output array (e.g., 'prospect_evaluations.*.criterion_scores')
        # @param group_by [String, Symbol] Field to group output by (e.g., 'criterion_code', 'coc_number')
        def initialize(evaluation_results = [], output_path: nil, group_by: nil)
          super(evaluation_results)
          @output_path = output_path
          @group_by = group_by&.to_sym
        end

        # Extract domain output values grouped by a field
        #
        # @param field_name [Symbol, String] Field to extract from each domain output item
        # @return [Hash<Symbol, Array>] Values grouped by group_by field
        #
        # @example
        #   aggregator.grouped_field_values(:score)
        #   # => { industry: [90, 92, 91], geography: [85, 87, 86], ... }
        def grouped_field_values(field_name)
          puts "🔍 DEBUG [Aggregator]: grouped_field_values called with field_name=#{field_name.inspect}"
          puts "🔍 DEBUG [Aggregator]: output_path=#{@output_path.inspect}, group_by=#{@group_by.inspect}"

          unless @output_path && @group_by
            puts "⚠️  DEBUG [Aggregator]: Missing output_path or group_by, returning empty hash"
            return {}
          end

          # Build grouped structure: { group_key => [values_from_all_runs] }
          grouped = Hash.new { |h, k| h[k] = [] }

          puts "🔍 DEBUG [Aggregator]: Processing #{@runs.size} runs..."
          @runs.each_with_index do |run, idx|
            puts "🔍 DEBUG [Aggregator]: Run #{idx + 1}..."
            # Extract domain output array using output_path
            output_items = extract_output_items(run)
            puts "🔍 DEBUG [Aggregator]: Extracted #{output_items.size} output items from run #{idx + 1}"

            # Group items and extract field values
            output_items.each_with_index do |item, item_idx|
              puts "🔍 DEBUG [Aggregator]:   Item #{item_idx}: #{item.inspect[0..200]}..." if item_idx < 2
              group_key = (item[@group_by] || item[@group_by.to_s])&.to_sym
              field_value = item[field_name] || item[field_name.to_s]
              puts "🔍 DEBUG [Aggregator]:   Item #{item_idx}: group_key=#{group_key.inspect}, field_value=#{field_value.inspect}" if item_idx < 2

              grouped[group_key] << field_value if group_key && !field_value.nil?
            end
          end

          puts "🔍 DEBUG [Aggregator]: Grouped result: #{grouped.inspect}"
          grouped
        end

        # Calculate consistency statistics for grouped values
        #
        # @param field_name [Symbol, String] Field to analyze
        # @param tolerance [Numeric] Maximum acceptable variance
        # @return [Hash] Consistency statistics per group
        #
        # @example
        #   aggregator.grouped_consistency_stats(:score, tolerance: 12)
        #   # => {
        #   #   industry: { min: 90, max: 92, range: 2, std_dev: 0.8, consistent: true },
        #   #   geography: { min: 85, max: 87, range: 2, std_dev: 0.8, consistent: true }
        #   # }
        def grouped_consistency_stats(field_name, tolerance: 15)
          grouped = grouped_field_values(field_name)

          grouped.each_with_object({}) do |(group_key, values), stats|
            next if values.empty?

            numeric_values = values.select { |v| v.is_a?(Numeric) }
            next if numeric_values.empty?

            min_val = numeric_values.min
            max_val = numeric_values.max
            range = max_val - min_val
            mean = numeric_values.sum.to_f / numeric_values.size
            variance = numeric_values.sum { |v| (v - mean)**2 } / numeric_values.size
            std_dev = Math.sqrt(variance)

            stats[group_key] = {
              min: min_val,
              max: max_val,
              range: range,
              mean: mean.round(2),
              std_dev: std_dev.round(2),
              consistent: range <= tolerance,
              values: numeric_values
            }
          end
        end

        # Get all unique group keys across all runs
        #
        # @return [Array<Symbol>] Unique group keys
        def group_keys
          grouped_field_values(:any_field).keys
        end

        private

        # Extract output items from a run using the configured output_path
        #
        # @param run [Hash] Single evaluation run result
        # @return [Array<Hash>] Domain output items
        def extract_output_items(run)
          puts "🔍 DEBUG [extract_output_items]: Starting extraction with path '#{@output_path}'"

          # Parse output_path (e.g., 'prospect_evaluations.*.criterion_scores')
          path_parts = @output_path.split('.')
          puts "🔍 DEBUG [extract_output_items]: path_parts = #{path_parts.inspect}"

          # Try to find the data starting from the run's top level first
          # This allows paths like 'prospect_evaluations.*.criterion_scores'
          # to work when prospect_evaluations is at run[:prospect_evaluations]
          first_part = path_parts.first

          # Check if first part exists at run level
          if run[first_part] || run[first_part.to_sym]
            puts "🔍 DEBUG [extract_output_items]: Found '#{first_part}' at run level"
            current = run
          else
            # Fall back to agent_result if first part not at run level
            agent_result = run[:agent_result] || run['agent_result']
            puts "🔍 DEBUG [extract_output_items]: '#{first_part}' not at run level, using agent_result"
            puts "🔍 DEBUG [extract_output_items]: agent_result present? #{!agent_result.nil?}"
            return [] unless agent_result
            current = agent_result
          end

          puts "🔍 DEBUG [extract_output_items]: Starting navigation from #{current == run ? 'run' : 'agent_result'} (keys: #{current.keys.inspect})"
          path_parts.each_with_index do |part, index|
            puts "🔍 DEBUG [extract_output_items]:   Step #{index}: part='#{part}', current type=#{current.class.name}"
            if part == '*'
              # Wildcard means "iterate over array elements"
              # The next part tells us which field to extract from each element
              next_part = path_parts[index + 1]

              if next_part && current.is_a?(Array)
                # Extract the next_part field from each array element
                current = current.flat_map do |item|
                  next [] unless item.is_a?(Hash)
                  value = item[next_part] || item[next_part.to_sym]
                  value.is_a?(Array) ? value : [value]
                end.compact

                # Skip the next part since we already processed it
                path_parts.delete_at(index + 1) if path_parts[index + 1] == next_part
              end
            else
              # Navigate down the path
              current = current[part] || current[part.to_sym]
              return [] unless current
            end
          end

          # Ensure we return an array
          current.is_a?(Array) ? current : [current]
        end
      end
    end
  end
end
