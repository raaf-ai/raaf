# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RAAF
  module Streaming
    ##
    # Streaming provider for AI agents
    #
    # Provides a streaming-enabled AI provider that wraps existing providers
    # with streaming capabilities. Supports both native streaming and
    # simulated streaming for providers that don't support it natively.
    #
    class StreamingProvider
      include RAAF::Logging

      # @return [Object] Underlying provider
      attr_reader :provider

      # @return [Hash] Streaming configuration
      attr_reader :config

      ##
      # Initialize streaming provider
      #
      # @param provider [Object] Underlying provider
      # @param config [Hash] Streaming configuration
      #
      def initialize(provider: nil, **config)
        @provider = provider || create_default_provider
        @config = {
          chunk_size: 1024,
          buffer_size: 4096,
          timeout: 30,
          retry_count: 3,
          enable_simulation: true,
          simulation_delay: 0.1
        }.merge(config)
        @stream_processor = StreamProcessor.new(**@config)
      end

      ##
      # Generate streaming response
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param options [Hash] Generation options
      # @yield [chunk] Yields each response chunk
      # @return [Result] Final result
      #
      def stream(messages, **options, &block)
        if supports_native_streaming?
          native_stream(messages, **options, &block)
        else
          simulated_stream(messages, **options, &block)
        end
      end

      ##
      # Check if provider supports streaming
      #
      # @return [Boolean] True if streaming is supported
      def supports_streaming?
        supports_native_streaming? || @config[:enable_simulation]
      end

      ##
      # Generate non-streaming response
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param options [Hash] Generation options
      # @return [Result] Response result
      #
      def generate(messages, **options)
        @provider.generate(messages, **options)
      end

      ##
      # Create streaming session
      #
      # @param agent [Agent] Agent instance
      # @param options [Hash] Session options
      # @return [StreamingSession] Streaming session
      #
      def create_session(agent, **options)
        StreamingSession.new(provider: self, agent: agent, **options)
      end

      ##
      # Get provider information
      #
      # @return [Hash] Provider information
      def info
        {
          name: self.class.name,
          supports_native_streaming: supports_native_streaming?,
          supports_simulation: @config[:enable_simulation],
          underlying_provider: @provider.class.name,
          config: @config
        }
      end

      ##
      # Get provider statistics
      #
      # @return [Hash] Provider statistics
      def stats
        {
          total_requests: @total_requests || 0,
          streaming_requests: @streaming_requests || 0,
          simulation_requests: @simulation_requests || 0,
          average_response_time: @average_response_time || 0,
          last_request_at: @last_request_at
        }
      end

      private

      def create_default_provider
        # Create a default ResponsesProvider
        RAAF::Models::ResponsesProvider.new
      end

      def supports_native_streaming?
        @provider.respond_to?(:stream) && @provider.method(:stream).arity != 0
      end

      def native_stream(messages, **options, &block)
        @streaming_requests = (@streaming_requests || 0) + 1
        @total_requests = (@total_requests || 0) + 1
        @last_request_at = Time.current
        
        start_time = Time.current
        
        begin
          result = @provider.stream(messages, **options) do |chunk|
            processed_chunk = process_chunk(chunk)
            block&.call(processed_chunk)
          end
          
          update_stats(start_time)
          result
        rescue StandardError => e
          log_error("Native streaming error", error: e)
          raise
        end
      end

      def simulated_stream(messages, **options, &block)
        @simulation_requests = (@simulation_requests || 0) + 1
        @total_requests = (@total_requests || 0) + 1
        @last_request_at = Time.current
        
        start_time = Time.current
        
        begin
          # Generate complete response
          result = @provider.generate(messages, **options)
          content = result.messages.last[:content]
          
          # Stream in chunks
          StreamProcessor.chunk_response(content, chunk_size: @config[:chunk_size]) do |chunk|
            processed_chunk = {
              content: chunk,
              type: :text,
              timestamp: Time.current.iso8601,
              simulated: true
            }
            
            block&.call(processed_chunk)
            
            # Add delay for realistic streaming
            sleep(@config[:simulation_delay]) if @config[:simulation_delay] > 0
          end
          
          update_stats(start_time)
          result
        rescue StandardError => e
          log_error("Simulated streaming error", error: e)
          raise
        end
      end

      def process_chunk(chunk)
        case chunk
        when String
          {
            content: chunk,
            type: :text,
            timestamp: Time.current.iso8601,
            simulated: false
          }
        when Hash
          chunk.merge(
            timestamp: Time.current.iso8601,
            simulated: false
          )
        else
          {
            content: chunk.to_s,
            type: :text,
            timestamp: Time.current.iso8601,
            simulated: false
          }
        end
      end

      def update_stats(start_time)
        duration = Time.current - start_time
        @total_response_time = (@total_response_time || 0) + duration
        @average_response_time = @total_response_time / @total_requests
      end
    end

    ##
    # Streaming session for agents
    #
    # Provides a streaming session that maintains conversation context
    # and handles streaming responses with proper lifecycle management.
    #
    class StreamingSession
      include RAAF::Logging

      # @return [StreamingProvider] Streaming provider
      attr_reader :provider

      # @return [Agent] Agent instance
      attr_reader :agent

      # @return [String] Session ID
      attr_reader :session_id

      # @return [Array<Hash>] Conversation messages
      attr_reader :messages

      ##
      # Initialize streaming session
      #
      # @param provider [StreamingProvider] Streaming provider
      # @param agent [Agent] Agent instance
      # @param session_id [String] Session ID
      # @param options [Hash] Session options
      #
      def initialize(provider:, agent:, session_id: nil, **options)
        @provider = provider
        @agent = agent
        @session_id = session_id || SecureRandom.hex(16)
        @messages = []
        @options = options
        @active = true
        @stream_handlers = {}
        @mutex = Mutex.new
        
        log_info("Streaming session created", session_id: @session_id, agent: @agent.name)
      end

      ##
      # Send message and stream response
      #
      # @param content [String] Message content
      # @param options [Hash] Message options
      # @yield [chunk] Yields each response chunk
      # @return [Result] Final result
      #
      def send_message(content, **options, &block)
        return unless @active
        
        # Add user message
        user_message = {
          role: "user",
          content: content,
          timestamp: Time.current.iso8601
        }
        
        @mutex.synchronize do
          @messages << user_message
        end
        
        # Prepare messages for provider
        provider_messages = @messages.map { |msg| msg.slice(:role, :content) }
        
        # Stream response
        result = @provider.stream(provider_messages, **options) do |chunk|
          @stream_handlers[:chunk]&.call(chunk)
          block&.call(chunk)
        end
        
        # Add assistant response
        assistant_message = {
          role: "assistant",
          content: result.messages.last[:content],
          timestamp: Time.current.iso8601,
          agent: @agent.name
        }
        
        @mutex.synchronize do
          @messages << assistant_message
        end
        
        result
      end

      ##
      # Get conversation history
      #
      # @param limit [Integer] Number of messages to retrieve
      # @return [Array<Hash>] Conversation messages
      #
      def history(limit = nil)
        @mutex.synchronize do
          limit ? @messages.last(limit) : @messages.dup
        end
      end

      ##
      # Clear conversation history
      #
      def clear_history
        @mutex.synchronize do
          @messages.clear
        end
        
        log_info("Conversation history cleared", session_id: @session_id)
      end

      ##
      # End streaming session
      #
      def end_session
        @active = false
        log_info("Streaming session ended", session_id: @session_id)
      end

      ##
      # Check if session is active
      #
      # @return [Boolean] True if active
      def active?
        @active
      end

      ##
      # Set stream event handler
      #
      # @param event [String] Event name
      # @param block [Proc] Event handler
      def on(event, &block)
        @stream_handlers[event.to_sym] = block
      end

      ##
      # Get session statistics
      #
      # @return [Hash] Session statistics
      def stats
        {
          session_id: @session_id,
          agent: @agent.name,
          message_count: @messages.size,
          active: @active,
          created_at: @created_at,
          provider: @provider.class.name
        }
      end

      ##
      # Export session data
      #
      # @return [Hash] Session data
      def export
        {
          session_id: @session_id,
          agent: @agent.name,
          messages: history,
          created_at: @created_at,
          options: @options
        }
      end

      ##
      # Import session data
      #
      # @param data [Hash] Session data
      def import(data)
        @mutex.synchronize do
          @messages = data[:messages] || []
        end
        
        log_info("Session data imported", session_id: @session_id, messages: @messages.size)
      end

      ##
      # Fork session with new agent
      #
      # @param new_agent [Agent] New agent
      # @return [StreamingSession] New session
      def fork(new_agent)
        new_session = self.class.new(
          provider: @provider,
          agent: new_agent,
          **@options
        )
        
        # Copy message history
        new_session.import(export)
        
        log_info("Session forked", 
                original_session: @session_id, 
                new_session: new_session.session_id,
                new_agent: new_agent.name)
        
        new_session
      end

      ##
      # Merge with another session
      #
      # @param other_session [StreamingSession] Other session
      def merge(other_session)
        @mutex.synchronize do
          @messages.concat(other_session.history)
          @messages.sort_by! { |msg| msg[:timestamp] }
        end
        
        log_info("Sessions merged", 
                session_id: @session_id, 
                other_session: other_session.session_id)
      end

      ##
      # Create checkpoint
      #
      # @return [Hash] Checkpoint data
      def checkpoint
        {
          session_id: @session_id,
          messages: history,
          timestamp: Time.current.iso8601
        }
      end

      ##
      # Restore from checkpoint
      #
      # @param checkpoint [Hash] Checkpoint data
      def restore(checkpoint)
        @mutex.synchronize do
          @messages = checkpoint[:messages] || []
        end
        
        log_info("Session restored from checkpoint", 
                session_id: @session_id, 
                checkpoint_time: checkpoint[:timestamp])
      end
    end
  end
end