# frozen_string_literal: true

module RAAF
  module Rails
    # Agents controller for RAAF Rails Engine
    class AgentsController < ApplicationController
      def index
        render RAAF::Rails::SimpleDashboard.new(title: "Agents")
      end
      
      def show
        render RAAF::Rails::SimpleDashboard.new(title: "Agent Details")
      end
      
      def new
        render RAAF::Rails::SimpleDashboard.new(title: "New Agent")
      end
      
      def create
        redirect_to agents_path
      end
      
      def edit
        render RAAF::Rails::SimpleDashboard.new(title: "Edit Agent")
      end
      
      def update
        redirect_to agents_path
      end
      
      def destroy
        redirect_to agents_path
      end
      
      # Custom actions
      def chat
        render RAAF::Rails::SimpleDashboard.new(title: "Agent Chat")
      end
      
      def test
        render json: { status: "ok", message: "Agent test endpoint" }
      end
      
      def deploy
        render json: { status: "ok", message: "Agent deployed" }
      end
      
      def undeploy
        render json: { status: "ok", message: "Agent undeployed" }
      end
    end
  end
end