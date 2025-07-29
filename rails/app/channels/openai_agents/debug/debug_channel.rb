module OpenaiAgents
  module Debug
    class DebugChannel < ApplicationCable::Channel
      def subscribed
        Rails.logger.info "🔌 OpenaiAgents::Debug::DebugChannel subscribed with session_id: #{params[:session_id]}"
        stream_from "openai_agents_debug_#{params[:session_id]}"
      end

      def unsubscribed
        Rails.logger.info "🔌 OpenaiAgents::Debug::DebugChannel unsubscribed for session_id: #{params[:session_id]}"
        # Any cleanup needed when channel is unsubscribed
      end

      def ping
        Rails.logger.info "🏓 OpenaiAgents::Debug::DebugChannel ping received for session_id: #{params[:session_id]}"
        ActionCable.server.broadcast(
          "openai_agents_debug_#{params[:session_id]}",
          {
            type: "pong",
            message: "Ping received at #{Time.current}",
            timestamp: Time.current.to_i
          }
        )
      end
    end
  end
end
