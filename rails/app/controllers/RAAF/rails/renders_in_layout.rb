# frozen_string_literal: true

module RAAF
  module Rails
    ##
    # Renders a Phlex page component inside the dashboard shell.
    #
    # Every HTML action in the engine ends this way, and each of them used to
    # build the layout itself; two controllers had already extracted the same
    # private method separately. A module rather than a method on
    # {ApplicationController} because the tracing controllers descend from
    # ActionController::Base directly and render the same shell.
    #
    module RendersInLayout
      private

      # Options are passed through to {RAAF::Rails::Tracing::BaseLayout} —
      # title, crumb, current, range, range_href, live, bundles — so a screen
      # still says what its shell needs and nothing here has to know the list.
      #
      # @param component [Phlex::HTML] the page
      # @param status [Symbol, Integer, nil] for the form actions that
      #   re-render an invalid record, and for the error pages
      def render_in_layout(component, status: nil, **layout)
        page = RAAF::Rails::Tracing::BaseLayout.new(**layout) { render component }

        status ? render(page, status: status) : render(page)
      end
    end
  end
end
