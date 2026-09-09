# frozen_string_literal: true

require "spec_helper"

# The style guide is the review surface for the library: a component that is
# not on it is a component nobody compares against the rest. Both KPI
# presentations are there so the difference between them is a choice somebody
# made rather than a difference between two screens nobody put side by side.
module RAAF
  module Rails
    module Ui
      RSpec.describe StyleGuide do
        subject(:html) { described_class.new.call }

        it "shows the icon-top-right presentation" do
          expect(html).to include(%(class="raaf-stat-card raaf-stat-card--danger"))
        end

        it "shows the icon-box presentation" do
          expect(html).to include("raaf-stat-card--leading")
          expect(html).to include("raaf-icon-box--danger")
        end

        it "shows every tone the tile speaks, in both presentations" do
          Molecules::StatCard::TONES.each do |tone|
            expect(html.scan("raaf-stat-card--#{tone}").size).to be >= 2
          end
        end
      end
    end
  end
end
