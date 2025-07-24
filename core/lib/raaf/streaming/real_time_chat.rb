# frozen_string_literal: true

require "json"
require "securerandom"

module RAAF

  module Streaming

    ##
    # Real-time chat interface for AI agents
    #
    # Provides a complete real-time chat solution combining WebSocket servers,
    # streaming responses, and agent communication. Supports multi-user chat,
    # agent handoffs, and message persistence.
    #
    class RealTimeChat

      include RAAF::Logging

      # @return [Agent] Primary agent
      attr_reader :agent

      # @return [WebSocketServer] WebSocket server
      attr_reader :websocket_server

      # @return [StreamProcessor] Stream processor
      attr_reader :stream_processor

      # @return [Hash] Chat configuration
      attr_reader :config

      ##
      # Initialize real-time chat
      #
      # @param agent [Agent] Primary agent
      # @param websocket_port [Integer] WebSocket port
      # @param websocket_host [String] WebSocket host
      # @param config [Hash] Chat configuration
      #
      def initialize(agent:, websocket_port: 8080, websocket_host: "localhost", **config)
        @agent = agent
        @config = config
        @websocket_server = WebSocketServer.new(
          port: websocket_port,
          host: websocket_host,
          **config.slice(:max_connections, :heartbeat_interval, :timeout)
        )
        @stream_processor = StreamProcessor.new(**config.slice(:chunk_size, :buffer_size))
        @chat_sessions = {}
        @active_streams = {}
        @message_history = {}
        @agents = { agent.name => agent }
        @mutex = Mutex.new

        setup_websocket_handlers
      end

      ##
      # Start chat server
      #
      def start
        log_info("Starting real-time chat server", port: @websocket_server.port)
        @websocket_server.start
        self
      end

      ##
      # Stop chat server
      #
      def stop
        log_info("Stopping real-time chat server")
        @websocket_server.stop
        self
      end

      ##
      # Add agent to chat
      #
      # @param agent [Agent] Agent to add
      def add_agent(agent)
        @mutex.synchronize do
          @agents[agent.name] = agent
        end

        log_info("Agent added to chat", agent_name: agent.name)
      end

      ##
      # Remove agent from chat
      #
      # @param agent_name [String] Agent name
      def remove_agent(agent_name)
        @mutex.synchronize do
          @agents.delete(agent_name)
        end

        log_info("Agent removed from chat", agent_name: agent_name)
      end

      ##
      # Get chat statistics
      #
      # @return [Hash] Chat statistics
      def stats
        {
          connected_clients: @websocket_server.connection_count,
          active_sessions: @chat_sessions.size,
          active_streams: @active_streams.size,
          available_agents: @agents.size,
          total_messages: @message_history.values.sum(&:size)
        }
      end

      ##
      # Get chat session
      #
      # @param session_id [String] Session ID
      # @return [Hash, nil] Chat session or nil if not found
      def get_session(session_id)
        @mutex.synchronize do
          @chat_sessions[session_id]
        end
      end

      ##
      # Get message history
      #
      # @param session_id [String] Session ID
      # @param limit [Integer] Number of messages to retrieve
      # @return [Array<Hash>] Message history
      def get_message_history(session_id, limit = 100)
        @mutex.synchronize do
          (@message_history[session_id] || []).last(limit)
        end
      end

      ##
      # Broadcast message to all clients
      #
      # @param message [Hash] Message to broadcast
      # @param channel [String] Channel to broadcast to
      def broadcast(message, channel: nil)
        @websocket_server.broadcast(message, channel: channel)
      end

      ##
      # Send message to specific client
      #
      # @param client_id [String] Client ID
      # @param message [Hash] Message to send
      def send_to_client(client_id, message)
        @websocket_server.send_to_client(client_id, message)
      end

      ##
      # Create chat room
      #
      # @param room_name [String] Room name
      # @param options [Hash] Room options
      # @return [String] Room ID
      def create_room(room_name, **options)
        room_id = SecureRandom.hex(16)

        @mutex.synchronize do
          @chat_sessions[room_id] = {
            id: room_id,
            name: room_name,
            type: :room,
            created_at: Time.now,
            participants: [],
            current_agent: @agent.name,
            options: options
          }
        end

        log_info("Chat room created", room_id: room_id, room_name: room_name)
        room_id
      end

      ##
      # Join chat room
      #
      # @param client_id [String] Client ID
      # @param room_id [String] Room ID
      def join_room(client_id, room_id)
        @mutex.synchronize do
          session = @chat_sessions[room_id]
          return false unless session

          session[:participants] << client_id unless session[:participants].include?(client_id)
        end

        @websocket_server.subscribe_to_channel(client_id, room_id)

        # Notify room participants
        @websocket_server.broadcast({
                                      type: "user_joined",
                                      room_id: room_id,
                                      user_id: client_id,
                                      timestamp: Time.now.iso8601
                                    }, channel: room_id)

        log_info("Client joined room", client_id: client_id, room_id: room_id)
        true
      end

      ##
      # Leave chat room
      #
      # @param client_id [String] Client ID
      # @param room_id [String] Room ID
      def leave_room(client_id, room_id)
        @mutex.synchronize do
          session = @chat_sessions[room_id]
          return false unless session

          session[:participants].delete(client_id)
        end

        @websocket_server.unsubscribe_from_channel(client_id, room_id)

        # Notify room participants
        @websocket_server.broadcast({
                                      type: "user_left",
                                      room_id: room_id,
                                      user_id: client_id,
                                      timestamp: Time.now.iso8601
                                    }, channel: room_id)

        log_info("Client left room", client_id: client_id, room_id: room_id)
        true
      end

      ##
      # Request agent handoff
      #
      # @param session_id [String] Session ID
      # @param target_agent [String] Target agent name
      # @param context [Hash] Handoff context
      def request_handoff(session_id, target_agent, context = {})
        @mutex.synchronize do
          session = @chat_sessions[session_id]
          return false unless session

          agent = @agents[target_agent]
          return false unless agent

          session[:current_agent] = target_agent
          session[:handoff_context] = context
          session[:handoff_at] = Time.now
        end

        log_info("Agent handoff requested",
                 session_id: session_id, target_agent: target_agent)
        true
      end

      private

      def setup_websocket_handlers
        @websocket_server.on_connection do |client|
          handle_client_connection(client)
        end

        @websocket_server.on_disconnection do |client|
          handle_client_disconnection(client)
        end

        @websocket_server.on_message do |client, message|
          handle_client_message(client, message)
        end

        @websocket_server.on_error do |client, error|
          handle_client_error(client, error)
        end
      end

      def handle_client_connection(client)
        session_id = SecureRandom.hex(16)

        @mutex.synchronize do
          @chat_sessions[session_id] = {
            id: session_id,
            client_id: client.id,
            type: :chat,
            created_at: Time.now,
            current_agent: @agent.name,
            message_count: 0
          }

          @message_history[session_id] = []
        end

        client.set_metadata("session_id", session_id)

        # Send welcome message
        client.send_message({
                              type: "welcome",
                              session_id: session_id,
                              agent: @agent.name,
                              timestamp: Time.now.iso8601
                            })

        log_info("Client connected to chat", client_id: client.id, session_id: session_id)
      end

      def handle_client_disconnection(client)
        session_id = client.metadata["session_id"]

        @mutex.synchronize do
          @chat_sessions.delete(session_id)
          @message_history.delete(session_id)
          @active_streams.delete(session_id)
        end

        log_info("Client disconnected from chat", client_id: client.id, session_id: session_id)
      end

      def handle_client_message(client, message)
        session_id = client.metadata["session_id"]
        message_type = message["type"]

        case message_type
        when "chat_message"
          handle_chat_message(client, session_id, message)
        when "start_stream"
          handle_start_stream(client, session_id, message)
        when "stop_stream"
          handle_stop_stream(client, session_id, message)
        when "handoff_request"
          handle_handoff_request(client, session_id, message)
        when "join_room"
          handle_join_room(client, message)
        when "leave_room"
          handle_leave_room(client, message)
        when "get_history"
          handle_get_history(client, session_id, message)
        else
          log_warn("Unknown message type", type: message_type, client_id: client.id)
        end
      end

      def handle_client_error(client, error)
        log_error("Client error", client_id: client.id, error: error)

        client.send_message({
                              type: "error",
                              message: "An error occurred",
                              timestamp: Time.now.iso8601
                            })
      end

      def handle_chat_message(client, session_id, message)
        content = message["content"]
        return unless content

        # Add to message history
        add_to_history(session_id, {
                         role: "user",
                         content: content,
                         timestamp: Time.now.iso8601,
                         client_id: client.id
                       })

        # Get current agent
        session = @chat_sessions[session_id]
        agent = @agents[session[:current_agent]]

        # Process with agent
        begin
          result = agent.run(content)
          response_content = result.messages.last[:content]

          # Add to message history
          add_to_history(session_id, {
                           role: "assistant",
                           content: response_content,
                           timestamp: Time.now.iso8601,
                           agent: agent.name
                         })

          # Send response
          client.send_message({
                                type: "chat_response",
                                content: response_content,
                                agent: agent.name,
                                session_id: session_id,
                                timestamp: Time.now.iso8601
                              })
        rescue StandardError => e
          log_error("Chat message processing error", error: e, session_id: session_id)

          client.send_message({
                                type: "error",
                                message: "Failed to process message",
                                timestamp: Time.now.iso8601
                              })
        end
      end

      def handle_start_stream(client, session_id, message)
        content = message["content"]
        return unless content

        # Get current agent
        session = @chat_sessions[session_id]
        agent = @agents[session[:current_agent]]

        # Start streaming
        stream_id = @stream_processor.start_stream(agent, content) do |chunk|
          client.send_message({
                                type: "stream_chunk",
                                chunk: chunk,
                                session_id: session_id,
                                stream_id: stream_id,
                                timestamp: Time.now.iso8601
                              })
        end

        @active_streams[session_id] = stream_id

        client.send_message({
                              type: "stream_started",
                              stream_id: stream_id,
                              session_id: session_id,
                              timestamp: Time.now.iso8601
                            })
      end

      def handle_stop_stream(client, session_id, _message)
        stream_id = @active_streams[session_id]
        return unless stream_id

        @stream_processor.stop_stream(stream_id)
        @active_streams.delete(session_id)

        client.send_message({
                              type: "stream_stopped",
                              stream_id: stream_id,
                              session_id: session_id,
                              timestamp: Time.now.iso8601
                            })
      end

      def handle_handoff_request(client, session_id, message)
        target_agent = message["target_agent"]
        context = message["context"] || {}

        if request_handoff(session_id, target_agent, context)
          client.send_message({
                                type: "handoff_completed",
                                target_agent: target_agent,
                                session_id: session_id,
                                timestamp: Time.now.iso8601
                              })
        else
          client.send_message({
                                type: "handoff_failed",
                                target_agent: target_agent,
                                session_id: session_id,
                                timestamp: Time.now.iso8601
                              })
        end
      end

      def handle_join_room(client, message)
        room_id = message["room_id"]
        return unless room_id

        if join_room(client.id, room_id)
          client.send_message({
                                type: "room_joined",
                                room_id: room_id,
                                timestamp: Time.now.iso8601
                              })
        else
          client.send_message({
                                type: "room_join_failed",
                                room_id: room_id,
                                timestamp: Time.now.iso8601
                              })
        end
      end

      def handle_leave_room(client, message)
        room_id = message["room_id"]
        return unless room_id

        return unless leave_room(client.id, room_id)

        client.send_message({
                              type: "room_left",
                              room_id: room_id,
                              timestamp: Time.now.iso8601
                            })
      end

      def handle_get_history(client, session_id, message)
        limit = message["limit"] || 100
        history = get_message_history(session_id, limit)

        client.send_message({
                              type: "message_history",
                              history: history,
                              session_id: session_id,
                              timestamp: Time.now.iso8601
                            })
      end

      def add_to_history(session_id, message)
        @mutex.synchronize do
          @message_history[session_id] ||= []
          @message_history[session_id] << message

          # Limit history size
          max_history = @config[:max_history_size] || 1000
          @message_history[session_id].shift(@message_history[session_id].size - max_history) if @message_history[session_id].size > max_history
        end
      end

    end

  end

end
