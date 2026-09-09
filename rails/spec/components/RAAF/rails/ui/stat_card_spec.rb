# frozen_string_literal: true

require "spec_helper"
require "active_support/core_ext/object/blank"

require_relative "../../../../../app/components/RAAF/rails/ui/base"
require_relative "../../../../../app/components/RAAF/rails/ui/atoms/icon"
require_relative "../../../../../app/components/RAAF/rails/ui/atoms/icon_box"
require_relative "../../../../../app/components/RAAF/rails/ui/molecules/sparkbars"
require_relative "../../../../../app/components/RAAF/rails/ui/molecules/stat_card"

# The console had two KPI tiles doing the same job in different halves of
# itself: one with the icon top-right and a delta beside the figure, one with
# an icon box on the left and neither. This is the tile that carries both, so
# a reader meets the same card on every screen.
module RAAF
  module Rails
    module Ui
      RSpec.describe Molecules::StatCard do
        # The health dialect the card used to accept alongside its own. Named
        # here now that the card itself no longer states it anywhere.
        RETIRED_TONES = %i[ok warn bad info].freeze

        def render(**args)
          described_class.new(**args).call
        end

        describe "presentations" do
          it "puts the icon in the head by default" do
            html = render(label: "Runs", value: "1,802", icon: "diagram-3")

            expect(html).to include("raaf-stat-card-head")
            expect(html).to include("raaf-icon")
            expect(html).not_to include("raaf-icon-box")
            expect(html).not_to include("raaf-stat-card--leading")
          end

          it "puts the icon in a box beside the figure when asked to lead with it" do
            html = render(label: "Runs", value: "1,802", icon: "diagram-3", layout: :leading)

            expect(html).to include("raaf-stat-card--leading")
            expect(html).to include("raaf-icon-box")
            expect(html).to include("raaf-stat-card-body")
          end

          # The icon box comes before the text in the markup, which is what puts
          # it on the left without the stylesheet reordering anything.
          it "renders the icon box ahead of the label" do
            html = render(label: "Runs", value: "1,802", icon: "diagram-3", layout: :leading)

            expect(html.index("raaf-icon-box")).to be < html.index("raaf-stat-card-label")
          end

          # A tile built by merging hashes can arrive with an explicit nil for
          # a key it never set, which is not a reason to raise.
          [:sideways, nil, "leading"].each do |layout|
            it "reads #{layout.inspect} as the presentation it can draw" do
              html = render(label: "Runs", value: "1,802", icon: "diagram-3", layout: layout)

              expect(html.include?("raaf-stat-card--leading")).to eq(layout == "leading")
            end
          end

          it "wraps the whole tile in a link in either presentation" do
            %i[corner leading].each do |layout|
              html = render(label: "Runs", value: 12, href: "/raaf/runs", layout: layout)

              expect(html).to start_with(%(<a href="/raaf/runs"))
            end
          end
        end

        # Neither the delta nor the sparkline belongs to a presentation. The
        # icon-box tiles went without them only because their component had
        # never been given them.
        describe "delta and sparkline" do
          %i[corner leading].each do |layout|
            it "draws both in the #{layout} presentation" do
              html = render(label: "Failure rate", value: "1.8%", delta: "+0.6pt",
                            note: "225 failed", icon: "exclamation-octagon",
                            layout: layout, series: [4, 6, 3, 9],
                            series_tips: ["Mon · 4", "Tue · 6", "Wed · 3", "Thu · 9"])

              expect(html).to include(%(<span class="raaf-stat-card-delta">+0.6pt</span>))
              expect(html).to include("raaf-sparkbars")
              expect(html).to include("raaf-stat-card-note")
            end
          end
        end

        # One vocabulary, the semantic set the atoms already speak. The health
        # dialect the icon-top-right tiles used to say — `ok / warn / bad /
        # info` — was aliased onto it while the screens migrated, and is now a
        # word the card does not know.
        describe "tone vocabulary" do
          it "names four tones" do
            expect(described_class::TONES).to eq(%i[accent success warning danger])
          end

          RETIRED_TONES.each do |tone|
            it "no longer answers to #{tone.inspect}" do
              args = { label: "Runs", value: 12, delta: "+1", icon: "diagram-3" }

              expect(render(**args, tone: tone)).to eq(render(**args))
            end
          end

          it "colours the icon with the tone the card was given" do
            html = render(label: "Errors", value: 17, icon: "x-octagon", tone: :danger)

            expect(html).to include("raaf-icon--danger")
          end

          it "colours the icon box with the tone the card was given" do
            html = render(label: "Errors", value: 17, icon: "x-octagon", tone: :danger,
                          layout: :leading)

            expect(html).to include("raaf-icon-box--danger")
          end

          it "ignores a tone it does not know" do
            html = render(label: "Runs", value: 12, tone: :purple)

            expect(html).to include(%(class="raaf-stat-card"))
          end

          # `Atoms::Icon` knows `:muted`, which this card does not, and the
          # Feedback screen passes it whenever there is no average to score.
          # A word the card dropped must not reach the icon behind its back.
          it "does not pass a tone it dropped on to the icon" do
            html = render(label: "Average", value: "—", icon: "graph-up", tone: :muted)

            expect(html).not_to include("raaf-icon--muted")
          end
        end

        # The tone name is the card's promise; the stylesheet is where it is
        # kept. A tone with no rule is a tone that renders as no tone at all.
        describe "the stylesheets behind the tones" do
          let(:stylesheets) do
            root = File.expand_path("../../../../../app/assets/stylesheets/RAAF/ui", __dir__)

            Dir[File.join(root, "**", "*.css")].to_h { |path| [path, File.read(path)] }
          end

          it "has an ink rule for every tone the card names" do
            css = stylesheets.fetch(
              stylesheets.keys.find { |path| path.end_with?("molecules/stat_card.css") }
            )

            described_class::TONES.each do |tone|
              expect(css).to include(".raaf-stat-card--#{tone} .raaf-stat-card-delta")
            end
          end

          # `health.css` tinted the sparkline by `--ok` / `--warn` / `--bad`,
          # and those rules stopped matching the moment the card renamed its
          # tones — a screen going grey with every test still green. Nothing
          # may be left addressing a name the card no longer emits.
          it "leaves no rule addressing a tone the card has stopped emitting" do
            stylesheets.each do |path, css|
              RETIRED_TONES.each do |tone|
                # `--warn` is a prefix of `--warning`, so the class has to end
                # where the name does.
                expect(css).not_to match(/\.raaf-stat-card--#{tone}(?![\w-])/),
                                   "#{File.basename(path)} still targets .raaf-stat-card--#{tone}"
              end
            end
          end
        end
      end
    end
  end
end
