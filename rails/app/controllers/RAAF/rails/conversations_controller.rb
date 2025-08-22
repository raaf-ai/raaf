# frozen_string_literal: true

module RAAF
  module Rails
    # Conversations controller for RAAF Rails Engine
    class ConversationsController < ApplicationController
      def index
        render RAAF::Rails::SimpleDashboard.new(title: "Conversations")
      end
      
      def show
        render RAAF::Rails::SimpleDashboard.new(title: "Conversation Details")
      end
      
      def create
        render json: { status: "ok", message: "Conversation created", id: SecureRandom.uuid }
      end
    end
  end
end