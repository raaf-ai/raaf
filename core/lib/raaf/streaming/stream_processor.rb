# frozen_string_literal: true

require "async"
require "json"

module RAAF

  module Streaming

    ##
    # Stream processor for handling streaming responses
    #
    # Processes streaming responses from AI providers and handles chunked data,
    # buffering, and real-time delivery to clients.
    #
    class StreamProcessor

      include RAAF::Logging

      # @return [Integer] Chunk size for streaming
      attr_reader :chunk_size

      # @return [Integer] Buffer size
      attr_reader :buffer_size

      # @return [Float] Timeout for streaming operations
      attr_reader :timeout

      # @return [Integer] Number of retry attempts
      attr_reader :retry_count

      ##
      # Initialize stream processor
      #
      # @param chunk_size [Integer] Size of chunks for streaming
      # @param buffer_size [Integer] Size of internal buffer
      # @param timeout [Float] Timeout for streaming operations
      # @param retry_count [Integer] Number of retry attempts
      #
      def initialize(chunk_size: 1024, buffer_size: 4096, timeout: 30, retry_count: 3)
        @chunk_size = chunk_size
        @buffer_size = buffer_size
        @timeout = timeout
        @retry_count = retry_count
        @active_streams = {}
        @stream_counter = 0
        @mutex = Mutex.new
      end

      ##
      # Start streaming response
      #
      # @param agent [Agent] Agent instance
      # @param message [String] Message to process
      # @param options [Hash] Streaming options
      # @yield [chunk] Yields each chunk of the response
      # @return [String] Stream ID
      #
      def start_stream(agent, message, **options, &block)
        stream_id = generate_stream_id

        @mutex.synchronize do
          @active_streams[stream_id] = {
            agent: agent,
            message: message,
            options: options,
            block: block,
            status: :starting,
            started_at: Time.current,
            chunks: [],
            total_chunks: 0
          }
        end

        # Start streaming in background
        Async do
          process_stream(stream_id)
        end

        stream_id
      end

      ##
      # Stop streaming
      #
      # @param stream_id [String] Stream ID to stop
      #
      def stop_stream(stream_id)
        @mutex.synchronize do
          stream = @active_streams[stream_id]
          if stream
            stream[:status] = :stopping
            log_info("Stopping stream", stream_id: stream_id)
          end
        end
      end

      ##
      # Get stream status
      #
      # @param stream_id [String] Stream ID
      # @return [Hash, nil] Stream status or nil if not found
      #
      def stream_status(stream_id)
        @mutex.synchronize do
          stream = @active_streams[stream_id]
          return nil unless stream

          {
            status: stream[:status],
            started_at: stream[:started_at],
            total_chunks: stream[:total_chunks],
            duration: Time.current - stream[:started_at]
          }
        end
      end

      ##
      # Get all active streams
      #
      # @return [Array<String>] Array of active stream IDs
      #
      def active_streams
        @mutex.synchronize do
          @active_streams.keys
        end
      end

      ##
      # Get stream statistics
      #
      # @return [Hash] Stream statistics
      #
      def stats
        @mutex.synchronize do
          {
            active_streams: @active_streams.size,
            total_streams: @stream_counter,
            streams_by_status: @active_streams.group_by { |_, stream| stream[:status] }
                                              .transform_values(&:size)
          }
        end
      end

      ##
      # Process streaming response with chunking
      #
      # @param response [String] Response content
      # @param chunk_size [Integer] Chunk size
      # @yield [chunk] Yields each chunk
      # @return [Array<String>] Array of chunks
      #
      def self.chunk_response(response, chunk_size: 1024)
        chunks = []

        # Split response into words to avoid breaking words
        words = response.split(/\s+/)
        current_chunk = []
        current_size = 0

        words.each do |word|
          word_size = word.bytesize + 1 # +1 for space

          if current_size + word_size > chunk_size && current_chunk.any?
            # Current chunk is full, yield it
            chunk = current_chunk.join(" ")
            chunks << chunk
            yield chunk if block_given?

            # Start new chunk
            current_chunk = [word]
            current_size = word_size
          else
            # Add word to current chunk
            current_chunk << word
            current_size += word_size
          end
        end

        # Add final chunk if any
        if current_chunk.any?
          chunk = current_chunk.join(" ")
          chunks << chunk
          yield chunk if block_given?
        end

        chunks
      end

      ##
      # Stream JSON responses
      #
      # @param data [Hash] Data to stream as JSON
      # @param chunk_size [Integer] Chunk size
      # @yield [chunk] Yields each JSON chunk
      # @return [Array<String>] Array of JSON chunks
      #
      def self.stream_json(data, chunk_size: 1024)
        json_string = JSON.generate(data)
        chunk_response(json_string, chunk_size: chunk_size) do |chunk|
          yield chunk if block_given?
        end
      end

      ##
      # Stream server-sent events
      #
      # @param data [Hash] Event data
      # @param event_type [String] Event type
      # @param event_id [String] Event ID
      # @yield [event] Yields formatted SSE event
      # @return [String] Formatted SSE event
      #
      def self.stream_sse(data, event_type: "message", event_id: nil)
        sse_event = ""
        sse_event += "id: #{event_id}\n" if event_id
        sse_event += "event: #{event_type}\n"
        sse_event += "data: #{JSON.generate(data)}\n\n"

        yield sse_event if block_given?
        sse_event
      end

      private

      def generate_stream_id
        @mutex.synchronize do
          @stream_counter += 1
          "stream_#{@stream_counter}_#{SecureRandom.hex(8)}"
        end
      end

      def process_stream(stream_id)
        stream = @active_streams[stream_id]
        return unless stream

        begin
          # Update status
          update_stream_status(stream_id, :processing)

          # Process with agent
          agent = stream[:agent]
          message = stream[:message]
          options = stream[:options]
          block = stream[:block]

          # Check if agent supports streaming
          if agent.provider.respond_to?(:stream)
            # Use provider's streaming capability
            agent.provider.stream(message, **options) do |chunk|
              next if stream[:status] == :stopping

              # Process chunk
              processed_chunk = process_chunk(chunk, stream_id)

              # Yield to block if provided
              block&.call(processed_chunk)

              # Store chunk
              add_chunk_to_stream(stream_id, processed_chunk)
            end
          else
            # Fallback to chunked response
            result = agent.run(message, **options)
            content = result.messages.last[:content]

            self.class.chunk_response(content, chunk_size: @chunk_size) do |chunk|
              next if stream[:status] == :stopping

              processed_chunk = {
                content: chunk,
                type: :text,
                timestamp: Time.current.iso8601,
                stream_id: stream_id
              }

              block&.call(processed_chunk)
              add_chunk_to_stream(stream_id, processed_chunk)
            end
          end

          # Mark as completed
          update_stream_status(stream_id, :completed)
        rescue StandardError => e
          log_error("Stream processing error", stream_id: stream_id, error: e)
          update_stream_status(stream_id, :error)

          # Notify error through block
          stream[:block]&.call({
                                 type: :error,
                                 message: e.message,
                                 timestamp: Time.current.iso8601,
                                 stream_id: stream_id
                               })
        ensure
          # Cleanup after delay
          Async do
            sleep(60) # Keep stream info for 1 minute
            cleanup_stream(stream_id)
          end
        end
      end

      def process_chunk(chunk, stream_id)
        case chunk
        when String
          {
            content: chunk,
            type: :text,
            timestamp: Time.current.iso8601,
            stream_id: stream_id
          }
        when Hash
          chunk.merge(
            timestamp: Time.current.iso8601,
            stream_id: stream_id
          )
        else
          {
            content: chunk.to_s,
            type: :text,
            timestamp: Time.current.iso8601,
            stream_id: stream_id
          }
        end
      end

      def update_stream_status(stream_id, status)
        @mutex.synchronize do
          stream = @active_streams[stream_id]
          if stream
            stream[:status] = status
            stream[:updated_at] = Time.current
          end
        end
      end

      def add_chunk_to_stream(stream_id, chunk)
        @mutex.synchronize do
          stream = @active_streams[stream_id]
          if stream
            stream[:chunks] << chunk
            stream[:total_chunks] += 1
          end
        end
      end

      def cleanup_stream(stream_id)
        @mutex.synchronize do
          @active_streams.delete(stream_id)
        end

        log_debug("Stream cleaned up", stream_id: stream_id)
      end

    end

  end

end
