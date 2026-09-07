# frozen_string_literal: true

module RAAF
  module Rails
    ##
    # Serves the living component library at /style_guide.
    #
    # The page renders the real components, so it cannot drift from what the
    # product pages show.
    #
    class StyleGuideController < ApplicationController
      def show
        render RAAF::Rails::Tracing::BaseLayout.new(title: "Style guide") {
          render RAAF::Rails::Ui::StyleGuide.new
        }
      end
    end
  end
end
