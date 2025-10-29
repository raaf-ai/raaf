# frozen_string_literal: true

require "time"

module RAAF
  module Continuation
    # Builder for partial results when merge failures occur
    #
    # This class constructs usable partial results from successfully processed chunks
    # when a merge operation fails. It marks incomplete sections, preserves valid data,
    # and adds failure annotations with error context.
    #
    # @example Building a partial result from chunks
    #   builder = PartialResultBuilder.new
    #   error = StandardError.new("CSV parse error on line 15")
    #   result = builder.build_partial_result_with_error(chunks, error)
    #   # => {
    #   #   content: "id,name\n1,John\n2,Jane\n...",
    #   #   metadata: {
    #   #     incomplete_after: 50,
    #   #     is_partial: true,
    #   #     error_section: { error_class: "StandardError", ... }
    #   #   }
    #   # }
    class PartialResultBuilder
      # Initialize a new PartialResultBuilder
      def initialize
      end

      # Combine chunks into a single string, preserving all content
      #
      # This method concatenates chunk content while preserving structure.
      # It handles various chunk formats and returns a combined string.
      #
      # @param chunks [Array] Array of chunk objects
      # @return [String] Combined content from all chunks
      #
      # @example Combining CSV chunks
      #   chunks = [
      #     { content: "id,name\n1,John\n" },
      #     { content: "2,Jane\n" }
      #   ]
      #   builder.combine_chunks(chunks)
      #   # => "id,name\n1,John\n2,Jane\n"
      def combine_chunks(chunks)
        return "" if chunks.nil? || chunks.empty?

        chunks.map { |chunk| extract_content(chunk) }
              .compact
              .join("")
      end

      # Build a partial result from chunks with incomplete marking
      #
      # Creates a structured result that marks where the data became incomplete
      # and indicates this is a partial result.
      #
      # @param chunks [Array] Array of chunk objects
      # @return [Hash] Partial result structure with content and metadata
      #
      # @example Building partial CSV result
      #   result = builder.build_partial_result(chunks)
      #   # => {
      #   #   content: "id,name\n1,John\n2,Jane",
      #   #   metadata: {
      #   #     incomplete_after: 28,
      #   #     is_partial: true,
      #   #     timestamp: "2025-10-29T12:34:56Z"
      #   #   }
      #   # }
      def build_partial_result(chunks)
        combined = combine_chunks(chunks)

        {
          content: combined,
          metadata: {
            incomplete_after: combined&.length || 0,
            is_partial: true,
            timestamp: Time.now.iso8601
          }
        }
      end

      # Add failure annotation to a partial result
      #
      # Takes an existing partial result and adds error section with
      # detailed failure information.
      #
      # @param chunks [Array] Array of chunk objects
      # @param error [StandardError] The error that caused the failure
      # @return [Hash] Partial result with failure annotation
      #
      # @example Adding error annotation
      #   error = CSV::MalformedCSVError.new("Unclosed quote")
      #   result = builder.add_failure_annotation(chunks, error)
      #   # => {
      #   #   content: "...",
      #   #   metadata: {
      #   #     error_section: {
      #   #       error_class: "CSV::MalformedCSVError",
      #   #       error_message: "Unclosed quote",
      #   #       timestamp: "2025-10-29T12:34:56Z"
      #   #     }
      #   #   }
      #   # }
      def add_failure_annotation(chunks, error)
        combined = combine_chunks(chunks)

        {
          content: combined,
          metadata: {
            error_section: {
              error_class: error.class.name,
              error_message: error.message,
              timestamp: Time.now.iso8601
            }
          }
        }
      end

      # Build a partial result with error annotation
      #
      # Combines the benefits of both partial result building and failure annotation.
      # Creates a complete partial result structure with both incomplete marking
      # and error details.
      #
      # @param chunks [Array] Array of chunk objects
      # @param error [StandardError] The error that caused the failure
      # @return [Hash] Complete partial result with all metadata
      #
      # @example Building complete partial result with error
      #   error = StandardError.new("Merge failed")
      #   result = builder.build_partial_result_with_error(chunks, error)
      #   # => {
      #   #   content: "id,name\n1,John\n2,Jane",
      #   #   metadata: {
      #   #     incomplete_after: 28,
      #   #     is_partial: true,
      #   #     error_section: {
      #   #       error_class: "StandardError",
      #   #       error_message: "Merge failed",
      #   #       timestamp: "2025-10-29T12:34:56Z"
      #   #     },
      #   #     timestamp: "2025-10-29T12:34:56Z"
      #   #   }
      #   # }
      def build_partial_result_with_error(chunks, error)
        combined = combine_chunks(chunks)

        {
          content: combined,
          metadata: {
            incomplete_after: combined&.length || 0,
            is_partial: true,
            error_section: {
              error_class: error.class.name,
              error_message: error.message,
              timestamp: Time.now.iso8601
            },
            timestamp: Time.now.iso8601
          }
        }
      end

      private

      # Extract content from various chunk formats
      #
      # Handles different chunk structures and returns usable content.
      #
      # @param chunk [Object] The chunk to extract content from
      # @return [String, nil] The extracted content or nil
      private

      def extract_content(chunk)
        return nil unless chunk

        if chunk.is_a?(Hash)
          # Try string keys first, then symbol keys
          chunk["content"] || chunk[:content] ||
            chunk["text"] || chunk[:text] ||
            chunk["data"] || chunk[:data] ||
            chunk["message"] || chunk[:message]
        elsif chunk.is_a?(String)
          chunk
        else
          chunk.to_s
        end
      end
    end
  end
end
