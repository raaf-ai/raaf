# frozen_string_literal: true

# An experiment has been able to name its scorers since the edit screen was
# built, and nothing read the list. The console ran experiments with no scoring
# block, so every case was recorded with an empty scores hash and every screen
# showed a dash where the verdict belonged.
RSpec.describe RAAF::Eval::ExperimentScorer do
  let(:dataset) { create(:dataset) }
  let(:item) do
    create(:dataset_item, dataset: dataset,
                          input: { "topic" => "pricing" },
                          expected_output: { "summary" => "a summary" })
  end

  let(:scorers) do
    [{ "key" => "briefing/quality:value_range", "evaluator" => "briefing",
       "check" => "quality:value_range", "enabled" => true, "weight" => 1.0 }]
  end

  let(:experiment) do
    create(:experiment, dataset: dataset, agent_name: "Briefer",
                        configuration: { "scorers" => scorers })
  end

  let(:output) { { content: "the answer", "confidence" => 0.7 } }

  # What an evaluator hands back: a verdict per field it graded.
  def evaluation(fields)
    instance_double(RAAF::Eval::DSL::EvaluationResult, field_results: fields)
  end

  def stub_evaluator(result)
    evaluator = instance_double(RAAF::Eval::DSL::Evaluator)
    allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build).and_return(evaluator)
    allow(evaluator).to receive(:evaluate).and_return(result)
    evaluator
  end

  describe "#scorable?" do
    it "is true when the experiment names a scorer" do
      expect(described_class.new(experiment).scorable?).to be(true)
    end

    # No block is not the same as a block that returns nothing. An experiment
    # nobody chose scorers for should record that it was never graded, rather
    # than look like one that scored zero everywhere.
    it "is false when the experiment names none" do
      experiment.update!(configuration: {})

      expect(described_class.new(experiment).scorable?).to be(false)
    end

    it "is false when every scorer it names is switched off" do
      experiment.update!(configuration: { "scorers" => [scorers.first.merge("enabled" => false)] })

      expect(described_class.new(experiment).scorable?).to be(false)
    end
  end

  describe "#call" do
    it "scores the case under the check's own name" do
      stub_evaluator(evaluation({ quality: { score: 0.82, label: "good" } }))

      expect(described_class.new(experiment).call(item, output))
        .to eq({ "quality:value_range" => 0.82 })
    end

    # A check names the field ahead of the colon and the evaluator that graded
    # it after. The result is keyed by field alone.
    it "reads the field named ahead of the colon" do
      stub_evaluator(evaluation({ "quality" => { "score" => 0.4 } }))

      expect(described_class.new(experiment).call(item, output))
        .to eq({ "quality:value_range" => 0.4 })
    end

    it "leaves out a check the evaluator returned no field for" do
      stub_evaluator(evaluation({ latency: { score: 0.9 } }))

      expect(described_class.new(experiment).call(item, output)).to eq({})
    end

    # A scorer that breaks is not a case that failed. Recording zero would say
    # the agent answered badly when what broke was the measurement.
    it "records nothing for an evaluator that raised" do
      evaluator = instance_double(RAAF::Eval::DSL::Evaluator)
      allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build).and_return(evaluator)
      allow(evaluator).to receive(:evaluate).and_raise(StandardError, "judge is down")

      expect(described_class.new(experiment).call(item, output)).to eq({})
    end

    it "runs one evaluator once for every check taken from it" do
      experiment.update!(configuration: { "scorers" => [
                           scorers.first,
                           { "key" => "briefing/latency:threshold", "evaluator" => "briefing",
                             "check" => "latency:threshold", "enabled" => true, "weight" => 1.0 }
                         ] })
      evaluator = stub_evaluator(evaluation({ quality: { score: 0.5 }, latency: { score: 0.6 } }))

      result = described_class.new(experiment).call(item, output)

      expect(evaluator).to have_received(:evaluate).once
      expect(result).to eq({ "quality:value_range" => 0.5, "latency:threshold" => 0.6 })
    end

    # The evaluators are handed the shape the continuous job builds out of a
    # span, so one cannot tell whether it is grading production traffic or a
    # dataset case.
    it "hands the evaluator the agent's answer and what was expected of it" do
      evaluator = stub_evaluator(evaluation({ quality: { score: 1.0 } }))

      described_class.new(experiment).call(item, output)

      expect(evaluator).to have_received(:evaluate) do |subject|
        expect(subject[:agent_name]).to eq("Briefer")
        expect(subject[:output_text]).to eq("the answer")
        expect(subject[:expected_output]).to include("summary" => "a summary")
        expect(subject[:confidence]).to eq(0.7)
      end
    end
  end
end
