# frozen_string_literal: true

require "async"
require "async/websocket"
require "json"

module RubyAIAgentsFactory
  module Streaming
    ##
    # WebSocket client for connecting to WebSocket servers
    #
    # Provides a WebSocket client for connecting to WebSocket servers
    # and handling real-time communication with AI agents.
    #
    class WebSocketClient
      include RubyAIAgentsFactory::Logging

      # @return [String] Server URL
      attr_reader :url

      # @return [Hash] Connection options
      attr_reader :options

      # @return [Boolean] Connection status
      attr_reader :connected

      ##
      # Initialize WebSocket client
      #
      # @param url [String] WebSocket server URL
      # @param options [Hash] Connection options
      #
      def initialize(url, **options)
        @url = url
        @options = options
        @connected = false
        @websocket = nil
        @message_handlers = {}
        @error_handlers = []
        @close_handlers = []
        @reconnect_attempts = 0
        @max_reconnect_attempts = options[:max_reconnect_attempts] || 5
        @reconnect_delay = options[:reconnect_delay] || 1.0
        @auto_reconnect = options[:auto_reconnect] || false
        @ping_interval = options[:ping_interval] || 30
        @ping_task = nil
        @mutex = Mutex.new
      end

      ##
      # Connect to WebSocket server
      #
      # @return [Boolean] True if connected successfully
      def connect
        return true if @connected

        begin
          log_info("Connecting to WebSocket server", url: @url)
          
          @websocket = Async::WebSocket::Client.new(@url)
          @connected = true
          @reconnect_attempts = 0
          
          # Start ping task
          start_ping_task
          
          # Start message handling
          start_message_handling
          
          log_info("Connected to WebSocket server", url: @url)
          true
        rescue StandardError => e
          log_error("Failed to connect to WebSocket server", url: @url, error: e)
          handle_connection_error(e)
          false
        end
      end

      ##
      # Disconnect from WebSocket server
      #
      def disconnect
        return unless @connected

        log_info("Disconnecting from WebSocket server", url: @url)
        
        @connected = false
        @ping_task&.stop
        @websocket&.close
        @websocket = nil
        
        log_info("Disconnected from WebSocket server", url: @url)
      end

      ##
      # Send message to server
      #
      # @param message [Hash] Message to send
      # @return [Boolean] True if sent successfully
      def send_message(message)
        return false unless @connected

        begin
          @websocket.send_message(JSON.generate(message))
          true
        rescue StandardError => e
          log_error("Failed to send message", error: e)
          false
        end
      end

      ##
      # Send ping to server
      #
      # @return [Boolean] True if sent successfully
      def ping
        return false unless @connected

        begin
          @websocket.ping
          true
        rescue StandardError => e
          log_error("Failed to send ping", error: e)
          false
        end
      end

      ##
      # Subscribe to channel
      #
      # @param channel [String] Channel name
      # @return [Boolean] True if subscribed successfully
      def subscribe(channel)
        send_message({
          type: "subscribe",
          channel: channel,
          timestamp: Time.current.iso8601
        })
      end

      ##
      # Unsubscribe from channel
      #
      # @param channel [String] Channel name
      # @return [Boolean] True if unsubscribed successfully
      def unsubscribe(channel)
        send_message({
          type: "unsubscribe",
          channel: channel,
          timestamp: Time.current.iso8601
        })
      end

      ##
      # Set message handler for specific message type
      #
      # @param type [String] Message type
      # @param block [Proc] Message handler
      def on_message(type = nil, &block)
        @mutex.synchronize do
          if type
            @message_handlers[type] = block
          else
            @message_handlers[:default] = block
          end
        end
      end

      ##
      # Set error handler
      #
      # @param block [Proc] Error handler
      def on_error(&block)
        @mutex.synchronize do
          @error_handlers << block
        end
      end

      ##
      # Set close handler
      #
      # @param block [Proc] Close handler
      def on_close(&block)
        @mutex.synchronize do
          @close_handlers << block
        end
      end

      ##
      # Set open handler
      #
      # @param block [Proc] Open handler
      def on_open(&block)
        @open_handler = block
      end

      ##
      # Check if connected
      #
      # @return [Boolean] True if connected
      def connected?
        @connected
      end

      ##
      # Get client statistics
      #
      # @return [Hash] Client statistics
      def stats
        {
          url: @url,
          connected: @connected,
          reconnect_attempts: @reconnect_attempts,
          max_reconnect_attempts: @max_reconnect_attempts,
          auto_reconnect: @auto_reconnect,
          ping_interval: @ping_interval
        }
      end

      ##
      # Start agent streaming session
      #
      # @param agent [Agent] Agent instance
      # @param message [String] Initial message
      # @param options [Hash] Streaming options
      # @yield [chunk] Yields each response chunk
      def start_agent_stream(agent, message, **options, &block)
        return unless @connected

        # Send streaming request
        send_message({
          type: "start_stream",
          agent_id: agent.id,
          message: message,
          options: options,
          timestamp: Time.current.iso8601
        })

        # Handle streaming responses
        on_message("stream_chunk") do |response|
          block&.call(response["chunk"])
        end

        on_message("stream_end") do |response|
          log_info("Stream ended", stream_id: response["stream_id"])
        end

        on_message("stream_error") do |response|
          log_error("Stream error", error: response["error"])
        end
      end

      ##
      # Stop agent streaming session
      #
      # @param stream_id [String] Stream ID to stop
      def stop_agent_stream(stream_id)
        send_message({
          type: "stop_stream",
          stream_id: stream_id,
          timestamp: Time.current.iso8601
        })
      end

      ##
      # Send agent message
      #
      # @param agent_id [String] Agent ID
      # @param message [String] Message content
      # @param options [Hash] Message options
      def send_agent_message(agent_id, message, **options)
        send_message({
          type: "agent_message",
          agent_id: agent_id,
          message: message,
          options: options,
          timestamp: Time.current.iso8601
        })
      end

      ##
      # Request agent handoff
      #
      # @param from_agent [String] Source agent ID
      # @param to_agent [String] Target agent ID
      # @param context [Hash] Handoff context
      def request_handoff(from_agent, to_agent, context = {})
        send_message({
          type: "handoff_request",
          from_agent: from_agent,
          to_agent: to_agent,
          context: context,
          timestamp: Time.current.iso8601
        })
      end

      private

      def start_ping_task
        @ping_task = Async do
          while @connected
            sleep(@ping_interval)
            break unless @connected
            
            unless ping
              log_warn("Ping failed, connection may be lost")
              handle_connection_loss
              break
            end
          end
        end
      end

      def start_message_handling
        Async do
          begin
            @websocket.each_message do |message|
              handle_message(message)
            end
          rescue StandardError => e
            log_error("Message handling error", error: e)
            handle_connection_error(e)
          end
        end
      end

      def handle_message(message)
        begin
          parsed_message = JSON.parse(message)
          message_type = parsed_message["type"]
          
          @mutex.synchronize do
            handler = @message_handlers[message_type] || @message_handlers[:default]
            handler&.call(parsed_message)
          end
        rescue JSON::ParserError => e
          log_error("Invalid JSON message received", error: e)
        rescue StandardError => e
          log_error("Message handling error", error: e)
          notify_error_handlers(e)
        end
      end

      def handle_connection_error(error)
        @connected = false
        @ping_task&.stop
        
        notify_error_handlers(error)
        
        if @auto_reconnect && @reconnect_attempts < @max_reconnect_attempts
          attempt_reconnect
        else
          notify_close_handlers
        end
      end

      def handle_connection_loss
        @connected = false
        @ping_task&.stop
        
        if @auto_reconnect && @reconnect_attempts < @max_reconnect_attempts
          attempt_reconnect
        else
          notify_close_handlers
        end
      end

      def attempt_reconnect
        @reconnect_attempts += 1
        delay = @reconnect_delay * @reconnect_attempts
        
        log_info("Attempting to reconnect", attempt: @reconnect_attempts, delay: delay)
        
        Async do
          sleep(delay)
          connect
        end
      end

      def notify_error_handlers(error)
        @mutex.synchronize do
          @error_handlers.each { |handler| handler.call(error) }
        end
      end

      def notify_close_handlers
        @mutex.synchronize do
          @close_handlers.each { |handler| handler.call }
        end
      end
    end
  end
end