# frozen_string_literal: true

require "rails_helper"

# Two routes used to render the same cost screen from two different billing
# sources, and their totals could disagree with nothing on either page saying
# which one you were reading.
RSpec.describe RAAF::Rails::Tracing::CostsController, type: :request do
  describe "GET /raaf/tracing/costs" do
    it "sends a reader to the console's one cost screen" do
      get tracing_costs_path

      expect(response).to redirect_to(dashboard_costs_path)
    end

    it "carries the selected window across the redirect" do
      get tracing_costs_path(range: "7d")

      expect(response).to redirect_to(dashboard_costs_path(range: "7d"))
    end

    # The forecast, the budget status and the recommendations are the JSON
    # caller's. The HTML branch used to compute all three and render none.
    it "still answers the JSON payload it always answered" do
      get tracing_costs_path(format: :json)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.keys)
        .to include("breakdown", "forecast", "budget_status", "recommendations")
    end
  end
end
