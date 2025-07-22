# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::Models Error classes" do
  it "defines model-specific error hierarchy" do
    expect(RAAF::Models::AuthenticationError).to be < RAAF::Error
    expect(RAAF::Models::RateLimitError).to be < RAAF::Error
    expect(RAAF::Models::ServerError).to be < RAAF::Error
    expect(RAAF::Models::APIError).to be < RAAF::Error
  end
end
