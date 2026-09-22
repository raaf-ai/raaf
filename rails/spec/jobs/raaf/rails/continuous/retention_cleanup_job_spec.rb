# frozen_string_literal: true

require "rails_helper"

# The two sweeps in this job do not agree on when a row is old, and the database
# has an opinion about that disagreement: raaf_evaluation_results.queue_item_id
# is a foreign key with no ON DELETE, and delete_all does not run the model's
# +dependent: :nullify+. So the queue sweep has to leave anything the result
# sweep decided to keep.
RSpec.describe RAAF::Rails::Continuous::RetentionCleanupJob, type: :job do
  subject(:cleanup) { described_class.perform_now }

  describe "a finished queue item whose results are still within their own retention" do
    let!(:queue_item) do
      create_queue_item(status: "completed", completed_at: 30.days.ago, evaluation_policy_id: nil)
    end

    let!(:result) { create_result(queue_item_id: queue_item.to_param, created_at: 1.day.ago) }

    it "is kept, rather than raising ForeignKeyViolation", :aggregate_failures do
      expect { cleanup }.not_to raise_error

      expect(queue_item.reload).to be_persisted
      expect(result.reload).to be_persisted
    end

    it "still lets the rest of the sweep report its counts" do
      expect(cleanup).to include(queue_items_deleted: 0)
    end
  end

  describe "a failed queue item whose results survive" do
    let!(:queue_item) do
      create_queue_item(status: "failed", completed_at: 30.days.ago, evaluation_policy_id: nil)
    end

    before { create_result(queue_item_id: queue_item.to_param, created_at: 1.day.ago) }

    it "is kept too" do
      expect { cleanup }.not_to raise_error
      expect(queue_item.reload).to be_persisted
    end
  end

  describe "a finished queue item nothing points at" do
    let!(:queue_item) do
      create_queue_item(status: "completed", completed_at: 30.days.ago, evaluation_policy_id: nil)
    end

    it "is deleted on its own retention" do
      expect(cleanup).to include(queue_items_deleted: 1)
      expect(RAAF::Eval::Models::EvaluationQueueItem.exists?(queue_item.id)).to be(false)
    end

    # A result written before the column existed carries NULL there, and a NULL
    # inside a NOT IN subquery makes the whole comparison unknown -- every queue
    # item would then look referenced and nothing would ever be swept.
    it "is still deleted when unrelated results carry a NULL queue_item_id" do
      create_result(queue_item_id: nil, created_at: 1.day.ago)

      expect(cleanup).to include(queue_items_deleted: 1)
    end
  end

  describe "a queue item whose results have already aged out" do
    let!(:queue_item) do
      create_queue_item(status: "completed", completed_at: 30.days.ago, evaluation_policy_id: nil)
    end

    before { create_result(queue_item_id: queue_item.to_param, created_at: 60.days.ago) }

    it "goes in the same sweep, once the result sweep has removed them" do
      expect(cleanup).to include(results_deleted: 1, queue_items_deleted: 1)
    end
  end
end
