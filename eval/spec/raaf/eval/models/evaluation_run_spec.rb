# frozen_string_literal: true

RSpec.describe RAAF::Eval::Models::EvaluationRun, type: :model do
  describe "validations" do
    it "requires name" do
      run = build(:evaluation_run, name: nil)
      expect(run).not_to be_valid
      expect(run.errors[:name]).to include("can't be blank")
    end

    it "requires baseline_span_id" do
      run = build(:evaluation_run, baseline_span_id: nil)
      expect(run).not_to be_valid
    end

    it "requires valid status" do
      run = build(:evaluation_run, status: "invalid")
      expect(run).not_to be_valid
    end

    it "accepts valid status values" do
      %w[pending running completed failed cancelled].each do |status|
        run = build(:evaluation_run, status: status)
        expect(run).to be_valid
      end
    end
  end

  describe "state transitions" do
    let(:run) { create(:evaluation_run) }

    it "can start a run" do
      expect { run.start! }.to change { run.status }.from("pending").to("running")
      expect(run.started_at).not_to be_nil
    end

    it "can complete a run" do
      run.start!
      expect { run.complete! }.to change { run.status }.to("completed")
      expect(run.completed_at).not_to be_nil
    end

    it "can fail a run" do
      run.start!
      expect { run.fail!("Error occurred") }.to change { run.status }.to("failed")
      expect(run.completed_at).not_to be_nil
    end
  end

  describe "#duration" do
    it "calculates duration when both timestamps present" do
      run = create(:evaluation_run)
      run.update!(started_at: Time.current, completed_at: Time.current + 10.seconds)
      
      expect(run.duration).to be_within(0.1).of(10.0)
    end

    it "returns nil when timestamps missing" do
      run = create(:evaluation_run)
      expect(run.duration).to be_nil
    end
  end

  describe "status checks" do
    it "identifies in_progress runs" do
      run = create(:evaluation_run, status: "running")
      expect(run).to be_in_progress
    end

    it "identifies finished runs" do
      run = create(:evaluation_run, status: "completed")
      expect(run).to be_finished

      run.update!(status: "failed")
      expect(run).to be_finished
    end
  end
end
