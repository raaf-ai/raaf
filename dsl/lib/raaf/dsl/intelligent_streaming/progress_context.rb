# frozen_string_literal: true

module RAAF
  module DSL
    module IntelligentStreaming
      # Immutable context for stream progress hooks
      #
      # Provides structured information about stream execution progress
      # to hook callbacks. This context is immutable to prevent hooks
      # from interfering with each other or the streaming execution.
      #
      # @example Using in a hook
      #   on_stream_start do |progress|
      #     puts "Stream #{progress.stream_number}/#{progress.total_streams}"
      #     puts "Processing #{progress.stream_data.size} items"
      #   end
      class ProgressContext
        attr_reader :stream_number, :total_streams, :stream_data, :metadata

        # Initialize a new ProgressContext
        #
        # @param stream_number [Integer] Current stream number (1-based)
        # @param total_streams [Integer] Total number of streams
        # @param stream_data [Array] Data being processed in this stream
        # @param metadata [Hash] Additional metadata about the stream
        def initialize(stream_number:, total_streams:, stream_data: [], metadata: {})
          @stream_number = stream_number
          @total_streams = total_streams
          @stream_data = stream_data.freeze
          @metadata = metadata.freeze
          freeze
        end

        # Get progress as a percentage
        #
        # @return [Float] Progress percentage (0.0 to 100.0)
        def progress_percentage
          return 0.0 if total_streams.zero?
          (stream_number.to_f / total_streams * 100).round(2)
        end

        # Check if this is the first stream
        #
        # @return [Boolean] true if this is the first stream
        def first_stream?
          stream_number == 1
        end

        # Check if this is the last stream
        #
        # @return [Boolean] true if this is the last stream
        def last_stream?
          stream_number == total_streams
        end

        # Get the size of the current stream
        #
        # @return [Integer] Number of items in current stream
        def stream_size
          stream_data.size
        end

        # Convert to hash representation
        #
        # @return [Hash] Context as a hash
        def to_h
          {
            stream_number: stream_number,
            total_streams: total_streams,
            stream_size: stream_size,
            progress_percentage: progress_percentage,
            first_stream: first_stream?,
            last_stream: last_stream?,
            metadata: metadata
          }
        end

        # String representation for debugging
        #
        # @return [String] Human-readable representation
        def to_s
          "Stream #{stream_number}/#{total_streams} (#{progress_percentage}%) - #{stream_size} items"
        end
      end
    end
  end
end