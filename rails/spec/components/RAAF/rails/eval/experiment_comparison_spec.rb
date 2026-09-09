# frozen_string_literal: true

require "spec_helper"
require "phlex"
require "phlex/rails"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/object/to_query"
require "active_support/core_ext/string/filters"

ui_root = File.expand_path("../../../../../app/components/RAAF/rails/ui", __dir__)
require File.join(ui_root, "base")
Dir[File.join(ui_root, "{atoms,molecules,organisms}/*.rb")].sort.each { |file| require file }
require File.expand_path("../../../../../app/components/RAAF/rails/tracing/base_component", __dir__)
require File.expand_path("../../../../../app/components/RAAF/rails/eval/experiment_comparison", __dir__)

# `ExperimentEngine#compare_experiments` produced all of this from the day it
# was written, had a spec, and had no caller anywhere in the console. So an
# experiment's score stood on its own, which is the whole of why a run could be
# counted and not judged.
module RAAF
  module Rails
    module Eval
      RSpec.describe ExperimentComparison, type: :component do
        def run(name, status: "completed")
          instance_double("Experiment", id: name.hash.abs % 1000, name: name, status: status,
                                        agent_name: "Briefer", model: "gpt-4o",
                                        aggregate_metrics: aggregate_metrics,
                                        dataset: instance_double("Dataset", name: "Briefings"))
        end

        # The tokens the run recorded, which is what the Spend tile prices.
        let(:aggregate_metrics) do
          { "tokens" => { "total_tokens" => 1400, "total_input_tokens" => 1000,
                          "total_output_tokens" => 400 } }
        end

        let(:experiment) { run("Briefing v2") }
        let(:against) { run("Briefing v1") }

        let(:metrics_comparison) do
          { success_rate: { a: 90.0, b: 95.0, delta: 5.0 },
            tokens: { a: 1000, b: 1400, delta: 400 },
            scores: { "quality:value_range" => { a: 0.6, b: 0.8, delta: 0.2 } } }
        end

        # Item 1 got worse, item 2 got better, item 3 did not move, and item 4
        # was scored by only one of the runs.
        let(:item_comparison) do
          [{ dataset_item_id: 1, a: { id: 11, overall_score: 0.9, status: "completed" },
             b: { id: 21, overall_score: 0.4, status: "completed" } },
           { dataset_item_id: 2, a: { id: 12, overall_score: 0.5, status: "completed" },
             b: { id: 22, overall_score: 0.7, status: "completed" } },
           { dataset_item_id: 3, a: { id: 13, overall_score: 0.8, status: "completed" },
             b: { id: 23, overall_score: 0.8, status: "completed" } },
           { dataset_item_id: 4, a: nil,
             b: { id: 24, overall_score: 0.3, status: "completed" } }]
        end

        let(:comparison) do
          { metrics_comparison: metrics_comparison, item_comparison: item_comparison }
        end

        let(:view_context) do
          instance_double("ActionView::Base").tap do |context|
            allow(context).to receive(:time_ago_in_words).and_return("2 hours")
            allow(context).to receive(:pluralize) { |count, word| "#{count} #{word}s" }
          end
        end

        let(:html) do
          component = described_class.new(experiment: experiment, against: against,
                                          candidates: [against], comparison: comparison)
          allow(component).to receive(:view_context).and_return(view_context)
          component.call
        end

        it "says which run is being held against which" do
          expect(html).to include("Briefing v2 vs Briefing v1")
        end

        # The direction has to be unambiguous or every number on the screen is
        # readable two ways.
        it "says which way a positive change reads" do
          expect(html).to include("A positive change means Briefing v2 scored higher")
        end

        it "counts the cases that scored lower" do
          expect(html).to include("Regressed")
          expect(html).to include("1 cases scored lower, listed first")
        end

        # A run is judged by what it broke. Opening on the cases that did not
        # move buries the answer.
        it "lists the worst fall first" do
          rows = html.scan(/#(\d+)<\/span>/).flatten
          expect(rows.first).to eq("1")
        end

        it "prints both scores and the change between them" do
          expect(html).to include("0.90")
          expect(html).to include("0.40")
          expect(html).to include("-0.50")
        end

        # A case only one run scored has no change to report, and calling it a
        # fall to zero would invent a regression out of a gap.
        it "leaves out a case only one run scored" do
          expect(html).to include("3 cases both runs scored")
        end

        it "reads a case that did not move as flat rather than as an improvement" do
          expect(html).to include("flat")
        end

        # More tokens for the same answers is a cost the score does not show.
        it "carries the token change beside the score" do
          expect(html).to include("Tokens")
          expect(html).to include("+400")
        end

        context "when the dataset has only this one run" do
          let(:html) do
            component = described_class.new(experiment: experiment, against: nil,
                                            candidates: [], comparison: nil)
            allow(component).to receive(:view_context).and_return(view_context)
            component.call
          end

          it "says so, and says what would make a comparison possible" do
            expect(html).to include("Nothing to compare against")
            expect(html).to include("Run the dataset again")
          end
        end
      end
    end
  end
end
