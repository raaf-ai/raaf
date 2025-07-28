# frozen_string_literal: true

# Load the WebsocketHandler file since it's not auto-loaded
require_relative "../../../lib/raaf/rails/websocket_handler"

# Mock required classes
module WebSocket
  module EventMachine
    class Server
      # Mock WebSocket server for testing
      def initialize(env)
        @env = env
      end

      def rack_response
        [200, {}, []]
      end
    end
  end
end

module Rack
  module Utils
    def self.parse_query(str)
      {}
    end
  end
end

RSpec.describe RAAF::Rails::WebsocketHandler do
  # Mock required models and jobs
  before do
    stub_const("AgentModel", Class.new)
    stub_const("ConversationJob", Class.new)
  end

  # Mock WebSocket connection
  let(:mock_ws) do
    double("WebSocket",
           send: nil,
           close: nil,
           state: :open)
  end

  describe ".call" do
    it "responds to call method" do
      expect(described_class).to respond_to(:call)
    end
  end

  describe "class structure" do
    it "includes RAAF::Logging" do
      expect(described_class.included_modules).to include(RAAF::Logging)
    end
  end

  describe "initialization" do
    let(:env) { { "HTTP_UPGRADE" => "websocket" } }
    let(:handler) { described_class.new(env) }

    it "creates a new instance with env" do
      expect(handler).to be_a(described_class)
    end
  end

  describe "private methods" do
    # Since we can't directly test private methods, we test their effects
    describe "message handling" do
      it "has handle_message method" do
        expect(described_class.private_instance_methods).to include(:handle_message)
      end

      it "has handle_chat_message method" do
        expect(described_class.private_instance_methods).to include(:handle_chat_message)
      end

      it "has handle_typing_indicator method" do
        expect(described_class.private_instance_methods).to include(:handle_typing_indicator)
      end

      it "has handle_join_agent method" do
        expect(described_class.private_instance_methods).to include(:handle_join_agent)
      end

      it "has handle_leave_agent method" do
        expect(described_class.private_instance_methods).to include(:handle_leave_agent)
      end

      it "has handle_ping method" do
        expect(described_class.private_instance_methods).to include(:handle_ping)
      end
    end

    describe "utility methods" do
      it "has send_message method" do
        expect(described_class.private_instance_methods).to include(:send_message)
      end

      it "has send_error method" do
        expect(described_class.private_instance_methods).to include(:send_error)
      end

      it "has broadcast_to_agent_session method" do
        expect(described_class.private_instance_methods).to include(:broadcast_to_agent_session)
      end

      it "has websocket_request? method" do
        expect(described_class.private_instance_methods).to include(:websocket_request?)
      end

      it "has extract_user_id method" do
        expect(described_class.private_instance_methods).to include(:extract_user_id)
      end
    end
  end

  describe "websocket handling" do
    it "has handle_websocket_connection method" do
      expect(described_class.private_instance_methods).to include(:handle_websocket_connection)
    end
  end

  describe "error handling" do
    it "has handle_error method" do
      expect(described_class.private_instance_methods).to include(:handle_error)
    end

    it "has handle_disconnect method" do
      expect(described_class.private_instance_methods).to include(:handle_disconnect)
    end
  end

  describe "helper methods" do
    it "has find_connection_by_websocket method" do
      expect(described_class.private_instance_methods).to include(:find_connection_by_websocket)
    end

    it "has find_connection_id method" do
      expect(described_class.private_instance_methods).to include(:find_connection_id)
    end

    it "has update_last_activity method" do
      expect(described_class.private_instance_methods).to include(:update_last_activity)
    end

    it "has can_access_agent? method" do
      expect(described_class.private_instance_methods).to include(:can_access_agent?)
    end

    it "has decode_jwt_token method" do
      expect(described_class.private_instance_methods).to include(:decode_jwt_token)
    end
  end

  describe "class methods" do
    it "responds to send_to_connection" do
      expect(described_class).to respond_to(:send_to_connection)
    end

    it "responds to broadcast_to_agent" do
      expect(described_class).to respond_to(:broadcast_to_agent)
    end
  end
end
