# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # Card — the glass container everything else sits inside.
        #
        # `flush:` does two things that used to be one. It removes the body
        # padding, and it clips the card's overflow so a row list's hover fill
        # cannot square off the rounded corners. A titled card gets the first
        # without the second: its body keeps its padding, so nothing reaches a
        # corner, and clipping it would only cut the readouts off the charts
        # and meters that titled cards are mostly full of.
        #
        # Given a `title`, the card renders a header strip with an actions slot
        # and a padded body. Given neither title nor actions, it is a plain
        # padded surface. Tables and row lists want `flush: true` so they can
        # run to the card's edge.
        #
        # @example Titled card with an action
        #   render(Organisms::Card.new(title: "Recent errors", subtitle: "last 24h")) do |card|
        #     card.actions { render Atoms::Button.new(label: "View all", size: :sm) }
        #     render Organisms::DataGrid.new(...)
        #   end
        #
        class Card < Base
          # @param title [String, nil] renders the header strip when present
          # @param subtitle [String, nil]
          # @param flush [Boolean] removes body padding, for tables and row lists
          # @param tight [Boolean] a smaller padding step
          # @param raised [Boolean] adds the elevation shadow
          def initialize(title: nil, subtitle: nil, flush: false, tight: false, raised: false,
                         class: nil, **attrs)
            @title = title
            @subtitle = subtitle
            @flush = flush
            @tight = tight
            @raised = raised
            @actions = nil
            @footer = nil
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            body = capture { yield(self) if block }

            div(class: css, **@attrs) do
              header_strip if @title
              wrap_body(body)
              div(class: "raaf-card-footer") { raw(safe(@footer)) } if @footer
            end
          end

          # Right-aligned controls in the header strip.
          def actions(&block)
            @actions = capture(&block)
            nil
          end

          # A bordered strip below the body.
          def footer(&block)
            @footer = capture(&block)
            nil
          end

          private

          def css
            tokens(
              "raaf-card",
              { "raaf-card--flush" => header? || @flush,
                "raaf-card--clip" => @flush,
                "raaf-card--tight" => @tight,
                "raaf-card--raised" => @raised },
              @class
            )
          end

          # A card with a header strip must be flush so the strip spans its width;
          # the body then re-applies its own padding.
          def header?
            !@title.nil?
          end

          def header_strip
            div(class: "raaf-card-header") do
              div do
                h3(class: "raaf-card-title") { @title }
                p(class: "raaf-card-subtitle") { @subtitle } if @subtitle
              end
              div(class: "raaf-card-actions") { raw(safe(@actions)) } if @actions
            end
          end

          def wrap_body(body)
            if header? && !@flush
              div(class: "raaf-card-body") { raw(safe(body)) }
            else
              raw(safe(body))
            end
          end
        end
      end
    end
  end
end
