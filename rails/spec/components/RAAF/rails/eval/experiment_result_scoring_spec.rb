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

# An experiment result carried a bar per score dimension and nothing saying what
# the dimension asked. `quality:value_range 0.62` names where the number came
# from; it says nothing about what was being measured or what it had to clear,
# which is what a reader is trying to decide on.
module RAAF
  module Rails
    module Eval
      RSpec.describe ExperimentResultShow, type: :component do
        let(:declared) do
          [{ "field_name" => "quality", "evaluator_type" => "value_range",
             "check_type" => "rule_based", "display_name" => "Quality In Range",
             "description" => "The briefing scores between 0.0 and 1.0",
             "options" => { "min" => 0.0, "max" => 1.0 } }]
        end

        let(:metadata) { { "declared_checks" => declared } }
        let(:scores) { { "quality:value_range" => 0.62 } }
        let(:enabled_scorers) { [{ key: "b/quality:value_range", enabled: true }] }

        let(:experiment) do
          instance_double("Experiment", id: 3, name: "Briefing v2", agent_name: "Briefer",
                                        model: "gpt-4o", provider: "openai",
                                        dataset: instance_double("Dataset", name: "Briefings"),
                                        scorers: enabled_scorers)
        end

        let(:item) do
          instance_double("DatasetItem", id: 9, source_span_id: nil, input: { "topic" => "pricing" },
                                         expected_output: nil)
        end

        let(:result) do
          instance_double("ExperimentResult", id: 11, dataset_item_id: 9, dataset_item: item,
                                              status: "completed", scores: scores,
                                              overall_score: 0.62, output: { "content" => "a briefing" },
                                              error_message: nil, metadata: metadata,
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

        it "names the check rather than the key the score is stored under" do
          expect(html).to include("Quality In Range")
        end

        it "says what the check asks" do
          expect(html).to include("How this scores")
          expect(html).to include("The briefing scores between 0.0 and 1.0")
        end

        # 0.62 means one thing inside 0.0..1.0 and another inside 0.0..5.0.
        it "prints the numbers the check was given" do
          expect(html).to include("Min")
          expect(html).to include("Max")
        end

        context "when the result recorded no checks" do
          let(:metadata) { {} }

          it "falls back to the key, without claiming a rule it does not have" do
            expect(html).to include("quality · value range")
            expect(html).not_to include("How this scores")
          end
        end

        # An unscored case means opposite things depending on whether anybody
        # asked for it to be scored, and the screen used to say the same thing
        # either way.
        context "when nothing scored the case" do
          let(:scores) { {} }

          context "and the experiment names scorers" do
            it "says the scorers returned nothing" do
              expect(html).to include("names scorers")
            end
          end

          context "and the experiment names none" do
            let(:enabled_scorers) { [] }

            it "says nothing was ever asked to measure it" do
              expect(html).to include("No scorer is switched on")
            end
          end
        end
      end
    end
  end
end
