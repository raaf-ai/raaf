# frozen_string_literal: true

module RAAF
  module Rails
    # Main dashboard controller for RAAF Rails Engine
    class DashboardController < ApplicationController
      def index
        @stats = {
          agents_count: 0,
          conversations_count: 0,
          messages_count: 0
        }
        
        render RAAF::Rails::SimpleDashboard.new(title: "Dashboard", stats: @stats)
      end
      
      def agents
        render RAAF::Rails::SimpleDashboard.new(title: "Agents")
      end
      
      def conversations
        render RAAF::Rails::SimpleDashboard.new(title: "Conversations")
      end
      
      def analytics
        render RAAF::Rails::SimpleDashboard.new(title: "Analytics")
      end
    end
  end
end