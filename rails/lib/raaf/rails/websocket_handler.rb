# frozen_string_literal: true

module RAAF
  module Rails
    ##
    # WebSocket handler for real-time agent conversations
    #
    # Provides WebSocket support for real-time chat with AI agents,
    # including message streaming, typing indicators, and session management.
    #
    class WebsocketHandler
      include RAAF::Logging

      ##
      # WebSocket connection handler
      #
      # Handles WebSocket connections for real-time agent interactions.
      #
      def self.call(env)
        new(env).call
      end

      def initialize(env)
        @env = env
        @connections = {}
        @agent_sessions = {}
      end

      def call
        if websocket_request?
          handle_websocket_connection
        else
          [404, {}, ["Not Found"]]
        end
      end

      private

      def websocket_request?
        @env["HTTP_UPGRADE"] == "websocket"
      end

      def handle_websocket_connection
        ws = WebSocket::EventMachine::Server.new(@env)

        ws.onopen do |handshake|
          connection_id = SecureRandom.uuid
          user_id = extract_user_id(handshake)
          
          @connections[connection_id] = {
            websocket: ws,
            user_id: user_id,
            created_at: Time.current,
            last_activity: Time.current
          }

          log_info("WebSocket connection opened", {
            connection_id: connection_id,
            user_id: user_id
          })

          send_message(ws, {
            type: "connected",
            connection_id: connection_id,
            timestamp: Time.current.iso8601
          })
        end

        ws.onmessage do |message|
          handle_message(ws, message)
        end

        ws.onclose do |code, reason|
          handle_disconnect(ws, code, reason)
        end

        ws.onerror do |error|
          handle_error(ws, error)
        end

        ws.rack_response
      end

      def handle_message(ws, raw_message)
        begin
          message = JSON.parse(raw_message)
          connection = find_connection_by_websocket(ws)
          
          return unless connection

          update_last_activity(connection)

          case message["type"]
          when "chat"
            handle_chat_message(ws, connection, message)
          when "typing"
            handle_typing_indicator(ws, connection, message)
          when "join_agent"
            handle_join_agent(ws, connection, message)
          when "leave_agent"
            handle_leave_agent(ws, connection, message)
          when "ping"
            handle_ping(ws, connection)
          else
            send_error(ws, "Unknown message type: #{message['type']}")
          end
        rescue JSON::ParserError => e
          send_error(ws, "Invalid JSON: #{e.message}")
        rescue StandardError => e
          log_error("WebSocket message error", error: e)
          send_error(ws, "Internal server error")
        end
      end

      def handle_chat_message(ws, connection, message)
        agent_id = message["agent_id"]
        content = message["content"]
        context = message["context"] || {}

        unless agent_id && content
          send_error(ws, "Missing agent_id or content")
          return
        end

        agent = AgentModel.find_by(id: agent_id)
        unless agent
          send_error(ws, "Agent not found")
          return
        end

        # Check permissions
        unless can_access_agent?(connection[:user_id], agent)
          send_error(ws, "Access denied")
          return
        end

        # Process message asynchronously
        ConversationJob.perform_async(
          connection[:user_id],
          agent_id,
          content,
          context.merge(websocket_connection_id: find_connection_id(ws))
        )

        # Send acknowledgment
        send_message(ws, {
          type: "message_received",
          timestamp: Time.current.iso8601
        })
      end

      def handle_typing_indicator(ws, connection, message)
        agent_id = message["agent_id"]
        typing = message["typing"]

        return unless agent_id

        # Broadcast typing indicator to other connections in the same agent session
        broadcast_to_agent_session(agent_id, {
          type: "typing",
          user_id: connection[:user_id],
          typing: typing,
          timestamp: Time.current.iso8601
        }, exclude: ws)
      end

      def handle_join_agent(ws, connection, message)
        agent_id = message["agent_id"]

        unless agent_id
          send_error(ws, "Missing agent_id")
          return
        end

        agent = AgentModel.find_by(id: agent_id)
        unless agent
          send_error(ws, "Agent not found")
          return
        end

        unless can_access_agent?(connection[:user_id], agent)
          send_error(ws, "Access denied")
          return
        end

        # Add to agent session
        @agent_sessions[agent_id] ||= Set.new
        @agent_sessions[agent_id] << ws

        send_message(ws, {
          type: "joined_agent",
          agent_id: agent_id,
          agent_name: agent.name,
          timestamp: Time.current.iso8601
        })

        log_info("User joined agent session", {
          user_id: connection[:user_id],
          agent_id: agent_id
        })
      end

      def handle_leave_agent(ws, connection, message)
        agent_id = message["agent_id"]

        return unless agent_id

        # Remove from agent session
        @agent_sessions[agent_id]&.delete(ws)
        @agent_sessions.delete(agent_id) if @agent_sessions[agent_id]&.empty?

        send_message(ws, {
          type: "left_agent",
          agent_id: agent_id,
          timestamp: Time.current.iso8601
        })

        log_info("User left agent session", {
          user_id: connection[:user_id],
          agent_id: agent_id
        })
      end

      def handle_ping(ws, connection)
        send_message(ws, {
          type: "pong",
          timestamp: Time.current.iso8601
        })
      end

      def handle_disconnect(ws, code, reason)
        connection = find_connection_by_websocket(ws)
        return unless connection

        connection_id = find_connection_id(ws)
        user_id = connection[:user_id]

        # Remove from all agent sessions
        @agent_sessions.each do |agent_id, sessions|
          sessions.delete(ws)
          @agent_sessions.delete(agent_id) if sessions.empty?
        end

        # Remove connection
        @connections.delete(connection_id)

        log_info("WebSocket connection closed", {
          connection_id: connection_id,
          user_id: user_id,
          code: code,
          reason: reason
        })
      end

      def handle_error(ws, error)
        connection = find_connection_by_websocket(ws)
        log_error("WebSocket error", {
          user_id: connection&.dig(:user_id),
          error: error
        })
      end

      def send_message(ws, message)
        ws.send(JSON.generate(message))
      end

      def send_error(ws, error_message)
        send_message(ws, {
          type: "error",
          message: error_message,
          timestamp: Time.current.iso8601
        })
      end

      def broadcast_to_agent_session(agent_id, message, exclude: nil)
        sessions = @agent_sessions[agent_id] || Set.new
        sessions.each do |session_ws|
          next if session_ws == exclude

          begin
            send_message(session_ws, message)
          rescue StandardError => e
            log_error("Broadcast error", error: e)
          end
        end
      end

      def find_connection_by_websocket(ws)
        @connections.values.find { |conn| conn[:websocket] == ws }
      end

      def find_connection_id(ws)
        @connections.find { |_, conn| conn[:websocket] == ws }&.first
      end

      def update_last_activity(connection)
        connection[:last_activity] = Time.current
      end

      def extract_user_id(handshake)
        # Extract user ID from query params or headers
        query_params = Rack::Utils.parse_query(handshake.query_string)
        user_id = query_params["user_id"]
        
        # Alternative: extract from JWT token
        if token = query_params["token"]
          user_id = decode_jwt_token(token)
        end

        user_id
      end

      def decode_jwt_token(token)
        # JWT token decoding logic here
        # This would integrate with your authentication system
        nil
      end

      def can_access_agent?(user_id, agent)
        # Check if user can access the agent
        # This depends on your authorization system
        return true if user_id.nil? # Allow anonymous access for demo

        agent.user_id == user_id || agent.public?
      end

      ##
      # Send message to specific WebSocket connection
      #
      # @param connection_id [String] Connection ID
      # @param message [Hash] Message to send
      #
      def self.send_to_connection(connection_id, message)
        # This would be implemented with a shared connection store
        # like Redis for multi-server deployments
      end

      ##
      # Broadcast message to all connections in agent session
      #
      # @param agent_id [String] Agent ID
      # @param message [Hash] Message to broadcast
      #
      def self.broadcast_to_agent(agent_id, message)
        # This would be implemented with a shared session store
        # like Redis for multi-server deployments
      end
    end
  end
end