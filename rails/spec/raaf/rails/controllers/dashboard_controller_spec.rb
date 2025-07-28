# frozen_string_literal: true

# Mock BaseController before loading DashboardController
module RAAF
  module Rails
    module Controllers
      class BaseController < ::ActionController::Base
        def self.before_action(*args)
          # Mock before_action
        end

        def self.rescue_from(*args)
          # Mock rescue_from
        end

        def self.protect_from_forgery(*args)
          # Mock protect_from_forgery
        end
      end
    end
  end
end

# Now load the controller file
require_relative "../../../../lib/raaf/rails/controllers/dashboard_controller"

RSpec.describe RAAF::Rails::Controllers::DashboardController do
  # Since DashboardController is a class that inherits from BaseController,
  # we need to test it as a class, not a module

  # Mock models
  before do
    # rubocop:disable Rails/ApplicationRecord
    # Using ::ActiveRecord::Base because ApplicationRecord isn't available in test environment
    stub_const("AgentModel", Class.new(ActiveRecord::Base))
    stub_const("ConversationModel", Class.new(ActiveRecord::Base))
    stub_const("MessageModel", Class.new(ActiveRecord::Base))
    # rubocop:enable Rails/ApplicationRecord
    stub_const("ConversationJob", Class.new)
  end

  describe "class structure" do
    it "inherits from BaseController" do
      expect(described_class.superclass).to eq(RAAF::Rails::Controllers::BaseController)
    end
  end

  describe "actions" do
    it "defines index action" do
      expect(described_class.instance_methods).to include(:index)
    end

    it "defines agents action" do
      expect(described_class.instance_methods).to include(:agents)
    end

    it "defines conversations action" do
      expect(described_class.instance_methods).to include(:conversations)
    end

    it "defines analytics action" do
      expect(described_class.instance_methods).to include(:analytics)
    end
  end

  describe "private methods" do
    it "includes set_current_user" do
      expect(described_class.private_instance_methods).to include(:set_current_user)
    end

    it "includes current_user_agents" do
      expect(described_class.private_instance_methods).to include(:current_user_agents)
    end

    it "includes current_user_conversations" do
      expect(described_class.private_instance_methods).to include(:current_user_conversations)
    end

    it "includes recent_conversations" do
      expect(described_class.private_instance_methods).to include(:recent_conversations)
    end

    it "includes dashboard_stats" do
      expect(described_class.private_instance_methods).to include(:dashboard_stats)
    end
  end

  describe "filter methods" do
    it "includes filter_conversations" do
      expect(described_class.private_instance_methods).to include(:filter_conversations)
    end
  end

  describe "analytics methods" do
    it "includes build_analytics" do
      expect(described_class.private_instance_methods).to include(:build_analytics)
    end

    it "includes conversations_over_time_data" do
      expect(described_class.private_instance_methods).to include(:conversations_over_time_data)
    end

    it "includes messages_by_agent_data" do
      expect(described_class.private_instance_methods).to include(:messages_by_agent_data)
    end

    it "includes token_usage_data" do
      expect(described_class.private_instance_methods).to include(:token_usage_data)
    end

    it "includes response_time_data" do
      expect(described_class.private_instance_methods).to include(:response_time_data)
    end

    it "includes popular_agents_data" do
      expect(described_class.private_instance_methods).to include(:popular_agents_data)
    end

    it "includes error_rate_data" do
      expect(described_class.private_instance_methods).to include(:error_rate_data)
    end
  end

  describe "calculation methods" do
    it "includes calculate_total_tokens" do
      expect(described_class.private_instance_methods).to include(:calculate_total_tokens)
    end

    it "includes calculate_avg_response_time" do
      expect(described_class.private_instance_methods).to include(:calculate_avg_response_time)
    end
  end
end
