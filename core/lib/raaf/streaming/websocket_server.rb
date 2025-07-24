# frozen_string_literal: true

require "async"
require "async/websocket"
require "async/http/endpoint"
require "json"
require "securerandom"

module RAAF

  module Streaming

    ##
    # WebSocket server for real-time communication
    #
    # Provides a WebSocket server for real-time bidirectional communication
    # between AI agents and clients. Supports connection management, message
    # broadcasting, and channel-based communication.
    #
    class WebSocketServer

      include RAAF::Logging

      # @return [Integer] Server port
      attr_reader :port

      # @return [String] Server host
      attr_reader :host

      # @return [Integer] Maximum connections
      attr_reader :max_connections

      # @return [Integer] Heartbeat interval in seconds
      attr_reader :heartbeat_interval

      # @return [Integer] Connection timeout in seconds
      attr_reader :timeout

      ##
      # Initialize WebSocket server
      #
      # @param port [Integer] Server port
      # @param host [String] Server host
      # @param max_connections [Integer] Maximum connections
      # @param heartbeat_interval [Integer] Heartbeat interval in seconds
      # @param timeout [Integer] Connection timeout in seconds
      #
      def initialize(port: 8080, host: "localhost", max_connections: 1000, heartbeat_interval: 30, timeout: 60)
        @port = port
        @host = host
        @max_connections = max_connections
        @heartbeat_interval = heartbeat_interval
        @timeout = timeout
        @clients = {}
        @channels = {}
        @running = false
        @server_task = nil
        @heartbeat_task = nil
        @mutex = Mutex.new
      end

      ##
      # Start the WebSocket server
      #
      def start
        return if @running

        @running = true
        log_info("Starting WebSocket server", port: @port, host: @host)

        @server_task = Async do
          endpoint = Async::HTTP::Endpoint.parse("ws://#{@host}:#{@port}")

          Async::WebSocket::Server.new(endpoint) do |websocket|
            handle_connection(websocket)
          end.run
        end

        @heartbeat_task = Async do
          heartbeat_loop
        end

        self
      end

      ##
      # Stop the WebSocket server
      #
      def stop
        return unless @running

        @running = false
        log_info("Stopping WebSocket server")

        @server_task&.stop
        @heartbeat_task&.stop

        # Close all client connections
        @mutex.synchronize do
          @clients.each_value(&:close)
          @clients.clear
          @channels.clear
        end

        self
      end

      ##
      # Check if server is running
      #
      # @return [Boolean] True if server is running
      def running?
        @running
      end

      ##
      # Get number of connected clients
      #
      # @return [Integer] Number of connected clients
      def connection_count
        @mutex.synchronize { @clients.size }
      end

      ##
      # Get connected client IDs
      #
      # @return [Array<String>] Array of client IDs
      def client_ids
        @mutex.synchronize { @clients.keys }
      end

      ##
      # Send message to specific client
      #
      # @param client_id [String] Client ID
      # @param message [Hash] Message to send
      # @return [Boolean] True if message was sent successfully
      def send_to_client(client_id, message)
        @mutex.synchronize do
          client = @clients[client_id]
          return false unless client

          begin
            client.send_message(message)
            true
          rescue StandardError => e
            log_error("Failed to send message to client", client_id: client_id, error: e)
            false
          end
        end
      end

      ##
      # Broadcast message to all clients
      #
      # @param message [Hash] Message to broadcast
      # @param channel [String, nil] Channel to broadcast to (nil for all)
      def broadcast(message, channel: nil)
        @mutex.synchronize do
          clients = if channel
                      @channels[channel] || []
                    else
                      @clients.values
                    end

          clients.each do |client|
            client.send_message(message)
          rescue StandardError => e
            log_error("Failed to broadcast message", client_id: client.id, error: e)
          end
        end
      end

      ##
      # Subscribe client to channel
      #
      # @param client_id [String] Client ID
      # @param channel [String] Channel name
      def subscribe_to_channel(client_id, channel)
        @mutex.synchronize do
          client = @clients[client_id]
          return false unless client

          @channels[channel] ||= []
          @channels[channel] << client unless @channels[channel].include?(client)
          client.channels << channel unless client.channels.include?(channel)

          log_debug("Client subscribed to channel", client_id: client_id, channel: channel)
          true
        end
      end

      ##
      # Unsubscribe client from channel
      #
      # @param client_id [String] Client ID
      # @param channel [String] Channel name
      def unsubscribe_from_channel(client_id, channel)
        @mutex.synchronize do
          client = @clients[client_id]
          return false unless client

          @channels[channel]&.delete(client)
          @channels.delete(channel) if @channels[channel] && @channels[channel].empty?
          client.channels.delete(channel)

          log_debug("Client unsubscribed from channel", client_id: client_id, channel: channel)
          true
        end
      end

      ##
      # Get server statistics
      #
      # @return [Hash] Server statistics
      def stats
        @mutex.synchronize do
          {
            running: @running,
            connections: @clients.size,
            channels: @channels.size,
            max_connections: @max_connections,
            clients_by_channel: @channels.transform_values(&:size)
          }
        end
      end

      ##
      # Set connection event handler
      #
      # @yield [client] Called when a client connects
      def on_connection(&block)
        @connection_handler = block
      end

      ##
      # Set disconnection event handler
      #
      # @yield [client] Called when a client disconnects
      def on_disconnection(&block)
        @disconnection_handler = block
      end

      ##
      # Set message event handler
      #
      # @yield [client, message] Called when a message is received
      def on_message(&block)
        @message_handler = block
      end

      ##
      # Set error event handler
      #
      # @yield [client, error] Called when an error occurs
      def on_error(&block)
        @error_handler = block
      end

      private

      def handle_connection(websocket)
        return if @clients.size >= @max_connections

        client = WebSocketClient.new(websocket, generate_client_id)

        @mutex.synchronize do
          @clients[client.id] = client
        end

        log_info("Client connected", client_id: client.id)
        @connection_handler&.call(client)

        begin
          websocket.each_message do |message|
            handle_message(client, message)
          end
        rescue StandardError => e
          log_error("WebSocket error", client_id: client.id, error: e)
          @error_handler&.call(client, e)
        ensure
          handle_disconnection(client)
        end
      end

      def handle_message(client, message)
        parsed_message = JSON.parse(message)
        @message_handler&.call(client, parsed_message)
      rescue JSON::ParserError => e
        log_error("Invalid JSON message", client_id: client.id, error: e)
        client.send_error("Invalid JSON format")
      rescue StandardError => e
        log_error("Message handling error", client_id: client.id, error: e)
        @error_handler&.call(client, e)
      end

      def handle_disconnection(client)
        @mutex.synchronize do
          @clients.delete(client.id)

          # Remove from all channels
          @channels.each_value { |clients| clients.delete(client) }
          @channels.reject! { |_, clients| clients.empty? }
        end

        log_info("Client disconnected", client_id: client.id)
        @disconnection_handler&.call(client)
      end

      def heartbeat_loop
        while @running
          sleep(@heartbeat_interval)
          next unless @running

          @mutex.synchronize do
            @clients.each_value do |client|
              client.ping
            rescue StandardError => e
              log_error("Heartbeat failed", client_id: client.id, error: e)
            end
          end
        end
      end

      def generate_client_id
        SecureRandom.hex(16)
      end

    end

    ##
    # WebSocket client wrapper
    #
    # Wraps a WebSocket connection with additional functionality
    # for message handling, channel management, and client state.
    #
    class WebSocketClient

      # @return [String] Client ID
      attr_reader :id

      # @return [Array<String>] Subscribed channels
      attr_reader :channels

      # @return [Time] Connection time
      attr_reader :connected_at

      ##
      # Initialize WebSocket client
      #
      # @param websocket [Async::WebSocket] WebSocket connection
      # @param id [String] Client ID
      #
      def initialize(websocket, id)
        @websocket = websocket
        @id = id
        @channels = []
        @connected_at = Time.now
        @last_ping = Time.now
        @metadata = {}
      end

      ##
      # Send message to client
      #
      # @param message [Hash] Message to send
      def send_message(message)
        @websocket.send_message(JSON.generate(message))
      end

      ##
      # Send error message to client
      #
      # @param error [String] Error message
      def send_error(error)
        send_message({
                       type: "error",
                       message: error,
                       timestamp: Time.now.iso8601
                     })
      end

      ##
      # Send ping to client
      #
      def ping
        @websocket.ping
        @last_ping = Time.now
      end

      ##
      # Close client connection
      #
      def close
        @websocket.close
      end

      ##
      # Check if client is alive
      #
      # @return [Boolean] True if client is alive
      def alive?
        Time.now - @last_ping < 60
      end

      ##
      # Get client metadata
      #
      # @return [Hash] Client metadata
      attr_reader :metadata

      ##
      # Set client metadata
      #
      # @param key [String] Metadata key
      # @param value [Object] Metadata value
      def set_metadata(key, value)
        @metadata[key] = value
      end

      ##
      # Get client statistics
      #
      # @return [Hash] Client statistics
      def stats
        {
          id: @id,
          connected_at: @connected_at,
          channels: @channels.size,
          alive: alive?,
          last_ping: @last_ping,
          metadata: @metadata
        }
      end

    end

  end

end
