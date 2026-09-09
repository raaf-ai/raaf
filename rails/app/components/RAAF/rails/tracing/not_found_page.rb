# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # A record that is not there.
      #
      # Almost always a trace or a span that has aged out of retention rather
      # than a wrong URL, so the page says that instead of "404".
      #
      class NotFoundPage < BaseComponent
        def initialize(message: nil, title: "Not found")
          @message = message ||
                     "That record is not in the store. Traces and spans are kept for a " \
                     "limited window, so an old link outlives what it points at."
          @title = title
        end

        def view_template
          div(class: "raaf-page") do
            render(Organisms::Card.new) do
              render Molecules::EmptyState.new(icon: "signpost-split", title: @title,
                                               text: @message)
            end

            actions
          end
        end

        private

        def actions
          div(class: "raaf-cluster") do
            render Atoms::Button.new(label: "Overview", icon: "house", href: dashboard_path)
            render Atoms::Button.new(label: "Traces", icon: "diagram-3", variant: :secondary,
                                     href: tracing_traces_path)
          end
        end
      end
    end
  end
end
