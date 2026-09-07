# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # StatCard — the console's KPI tile.
        #
        # Label and icon on one line, a large tabular figure with its delta
        # beside it, and a note underneath. `tone:` colours the icon and the
        # delta together, which are the two parts that carry meaning.
        #
        # `series:` draws a sparkline between the figure and the note, which
        # is how the continuous Health cards read: a number is a claim, and the
        # bars under it are whether the number has been that all week.
        #
        # @example
        #   render Molecules::StatCard.new(
        #     label: "Failure rate", value: "1.8%", delta: "+0.6pt", tone: :bad,
        #     note: "225 failed · 23 error signatures", icon: "exclamation-octagon",
        #     series: [4, 6, 3, 9, 12],
        #     series_tips: ["Mon · 4 failures", "Tue · 6", "Wed · 3", "Thu · 9", "Fri · 12"]
        #   )
        #
        class StatCard < Base
          TONES = %i[ok warn bad info].freeze

          # @param label [String] uppercase caption
          # @param value [String, Numeric] the headline figure
          # @param delta [String, nil] change beside the figure
          # @param note [String, nil] supporting line underneath
          # @param icon [String, nil] Bootstrap Icons name
          # @param tone [Symbol, nil] :ok, :warn, :bad or :info
          # @param series [Array<Numeric>, nil] sparkline under the figure
          # @param series_tips [Array<String>, nil] hover readout per bucket
          # @param href [String, nil] makes the whole tile a link
          def initialize(label:, value:, delta: nil, note: nil, icon: nil, tone: nil,
                         series: nil, series_tips: nil, href: nil, class: nil, **attrs)
            @label = label
            @value = value
            @delta = delta
            @note = note
            @icon = icon
            @tone = tone
            @series = series
            @series_tips = series_tips
            @href = href
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            css = tokens("raaf-stat-card", modifier("raaf-stat-card", @tone, TONES), @class)

            if @href
              a(href: @href, class: css, **@attrs) { body }
            else
              div(class: css, **@attrs) { body }
            end
          end

          private

          def body
            div(class: "raaf-stat-card-head") do
              span(class: "raaf-stat-card-label") { @label }
              render Atoms::Icon.new(@icon, size: :sm, tone: icon_tone) if @icon
            end

            div(class: "raaf-stat-card-figure") do
              span(class: "raaf-stat-card-value") { @value.to_s }
              span(class: "raaf-stat-card-delta") { @delta } if @delta
            end

            sparkline if @series.present?

            div(class: "raaf-stat-card-note") { @note } if @note
          end

          def sparkline
            render Molecules::Sparkbars.new(values: @series, tips: Array(@series_tips),
                                            label: "#{@label} over the window",
                                            class: "raaf-stat-card-spark")
          end

          # Icon::TONES speaks in semantic names; map the health tones onto it.
          def icon_tone
            { ok: :success, warn: :warning, bad: :danger, info: :accent }[@tone]
          end
        end
      end
    end
  end
end
