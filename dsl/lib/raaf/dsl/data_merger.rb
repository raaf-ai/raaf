# frozen_string_literal: true

module RAAF
  module DSL
    # Smart data merging utilities for multi-agent workflows
    # Provides intelligent merging strategies for combining results from multiple agents
    #
    # @example Basic usage
    #   merger = DataMerger.new
    #   
    #   # Define merge strategy
    #   merger.merge_strategy(:companies) do
    #     key_field :company_domain
    #     merge_arrays :contact_emails, :social_profiles
    #     prefer_latest :last_updated_at
    #     sum_fields :employee_count
    #     combine_objects :enrichment_data, strategy: :deep_merge
    #   end
    #   
    #   # Merge results
    #   search_results = search_agent.call
    #   enrichment_results = enrichment_agent.call
    #   final_result = merger.merge(search_results, enrichment_results)
    #
    class DataMerger
      def initialize
        @merge_strategies = {}
        @default_strategy = DefaultMergeStrategy.new
      end

      # Define a merge strategy for a specific data type
      #
      # @param data_type [Symbol] The type of data being merged (e.g., :companies, :prospects)
      # @param block [Proc] Block defining the merge strategy
      #
      def merge_strategy(data_type, &block)
        strategy = MergeStrategy.new
        strategy.instance_eval(&block) if block_given?
        @merge_strategies[data_type] = strategy
      end

      # Merge multiple agent results using configured strategies
      #
      # @param results [Array<Hash>] Array of agent results to merge
      # @param data_type [Symbol] Type of data being merged
      # @return [Hash] Merged result
      #
      def merge(*results, data_type: :default)
        return {} if results.empty?
        return results.first if results.size == 1

        strategy = @merge_strategies[data_type] || @default_strategy
        
        # Extract data arrays from agent results
        data_arrays = results.map { |result| extract_data_array(result, data_type) }
        
        # Merge the data
        merged_data = merge_data_arrays(data_arrays, strategy)
        
        # Build final result
        {
          success: results.all? { |r| r[:success] != false },
          data: merged_data,
          merge_metadata: {
            sources: results.size,
            strategy: data_type,
            merged_count: merged_data.size,
            timestamp: Time.current.iso8601
          },
          source_results: results
        }
      end

      # Merge arrays of data objects using the specified strategy
      def merge_data_arrays(data_arrays, strategy)
        return [] if data_arrays.empty?
        
        # Flatten and group by key field
        all_items = data_arrays.flatten.compact
        return all_items if strategy.key_field.nil?
        
        grouped_items = all_items.group_by { |item| item[strategy.key_field] || item[strategy.key_field.to_s] }
        
        # Merge each group
        grouped_items.map do |key, items|
          next items.first if items.size == 1
          
          merge_item_group(items, strategy)
        end.compact
      end

      # Merge a group of items that share the same key
      def merge_item_group(items, strategy)
        base_item = items.first.dup
        
        items[1..-1].each do |item|
          merge_two_items(base_item, item, strategy)
        end
        
        base_item
      end

      # Merge two individual items according to the strategy
      def merge_two_items(base_item, new_item, strategy)
        new_item.each do |key, value|
          key_sym = key.to_sym
          key_str = key.to_s
          
          if strategy.array_merge_fields.include?(key_sym) || strategy.array_merge_fields.include?(key_str)
            # Merge arrays
            base_array = Array(base_item[key])
            new_array = Array(value)
            base_item[key] = (base_array + new_array).uniq
            
          elsif strategy.latest_fields.include?(key_sym) || strategy.latest_fields.include?(key_str)
            # Use latest non-nil value
            base_item[key] = value if value && value != ""
            
          elsif strategy.sum_fields.include?(key_sym) || strategy.sum_fields.include?(key_str)
            # Sum numeric values
            base_value = base_item[key] || 0
            base_item[key] = base_value + (value || 0) if value.is_a?(Numeric)
            
          elsif strategy.object_merge_fields.include?(key_sym) || strategy.object_merge_fields.include?(key_str)
            # Deep merge objects
            if base_item[key].is_a?(Hash) && value.is_a?(Hash)
              base_item[key] = deep_merge_objects(base_item[key], value)
            else
              base_item[key] = value
            end
            
          elsif strategy.custom_merge_rules[key_sym] || strategy.custom_merge_rules[key_str]
            # Apply custom merge rule
            rule = strategy.custom_merge_rules[key_sym] || strategy.custom_merge_rules[key_str]
            base_item[key] = rule.call(base_item[key], value)
            
          else
            # Default: prefer new value if not nil
            base_item[key] = value if value
          end
        end
      end

      # Deep merge two hash objects
      def deep_merge_objects(base_obj, new_obj)
        base_obj = base_obj.dup
        
        new_obj.each do |key, value|
          if base_obj[key].is_a?(Hash) && value.is_a?(Hash)
            base_obj[key] = deep_merge_objects(base_obj[key], value)
          elsif base_obj[key].is_a?(Array) && value.is_a?(Array)
            base_obj[key] = (base_obj[key] + value).uniq
          else
            base_obj[key] = value
          end
        end
        
        base_obj
      end

      private

      # Extract data array from agent result
      def extract_data_array(result, data_type)
        return [] unless result.is_a?(Hash)
        
        # Try multiple possible data locations
        data = result[:data] || result["data"] || result
        
        # Look for specific data type key
        if data.is_a?(Hash)
          type_data = data[data_type] || data[data_type.to_s]
          return Array(type_data) if type_data
        end
        
        # If data is already an array, use it
        return data if data.is_a?(Array)
        
        # Otherwise wrap in array
        [data].compact
      end
    end

    # Merge strategy configuration class
    class MergeStrategy
      attr_reader :key_field, :array_merge_fields, :latest_fields, :sum_fields, 
                  :object_merge_fields, :custom_merge_rules

      def initialize
        @key_field = nil
        @array_merge_fields = []
        @latest_fields = []
        @sum_fields = []
        @object_merge_fields = []
        @custom_merge_rules = {}
      end

      # Set the key field for grouping items
      def key_field(field_name)
        @key_field = field_name
      end

      # Fields that should be merged as arrays (union)
      def merge_arrays(*fields)
        @array_merge_fields.concat(fields.map(&:to_sym))
      end

      # Fields that should use the latest non-nil value
      def prefer_latest(*fields)
        @latest_fields.concat(fields.map(&:to_sym))
      end

      # Fields that should be summed (for numeric values)
      def sum_fields(*fields)
        @sum_fields.concat(fields.map(&:to_sym))
      end

      # Fields that should be deep merged as objects
      def combine_objects(*fields, strategy: :deep_merge)
        @object_merge_fields.concat(fields.map(&:to_sym))
      end

      # Define custom merge rule for specific fields
      def custom_merge(field_name, &block)
        @custom_merge_rules[field_name.to_sym] = block
      end
    end

    # Default merge strategy (when no specific strategy is defined)
    class DefaultMergeStrategy
      def key_field
        nil
      end

      def array_merge_fields
        []
      end

      def latest_fields
        []
      end

      def sum_fields
        []
      end

      def object_merge_fields
        []
      end

      def custom_merge_rules
        {}
      end
    end

    # Utility methods for common merge operations
    module MergeUtils
      # Merge prospect data from multiple discovery sources
      def self.merge_prospect_data(*results)
        merger = DataMerger.new
        
        merger.merge_strategy(:prospects) do
          key_field :company_domain
          merge_arrays :contact_emails, :phone_numbers, :social_profiles, :technologies
          prefer_latest :last_updated_at, :funding_stage, :employee_range
          sum_fields :confidence_score
          combine_objects :enrichment_data, :social_data
          
          # Custom merge for scores (average instead of sum)
          custom_merge(:overall_score) do |base_value, new_value|
            return new_value unless base_value
            return base_value unless new_value
            ((base_value + new_value) / 2.0).round(1)
          end
        end
        
        merger.merge(*results, data_type: :prospects)
      end

      # Merge company enrichment data from multiple sources
      def self.merge_enrichment_data(*results)
        merger = DataMerger.new
        
        merger.merge_strategy(:companies) do
          key_field :website_domain
          merge_arrays :technologies, :integrations, :social_profiles, :funding_rounds
          prefer_latest :employee_count, :revenue_range, :last_funding_date
          combine_objects :contact_info, :company_metrics, :market_data
          
          # Custom merge for technology confidence
          custom_merge(:tech_confidence) do |base_value, new_value|
            [base_value || 0, new_value || 0].max
          end
        end
        
        merger.merge(*results, data_type: :companies)
      end

      # Merge stakeholder data from different discovery methods
      def self.merge_stakeholder_data(*results)
        merger = DataMerger.new
        
        merger.merge_strategy(:stakeholders) do
          key_field :linkedin_url
          merge_arrays :email_addresses, :social_profiles, :previous_roles
          prefer_latest :current_title, :department, :seniority_level
          combine_objects :contact_attempts, :engagement_history
          
          # Custom merge for influence scores
          custom_merge(:influence_score) do |base_value, new_value|
            # Take highest confidence score
            return new_value unless base_value
            return base_value unless new_value
            new_value > base_value ? new_value : base_value
          end
        end
        
        merger.merge(*results, data_type: :stakeholders)
      end
    end
  end
end