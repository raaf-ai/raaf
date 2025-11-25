# frozen_string_literal: true

RSpec.describe RAAF::Eval::Models::EvaluationQueueItem, type: :model do
  describe "validations" do
    it "requires span_id" do
      item = build(:evaluation_queue_item, span_id: nil)
      expect(item).not_to be_valid
      expect(item.errors[:span_id]).to include("can't be blank")
    end

    it "requires trace_id" do
      item = build(:evaluation_queue_item, trace_id: nil)
      expect(item).not_to be_valid
      expect(item.errors[:trace_id]).to include("can't be blank")
    end

    it "requires valid status" do
      item = build(:evaluation_queue_item, status: "invalid")
      expect(item).not_to be_valid
      expect(item.errors[:status]).to be_present
    end

    it "accepts valid status values" do
      %w[pending running completed failed cancelled].each do |status|
        item = build(:evaluation_queue_item, status: status)
        expect(item).to be_valid, "Expected status '#{status}' to be valid"
      end
    end
  end

  describe "scopes" do
    before do
      create(:evaluation_queue_item, status: "pending", priority: 50)
      create(:evaluation_queue_item, status: "pending", priority: 90)
      create(:evaluation_queue_item, :running)
      create(:evaluation_queue_item, :completed)
      create(:evaluation_queue_item, :failed)
    end

    it "returns pending items" do
      expect(described_class.pending.count).to eq(2)
    end

    it "returns running items" do
      expect(described_class.running.count).to eq(1)
    end

    it "returns completed items" do
      expect(described_class.completed.count).to eq(1)
    end

    it "returns failed items" do
      expect(described_class.failed.count).to eq(1)
    end

    it "returns processable items ordered by priority and scheduled_at" do
      processable = described_class.processable
      expect(processable.count).to eq(2) # Only pending items
      expect(processable.first.priority).to eq(90) # High priority first
    end

    it "returns retryable items" do
      item = create(:evaluation_queue_item, :retrying)
      expect(described_class.retryable.count).to eq(1)
    end
  end

  describe "state transitions" do
    let(:item) { create(:evaluation_queue_item) }

    describe "#start!" do
      it "transitions from pending to running" do
        expect { item.start! }.to change { item.status }.from("pending").to("running")
      end

      it "sets started_at timestamp" do
        item.start!
        expect(item.started_at).not_to be_nil
      end

      it "raises error if not pending" do
        item.update!(status: "completed")
        expect { item.start! }.to raise_error(RAAF::Eval::InvalidStateTransition)
      end
    end

    describe "#complete!" do
      before { item.start! }

      it "transitions from running to completed" do
        expect { item.complete! }.to change { item.status }.from("running").to("completed")
      end

      it "sets completed_at timestamp" do
        item.complete!
        expect(item.completed_at).not_to be_nil
      end
    end

    describe "#fail!" do
      before { item.start! }

      it "transitions from running to failed" do
        item.update!(attempts: 3)
        expect { item.fail!("Error message") }.to change { item.status }.from("running").to("failed")
      end

      it "records error information" do
        item.fail!("Test error", "TestError")
        expect(item.error_message).to eq("Test error")
        expect(item.error_class).to eq("TestError")
      end

      it "schedules retry if attempts remaining" do
        item.fail!("Error")
        expect(item.status).to eq("pending")
        expect(item.next_retry_at).not_to be_nil
      end

      it "marks as failed when max attempts reached" do
        item.update!(attempts: 2, max_attempts: 3)
        item.fail!("Error")
        expect(item.status).to eq("failed")
      end
    end

    describe "#cancel!" do
      it "transitions to cancelled from pending" do
        expect { item.cancel! }.to change { item.status }.to("cancelled")
      end

      it "transitions to cancelled from running" do
        item.start!
        expect { item.cancel! }.to change { item.status }.to("cancelled")
      end

      it "sets completed_at timestamp" do
        item.cancel!
        expect(item.completed_at).not_to be_nil
      end
    end

    describe "#retry!" do
      let(:item) { create(:evaluation_queue_item, :failed) }

      it "resets status to pending" do
        item.retry!
        expect(item.status).to eq("pending")
      end

      it "clears error information" do
        item.retry!
        expect(item.error_message).to be_nil
        expect(item.error_class).to be_nil
      end

      it "resets attempts counter" do
        item.retry!
        expect(item.attempts).to eq(0)
      end
    end
  end

  describe "#increment_attempts!" do
    let(:item) { create(:evaluation_queue_item, attempts: 0) }

    it "increments attempts counter" do
      expect { item.increment_attempts! }.to change { item.attempts }.by(1)
    end
  end

  describe "#can_retry?" do
    it "returns true when attempts < max_attempts" do
      item = build(:evaluation_queue_item, attempts: 1, max_attempts: 3)
      expect(item.can_retry?).to be true
    end

    it "returns false when attempts >= max_attempts" do
      item = build(:evaluation_queue_item, attempts: 3, max_attempts: 3)
      expect(item.can_retry?).to be false
    end
  end

  describe "#schedule_retry!" do
    let(:item) { create(:evaluation_queue_item, :running, attempts: 1) }

    it "sets next_retry_at with exponential backoff" do
      item.schedule_retry!
      expect(item.next_retry_at).to be > Time.current
    end

    it "increases backoff with more attempts" do
      item.schedule_retry!
      first_retry = item.next_retry_at

      item.update!(attempts: 3)
      item.schedule_retry!
      second_retry = item.next_retry_at

      expect(second_retry - Time.current).to be > (first_retry - Time.current)
    end
  end

  describe "#duration" do
    it "returns nil when not started" do
      item = build(:evaluation_queue_item)
      expect(item.duration).to be_nil
    end

    it "returns nil when not completed" do
      item = build(:evaluation_queue_item, :running)
      expect(item.duration).to be_nil
    end

    it "calculates duration when both timestamps present" do
      item = build(:evaluation_queue_item, :completed,
                   started_at: 1.minute.ago,
                   completed_at: Time.current)
      expect(item.duration).to be_within(1).of(60)
    end
  end

  describe "associations" do
    let(:item) { create(:evaluation_queue_item) }

    it "belongs to evaluation_policy" do
      expect(item.evaluation_policy).to be_a(RAAF::Eval::Models::EvaluationPolicy)
    end

    it "has many evaluation results" do
      result = create(:continuous_evaluation_result, evaluation_queue_item: item)
      expect(item.continuous_evaluation_results).to include(result)
    end
  end
end
