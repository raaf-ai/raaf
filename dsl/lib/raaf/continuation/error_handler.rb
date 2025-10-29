# frozen_string_literal: true

require "logger"

module RAAF
  module Continuation
    # Error handler for merge failures with 3-level fallback chain
    #
    # This class implements sophisticated error handling for merge operations
    # with a 3-level fallback strategy:
    #
    # Level 1: Format-specific merge (primary approach)
    # Level 2: Simple line concatenation (fallback when format-specific fails)
    # Level 3: First chunk only (fallback when all else fails)
    #
    # @example Basic error handling
    #   handler = ErrorHandler.new
    #   result = handler.handle_merge_failure(merger, chunks, config)
    #   # Returns partial result or raises error based on config.on_failure
    #
    # @example With tracking
    #   handler = ErrorHandler.new
    #   result = handler.handle_merge_failure(merger, chunks, config)
    #   if result[:metadata][:fallback_level]
    #     puts "Used fallback level: #{result[:metadata][:fallback_level]}"
    #   end
    class ErrorHandler
      # Initialize a new ErrorHandler
      #
      # @param logger [Logger, nil] Optional logger for error details
      def initialize(logger: nil)
        @logger = logger || get_default_logger
        @partial_result_builder = PartialResultBuilder.new
      end

      # Handle merge failure with 3-level fallback chain
      #
      # Attempts to recover from merge failures by trying progressive fallback
      # strategies. Respects the config.on_failure mode for final error handling.
      #
      # @param merger [BaseMerger] The merger that failed
      # @param chunks [Array] Array of chunks being merged
      # @param config [Config] Configuration including on_failure mode
      #
      # @return [Hash] Partial result or error result
      # @raise [MergeError] If config.on_failure is :raise_error
      #
      # @example Success with fallback tracking
      #   result = handler.handle_merge_failure(merger, chunks, config)
      #   # => {
      #   #   content: "partial content...",
      #   #   metadata: {
      #   #     merge_success: false,
      #   #     fallback_level: 2,  # Fell back to line concatenation
      #   #     fallback_reason: "Format-specific merge failed",
      #   #     ...
      #   #   }
      #   # }
      #
      # @example With error raising
      #   config = Config.new(on_failure: :raise_error)
      #   handler.handle_merge_failure(merger, chunks, config)
      #   # Raises MergeError with context
      def handle_merge_failure(merger, chunks, config, original_error = nil)
        log_failure_start(merger, chunks, original_error)

        # Try Level 1: Format-specific merge
        result = attempt_level_1_format_merge(merger, chunks, config, original_error)
        return result if result[:metadata][:merge_success]

        # Level 1 failed, try Level 2: Simple line concatenation
        result = attempt_level_2_concatenation(chunks, config, original_error)
        return result if result[:metadata][:merge_success]

        # Level 2 failed, try Level 3: First chunk only
        result = attempt_level_3_first_chunk(chunks, config, original_error)

        # All fallbacks attempted, handle failure based on config
        handle_final_result(result, config, original_error)
      end

      private

      # Attempt Level 1: Format-specific merge
      #
      # This is the primary merge strategy using the specific merger
      # with its format-specific logic.
      #
      # @param merger [BaseMerger] The merger to use
      # @param chunks [Array] Chunks to merge
      # @param config [Config] Configuration
      # @param original_error [StandardError, nil] Original error if retrying
      # @return [Hash] Result with fallback_level metadata
      private

      def attempt_level_1_format_merge(merger, chunks, config, original_error)
        log_info("Attempting Level 1: Format-specific merge")

        result = merger.merge(chunks)
        result[:metadata][:fallback_level] = 1
        result[:metadata][:fallback_used] = false

        result
      rescue StandardError => e
        log_warn("Level 1 failed: #{e.class.name}: #{e.message}")

        {
          content: nil,
          metadata: {
            merge_success: false,
            fallback_level: 1,
            fallback_used: false,
            fallback_reason: "#{e.class.name}: #{e.message}",
            chunk_count: chunks.is_a?(Array) ? chunks.size : 0,
            timestamp: Time.now.iso8601,
            merge_error: {
              error_class: e.class.name,
              error_message: e.message
            }
          }
        }
      end

      # Attempt Level 2: Simple line concatenation
      #
      # When format-specific merge fails, fall back to simple line-by-line
      # concatenation. This is a more forgiving approach that doesn't care
      # about format specifics.
      #
      # @param chunks [Array] Chunks to merge
      # @param config [Config] Configuration
      # @param original_error [StandardError, nil] Original error
      # @return [Hash] Result with fallback_level metadata
      private

      def attempt_level_2_concatenation(chunks, config, original_error)
        log_info("Attempting Level 2: Simple line concatenation")

        begin
          combined_content = simple_concatenate(chunks)
          log_success("Level 2: Concatenation succeeded")

          {
            content: combined_content,
            metadata: {
              merge_success: true,
              fallback_level: 2,
              fallback_used: true,
              fallback_reason: "Format-specific merge failed, used concatenation",
              chunk_count: chunks.is_a?(Array) ? chunks.size : 0,
              timestamp: Time.now.iso8601
            }
          }
        rescue StandardError => e
          log_warn("Level 2 failed: #{e.class.name}: #{e.message}")

          {
            content: nil,
            metadata: {
              merge_success: false,
              fallback_level: 2,
              fallback_used: false,
              fallback_reason: "Concatenation failed: #{e.class.name}",
              chunk_count: chunks.is_a?(Array) ? chunks.size : 0,
              timestamp: Time.now.iso8601,
              merge_error: {
                error_class: e.class.name,
                error_message: e.message
              }
            }
          }
        end
      end

      # Attempt Level 3: First chunk only
      #
      # As a last resort, return only the first successful chunk.
      # This ensures we have at least some valid data.
      #
      # @param chunks [Array] Chunks to process
      # @param config [Config] Configuration
      # @param original_error [StandardError, nil] Original error
      # @return [Hash] Result with fallback_level metadata
      private

      def attempt_level_3_first_chunk(chunks, config, original_error)
        log_info("Attempting Level 3: First chunk only")

        begin
          first_content = extract_first_valid_chunk(chunks)

          if first_content
            log_success("Level 3: Got first chunk")

            {
              content: first_content,
              metadata: {
                merge_success: true,
                fallback_level: 3,
                fallback_used: true,
                fallback_reason: "Both merge and concatenation failed, using first chunk only",
                chunk_count: chunks.is_a?(Array) ? chunks.size : 0,
                timestamp: Time.now.iso8601
              }
            }
          else
            log_error("Level 3: No valid content found in any chunk")

            {
              content: nil,
              metadata: {
                merge_success: false,
                fallback_level: 3,
                fallback_used: false,
                fallback_reason: "No valid content found in any chunk",
                chunk_count: chunks.is_a?(Array) ? chunks.size : 0,
                timestamp: Time.now.iso8601
              }
            }
          end
        rescue StandardError => e
          log_error("Level 3 failed unexpectedly: #{e.class.name}: #{e.message}")

          {
            content: nil,
            metadata: {
              merge_success: false,
              fallback_level: 3,
              fallback_used: false,
              fallback_reason: "First chunk extraction failed: #{e.class.name}",
              chunk_count: chunks.is_a?(Array) ? chunks.size : 0,
              timestamp: Time.now.iso8601,
              merge_error: {
                error_class: e.class.name,
                error_message: e.message
              }
            }
          }
        end
      end

      # Handle the final result based on configuration
      #
      # If the result has content (any fallback succeeded), returns it.
      # Otherwise, respects the config.on_failure setting:
      # - :return_partial: Returns the partial result
      # - :raise_error: Raises MergeError
      #
      # @param result [Hash] The result from fallback attempts
      # @param config [Config] Configuration
      # @param original_error [StandardError, nil] Original error
      # @return [Hash] The result to return
      # @raise [MergeError] If config.on_failure is :raise_error
      private

      def handle_final_result(result, config, original_error)
        # If we have content, return it even if fallback was used
        return result if result[:content].present?

        # No content from any fallback level
        case config.on_failure
        when :return_partial
          log_info("No content available, returning empty partial result")
          result
        when :raise_error
          log_error("All fallback levels failed, raising MergeError")
          raise MergeError.new(
            "All merge fallback strategies failed",
            original_error: original_error,
            error_details: result[:metadata][:merge_error]
          )
        else
          # Default to return_partial if unknown mode
          result
        end
      end

      # Simple line-by-line concatenation fallback
      #
      # @param chunks [Array] Chunks to concatenate
      # @return [String] Concatenated content
      private

      def simple_concatenate(chunks)
        return "" if chunks.nil? || chunks.empty?

        chunks.map { |chunk| extract_content(chunk) }
              .compact
              .join("\n")
      end

      # Extract first valid chunk content
      #
      # @param chunks [Array] Chunks to search
      # @return [String, nil] First valid content found
      private

      def extract_first_valid_chunk(chunks)
        return nil if chunks.nil? || chunks.empty?

        chunks.each do |chunk|
          content = extract_content(chunk)
          return content if content.present?
        end

        nil
      end

      # Extract content from a chunk
      #
      # @param chunk [Object] Chunk to extract from
      # @return [String, nil] Extracted content
      private

      def extract_content(chunk)
        return nil unless chunk

        if chunk.is_a?(Hash)
          chunk["content"] || chunk[:content] ||
            chunk["text"] || chunk[:text] ||
            chunk["data"] || chunk[:data] ||
            chunk["message"] || chunk[:message]
        elsif chunk.is_a?(String)
          chunk
        else
          nil
        end
      end

      # Logging helpers
      private

      def log_failure_start(merger, chunks, original_error)
        message = "Starting merge error handling"
        message += " (#{original_error.class.name})" if original_error
        log_warn(message)
      end

      def log_info(message)
        @logger.info("ℹ️ #{message}") if @logger
      end

      def log_warn(message)
        @logger.warn("⚠️ #{message}") if @logger
      end

      def log_error(message)
        @logger.error("❌ #{message}") if @logger
      end

      def log_success(message)
        @logger.info("✅ #{message}") if @logger
      end

      def get_default_logger
        if defined?(Rails) && Rails.logger
          Rails.logger
        else
          Logger.new($stdout)
        end
      end
    end
  end
end
