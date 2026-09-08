# frozen_string_literal: true

# The overall score was the mean of a jsonb hash, averaged in Ruby on every
# read, so the results table could only order by recency. "Show me the worst
# twenty cases" — which is how a run is actually read — could be asked of the
# rows already loaded or of nothing at all.
RSpec.describe RAAF::Eval::Models::ExperimentResult do
  let(:dataset) { create(:dataset) }
  let(:experiment) { create(:experiment, dataset: dataset) }

  def result_with(scores, status: "completed")
    create(:experiment_result, experiment: experiment,
                               dataset_item: create(:dataset_item, dataset: dataset),
                               scores: scores, status: status)
  end

  describe "the stored score" do
    it "is written when the result is saved" do
      result = result_with({ "quality" => 0.8, "latency" => 0.4 })

      expect(result[:overall_score]).to be_within(0.0001).of(0.6)
    end

    it "follows the scores when they change" do
      result = result_with({ "quality" => 0.2 })
      result.update!(scores: { "quality" => 0.9 })

      expect(result[:overall_score]).to be_within(0.0001).of(0.9)
    end

    it "stays empty for a result nothing scored" do
      expect(result_with({})[:overall_score]).to be_nil
    end

    # A row saved before the column existed is still scored, and reading it as
    # unscored would drop it off every screen at once.
    it "is averaged out of the hash for a row that has none" do
      result = result_with({ "quality" => 0.5 })
      described_class.where(id: result.id).update_all(overall_score: nil)

      expect(result.reload.overall_score).to be_within(0.0001).of(0.5)
    end
  end

  describe ".worst_first" do
    it "orders the run by score, lowest first" do
      result_with({ "quality" => 0.9 })
      result_with({ "quality" => 0.1 })
      result_with({ "quality" => 0.5 })

      expect(experiment.experiment_results.worst_first.map(&:overall_score))
        .to eq([0.1, 0.5, 0.9])
    end

    # An unscored case has no verdict to rank, and putting it first would bury
    # the failures under cases nobody measured.
    it "puts a case without a score last" do
      result_with({})
      scored = result_with({ "quality" => 0.3 })

      expect(experiment.experiment_results.worst_first.first).to eq(scored)
    end
  end

  describe ".scoring_below" do
    it "asks the whole run rather than the page in front of you" do
      result_with({ "quality" => 0.9 })
      failing = result_with({ "quality" => 0.2 })

      expect(experiment.experiment_results.scoring_below(0.5)).to contain_exactly(failing)
    end

    it "leaves out a case that has no score to be below anything" do
      result_with({})

      expect(experiment.experiment_results.scoring_below(0.5)).to be_empty
    end
  end

  # RAAF's migrations are copied into a host application by hand, so a console
  # can run ahead of its own database. Asking for an ordering the database
  # cannot give should leave the page unsorted, not broken.
  describe "a database without the column" do
    before { allow(described_class).to receive(:overall_score_stored?).and_return(false) }

    it "falls back to newest first rather than raising" do
      result_with({ "quality" => 0.9 })

      expect { experiment.experiment_results.worst_first.to_a }.not_to raise_error
    end

    it "answers the below-the-line filter with nothing rather than raising" do
      result_with({ "quality" => 0.1 })

      expect(experiment.experiment_results.scoring_below(0.5)).to be_empty
    end
  end
end
