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
require File.expand_path("../../../../../app/components/RAAF/rails/continuous/result_show", __dir__)

# A score of 1.00 says nothing on its own. The screen used to offer "whether
# this verdict is the odd one out" and answer it with other results of the same
# policy — empty whenever the policy had graded one span, which is exactly when
# somebody is reading a single verdict and wondering what to make of it.
module RAAF
  module Rails
    module Continuous
      RSpec.describe ResultShow, "the check's own history", type: :component do
        let(:result) do
          instance_double(
            "ContinuousEvaluationResult",
            id: 690, span_id: "span_ed99", trace_id: "trace_0854", status: "good",
            score: 1.0, scores: { "scored_events" => 1.0 }, agent_name: "TimelineRelevanceScorer",
            model: nil, provider: nil, environment: "development",
            evaluator_name: "timeline_relevance", evaluator_type: "rule_based",
            evaluator_version: nil, evaluation_policy: nil, evaluation_policy_id: nil,
            evaluation_queue_item: nil, reasoning: "15/15 on the scale",
            details: { "field_name" => "scored_events" }, metadata: {}, metrics: nil,
            created_at: Time.now, evaluation_started_at: Time.now,
            evaluation_completed_at: Time.now, evaluation_duration_ms: 0.4
          )
        end

        let(:history) do
          instance_double("CheckHistory", any?: true, results: [], count: 13,
                                          median: 1.0, rank: nil, flat?: flat,
                                          previous: nil, average: nil, earlier_count: 0,
                                          delta_vs_previous: nil, delta_vs_average: nil,
                                          repeat_count: 1, repeats_agree?: nil)
        end

        let(:flat) { false }

        let(:view_context) do
          instance_double("ActionView::Base").tap do |context|
            allow(context).to receive(:time_ago_in_words).and_return("2 hours")
            allow(context).to receive(:pluralize) { |count, word| "#{count} #{word}s" }
          end
        end

        let(:html) do
          stub_const("RAAF::Eval::Continuous::EvaluatorDiscovery",
                     class_double("EvaluatorDiscovery").tap do |double|
                       allow(double).to receive(:build).and_raise(NameError, "none")
                     end)
          component = described_class.new(result: result, history: history)
          allow(component).to receive(:view_context).and_return(view_context)
          component.call
        end

        it "asks what this check usually scores rather than what the policy did" do
          expect(html).to include("How this check usually scores")
          expect(html).not_to include("same policy")
        end

        it "says how many scores it is reading the verdict against" do
          expect(html).to include("13 scores")
          expect(html).to include("median 1.00")
        end

        # The one fact a single result can never carry. Thirteen verdicts of
        # 1.00 do not mean the agent is good; they mean the check has not yet
        # told anybody anything.
        context "when the check has returned the same number every time" do
          let(:flat) { true }

          it "says the check has distinguished nothing" do
            expect(html).to include("Never varies")
            expect(html).to include("has not distinguished anything yet")
          end
        end

        context "when the check has varied" do
          it "makes no such claim" do
            expect(html).not_to include("Never varies")
          end
        end

        # Ranking a verdict among identical verdicts would call the same number
        # both the highest and the lowest.
        context "when the verdict sits among the check's highest" do
          let(:history) do
            instance_double("CheckHistory", any?: true, results: [], count: 8,
                                            median: 0.6, rank: 0.9, flat?: false,
                                            previous: nil, average: nil, earlier_count: 0,
                                            delta_vs_previous: nil, delta_vs_average: nil,
                                            repeat_count: 1, repeats_agree?: nil)
          end

          it "says where this one sits" do
            expect(html).to include("among its highest")
          end
        end

        # Every result of this check on the console's own data was a replay of
        # one span. Measuring across them reported four scores and a running
        # average off a single span; reporting nothing left a card headed "how
        # this check usually scores" blank under a check on its eighth run.
        context "when the check has only ever graded this span" do
          let(:history) do
            instance_double("CheckHistory", any?: false, results: [], count: 1,
                                            median: 1.0, rank: nil, flat?: nil,
                                            previous: nil, average: nil, earlier_count: 0,
                                            delta_vs_previous: nil, delta_vs_average: nil,
                                            repeat_count: 8, repeats_agree?: true)
          end

          it "says what those runs were, and what they were not" do
            expect(html).to include("Only this span, graded 8 times")
            expect(html).to include("returned 1.00")
            expect(html).to include("not that it can tell two spans apart")
          end

          it "does not report them as a history of how the check scores" do
            expect(html).to include("8 runs on this span")
            expect(html).not_to include("Never varies")
            expect(html).not_to include("vs running average")
          end
        end

        context "when the check has run once and only here" do
          let(:history) do
            instance_double("CheckHistory", any?: false, results: [], count: 1,
                                            median: 1.0, rank: nil, flat?: nil,
                                            previous: nil, average: nil, earlier_count: 0,
                                            delta_vs_previous: nil, delta_vs_average: nil,
                                            repeat_count: 1, repeats_agree?: nil)
          end

          it "says there is nothing to compare with" do
            expect(html).to include("Nothing to compare with")
            expect(html).to include("no other span for this check")
          end
        end

        # 0.62 is good news after 0.40 and bad news after 0.90. The number on
        # its own cannot say which.
        context "when the check has run before" do
          let(:previous) { instance_double("ContinuousEvaluationResult", score: 0.9) }

          let(:history) do
            instance_double("CheckHistory", any?: true, results: [], count: 9,
                                            median: 0.7, rank: 0.2, flat?: false,
                                            previous: previous, average: 0.65, earlier_count: 8,
                                            delta_vs_previous: -0.28, delta_vs_average: -0.03,
                                            repeat_count: 1, repeats_agree?: nil)
          end

          it "prints what the check said last time, and the movement since" do
            expect(html).to include("vs last run")
            expect(html).to include("0.90")
            expect(html).to include("-0.28")
          end

          it "prints the running average and how many spans it covers" do
            expect(html).to include("vs running average")
            expect(html).to include("0.65 over 8 spans")
            expect(html).to include("-0.03")
          end
        end

        # A movement under the console's noise floor is the same answer twice,
        # and "+0.00" invites it to be read as a change.
        context "when the score has not moved" do
          let(:history) do
            instance_double("CheckHistory", any?: true, results: [], count: 9,
                                            median: 1.0, rank: nil, flat?: false,
                                            previous: instance_double("ContinuousEvaluationResult", score: 1.0),
                                            average: 1.0, earlier_count: 8,
                                            delta_vs_previous: 0.0, delta_vs_average: 0.0,
                                            repeat_count: 1, repeats_agree?: nil)
          end

          it "says unchanged rather than plus nothing" do
            expect(html).to include("unchanged")
            expect(html).not_to include("+0.00")
          end
        end
      end
    end
  end
end
