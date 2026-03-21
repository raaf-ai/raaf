# frozen_string_literal: true

RSpec.describe RAAF::Eval::Models::Experiment, type: :model do
  describe "validations" do
    it "requires name" do
      experiment = build(:experiment, name: nil)
      expect(experiment).not_to be_valid
    end

    it "requires valid status" do
      experiment = build(:experiment, status: "invalid")
      expect(experiment).not_to be_valid
    end

    it "accepts valid status values" do
      %w[pending running completed failed cancelled].each do |status|
        experiment = build(:experiment, status: status)
        expect(experiment).to be_valid
      end
    end
  end

  describe "state transitions" do
    let(:dataset) { create(:dataset, items_count: 5) }
    let(:experiment) { create(:experiment, dataset: dataset) }

    it "can start an experiment" do
      experiment.start!
      expect(experiment.status).to eq("running")
      expect(experiment.started_at).not_to be_nil
      expect(experiment.total_items).to eq(5)
    end

    it "can complete an experiment" do
      experiment.start!
      experiment.complete!
      expect(experiment.status).to eq("completed")
      expect(experiment.completed_at).not_to be_nil
    end

    it "can fail an experiment" do
      experiment.start!
      experiment.fail!("Something went wrong")
      expect(experiment.status).to eq("failed")
    end

    it "can cancel an experiment" do
      experiment.start!
      experiment.cancel!
      expect(experiment.status).to eq("cancelled")
    end
  end

  describe "#record_result!" do
    let(:experiment) { create(:experiment) }
    let(:dataset_item) { create(:dataset_item, dataset: experiment.dataset) }

    it "creates a result and increments completed count" do
      result = experiment.record_result!(
        dataset_item: dataset_item,
        output: { content: "Test response" },
        scores: { relevance: 0.9 },
        token_metrics: { total_tokens: 100 }
      )

      expect(result).to be_persisted
      expect(result.status).to eq("completed")
      expect(experiment.reload.completed_items).to eq(1)
    end
  end

  describe "#record_failure!" do
    let(:experiment) { create(:experiment) }
    let(:dataset_item) { create(:dataset_item, dataset: experiment.dataset) }

    it "creates a failed result and increments failed count" do
      result = experiment.record_failure!(
        dataset_item: dataset_item,
        error: "API timeout"
      )

      expect(result.status).to eq("failed")
      expect(result.error_message).to eq("API timeout")
      expect(experiment.reload.failed_items).to eq(1)
    end
  end

  describe "#progress_percentage" do
    let(:experiment) { create(:experiment, total_items: 10, completed_items: 3, failed_items: 2) }

    it "calculates progress correctly" do
      expect(experiment.progress_percentage).to eq(50.0)
    end

    it "returns 0 for no items" do
      experiment.update!(total_items: 0)
      expect(experiment.progress_percentage).to eq(0.0)
    end
  end

  describe "#average_score" do
    let(:experiment) { create(:experiment) }

    before do
      item1 = create(:dataset_item, dataset: experiment.dataset)
      item2 = create(:dataset_item, dataset: experiment.dataset)
      create(:experiment_result, experiment: experiment, dataset_item: item1, scores: { "relevance" => 0.8 })
      create(:experiment_result, experiment: experiment, dataset_item: item2, scores: { "relevance" => 0.6 })
    end

    it "calculates average for a specific score" do
      expect(experiment.average_score("relevance")).to be_within(0.01).of(0.7)
    end
  end

  describe "#duration" do
    it "calculates duration when timestamps present" do
      experiment = create(:experiment)
      experiment.update!(started_at: Time.current, completed_at: Time.current + 30.seconds)
      expect(experiment.duration).to be_within(0.1).of(30.0)
    end

    it "returns nil without timestamps" do
      experiment = create(:experiment)
      expect(experiment.duration).to be_nil
    end
  end

  describe "status checks" do
    it "identifies in_progress experiments" do
      experiment = create(:experiment, status: "running")
      expect(experiment).to be_in_progress
    end

    it "identifies finished experiments" do
      %w[completed failed cancelled].each do |status|
        experiment = create(:experiment, status: status)
        expect(experiment).to be_finished
      end
    end
  end

  describe "scopes" do
    it "filters by dataset" do
      dataset = create(:dataset)
      exp = create(:experiment, dataset: dataset)
      create(:experiment)

      expect(described_class.for_dataset(dataset)).to eq([exp])
    end

    it "filters by agent" do
      exp = create(:experiment, agent_name: "MyAgent")
      create(:experiment, agent_name: "OtherAgent")

      expect(described_class.for_agent("MyAgent")).to eq([exp])
    end
  end
end
