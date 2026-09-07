# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # MetricCard — one headline number per tile.
        #
        # Becomes a link when given an href, so the dashboard's summary tiles
        # can drill into the filtered list they summarise.
        #
        # @example
        #   render Molecules::MetricCard.new(
        #     label: "Failed spans", value: 17, icon: "x-octagon", tone: :danger,
        #     href: spans_path(status: "error"), hint: "last 24 hours"
        #   )
        #
        class MetricCard < Base
          TONES = %i[accent success warning danger].freeze

          # @param label [String] uppercase caption
          # @param value [String, Numeric] the headline figure
          # @param icon [String, nil] Bootstrap Icons name for the leading box
          # @param tone [Symbol, nil] colours the icon box
          # @param hint [String, nil] small caption under the value
          # @param href [String, nil] makes the whole tile a link
          def initialize(label:, value:, icon: nil, tone: nil, hint: nil, href: nil,
                         class: nil, **attrs)
            @label = label
            @value = value
            @icon = icon
            @tone = tone
            @hint = hint
            @href = href
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            css = tokens("raaf-metric-card", @class)

            if @href
              a(href: @href, class: css, **@attrs) { body }
            else
              div(class: css, **@attrs) { body }
            end
          end

          private

          def body
            render Atoms::IconBox.new(@icon, tone: @tone) if @icon

            div(class: "raaf-metric-card-body") do
              div(class: "raaf-metric-card-label") { @label }
              div(class: "raaf-metric-card-value") { @value.to_s }
              div(class: "raaf-metric-card-hint") { @hint } if @hint
            end
          end
        end
      end
    end
  end
end
