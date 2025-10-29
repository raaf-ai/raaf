# frozen_string_literal: true

module RAAF
  module Continuation
    # Exception class for merge failures
    #
    # Raised when a merge operation fails and on_failure is set to :raise_error.
    # Includes detailed error information for debugging.
    #
    # @example Catching merge errors
    #   begin
    #     merger.merge(chunks)
    #   rescue RAAF::Continuation::MergeError => e
    #     puts "Merge failed: #{e.message}"
    #     puts "Error class: #{e.merge_error_metadata[:error_class]}"
    #   end
    class MergeError < StandardError
      # @return [Hash] Metadata about the merge error
      attr_reader :merge_error_metadata

      # Initialize a new MergeError
      #
      # @param message [String] Human-readable error message
      # @param original_error [StandardError, nil] The underlying error that caused the merge to fail
      # @param error_details [Hash, nil] Additional error context
      #
      # @example Creating with original error
      #   begin
      #     JSON.parse(invalid_json)
      #   rescue JSON::ParserError => e
      #     raise MergeError.new("Failed to merge JSON chunks", original_error: e)
      #   end
      #
      # @example Creating with error details
      #   raise MergeError.new(
      #     "Failed to parse CSV",
      #     error_details: {
      #       error_class: "CSV::MalformedCSVError",
      #       error_message: "Unclosed quote in line 5",
      #       backtrace: error.backtrace
      #     }
      #   )
      def initialize(message, original_error: nil, error_details: nil)
        super(message)

        @merge_error_metadata = if error_details
          error_details.dup
        elsif original_error
          {
            error_class: original_error.class.name,
            error_message: original_error.message,
            backtrace: original_error.backtrace&.first(5)
          }
        else
          {
            error_class: self.class.name,
            error_message: message
          }
        end
      end
    end

    # Exception class for truncation failures
    #
    # Raised when response truncation fails and recovery is not possible.
    # This typically indicates a fundamental issue with the response content.
    #
    # @example Catching truncation errors
    #   begin
    #     truncator.truncate(response)
    #   rescue RAAF::Continuation::TruncationError => e
    #     puts "Cannot process response: #{e.message}"
    #   end
    class TruncationError < StandardError
      # @return [Hash] Metadata about the truncation error
      attr_reader :truncation_error_metadata

      # Initialize a new TruncationError
      #
      # @param message [String] Human-readable error message
      # @param original_error [StandardError, nil] The underlying error
      # @param context [Hash, nil] Additional context about the truncation attempt
      #
      # @example Creating with context
      #   raise TruncationError.new(
      #     "Cannot truncate empty response",
      #     context: {
      #       response_length: 0,
      #       truncation_target: 1000,
      #       format: :json
      #     }
      #   )
      def initialize(message, original_error: nil, context: nil)
        super(message)

        @truncation_error_metadata = if context
          context.dup
        elsif original_error
          {
            error_class: original_error.class.name,
            error_message: original_error.message
          }
        else
          {
            error_class: self.class.name,
            error_message: message
          }
        end
      end
    end
  end
end
