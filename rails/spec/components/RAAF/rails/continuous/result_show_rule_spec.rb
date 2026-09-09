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

# A continuous result records the field it graded and the number it came out
# with. What was asked of that field — the rule's name, the sentence behind it,
# the bounds it had to sit inside — is declared on the evaluator, and none of it
# used to reach this screen. So `confidence 1.00` read as an agent that was
# certain, when it says only that the agent returned a number between 0 and 1.
module RAAF
  module Rails
    module Continuous
      RSpec.describe ResultShow, type: :component do
        # What `EvaluatorDefinition.evaluated_checks` hands back for the
        # AccountBriefing evaluator's confidence field.
        let(:confidence_check) do
          { field_name: :confidence, evaluator_type: :value_range, check_type: :rule_based,
            display_name: "Confidence In Range",
            description: "Confidence is between 0.0 and 1.0",
            options: { min: 0.0, max: 1.0, threshold_good: 0.99, threshold_average: 0.9 } }
        end

        let(:checks) { [confidence_check] }

        let(:evaluator_class) do
          instance_double("EvaluatorClass", display_name: "Account Briefing",
                                            description: "Checks the briefing has a summary",
                                            evaluated_checks: checks)
        end

        let(:details) do
          { "field_name" => "confidence",
            "result" => {
              "label" => "good", "score" => 1.0,
              "message" => "[GOOD] 1/1 values within 0.0..1.0",
              "details" => { "total" => 1, "in_range" => 1, "out_of_range" => 0,
                             "missing" => 0, "range" => "0.0..1.0", "offending_sample" => [] }
            } }
        end

        let(:result) do
          instance_double(
            "ContinuousEvaluationResult",
            id: 526, span_id: "span_0148", trace_id: "trace_6eda", status: "good",
            score: 1.0, scores: { "confidence" => 1.0 }, agent_name: "AccountBriefing",
            model: nil, provider: nil, environment: "development",
            evaluator_name: "intelligence_account_briefing", evaluator_type: "rule_based",
            evaluator_version: nil, evaluation_policy: nil, evaluation_policy_id: nil,
            evaluation_queue_item: nil, reasoning: "[GOOD] 1/1 values within 0.0..1.0",
            details: details, metadata: {}, metrics: nil, created_at: Time.now,
            evaluation_started_at: Time.now, evaluation_completed_at: Time.now,
            evaluation_duration_ms: 0.4
          )
        end

        # The two Rails view helpers this screen reaches for through Phlex.
        # Neither is what is being tested, and without an application there is
        # no view context to answer them.
        let(:view_context) do
          instance_double("ActionView::Base").tap do |context|
            allow(context).to receive(:time_ago_in_words).and_return("2 hours")
            allow(context).to receive(:pluralize) { |count, word| "#{count} #{word}s" }
          end
        end

        let(:html) do
          stub_const("RAAF::Eval::Continuous::EvaluatorDiscovery", discovery)
          component = described_class.new(result: result)
          allow(component).to receive(:view_context).and_return(view_context)
          component.call
        end

        let(:discovery) { class_double("EvaluatorDiscovery", build: evaluator_class) }

        # A row is one check now, so its score arrives keyed `field:evaluator`
        # rather than by the field alone -- see EvaluationJob#store_check_result.
        context "when the row records one check's own verdict" do
          let(:details) do
            { "field_name" => "confidence", "check_key" => "confidence:value_range",
              "result" => { "label" => "good", "score" => 1.0,
                            "message" => "[GOOD] 1/1 values within 0.0..1.0" } }
          end

          let(:result) do
            instance_double(
              "ContinuousEvaluationResult",
              id: 526, span_id: "span_0148", trace_id: "trace_6eda", status: "good",
              score: 1.0, scores: { "confidence:value_range" => 1.0 },
              agent_name: "AccountBriefing", model: nil, provider: nil,
              environment: "development", evaluator_name: "intelligence_account_briefing",
              evaluator_type: "rule_based", evaluator_version: nil, evaluation_policy: nil,
              evaluation_policy_id: nil, evaluation_queue_item: nil,
              reasoning: "[GOOD] 1/1 values within 0.0..1.0", details: details,
              metadata: { "field_name" => "confidence", "check_name" => "confidence:value_range" },
              metrics: nil, created_at: Time.now, evaluation_started_at: Time.now,
              evaluation_completed_at: Time.now, evaluation_duration_ms: 0.4
            )
          end

          it "still names the rule the score came from" do
            expect(html).to include("Confidence In Range")
          end
        end

        it "names the rule that produced the number, not the field it read" do
          expect(html).to include("Confidence In Range")
        end

        it "says what the rule asks" do
          expect(html).to include("How this scores")
          expect(html).to include("Confidence is between 0.0 and 1.0")
        end

        # The scorer is the arithmetic. Without it the parameters below read as
        # four unattached numbers and there is nothing to go and read the
        # formula in.
        it "names the scorer beside the rule" do
          expect(html).to include("value range")
        end

        # 1.00 was scored "good" because the rule declares 0.99 as the bar. That
        # threshold is the whole reason the verdict is what it is.
        it "prints the numbers the rule was given" do
          expect(html).to include("0.99")
          expect(html).to include("Threshold good")
        end

        # A scorer shared by two agents is told which attribute holds an item's
        # identity, because the agents name it differently. That is wiring, not
        # a bound the verdict was reached against, and the identities it picks
        # out are already printed beside the items that failed — so listing it
        # here puts a label under "How this scores" with no figure to pair it
        # with.
        context "when a check was configured with where to find an item's id" do
          let(:confidence_check) do
            { field_name: :confidence, evaluator_type: :value_range, check_type: :rule_based,
              display_name: "Confidence In Range",
              description: "Confidence is between 0.0 and 1.0",
              options: { min: 0.0, max: 1.0, threshold_good: 0.99, id_key: :tender_canonical_key } }
          end

          it "does not list the attribute among what the rule asks" do
            expect(html).not_to include("Id key")
            expect(html).not_to include("tender_canonical_key")
          end

          it "still prints the bounds beside it" do
            expect(html).to include("Threshold good")
          end
        end

        # The bars are still read off `scores`, which is keyed by field, so the
        # subtitle keeps saying which field they came from.
        it "still says which field was graded" do
          expect(html).to include("one check, on confidence")
        end

        context "when the evaluator declares several checks on the field" do
          let(:checks) do
            [confidence_check,
             { field_name: :confidence, evaluator_type: :completeness, check_type: :rule_based,
               display_name: "Confidence Present", description: "A confidence was returned",
               options: { threshold: 1.0 } }]
          end

          # Which of the two graded this row is not recorded anywhere, and
          # putting the wrong rule's name and bounds under the figures would be
          # worse than leaving them bare.
          it "leaves the rule unnamed rather than guessing between them" do
            expect(html).not_to include("Confidence In Range")
            expect(html).not_to include("Confidence Present")
          end
        end

        # `off_scale: []` is the check's best possible answer: nothing was off
        # the scale. Printed blank it came out as the em dash the screen uses
        # for a measurement nobody took, so a clean result and an unmeasured
        # one were the same two characters.
        context "when a check found none of what it looks for" do
          let(:details) do
            { "field_name" => "confidence",
              "result" => {
                "label" => "good", "score" => 1.0, "message" => "[GOOD] all on scale",
                "details" => { "total" => 15, "off_scale" => [], "unreasoned" => [],
                               "distribution" => {} }
              } }
          end

          it "says none rather than printing a dash" do
            expect(html).to include("none")
          end

          it "keeps the count that was measured beside it" do
            expect(html).to include("15")
          end
        end

        context "when the evaluator can no longer be read back" do
          let(:discovery) do
            class_double("EvaluatorDiscovery").tap do |double|
              allow(double).to receive(:build).and_raise(NameError, "gone")
            end
          end

          it "renders the verdict without a rule under it" do
            expect(html).to include("Check breakdown")
            expect(html).to include("confidence")
          end

          # An empty section reads as a check with nothing to explain, which is
          # the one thing this is not.
          it "says the rule is unrecoverable rather than showing nothing" do
            expect(html).to include("can no longer be read back")
          end
        end

        # The row records what was asked of it when it was graded. Reading that
        # back beats asking the evaluator of the same name today, which is a
        # different object whenever anybody has touched it since.
        context "when the result stored the checks it was graded against" do
          let(:details) do
            super().merge(
              "declared_checks" => [
                { "field_name" => "confidence", "evaluator_type" => "value_range",
                  "check_type" => "rule_based", "display_name" => "Confidence In Range",
                  "description" => "Confidence is between 0.0 and 1.0",
                  "options" => { "min" => 0.0, "max" => 1.0, "threshold_good" => 0.99 } }
              ]
            )
          end

          context "and the evaluator is gone" do
            let(:discovery) do
              class_double("EvaluatorDiscovery").tap do |double|
                allow(double).to receive(:build).and_raise(NameError, "gone")
              end
            end

            it "still says what the rule asked" do
              expect(html).to include("How this scores")
              expect(html).to include("Confidence is between 0.0 and 1.0")
              expect(html).to include("0.99")
            end

            it "makes no claim that the rule is unrecoverable" do
              expect(html).not_to include("can no longer be read back")
            end
          end

          # A bound widened after this result was scored would otherwise be
          # printed under a verdict that was never held to it.
          context "and the evaluator has since been changed" do
            let(:checks) do
              [confidence_check.merge(description: "Confidence is between 0.0 and 5.0",
                                      options: { min: 0.0, max: 5.0 })]
            end

            it "prints the rule the verdict was actually reached against" do
              expect(html).to include("Confidence is between 0.0 and 1.0")
              expect(html).not_to include("Confidence is between 0.0 and 5.0")
            end
          end
        end
      end
    end
  end
end
