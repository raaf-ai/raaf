# frozen_string_literal: true

require_relative "raaf/streaming/version"
require_relative "raaf/streaming/stream_processor"
require_relative "raaf/streaming/websocket_server"
require_relative "raaf/streaming/websocket_client"
require_relative "raaf/streaming/async_runner"
require_relative "raaf/streaming/background_processor"
require_relative "raaf/streaming/event_emitter"
require_relative "raaf/streaming/message_queue"
require_relative "raaf/streaming/real_time_chat"
require_relative "raaf/streaming/streaming_provider"

module RAAF
  ##
  # Real-time streaming and async processing for Ruby AI Agents Factory
  #
  # The Streaming module provides comprehensive real-time capabilities for AI agents
  # including streaming responses, WebSocket communication, async processing, and
  # background job handling. It enables building responsive, real-time AI applications
  # with support for live conversations, streaming responses, and event-driven
  # architectures.
  #
  # Key features:
  # - **Streaming Responses** - Real-time streaming of AI agent responses
  # - **WebSocket Support** - Bidirectional real-time communication
  # - **Async Processing** - Non-blocking agent operations
  # - **Background Jobs** - Queue-based background processing
  # - **Event Emitters** - Publish-subscribe event system
  # - **Message Queues** - Reliable message handling
  # - **Real-time Chat** - Live chat interface components
  # - **Connection Management** - Scalable connection handling
  #
  # @example Basic streaming setup
  #   require 'raaf-streaming'
  #   
  #   # Create streaming provider
  #   streaming_provider = RAAF::Streaming::StreamingProvider.new
  #   
  #   # Create agent with streaming
  #   agent = RAAF::Agent.new(
  #     name: "StreamingAgent",
  #     instructions: "You are a helpful assistant",
  #     provider: streaming_provider
  #   )
  #   
  #   # Stream response
  #   agent.stream("Tell me a story") do |chunk|
  #     puts chunk[:content]
  #   end
  #
  # @example WebSocket server
  #   require 'raaf-streaming'
  #   
  #   # Create WebSocket server
  #   server = RAAF::Streaming::WebSocketServer.new(port: 8080)
  #   
  #   # Handle connections
  #   server.on_connection do |client|
  #     puts "Client connected: #{client.id}"
  #     
  #     client.on_message do |message|
  #       # Process message with agent
  #       response = agent.run(message[:content])
  #       client.send_message({
  #         type: "response",
  #         content: response.messages.last[:content]
  #       })
  #     end
  #   end
  #   
  #   # Start server
  #   server.start
  #
  # @example Async processing
  #   require 'raaf-streaming'
  #   
  #   # Create async runner
  #   async_runner = RAAF::Streaming::AsyncRunner.new
  #   
  #   # Process messages asynchronously
  #   async_runner.process_async(agent, "Hello") do |result|
  #     puts "Async result: #{result.messages.last[:content]}"
  #   end
  #
  # @example Background processing
  #   require 'raaf-streaming'
  #   
  #   # Create background processor
  #   processor = RAAF::Streaming::BackgroundProcessor.new
  #   
  #   # Queue background job
  #   processor.enqueue_job(:process_message, {
  #     agent_id: agent.id,
  #     message: "Process this in background",
  #     priority: :high
  #   })
  #
  # @example Real-time chat
  #   require 'raaf-streaming'
  #   
  #   # Create real-time chat
  #   chat = RAAF::Streaming::RealTimeChat.new(
  #     agent: agent,
  #     websocket_port: 8080
  #   )
  #   
  #   # Start chat server
  #   chat.start
  #
  # @since 1.0.0
  module Streaming
    # Default configuration
    DEFAULT_CONFIG = {
      # WebSocket settings
      websocket: {
        port: 8080,
        host: "localhost",
        max_connections: 1000,
        heartbeat_interval: 30,
        timeout: 60
      },
      
      # Streaming settings
      streaming: {
        chunk_size: 1024,
        buffer_size: 4096,
        timeout: 30,
        retry_count: 3
      },
      
      # Async settings
      async: {
        pool_size: 10,
        queue_size: 100,
        timeout: 60
      },
      
      # Background processing
      background: {
        redis_url: "redis://localhost:6379",
        workers: 5,
        retry_count: 3,
        retry_delay: 1.0
      },
      
      # Event system
      events: {
        max_listeners: 10,
        emit_timeout: 5.0,
        enable_wildcards: true
      },
      
      # Message queue
      message_queue: {
        redis_url: "redis://localhost:6379",
        max_size: 10000,
        batch_size: 100
      }
    }.freeze

    class << self
      # @return [Hash] Current configuration
      attr_accessor :config

      ##
      # Configure streaming settings
      #
      # @param options [Hash] Configuration options
      # @yield [config] Configuration block
      #
      # @example Configure streaming
      #   RAAF::Streaming.configure do |config|
      #     config.websocket.port = 9090
      #     config.streaming.chunk_size = 512
      #     config.async.pool_size = 20
      #   end
      #
      def configure
        @config ||= deep_dup(DEFAULT_CONFIG)
        yield @config if block_given?
        @config
      end

      ##
      # Get current configuration
      #
      # @return [Hash] Current configuration
      def config
        @config ||= deep_dup(DEFAULT_CONFIG)
      end

      ##
      # Create a WebSocket server
      #
      # @param options [Hash] Server options
      # @return [WebSocketServer] WebSocket server instance
      def create_websocket_server(**options)
        WebSocketServer.new(**config[:websocket].merge(options))
      end

      ##
      # Create a streaming provider
      #
      # @param options [Hash] Provider options
      # @return [StreamingProvider] Streaming provider instance
      def create_streaming_provider(**options)
        StreamingProvider.new(**config[:streaming].merge(options))
      end

      ##
      # Create an async runner
      #
      # @param options [Hash] Runner options
      # @return [AsyncRunner] Async runner instance
      def create_async_runner(**options)
        AsyncRunner.new(**config[:async].merge(options))
      end

      ##
      # Create a background processor
      #
      # @param options [Hash] Processor options
      # @return [BackgroundProcessor] Background processor instance
      def create_background_processor(**options)
        BackgroundProcessor.new(**config[:background].merge(options))
      end

      ##
      # Create an event emitter
      #
      # @param options [Hash] Emitter options
      # @return [EventEmitter] Event emitter instance
      def create_event_emitter(**options)
        EventEmitter.new(**config[:events].merge(options))
      end

      ##
      # Create a message queue
      #
      # @param options [Hash] Queue options
      # @return [MessageQueue] Message queue instance
      def create_message_queue(**options)
        MessageQueue.new(**config[:message_queue].merge(options))
      end

      ##
      # Create a real-time chat
      #
      # @param agent [Agent] Agent instance
      # @param options [Hash] Chat options
      # @return [RealTimeChat] Real-time chat instance
      def create_real_time_chat(agent, **options)
        RealTimeChat.new(agent: agent, **options)
      end

      ##
      # Start streaming services
      #
      # Starts all configured streaming services including WebSocket servers,
      # background processors, and message queues.
      #
      def start_services
        @services = []
        
        # Start WebSocket server if configured
        if config[:websocket][:enabled]
          websocket_server = create_websocket_server
          websocket_server.start
          @services << websocket_server
        end
        
        # Start background processor if configured
        if config[:background][:enabled]
          background_processor = create_background_processor
          background_processor.start
          @services << background_processor
        end
        
        # Start message queue if configured
        if config[:message_queue][:enabled]
          message_queue = create_message_queue
          message_queue.start
          @services << message_queue
        end
        
        @services
      end

      ##
      # Stop streaming services
      #
      # Stops all running streaming services gracefully.
      #
      def stop_services
        @services&.each(&:stop)
        @services&.clear
      end

      ##
      # Get streaming statistics
      #
      # @return [Hash] Statistics from all streaming services
      def stats
        {
          websocket_connections: websocket_connection_count,
          async_jobs: async_job_count,
          background_jobs: background_job_count,
          message_queue_size: message_queue_size,
          active_streams: active_stream_count
        }
      end

      ##
      # Enable streaming for an agent
      #
      # @param agent [Agent] Agent to enable streaming for
      # @param options [Hash] Streaming options
      # @return [Agent] Agent with streaming enabled
      def enable_streaming(agent, **options)
        streaming_provider = create_streaming_provider(**options)
        agent.provider = streaming_provider
        agent
      end

      ##
      # Create a streaming session
      #
      # @param agent [Agent] Agent instance
      # @param options [Hash] Session options
      # @return [StreamingSession] Streaming session instance
      def create_streaming_session(agent, **options)
        StreamingSession.new(agent: agent, **options)
      end

      ##
      # Broadcast message to all connected clients
      #
      # @param message [Hash] Message to broadcast
      # @param channel [String] Channel to broadcast to
      def broadcast(message, channel: nil)
        websocket_server = @services&.find { |s| s.is_a?(WebSocketServer) }
        websocket_server&.broadcast(message, channel: channel)
      end

      ##
      # Send message to specific client
      #
      # @param client_id [String] Client ID
      # @param message [Hash] Message to send
      def send_to_client(client_id, message)
        websocket_server = @services&.find { |s| s.is_a?(WebSocketServer) }
        websocket_server&.send_to_client(client_id, message)
      end

      ##
      # Subscribe to streaming events
      #
      # @param event [String] Event name
      # @param block [Proc] Event handler
      def on(event, &block)
        event_emitter = @event_emitter ||= create_event_emitter
        event_emitter.on(event, &block)
      end

      ##
      # Emit streaming event
      #
      # @param event [String] Event name
      # @param data [Hash] Event data
      def emit(event, data = {})
        event_emitter = @event_emitter ||= create_event_emitter
        event_emitter.emit(event, data)
      end

      private

      def websocket_connection_count
        websocket_server = @services&.find { |s| s.is_a?(WebSocketServer) }
        websocket_server&.connection_count || 0
      end

      def async_job_count
        async_runner = @services&.find { |s| s.is_a?(AsyncRunner) }
        async_runner&.job_count || 0
      end

      def background_job_count
        background_processor = @services&.find { |s| s.is_a?(BackgroundProcessor) }
        background_processor&.job_count || 0
      end

      def message_queue_size
        message_queue = @services&.find { |s| s.is_a?(MessageQueue) }
        message_queue&.size || 0
      end

      def active_stream_count
        # Count active streaming sessions
        StreamingSession.active_sessions.size
      end

      def deep_dup(hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key] = value.is_a?(Hash) ? deep_dup(value) : value.dup
        end
      rescue TypeError
        hash
      end
    end
  end
end