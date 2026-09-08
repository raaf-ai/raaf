# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::AssetsController, type: :request do
  describe "GET the console stylesheet" do
    it "answers with the current stylesheet" do
      get raaf_rails.console_stylesheet_path(RAAF::Rails::Ui::Stylesheet.digest)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/css")
      expect(response.body).to eq(RAAF::Rails::Ui::Stylesheet.call)
    end
  end

  describe "GET the console JavaScript" do
    # The layout loads this with a plain <script type="module" src="...">, so
    # the request is a non-XHR GET answering with a JavaScript media type --
    # exactly what Rails' cross-origin check rejects with a 422. It fired in
    # production the day the split-out bundle shipped, leaving every console
    # page styled and inert. The check has nothing to protect here: the body is
    # the same bytes for every visitor and carries nothing session-specific.
    it "answers a plain <script src> request instead of raising InvalidCrossOriginRequest" do
      get raaf_rails.console_javascript_path(RAAF::Rails::Ui::Javascript.digest)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/javascript")
      expect(response.body).to eq(RAAF::Rails::Ui::Javascript.call)
    end
  end
end
