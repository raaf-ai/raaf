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
        render_in_layout RAAF::Rails::Ui::StyleGuide.new, title: "Style guide"
      end
    end
  end
end
