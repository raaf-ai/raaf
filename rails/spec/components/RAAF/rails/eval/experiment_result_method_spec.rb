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
require File.expand_path("../../../../../app/components/RAAF/rails/eval/experiment_result_show", __dir__)

# An experiment takes its checks from several evaluators at once, so one case
# is routinely graded by a judge and a rule together. The bars said only that
# both came out around 0.6.
module RAAF
  module Rails
    module Eval
      RSpec.describe ExperimentResultShow, type: :component do
        let(:rule) do
          { "field_name" => "quality", "evaluator_type" => "value_range",
            "check_type" => "rule_based", "display_name" => "Quality In Range" }
        end

        let(:judge) do
          { "field_name" => "tone", "evaluator_type" => "llm_judge",
            "check_type" => "llm_judge", "display_name" => "Tone Fits" }
        end

        let(:declared) { [rule] }
        let(:scores) { { "quality:value_range" => 0.62 } }

        let(:experiment) do
          instance_double("Experiment", id: 3, name: "Briefing v2", agent_name: "Briefer",
                                        model: "gpt-4o", provider: "openai",
                                        dataset: instance_double("Dataset", name: "Briefings"),
                                        scorers: [{ key: "b/quality:value_range", enabled: true }])
        end

        let(:item) do
          instance_double("DatasetItem", id: 9, source_span_id: nil, input: { "topic" => "pricing" },
                                         expected_output: nil)
        end

        let(:result) do
          instance_double("ExperimentResult", id: 11, dataset_item_id: 9, dataset_item: item,
                                              status: "completed", scores: scores,
                                              overall_score: 0.62, output: { "content" => "a briefing" },
                                              error_message: nil,
                                              metadata: { "declared_checks" => declared },
                                              token_metrics: {}, latency_metrics: {},
                                              duration: 1.2, duration_seconds: 1.2,
                                              started_at: Time.now, completed_at: Time.now,
                                              result_trace_id: nil, result_span_id: nil)
        end

        let(:view_context) do
          instance_double("ActionView::Base").tap do |context|
            allow(context).to receive(:time_ago_in_words).and_return("2 hours")
            allow(context).to receive(:pluralize) { |count, word| "#{count} #{word}s" }
          end
        end

        let(:html) do
          component = described_class.new(experiment: experiment, result: result)
          allow(component).to receive(:view_context).and_return(view_context)
          component.call
        end

        it "says what did the scoring, beside what it scored" do
          expect(html).to include("Rule-based")
        end

        context "when a judge and a rule graded the same case" do
          let(:declared) { [rule, judge] }
          let(:scores) { { "quality:value_range" => 0.62, "tone:llm_judge" => 0.8 } }

          it "heads the case as mixed rather than picking one" do
            expect(html).to include("Mixed")
          end

          it "names the method on each bar" do
            expect(html).to include("Rule-based")
            expect(html).to include("LLM judge")
          end
        end

        # A run whose bars are all the same kind is headed once; repeating it
        # down the column says nothing.
        it "leaves the bars unlabelled where they agree" do
          expect(html).not_to include("raaf-meter-lead")
        end

        context "when the result recorded no checks" do
          let(:declared) { [] }

          it "claims no method it was not told" do
            expect(html).not_to include("Rule-based")
            expect(html).not_to include("LLM judge")
          end
        end
      end
    end
  end
end
