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

  # The JSON API was never a page and is untouched.
  it "keeps the JSON API" do
    get "/raaf/api/v1/agents"

    expect(response).to have_http_status(:success)
  end

  it "renders no page through SimpleDashboard, because there is none" do
    expect(defined?(RAAF::Rails::SimpleDashboard)).to be_nil
  end
end
