# frozen_string_literal: true

require "spec_helper"
require "active_support/core_ext/object/blank"

require_relative "../../../../../app/components/RAAF/rails/ui/base"
require_relative "../../../../../app/components/RAAF/rails/ui/atoms/bar"
require_relative "../../../../../app/components/RAAF/rails/ui/atoms/mono"
require_relative "../../../../../app/components/RAAF/rails/ui/molecules/sparkbars"
require_relative "../../../../../app/components/RAAF/rails/ui/molecules/meter_row"

# A bar's height is a comparison and nothing else. Which hour it covers, and
# what share it is a share of, are the two questions a reader has in front of
# every graph on the console, and neither is printed anywhere on the mark. The
# readout is where they get answered.
module RAAF
  module Rails
    module Ui
      RSpec.describe "chart hover readouts" do
        describe Molecules::Sparkbars do
          let(:tips) { ["09:00 · 3 runs", "10:00 · 5 runs", "11:00 · no runs"] }

          def render(**args)
            described_class.new(**args).call
          end

          it "gives every bucket its own readout" do
            html = render(values: [3, 5, 0], tips: tips)

            tips.each { |tip| expect(html).to include(%(role="tooltip">#{tip})) }
          end

          # The bar for an empty bucket is a stub twelve percent tall, and it is
          # exactly the bucket somebody wants named. The cell around it is what
          # makes it hoverable.
          it "hangs the readout on a full-height cell, not on the bar" do
            html = render(values: [3, 5, 0], tips: tips)

            expect(html).to include('class="raaf-sparkbar-cell raaf-tooltip"')
            expect(html.scan("raaf-sparkbar-cell").size).to eq(3)
          end

          # `role="img"` makes the bars presentational, so no readout reaches a
          # screen reader however it is marked up. The peak is the bucket a
          # reader would have gone looking for, so the label carries it.
          it "folds the peak bucket into the accessible label" do
            html = render(values: [3, 9, 0], label: "Recent runs",
                          tips: ["09:00 · 3 runs", "10:00 · 9 runs", "11:00 · no runs"])

            expect(html).to include('aria-label="Recent runs. Peak: 10:00 · 9 runs"')
          end

          it "draws a plain cell where the caller has nothing to say" do
            html = render(values: [3, 5], label: "Bare")

            expect(html).to include('aria-label="Bare"')
            expect(html).not_to include("raaf-tooltip")
          end
        end

        describe Molecules::MeterRow do
          it "puts the readout on the bar" do
            html = described_class.new(name: "gpt-4o", value: "$182.40", pct: 68,
                                       tip: "gpt-4o · $182.40 · 34% of the bill").call

            expect(html).to include('class="raaf-meter-bar raaf-tooltip"')
            expect(html).to include(%(role="tooltip">gpt-4o · $182.40 · 34% of the bill))
          end

          # The row prints the name and the figure already. A row told nothing
          # extra says nothing extra rather than repeating itself on hover.
          it "stays as it was without one" do
            html = described_class.new(name: "gpt-4o", value: "$182.40", pct: 68).call

            expect(html).to include('class="raaf-meter-bar"')
            expect(html).not_to include("raaf-tooltip")
          end

          # Assistive technology never needed the readout: the fill underneath
          # is a progressbar carrying the same figure.
          it "leaves the bar's own percentage on the progressbar role" do
            html = described_class.new(name: "gpt-4o", value: "$182.40", pct: 68).call

            expect(html).to include('role="progressbar"')
            expect(html).to include('aria-valuenow="68"')
          end
        end
      end
    end
  end
end
