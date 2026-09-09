# frozen_string_literal: true

require "rails_helper"

# The Live / Paused control in the header toggles one thing: the refresh timer
# on the document. Until the flag reached that controller the badge was
# decorative — a screen asking not to be reloaded printed "Paused" and reloaded
# anyway, and the editors under it lost half-typed input every 30 seconds.
RSpec.describe RAAF::Rails::Tracing::BaseLayout, type: :component do
  def body_data(**args)
    described_class.new(**args).send(:body_data)
  end

  it "starts the timer on a screen that tails production" do
    expect(body_data(live: true)).to include(auto_refresh_enabled_value: true,
                                             auto_refresh_interval_value: 30_000)
  end

  it "leaves the timer standing down on a screen that asked not to reload" do
    expect(body_data(live: false)).to include(auto_refresh_enabled_value: false)
  end

  # The controller is still on the document when paused, so the badge remains a
  # control rather than a label: a reader can turn tailing on from it.
  it "keeps the controller and the interval on a paused page" do
    expect(body_data(live: false)).to include(controller: "auto-refresh tooltip",
                                              auto_refresh_interval_value: 30_000)
  end

  it "tails by default, which is what a list screen wants" do
    expect(body_data).to include(auto_refresh_enabled_value: true)
  end
end
