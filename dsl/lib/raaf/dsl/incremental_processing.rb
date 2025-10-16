# frozen_string_literal: true

require_relative 'incremental_config'

module RAAF
  module DSL
    # Incremental processing module for RAAF agents
    #
    # This module provides a DSL for configuring incremental processing of array inputs,
    # allowing agents to automatically skip already-processed records, load existing data,
    # and persist results in batches for crash resilience and memory efficiency.
    #
    # Key features:
    # - Auto-detection of input/output fields from context and schema
    # - Closure-based DSL for skip logic, data loading, and persistence
    # - Optional batching for memory efficiency
    # - Force reprocess override via context
    # - Automatic hook integration
    #
    # @example Agent with incremental processing
    #   class QuickFitAnalyzer < ApplicationAgent
    #     context do
    #       required :company_list, incremental: true  # Mark for incremental processing
    #       required :product, :company, :market
    #     end
    #
    #     schema do
    #       field :prospects, type: :array, required: true  # Auto-detected output
    #     end
    #
    #     incremental_processing do
    #       chunk_size 20  # Process in batches of 20
    #
    #       skip_if do |record, context|
    #         Prospect.exists?(coc_number: record[:coc_number])
    #       end
    #
    #       load_existing do |record, context|
    #         prospect = Prospect.find_by(coc_number: record[:coc_number])
    #         { name: record[:name], quick_fit_score: prospect.quick_analysis_data[:score] }
    #       end
    #
    #       persistence_handler do |batch_results, context|
    #         batch_results.each { |result| persist_prospect(result, context) }
    #       end
    #     end
    #   end
    #
    module IncrementalProcessing
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # DSL method for configuring incremental processing
        #
        # @yieldparam config [IncrementalConfig] Configuration object to set up
        # @raise [ArgumentError] if no block is provided
        # @return [IncrementalConfig] The configured object
        #
        # @example
        #   incremental_processing do
        #     chunk_size 20
        #
        #     skip_if { |record, context| record_exists?(record) }
        #     load_existing { |record, context| load_from_db(record) }
        #     persistence_handler { |batch, context| save_batch(batch) }
        #   end
        def incremental_processing(&block)
          raise ArgumentError, "block required" unless block_given?

          config = IncrementalConfig.new
          config.instance_eval(&block)
          self._incremental_config = config
        end

        # Declare which context field contains the incremental input data
        #
        # This explicitly marks which field in the agent's context should be
        # processed incrementally. Used by ApplicationAgent to auto-detect the
        # input field without requiring metadata on context field declarations.
        #
        # @param field_name [Symbol, String] Name of the context field
        # @return [Symbol] The stored field name
        #
        # @example
        #   class QuickFitAnalyzer < ApplicationAgent
        #     context do
        #       required :company_list, :product, :company
        #     end
        #
        #     incremental_input_field :company_list
        #
        #     incremental_processing do
        #       # ... configuration
        #     end
        #   end
        def incremental_input_field(field_name)
          self._incremental_input_field = field_name.to_sym
        end

        # Get the declared incremental input field
        #
        # @return [Symbol, nil] The input field name or nil if not declared
        def _incremental_input_field
          @_incremental_input_field
        end

        # Set the incremental input field
        #
        # @param field [Symbol] The field name
        # @return [Symbol] The stored field name
        def _incremental_input_field=(field)
          @_incremental_input_field = field
        end

        # Declare which schema field contains the incremental output data
        #
        # This explicitly marks which field in the agent's schema represents the
        # output array. Used by ApplicationAgent to auto-detect the output field.
        #
        # @param field_name [Symbol, String] Name of the schema field
        # @return [Symbol] The stored field name
        #
        # @example
        #   class QuickFitAnalyzer < ApplicationAgent
        #     schema do
        #       field :prospects, type: :array
        #     end
        #
        #     incremental_output_field :prospects
        #
        #     incremental_processing do
        #       # ... configuration
        #     end
        #   end
        def incremental_output_field(field_name)
          self._incremental_output_field = field_name.to_sym
        end

        # Get the declared incremental output field
        #
        # @return [Symbol, nil] The output field name or nil if not declared
        def _incremental_output_field
          @_incremental_output_field
        end

        # Set the incremental output field
        #
        # @param field [Symbol] The field name
        # @return [Symbol] The stored field name
        def _incremental_output_field=(field)
          @_incremental_output_field = field
        end

        # Get the incremental processing configuration
        #
        # @return [IncrementalConfig, nil] The configuration or nil if not configured
        def _incremental_config
          @_incremental_config
        end

        # Set the incremental processing configuration
        #
        # @param config [IncrementalConfig] The configuration to store
        # @return [IncrementalConfig] The stored configuration
        def _incremental_config=(config)
          @_incremental_config = config
        end
      end

      # Check if incremental processing is enabled for this agent
      #
      # @return [Boolean] true if incremental processing is configured
      def incremental_processing?
        !incremental_config.nil?
      end

      # Get the incremental processing configuration for this agent instance
      #
      # @return [IncrementalConfig, nil] The configuration or nil if not configured
      def incremental_config
        self.class._incremental_config
      end
    end
  end
end
