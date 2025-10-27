# frozen_string_literal: true

module RAAF
  module DSL
    # Incremental processor for batch processing with skip detection
    #
    # This class handles the actual execution of incremental processing logic,
    # including batching, skip detection, data loading, persistence, and result accumulation.
    #
    # The processor works by:
    # 1. Splitting input items into batches (if chunk_size configured)
    # 2. For each batch:
    #    a. Filtering items using skip_if logic
    #    b. Loading existing data for skipped items
    #    c. Processing non-skipped items through provided block
    #    d. Persisting batch results via persistence_handler
    # 3. Merging all results (processed + skipped) in original order
    #
    # @example Basic usage
    #   processor = RAAF::DSL::IncrementalProcessor.new(agent, config)
    #
    #   result = processor.process(input_items, context) do |items, context|
    #     # Process items through AI or other logic
    #     items.map { |item| ai_process(item) }
    #   end
    #
    class IncrementalProcessor
      # @return [Object] The agent instance using this processor
      attr_reader :agent

      # @return [IncrementalConfig] The incremental processing configuration
      attr_reader :config

      # Initialize a new incremental processor
      #
      # @param agent [Object] The agent instance
      # @param config [IncrementalConfig] The incremental processing configuration
      # @raise [ArgumentError] if agent or config is nil
      # @raise [RuntimeError] if configuration is incomplete
      def initialize(agent, config)
        raise ArgumentError, "agent cannot be nil" unless agent
        raise ArgumentError, "config cannot be nil" unless config

        # Validate configuration completeness
        config.validate!

        @agent = agent
        @config = config
      end

      # Process input items with incremental logic
      #
      # This method:
      # 1. Splits input into batches FIRST
      # 2. For each batch:
      #    a. Detects which items should be skipped
      #    b. Loads existing data for skipped items
      #    c. Processes non-skipped items
      #    d. Calls persistence_handler with processed items
      # 3. Merges all results (processed + skipped) in original order
      #
      # @param input_items [Array<Hash>] Input items to process
      # @param context [Hash] Agent context (must support [] access)
      # @yieldparam items [Array<Hash>] Batch of non-skipped items to process
      # @yieldparam context [Hash] Agent context
      # @yieldreturn [Array<Hash>] Processed results for batch
      # @return [Array<Hash>] All results (processed + skipped) in original order
      #
      # @example
      #   result = processor.process(companies, context) do |batch, ctx|
      #     batch.map { |company| analyze_company(company, ctx) }
      #   end
      #
      def process(input_items, context, &block)
        raise ArgumentError, "Processing block is required" unless block_given?

        # Handle empty input
        return [] if input_items.empty?

        # Check force_reprocess flag
        force_reprocess = context[:force_reprocess] || false

        # Determine batch size
        batch_size = config.chunk_size || input_items.count

        # Split input into batches FIRST
        batches = input_items.each_slice(batch_size).to_a

        # Get agent name for logging
        agent_name = @agent.class.name.split('::').last

        RAAF.logger.info "🔍 [#{agent_name}] Input: #{input_items.count} items"
        RAAF.logger.info "📦 [#{agent_name}] Processing in #{batches.count} batch(es) of max #{batch_size} items"

        # Track all results
        all_skipped = []
        all_processed = []
        total_skipped_count = 0
        total_processed_count = 0

        # Process each batch
        batches.each_with_index do |batch, batch_idx|
          batch_number = batch_idx + 1

          # Partition batch into skipped and to-process
          skipped_items, items_to_process = partition_batch(batch, context, force_reprocess)

          total_skipped_count += skipped_items.count
          total_processed_count += items_to_process.count

          RAAF.logger.info "⚙️  [#{agent_name}] Batch #{batch_number}/#{batches.count}: #{batch.count} items (#{skipped_items.count} skipped, #{items_to_process.count} to process)"

          # Skip processing if no items to process
          if items_to_process.empty?
            all_skipped.concat(skipped_items)
            next
          end

          # Process non-skipped items
          start_time = Time.now
          batch_results = block.call(items_to_process, context)
          duration_ms = ((Time.now - start_time) * 1000).round(2)

          RAAF.logger.info "✅ [#{agent_name}] Batch #{batch_number} processed in #{duration_ms}ms"

          # Persist batch results
          persist_batch(batch_results, context)

          # Accumulate results
          all_skipped.concat(skipped_items)
          all_processed.concat(batch_results)
        end

        # Log final metrics
        RAAF.logger.info "⏭️  [#{agent_name}] Total skipped: #{total_skipped_count} items (existing)"
        RAAF.logger.info "⚡ [#{agent_name}] Total processed: #{total_processed_count} items"

        # Merge processed and skipped items in original order
        merge_results(input_items, all_processed, all_skipped)
      end

      private

      # Partition batch items into skipped and to-process groups
      #
      # @param batch_items [Array<Hash>] Items in this batch
      # @param context [Hash] Agent context
      # @param force_reprocess [Boolean] Whether to skip detection
      # @return [Array<(Array<Hash>, Array<Hash>)>] [skipped_items, items_to_process]
      def partition_batch(batch_items, context, force_reprocess)
        skipped_items = []
        items_to_process = []

        batch_items.each do |item|
          # Check if item should be skipped (unless force_reprocess)
          should_skip = !force_reprocess && config.skip_if_block.call(item, context)

          if should_skip
            # Load existing data for skipped item
            existing_data = config.load_existing_block.call(item, context)
            skipped_items << { original: item, data: existing_data }
          else
            # Mark for processing
            items_to_process << item
          end
        end

        [skipped_items, items_to_process]
      end

      # Persist batch results via persistence_handler
      #
      # @param batch_results [Array<Hash>] Results to persist
      # @param context [Hash] Agent context
      # @return [void]
      def persist_batch(batch_results, context)
        return if batch_results.empty?

        agent_name = @agent.class.name.split('::').last

        RAAF.logger.info "💾 [#{agent_name}] Persisting batch of #{batch_results.count} items"

        start_time = Time.now

        # Convert batch_results to indifferent access before passing to handler
        # This ensures application code can use either symbol or string keys
        indifferent_results = batch_results.map do |result|
          RAAF::Utils.indifferent_access(result)
        end

        # Call persistence handler with indifferent access data
        config.persistence_handler_block.call(indifferent_results, context)

        duration_ms = ((Time.now - start_time) * 1000).round(2)
        RAAF.logger.info "✅ [#{agent_name}] Batch persisted in #{duration_ms}ms"
      end

      # Merge processed and skipped items in original order
      #
      # @param original_items [Array<Hash>] Original input items
      # @param processed_items [Array<Hash>] Processed results
      # @param skipped_items [Array<Hash>] Skipped items with loaded data
      # @return [Array<Hash>] Merged results in original order
      def merge_results(original_items, processed_items, skipped_items)
        # Create lookup maps for fast access
        # For processed items, we'll match by original record reference
        # For skipped items, we already have the mapping

        # Build skipped lookup by original item reference
        skipped_lookup = {}
        skipped_items.each do |skipped|
          # Use object_id as key for exact reference matching
          skipped_lookup[skipped[:original].object_id] = skipped[:data]
        end

        # Build processed lookup by matching items that were processed
        # We need to track which items were processed vs skipped
        processed_lookup = {}
        processed_index = 0

        # Reconstruct results in original order
        result = []

        original_items.each do |original_item|
          if skipped_lookup.key?(original_item.object_id)
            # Use skipped data
            result << skipped_lookup[original_item.object_id]
          else
            # Use processed data
            processed_item = processed_items[processed_index]

            # Check for nil - indicates result_transform broke 1:1 correspondence
            if processed_item.nil?
              agent_name = @agent.class.name.split('::').last
              error_msg = "❌ [#{agent_name}] CRITICAL: result_transform broke 1:1 correspondence! " \
                          "Expected #{original_items.count - skipped_items.count} processed items, " \
                          "but only got #{processed_items.compact.count}. " \
                          "This usually means result_transform is filtering items (e.g., .select, .reject). " \
                          "Result transforms must return ALL processed items to maintain order."

              RAAF.logger.error error_msg
              raise ArgumentError, error_msg
            end

            result << processed_item
            processed_index += 1
          end
        end

        agent_name = @agent.class.name.split('::').last
        RAAF.logger.info "🔄 [#{agent_name}] Merged #{result.count} total items (#{processed_items.count} processed + #{skipped_items.count} skipped)"

        result
      end
    end
  end
end
