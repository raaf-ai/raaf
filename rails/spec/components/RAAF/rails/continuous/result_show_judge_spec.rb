# frozen_string_literal: true

require "spec_helper"
require "phlex"
require "phlex/rails"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/object/to_query"
require "active_support/core_ext/string/filters"

ui_root = File.expand_path("../../../../../app/components/RAAF/rails/ui", __dir__)
require File.join(ui_root, "base")
Dir[File.join(ui_root, "{atoms,molecules,organisms}/*.rb")].each { |file| require file }
require File.expand_path("../../../../../app/components/RAAF/rails/tracing/base_component", __dir__)
require File.expand_path("../../../../../app/components/RAAF/rails/continuous/result_show", __dir__)

# A GEval judge scores against criteria one at a time and writes a paragraph
# per criterion. All of it reached this screen as key-value cells: the summary
# in a 220px monospace column, and the six criteria as one inspected Ruby array
# clipped at 600 characters — so a reader could see that six criteria had been
# weighed and could read about one and a half of them.
module RAAF
  module Rails
    module Continuous
      RSpec.describe ResultShow, "a judge's criteria", type: :component do
        let(:chain_of_thought) do
          "The output contains no stakeholders, which results in a complete failure to " \
            "meet any of the evaluation criteria."
        end

        let(:criteria) do
          [{ "criterion" => "criterion_1", "weight" => 1.0, "score" => 0.0,
             "description" => "Stakeholders cover the buying committee with relevant roles — " \
                              "practitioners who evaluate the product AND at least one approver. " \
                              "Score 100% if both are present.",
             "reasoning" => "There are no stakeholders listed in the output, so there are no " \
                            "roles present to evaluate." },
           { "criterion" => "criterion_2", "weight" => 1.0, "score" => 1.0,
             "description" => "Every title is specific rather than generic.",
             "reasoning" => "No generic titles were used." }]
        end

        let(:details) do
          { "field_name" => "output",
            "result" => {
              "label" => "bad", "score" => 0.0, "message" => "[BAD] GEval: 0%",
              "details" => {
                "method" => "g_eval", "evaluated_field" => "output", "criteria_count" => 2,
                "chain_of_thought" => chain_of_thought,
                "criteria_evaluation" => criteria,
                "judge_model" => "gpt-4o-mini",
                "judge_usage" => { "input_tokens" => 693, "output_tokens" => 423,
                                   "total_tokens" => 1116 },
                "thresholds" => { "good" => 0.75, "average" => 0.5, "used" => "bad (<0.5)" },
                "evaluation_note" => "Fails to adequately meet criteria (0/2 passed, 0%)"
              }
            } }
        end

        let(:result) do
          instance_double(
            "ContinuousEvaluationResult",
            id: 491, span_id: "span_a34d", trace_id: "trace_0502", status: "bad",
            score: 0.0, scores: { "output" => 0.0 }, agent_name: "DmuStakeholderDiscoveryAgent",
            model: "gemini-2.5-flash", provider: nil, environment: "development",
            evaluator_name: "dmu_discovery", evaluator_type: "llm_judge",
            evaluator_version: nil, evaluation_policy: nil, evaluation_policy_id: nil,
            evaluation_queue_item: nil, reasoning: "[BAD] GEval: 0%",
            details: details, metadata: {}, metrics: nil, created_at: Time.now,
            evaluation_started_at: Time.now, evaluation_completed_at: Time.now,
            evaluation_duration_ms: 3200.0
          )
        end

        let(:view_context) do
          instance_double("ActionView::Base").tap do |context|
            allow(context).to receive(:time_ago_in_words).and_return("6 hours")
            allow(context).to receive(:pluralize) { |count, word| "#{count} #{word}s" }
          end
        end

        let(:html) do
          stub_const("RAAF::Eval::Continuous::EvaluatorDiscovery", discovery)
          component = described_class.new(result: result)
          allow(component).to receive(:view_context).and_return(view_context)
          component.call
        end

        let(:discovery) { class_double("EvaluatorDiscovery", build: nil) }

        it "sets the judge's summary as prose rather than as a monospace cell" do
          expect(html).to include(chain_of_thought)
          expect(html).to include("raaf-finding-summary")
          expect(html).not_to include("CHAIN OF THOUGHT")
        end

        # The whole of what makes a judge's number readable is why it scored
        # each criterion the way it did, and inspecting the array printed the
        # hash rockets and cut the sixth criterion off mid-word.
        it "gives every criterion a row with its own reasoning" do
          expect(html).to include("There are no stakeholders listed in the output")
          expect(html).to include("No generic titles were used.")
          expect(html).not_to include("=&gt;")
        end

        # `criterion_1` names nothing; the claim the criterion makes does.
        it "heads each row with the claim rather than its index" do
          expect(html).to include("Stakeholders cover the buying committee with relevant roles")
          expect(html).not_to include("Criterion 1")
        end

        it "keeps the criterion's own instructions behind a disclosure" do
          expect(html).to include("what this criterion asks")
          expect(html).to include("Score 100% if both are present.")
        end

        # Two criteria scored 0.00 and 1.00. A reader who cannot see the dots
        # has the figures, and the dots themselves say which is which.
        it "says the verdict in words as well as in colour" do
          expect(html).to include('aria-label="not met"')
          expect(html).to include('aria-label="met"')
          expect(html).to include("0.00").and include("1.00")
        end

        it "lists the criteria as a list, so their number is announced" do
          expect(html).to include("<ol class=\"raaf-criteria\">")
          expect(html.scan('<li class="raaf-criterion">').size).to eq(2)
        end

        # `{"good":0.75,"used":"bad (<0.5)","average":0.5}` has to be parsed by
        # eye before it says anything.
        it "prints the thresholds as the sentence they are" do
          expect(html).to include("good ≥ 0.75 · average ≥ 0.5 · scored bad (&lt;0.5)")
          expect(html).not_to include("{&quot;good&quot;")
        end

        it "prints the judge's usage as labelled figures rather than JSON" do
          expect(html).to include("input tokens 693")
          expect(html).not_to include("{&quot;input_tokens&quot;")
        end

        # The list is the count, and printing it as well pairs a label with a
        # figure the reader can see.
        it "drops the criteria count once the criteria are on the screen" do
          expect(html).not_to include("Criteria count")
        end
      end
    end
  end
end
