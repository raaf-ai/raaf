# frozen_string_literal: true

require "rails_helper"

# /raaf/agents, /dashboard/conversations and /dashboard/analytics rendered
# SimpleDashboard: a standalone HTML document with its own nav and its own
# inline stylesheet, outside the console shell entirely. A reader who followed
# one lost the sidebar and landed somewhere that looked like a different
# application.
RSpec.describe "routes outside the console shell", type: :request do
  it "no longer routes the agent-management stubs" do
    expect { get "/raaf/agents" }.to raise_error(ActionController::RoutingError)
  end

  it "no longer routes the conversation stub" do
    expect { get "/raaf/dashboard/conversations" }.to raise_error(ActionController::RoutingError)
  end

  it "no longer routes the analytics stub" do
    expect { get "/raaf/dashboard/analytics" }.to raise_error(ActionController::RoutingError)
  end

  # The JSON API rendered no page, so it outlived the screens by one ticket.
  # It answered 200 to every call over data it never stored, which is worse
  # than a 404: an integration against it fails silently and forever.
  it "no longer routes the JSON agent API" do
    expect { get "/raaf/api/v1/agents" }.to raise_error(ActionController::RoutingError)
  end

  it "no longer routes its nested conversations" do
    expect { get "/raaf/api/v1/agents/1/conversations" }.to raise_error(ActionController::RoutingError)
  end

  it "renders no page through SimpleDashboard, because there is none" do
    expect(defined?(RAAF::Rails::SimpleDashboard)).to be_nil
  end
end
