# frozen_string_literal: true

module RAAF
  module Rails
    module Continuous
      ##
      # Score trends — every evaluator's score against every bucket in the
      # window, from RAAF Eval.dc.html.
      #
      # The screen answers the topbar's range like the rest of the console
      # rather than the design's fixed 30 days, and opens on 30 days so the
      # default is the one the canvas draws. A month is also the shortest
      # window a drift is visible in: an evaluator sampling a few spans an
      # hour has nothing to say over a day.
      class TrendsController < BaseController
        MODES = %w[median absolute].freeze

        # GET /raaf/continuous/trends
        def index
          @trends = ScoreTrendSeries.call(range: current_range)

          respond_to do |format|
            format.html { html_screen }
            format.json { render json: @trends }
          end
        end

        private

        def html_screen
          screen = ScoreTrends.new(trends: @trends, mode: mode, mode_href: mode_href)

          render_in_layout screen, title: "Score trends", crumb: "Continuous",
                                   range: current_range, range_href: range_href
        end

        # Which colouring the grid is showing. Anything else is the default
        # rather than an error: the value arrives from a link anyone can edit.
        def mode
          MODES.include?(params[:mode]) ? params[:mode] : "median"
        end

        # Switching the colouring keeps the range and everything else in the
        # URL, so it is a way of reading the same grid rather than a reset.
        def mode_href
          ->(value) { "#{request.path}?#{request.query_parameters.merge('mode' => value).to_query}" }
        end

        # Overrides the continuous console's week. A drift takes a month to
        # become visible, and this is the one screen whose whole subject is the
        # drift rather than what is happening right now.
        def default_range
          "30d"
        end
      end
    end
  end
end
