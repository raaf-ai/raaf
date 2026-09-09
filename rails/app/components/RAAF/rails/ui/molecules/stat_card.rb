# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # StatCard — the console's KPI tile.
        #
        # A large tabular figure with its delta beside it, a note underneath,
        # and an icon in one of two places. `layout: :corner` (the default)
        # puts the icon at the top right, on the label's line. `layout:
        # :leading` puts it in a tinted box to the left of the whole tile.
        #
        # Both presentations are the same card: the delta, the note and the
        # sparkline are available to either, and both speak the one tone
        # vocabulary in {TONES}. The icon-box tiles elsewhere in the console
        # went without a delta only because their component had never been
        # given one, which is not a reason for a reader to meet a different
        # KPI row on every second screen.
        #
        # `series:` draws a sparkline between the figure and the note, which
        # is how the continuous Health cards read: a number is a claim, and the
        # bars under it are whether the number has been that all week.
        #
        # @example
        #   render Molecules::StatCard.new(
        #     label: "Failure rate", value: "1.8%", delta: "+0.6pt", tone: :danger,
        #     note: "225 failed · 23 error signatures", icon: "exclamation-octagon",
        #     series: [4, 6, 3, 9, 12],
        #     series_tips: ["Mon · 4 failures", "Tue · 6", "Wed · 3", "Thu · 9", "Fri · 12"]
        #   )
        #
        class StatCard < Base
          LAYOUTS = %i[corner leading].freeze

          # The console's one tone vocabulary. It is the semantic set the atoms
          # already speak, so `tone:` means the same word on a card, an icon
          # and a badge.
          TONES = %i[accent success warning danger].freeze

          # The health dialect (`ok / warn / bad / info`) mapped onto it. Kept
          # so a call site that still speaks it renders identically, and so the
          # mapping is stated once rather than decided per tile.
          TONE_ALIASES = { ok: :success, warn: :warning, bad: :danger, info: :accent }.freeze

          # @param label [String] uppercase caption
          # @param value [String, Numeric] the headline figure
          # @param delta [String, nil] change beside the figure
          # @param note [String, nil] supporting line underneath
          # @param icon [String, nil] Bootstrap Icons name
          # @param tone [Symbol, nil] a {TONES} name, or a {TONE_ALIASES} key
          # @param layout [Symbol] :corner or :leading
          # @param series [Array<Numeric>, nil] sparkline under the figure
          # @param series_tips [Array<String>, nil] hover readout per bucket
          # @param href [String, nil] makes the whole tile a link
          def initialize(label:, value:, delta: nil, note: nil, icon: nil, tone: nil,
                         layout: :corner, series: nil, series_tips: nil, href: nil,
                         class: nil, **attrs)
            @label = label
            @value = value
            @delta = delta
            @note = note
            @icon = icon
            @tone = normalize_tone(tone)
            @layout = layout.to_s == "leading" ? :leading : :corner
            @series = series
            @series_tips = series_tips
            @href = href
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            css = tokens("raaf-stat-card", layout_modifier,
                         modifier("raaf-stat-card", @tone, TONES), @class)

            if @href
              a(href: @href, class: css, **@attrs) { body }
            else
              div(class: css, **@attrs) { body }
            end
          end

          private

          def leading?
            @layout == :leading
          end

          # `:corner` is the tile's own shape, so it carries no modifier.
          def layout_modifier
            leading? ? "raaf-stat-card--leading" : nil
          end

          # Resolved once, in the constructor, so the modifier class and the
          # icon can never disagree about which tone the card is in. A word
          # from neither vocabulary is dropped rather than passed on: the atoms
          # know tones this card does not, and a tile should not colour its
          # icon by a name it just refused to colour its delta by.
          def normalize_tone(tone)
            return nil if tone.nil?

            resolved = TONE_ALIASES.fetch(tone.to_sym, tone.to_sym)
            TONES.include?(resolved) ? resolved : nil
          end

          # The icon box is a sibling of the text rather than part of it, so the
          # column beside it stays a column and the box sets its own height.
          def body
            return contents unless leading?

            render Atoms::IconBox.new(@icon, tone: @tone) if @icon
            div(class: "raaf-stat-card-body") { contents }
          end

          def contents
            div(class: "raaf-stat-card-head") do
              span(class: "raaf-stat-card-label") { @label }
              render Atoms::Icon.new(@icon, size: :sm, tone: @tone) if @icon && !leading?
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
        end
      end
    end
  end
end
