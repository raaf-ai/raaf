# frozen_string_literal: true

RSpec.describe RAAF::Eval::ExperimentEngine do
  let(:engine) { described_class.new }

  describe "#create_experiment" do
    let(:dataset) { create(:dataset) }

    it "creates an experiment with given configuration" do
      experiment = engine.create_experiment(
        name: "Test Experiment",
        dataset: dataset,
        agent_name: "TestAgent",
        model: "gpt-4o",
        configuration: { temperature: 0.5 }
      )

      expect(experiment).to be_persisted
      expect(experiment.name).to eq("Test Experiment")
      expect(experiment.dataset).to eq(dataset)
      expect(experiment.model).to eq("gpt-4o")
    end
  end

  describe "#run_experiment" do
    let(:dataset) { create(:dataset) }
    let(:experiment) { create(:experiment, dataset: dataset) }

    before do
      3.times do |i|
        create(:dataset_item, dataset: dataset, input: { messages: [{ role: "user", content: "Q#{i}" }] })
      end
    end

    it "runs dry experiment against all items" do
      result = engine.run_experiment(experiment)

      expect(result.status).to eq("completed")
      expect(result.completed_items).to eq(3)
      expect(result.experiment_results.count).to eq(3)
    end

    it "accepts custom scoring block" do
      engine.run_experiment(experiment) do |_item, _output|
        { custom_score: 0.95 }
      end

      scores = experiment.experiment_results.map { |r| r.scores["custom_score"] }
      expect(scores).to all(eq(0.95))
    end

    # The console runs an experiment with no block, and used to record every
    # case unscored — which is why an experiment's results could be counted but
    # never judged.
    context "when the experiment names its own scorers" do
      before do
        experiment.update!(configuration: {
                             "scorers" => [{ "key" => "briefing/quality:value_range",
                                             "evaluator" => "briefing",
                                             "check" => "quality:value_range",
                                             "enabled" => true, "weight" => 1.0 }]
                           })

        evaluator = instance_double(RAAF::Eval::DSL::Evaluator)
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:build).and_return(evaluator)
        allow(evaluator).to receive(:evaluate).and_return(
          instance_double(RAAF::Eval::DSL::EvaluationResult,
                          field_results: { quality: { score: 0.75 } })
        )
      end

      it "scores every case with them, without being handed a block" do
        engine.run_experiment(experiment)

        scores = experiment.experiment_results.map { |r| r.scores["quality:value_range"] }
        expect(scores).to all(eq(0.75))
      end

      it "gives the run an overall score the screens can order and colour by" do
        engine.run_experiment(experiment)

        expect(experiment.experiment_results.map(&:overall_score)).to all(eq(0.75))
      end

      # A block passed in is the caller being explicit, and stays in charge.
      it "yields to a block the caller brings" do
        engine.run_experiment(experiment) { |_item, _output| { custom_score: 0.1 } }

        expect(experiment.experiment_results.map { |r| r.scores.keys }.flatten.uniq)
          .to eq(["custom_score"])
      end
    end
  end

  describe "#compare_experiments" do
    let(:dataset) { create(:dataset) }
    let(:item) { create(:dataset_item, dataset: dataset) }

    it "compares two experiments" do
      exp_a = create(:experiment, dataset: dataset, model: "gpt-4o", status: "completed",
                                  aggregate_metrics: { "success_rate" => 95.0, "scores" => { "relevance" => { "avg" => 0.85 } },
                                                       "tokens" => { "total_tokens" => 500 } })
      exp_b = create(:experiment, dataset: dataset, model: "claude-3-5-sonnet", status: "completed",
                                  aggregate_metrics: { "success_rate" => 98.0, "scores" => { "relevance" => { "avg" => 0.90 } },
                                                       "tokens" => { "total_tokens" => 450 } })

      comparison = engine.compare_experiments(exp_a, exp_b)

      expect(comparison[:experiments][:a][:model]).to eq("gpt-4o")
      expect(comparison[:experiments][:b][:model]).to eq("claude-3-5-sonnet")
      expect(comparison[:metrics_comparison][:success_rate][:delta]).to eq(3.0)
    end
  end
end
