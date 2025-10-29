# frozen_string_literal: true

require "time"

module RAAF
  module Continuation
    module Mergers
      # Abstract base class for continuation chunk mergers
      #
      # This class provides common functionality for merging continuation chunks
      # from RAAF agents, including content extraction, metadata building, and
      # error handling with fallback strategies.
      #
      # Subclasses must implement the #merge method to define specific merging behavior.
      # Error handling is automatic - subclasses don't need to catch exceptions.
      #
      # @abstract Subclasses must implement the #merge method
      #
      # @example Creating a custom merger
      #   class MyMerger < RAAF::Continuation::Mergers::BaseMerger
      #     def merge(chunks)
      #       contents = chunks.map { |chunk| extract_content(chunk) }.compact
      #       {
      #         content: contents.join("\n"),
      #         metadata: build_metadata(chunks, true)
      #       }
      #     end
      #   end
      #
      # @example Using protected helper methods
      #   def merge(chunks)
      #     begin
      #       contents = chunks.map { |chunk| extract_content(chunk) }
      #       result = contents.compact.join("\n")
      #       {
      #         content: result,
      #         metadata: build_metadata(chunks, true)
      #       }
      #     rescue StandardError => e
      #       handle_merge_error(chunks, e)  # Uses ErrorHandler with fallbacks
      #     end
      #   end
      class BaseMerger
        # Initialize a new BaseMerger
        #
        # @param config [RAAF::Continuation::Config, nil] Configuration object
        #   If nil, uses default configuration
        def initialize(config = nil)
          @config = config || RAAF::Continuation::Config.new
          @error_handler = ErrorHandler.new
        end

        # Merge continuation chunks into a single result
        #
        # @abstract Subclasses must implement this method
        #
        # @param chunks [Array] Array of chunks to merge
        # @return [Object] Merged result (format depends on subclass)
        #
        # @raise [NotImplementedError] Always raised as this is an abstract method
        def merge(chunks)
          raise NotImplementedError, "Subclasses must implement #merge method"
        end

        protected

        # Extract content from various chunk formats
        #
        # This method handles different chunk structures:
        # - Hash chunks with keys: :content, "content", :message, "message", :text, "text", :data, "data"
        # - String chunks (returned as-is)
        # - Other types (returned as-is)
        #
        # @param chunk [Object] The chunk to extract content from
        # @return [Object, nil] The extracted content or nil if no content found
        #
        # @example Hash with content key
        #   extract_content({ content: "Hello" })  # => "Hello"
        #   extract_content({ "content" => "Hello" })  # => "Hello"
        #
        # @example Hash with message key (nested)
        #   extract_content({ message: { content: "Hello" } })  # => "Hello"
        #   extract_content({ "message" => "Hello" })  # => "Hello"
        #
        # @example String chunk
        #   extract_content("Plain text")  # => "Plain text"
        #
        # @example No recognizable content
        #   extract_content({ id: 123 })  # => nil
        def extract_content(chunk)
          return nil unless chunk

          if chunk.is_a?(Hash)
            # Priority order: content > text > data > message
            # Try string keys first
            content = chunk["content"] || chunk["text"] || chunk["data"]

            # Try symbol keys if string keys didn't work
            content ||= chunk[:content] || chunk[:text] || chunk[:data]

            # If still no content, check for message field (could be nested or direct)
            if content.nil?
              # Check for message with string key
              if chunk["message"]
                if chunk["message"].is_a?(Hash)
                  # Try to extract content from nested message
                  content = chunk["message"]["content"] || chunk["message"][:content] || chunk["message"]
                else
                  # Direct message value
                  content = chunk["message"]
                end
              end

              # Check for message with symbol key if string didn't work
              if content.nil? && chunk[:message]
                if chunk[:message].is_a?(Hash)
                  # Try to extract content from nested message
                  content = chunk[:message][:content] || chunk[:message]["content"] || chunk[:message]
                else
                  # Direct message value
                  content = chunk[:message]
                end
              end
            end

            content
          else
            # For non-hash chunks, return them directly
            chunk
          end
        end

        # Build metadata for merge results
        #
        # Creates a metadata hash with information about the merge operation,
        # including success status, chunk count, timestamp, and optional error details.
        #
        # @param chunks [Array, Object] The chunks that were merged
        # @param merge_success [Boolean] Whether the merge was successful
        # @param error [StandardError, nil] Optional error object if merge failed
        #
        # @return [Hash] Metadata hash with the following keys:
        #   - :merge_success [Boolean] Success status
        #   - :chunk_count [Integer] Number of chunks processed
        #   - :timestamp [String] ISO8601 formatted timestamp
        #   - :merge_error [Hash, nil] Error details (only if error provided)
        #
        # @example Successful merge
        #   build_metadata(chunks, true)
        #   # => {
        #   #   merge_success: true,
        #   #   chunk_count: 5,
        #   #   timestamp: "2025-10-29T12:34:56Z"
        #   # }
        #
        # @example Failed merge with error
        #   build_metadata(chunks, false, StandardError.new("Parse error"))
        #   # => {
        #   #   merge_success: false,
        #   #   chunk_count: 3,
        #   #   timestamp: "2025-10-29T12:34:56Z",
        #   #   merge_error: {
        #   #     error_class: "StandardError",
        #   #     error_message: "Parse error"
        #   #   }
        #   # }
        def build_metadata(chunks, merge_success, error = nil)
          metadata = {
            merge_success: merge_success,
            chunk_count: chunks.is_a?(Array) ? chunks.size : 0,
            timestamp: Time.now.iso8601
          }

          if error
            metadata[:merge_error] = {
              error_class: error.class.name,
              error_message: error.message
            }
          end

          metadata
        end

        # Handle merge errors with fallback strategies
        #
        # This method is called by subclasses when an exception occurs during
        # merge. It delegates to the ErrorHandler to attempt recovery using
        # a 3-level fallback chain and respects the configuration on_failure mode.
        #
        # @param chunks [Array] The chunks being merged
        # @param error [StandardError] The error that occurred
        # @return [Hash] Result hash with content and metadata
        # @raise [MergeError] If config.on_failure is :raise_error
        #
        # @example Using in a merger subclass
        #   def merge(chunks)
        #     begin
        #       # Merge logic here
        #     rescue StandardError => e
        #       return handle_merge_error(chunks, e)
        #     end
        #   end
        def handle_merge_error(chunks, error)
          @error_handler.handle_merge_failure(self, chunks, @config, error)
        end

        private

        # Configuration object
        # @return [RAAF::Continuation::Config] The configuration for this merger
        attr_reader :config
      end
    end
  end
end
