# frozen_string_literal: true

module RAAF
  module DSL
    # Configuration class for incremental processing
    #
    # This class stores the configuration for how an agent should handle incremental processing,
    # including batch sizing and the three required closures for skip detection, data loading,
    # and persistence handling.
    #
    # @example Basic incremental configuration
    #   config = RAAF::DSL::IncrementalConfig.new
    #   config.instance_eval do
    #     chunk_size 20
    #
    #     skip_if do |record, context|
    #       # Check if record already processed
    #       Company.exists?(website: record[:website])
    #     end
    #
    #     load_existing do |record, context|
    #       # Load existing data for skipped records
    #       company = Company.find_by(website: record[:website])
    #       { id: company.id, name: company.name, enrichment_data: company.enrichment_data }
    #     end
    #
    #     persistence_handler do |batch_results, context|
    #       # Persist each batch to database
    #       batch_results.each { |result| persist_to_database(result) }
    #     end
    #   end
    #
    class IncrementalConfig
      # @return [Integer, nil] Size of batches for processing (nil = process all at once)
      attr_reader :chunk_size

      # @return [Proc, nil] Block to check if record should be skipped
      attr_reader :skip_if_block

      # @return [Proc, nil] Block to load existing data for skipped records
      attr_reader :load_existing_block

      # @return [Proc, nil] Block to persist batch results
      attr_reader :persistence_handler_block

      def initialize
        @chunk_size = nil  # Default: process all at once
        @skip_if_block = nil
        @load_existing_block = nil
        @persistence_handler_block = nil
      end

      # Set the chunk size for batch processing
      #
      # @param size [Integer, nil] Number of records per batch, or nil to process all at once
      # @raise [ArgumentError] if size is not a positive integer or nil
      # @return [Integer, nil] The configured chunk size
      def chunk_size(size = nil)
        if size.nil?
          @chunk_size
        else
          unless size.is_a?(Integer) && size > 0
            raise ArgumentError, "chunk_size must be a positive integer, got: #{size.inspect}"
          end
          @chunk_size = size
        end
      end

      # Define the skip_if closure
      #
      # This closure receives a record and context, and returns true if the record
      # should be skipped (already processed) or false if it needs processing.
      #
      # @yieldparam record [Hash] The input record to check
      # @yieldparam context [Hash] The agent context
      # @yieldreturn [Boolean] true to skip this record, false to process it
      # @raise [ArgumentError] if no block is provided
      # @return [Proc] The skip_if block
      #
      # @example
      #   skip_if do |record, context|
      #     Prospect.exists?(coc_number: record[:coc_number])
      #   end
      def skip_if(&block)
        raise ArgumentError, "skip_if requires a block" unless block_given?
        @skip_if_block = block
      end

      # Define the load_existing closure
      #
      # This closure receives a record and context for a skipped record, and returns
      # the existing data from the database that matches the agent's output schema.
      #
      # @yieldparam record [Hash] The input record that was skipped
      # @yieldparam context [Hash] The agent context
      # @yieldreturn [Hash] Existing data matching the agent's output schema
      # @raise [ArgumentError] if no block is provided
      # @return [Proc] The load_existing block
      #
      # @example
      #   load_existing do |record, context|
      #     prospect = Prospect.find_by(coc_number: record[:coc_number])
      #     {
      #       name: record[:name],
      #       quick_fit_score: prospect.quick_analysis_data[:score],
      #       passed_filter: prospect.quick_analysis_data[:passed_filter]
      #     }
      #   end
      def load_existing(&block)
        raise ArgumentError, "load_existing requires a block" unless block_given?
        @load_existing_block = block
      end

      # Define the persistence_handler closure
      #
      # This closure receives batch results and context after each batch completes,
      # and is responsible for persisting the results to the database.
      #
      # @yieldparam batch_results [Array<Hash>] Array of processed results for this batch
      # @yieldparam context [Hash] The agent context
      # @raise [ArgumentError] if no block is provided
      # @return [Proc] The persistence_handler block
      #
      # @example
      #   persistence_handler do |batch_results, context|
      #     batch_results.each do |result|
      #       Prospect.create!(
      #         name: result[:name],
      #         quick_analysis_data: { score: result[:quick_fit_score] }
      #       )
      #     end
      #   end
      def persistence_handler(&block)
        raise ArgumentError, "persistence_handler requires a block" unless block_given?
        @persistence_handler_block = block
      end

      # Validate that all required closures are defined
      #
      # @raise [RuntimeError] if any required closure is missing
      # @return [Boolean] true if valid
      def validate!
        errors = []
        errors << "skip_if block is required" unless @skip_if_block
        errors << "load_existing block is required" unless @load_existing_block
        errors << "persistence_handler block is required" unless @persistence_handler_block

        unless errors.empty?
          raise RuntimeError, "Incremental processing configuration incomplete: #{errors.join(', ')}"
        end

        true
      end

      # Check if configuration is complete (has all required blocks)
      #
      # @return [Boolean] true if all required blocks are defined
      def complete?
        @skip_if_block && @load_existing_block && @persistence_handler_block
      end
    end
  end
end
