# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Queue Monitoring", type: :feature, js: true do
  # These tests verify the user workflow for monitoring and managing the
  # continuous evaluation queue through the RAAF Rails dashboard UI.

  let!(:policy) do
    EvaluationPolicy.create!(
      name: "Test Policy",
      agent_name: "TestAgent",
      sampling_mode: "percentage",
      sample_rate: 10,
      active: true,
      evaluators: []
    )
  end

  describe "Queue Overview" do
    before do
      # Create queue items with various statuses
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-pending-1",
        trace_id: "trace-1",
        status: "pending",
        priority: 50,
        scheduled_at: Time.current
      )
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-pending-2",
        trace_id: "trace-2",
        status: "pending",
        priority: 75,
        scheduled_at: Time.current
      )
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-running-1",
        trace_id: "trace-3",
        status: "running",
        priority: 50,
        started_at: Time.current
      )
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-completed-1",
        trace_id: "trace-4",
        status: "completed",
        completed_at: Time.current
      )
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-failed-1",
        trace_id: "trace-5",
        status: "failed",
        attempts: 3,
        error_message: "Timeout error",
        error_class: "TimeoutError"
      )
    end

    it "displays queue statistics summary" do
      visit raaf_rails_continuous_queue_index_path

      within ".queue-stats" do
        expect(page).to have_content("Pending")
        expect(page).to have_content("2")
        expect(page).to have_content("Running")
        expect(page).to have_content("1")
        expect(page).to have_content("Completed")
        expect(page).to have_content("1")
        expect(page).to have_content("Failed")
        expect(page).to have_content("1")
      end
    end

    it "displays queue items with status indicators" do
      visit raaf_rails_continuous_queue_index_path

      expect(page).to have_css(".status-pending", minimum: 2)
      expect(page).to have_css(".status-running", minimum: 1)
      expect(page).to have_css(".status-completed", minimum: 1)
      expect(page).to have_css(".status-failed", minimum: 1)
    end

    it "shows queue items in priority order" do
      visit raaf_rails_continuous_queue_index_path

      # Items should be sorted by priority (descending) then scheduled time
      within "tbody" do
        rows = page.all("tr")
        # High priority item should appear before lower priority
        expect(rows.first).to have_content("span-pending-2")
      end
    end

    it "displays item details including span ID, policy, and status" do
      visit raaf_rails_continuous_queue_index_path

      within "tbody tr:first-child" do
        expect(page).to have_content("span-")
        expect(page).to have_content("Test Policy")
        expect(page).to have_css(".badge, .status-badge")
      end
    end
  end

  describe "Queue Filtering" do
    before do
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-filter-pending",
        status: "pending"
      )
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-filter-failed",
        status: "failed"
      )
    end

    it "filters queue by pending status" do
      visit raaf_rails_continuous_queue_index_path

      select "Pending", from: "Status"
      click_button "Filter"

      expect(page).to have_content("span-filter-pending")
      expect(page).not_to have_content("span-filter-failed")
    end

    it "filters queue by failed status" do
      visit raaf_rails_continuous_queue_index_path(status: "failed")

      expect(page).to have_content("span-filter-failed")
      expect(page).not_to have_content("span-filter-pending")
    end

    it "filters queue by policy" do
      other_policy = EvaluationPolicy.create!(
        name: "Other Policy",
        agent_name: "OtherAgent",
        evaluators: []
      )

      EvaluationQueue.create!(
        evaluation_policy: other_policy,
        evaluation_policy_id: other_policy.id,
        span_id: "span-other-policy",
        status: "pending"
      )

      visit raaf_rails_continuous_queue_index_path(policy_id: policy.id)

      expect(page).to have_content("span-filter-pending")
      expect(page).not_to have_content("span-other-policy")
    end

    it "clears filters and shows all items" do
      visit raaf_rails_continuous_queue_index_path(status: "pending")

      click_link "Clear Filters"

      expect(page).to have_content("span-filter-pending")
      expect(page).to have_content("span-filter-failed")
    end
  end

  describe "Queue Item Details" do
    let!(:queue_item) do
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-details-1",
        trace_id: "trace-details-1",
        status: "completed",
        priority: 75,
        attempts: 1,
        scheduled_at: 5.minutes.ago,
        started_at: 4.minutes.ago,
        completed_at: 3.minutes.ago,
        metadata: { "source" => "webhook" }
      )
    end

    it "displays complete queue item information" do
      visit raaf_rails_continuous_queue_path(queue_item)

      expect(page).to have_content("span-details-1")
      expect(page).to have_content("trace-details-1")
      expect(page).to have_content("Test Policy")
      expect(page).to have_content("completed")
      expect(page).to have_content("75")
      expect(page).to have_content("1")
    end

    it "shows timing information" do
      visit raaf_rails_continuous_queue_path(queue_item)

      expect(page).to have_content("Scheduled")
      expect(page).to have_content("Started")
      expect(page).to have_content("Completed")
    end

    it "displays metadata if present" do
      visit raaf_rails_continuous_queue_path(queue_item)

      within ".metadata-section" do
        expect(page).to have_content("source")
        expect(page).to have_content("webhook")
      end
    end

    it "provides link to associated span" do
      visit raaf_rails_continuous_queue_path(queue_item)

      expect(page).to have_link("View Span", href: %r{/tracing/spans/})
    end

    it "shows evaluation results for completed items" do
      # Create associated result
      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        span_id: "span-details-1",
        evaluator_name: "token_limit",
        evaluator_type: "rule_based",
        status: "passed",
        score: 0.95,
        agent_name: "TestAgent"
      )

      visit raaf_rails_continuous_queue_path(queue_item)

      within ".evaluation-results" do
        expect(page).to have_content("token_limit")
        expect(page).to have_content("passed")
        expect(page).to have_content("0.95")
      end
    end
  end

  describe "Failed Item Details" do
    let!(:failed_item) do
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-failed-details",
        status: "failed",
        attempts: 3,
        error_message: "Connection timeout after 30 seconds",
        error_class: "Net::TimeoutError"
      )
    end

    it "displays error information for failed items" do
      visit raaf_rails_continuous_queue_path(failed_item)

      expect(page).to have_content("Net::TimeoutError")
      expect(page).to have_content("Connection timeout after 30 seconds")
      expect(page).to have_content("3 attempts")
    end

    it "provides retry button for failed items" do
      visit raaf_rails_continuous_queue_path(failed_item)

      expect(page).to have_button("Retry")
    end
  end

  describe "Retrying Failed Evaluations" do
    let!(:failed_item) do
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-retry-test",
        status: "failed",
        attempts: 3,
        error_message: "API error"
      )
    end

    before do
      # Mock the job enqueuing
      allow(RAAF::Eval::Continuous::EvaluationJob).to receive(:perform_later)
    end

    it "retries a single failed item from the detail page" do
      visit raaf_rails_continuous_queue_path(failed_item)

      click_button "Retry"

      expect(page).to have_content("Evaluation requeued")
      expect(page).to have_current_path(raaf_rails_continuous_queue_index_path)
    end

    it "resets attempt count when retrying" do
      visit raaf_rails_continuous_queue_path(failed_item)

      click_button "Retry"

      failed_item.reload
      expect(failed_item.attempts).to eq(0)
      expect(failed_item.status).to eq("pending")
      expect(failed_item.error_message).to be_nil
    end

    it "retries a failed item from the queue list" do
      visit raaf_rails_continuous_queue_index_path(status: "failed")

      within "[data-queue-item-id='#{failed_item.id}']" do
        click_button "Retry"
      end

      expect(page).to have_content("Evaluation requeued")
    end

    it "enqueues a new evaluation job" do
      expect(RAAF::Eval::Continuous::EvaluationJob).to receive(:perform_later).with(
        span_id: "span-retry-test",
        policy_id: policy.id
      )

      visit raaf_rails_continuous_queue_path(failed_item)
      click_button "Retry"
    end
  end

  describe "Bulk Retry All Failed" do
    before do
      3.times do |i|
        EvaluationQueue.create!(
          evaluation_policy: policy,
          evaluation_policy_id: policy.id,
          span_id: "span-bulk-fail-#{i}",
          status: "failed",
          error_message: "Bulk failure test"
        )
      end

      allow(RAAF::Eval::Continuous::EvaluationJob).to receive(:perform_later)
    end

    it "retries all failed items at once" do
      visit raaf_rails_continuous_queue_index_path

      click_button "Retry All Failed"

      expect(page).to have_content("3 evaluations requeued")
    end

    it "shows confirmation dialog before bulk retry" do
      visit raaf_rails_continuous_queue_index_path

      accept_confirm("Are you sure you want to retry all 3 failed evaluations?") do
        click_button "Retry All Failed"
      end

      expect(page).to have_content("evaluations requeued")
    end

    it "disables bulk retry button when no failed items" do
      # Clear failed items
      EvaluationQueue.records.select { |q| q.status == "failed" }.each do |item|
        item.status = "completed"
      end

      visit raaf_rails_continuous_queue_index_path

      expect(page).to have_button("Retry All Failed", disabled: true)
    end
  end

  describe "Cancelling Pending Evaluations" do
    let!(:pending_item) do
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-cancel-test",
        status: "pending"
      )
    end

    it "cancels a pending item from the detail page" do
      visit raaf_rails_continuous_queue_path(pending_item)

      click_button "Cancel"

      expect(page).to have_content("Evaluation cancelled")
      expect(page).to have_current_path(raaf_rails_continuous_queue_index_path)
    end

    it "updates item status to cancelled" do
      visit raaf_rails_continuous_queue_path(pending_item)

      click_button "Cancel"

      pending_item.reload
      expect(pending_item.status).to eq("cancelled")
    end

    it "cancels from queue list" do
      visit raaf_rails_continuous_queue_index_path

      within "[data-queue-item-id='#{pending_item.id}']" do
        click_button "Cancel"
      end

      expect(page).to have_content("Evaluation cancelled")
    end

    it "cannot cancel running or completed items" do
      pending_item.update!(status: "running")

      visit raaf_rails_continuous_queue_path(pending_item)

      expect(page).not_to have_button("Cancel")
    end
  end

  describe "Clearing Completed Items" do
    before do
      2.times do |i|
        EvaluationQueue.create!(
          evaluation_policy: policy,
          evaluation_policy_id: policy.id,
          span_id: "span-completed-#{i}",
          status: "completed"
        )
      end
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-cancelled-1",
        status: "cancelled"
      )
      EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-pending-1",
        status: "pending"
      )
    end

    it "clears completed and cancelled items" do
      visit raaf_rails_continuous_queue_index_path

      accept_confirm do
        click_button "Clear Completed"
      end

      expect(page).to have_content("3 completed items cleared")
    end

    it "preserves pending and running items" do
      visit raaf_rails_continuous_queue_index_path

      accept_confirm do
        click_button "Clear Completed"
      end

      expect(page).to have_content("span-pending-1")
      expect(page).not_to have_content("span-completed-")
    end

    it "updates queue statistics after clearing" do
      visit raaf_rails_continuous_queue_index_path

      accept_confirm do
        click_button "Clear Completed"
      end

      within ".queue-stats" do
        expect(page).to have_content("Completed")
        expect(page).to have_content("0")
      end
    end
  end

  describe "Real-time Updates" do
    it "updates queue display via Turbo Streams" do
      visit raaf_rails_continuous_queue_index_path

      # Simulate a new item being added via Turbo Stream
      expect(page).to have_css("[data-turbo-stream]", visible: false)
    end

    it "shows processing indicator for running items" do
      running_item = EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-running-indicator",
        status: "running",
        started_at: Time.current
      )

      visit raaf_rails_continuous_queue_index_path

      within "[data-queue-item-id='#{running_item.id}']" do
        expect(page).to have_css(".animate-pulse, .spinner, .loading-indicator")
      end
    end

    it "auto-refreshes queue statistics periodically" do
      visit raaf_rails_continuous_queue_index_path

      # Check for auto-refresh meta tag or Stimulus controller
      expect(page).to have_css("[data-controller*='auto-refresh'], meta[http-equiv='refresh']", visible: false)
    end
  end

  describe "Queue Pagination" do
    before do
      60.times do |i|
        EvaluationQueue.create!(
          evaluation_policy: policy,
          evaluation_policy_id: policy.id,
          span_id: "span-paginated-#{i}",
          status: "pending"
        )
      end
    end

    it "paginates queue items" do
      visit raaf_rails_continuous_queue_index_path

      expect(page).to have_css(".pagination")
      expect(page).to have_link("2")
      expect(page).to have_link("Next")
    end

    it "navigates between pages" do
      visit raaf_rails_continuous_queue_index_path

      click_link "2"

      expect(page).to have_current_path(raaf_rails_continuous_queue_index_path(page: 2))
    end

    it "preserves filters when paginating" do
      visit raaf_rails_continuous_queue_index_path(status: "pending")

      click_link "2"

      expect(page).to have_current_path(raaf_rails_continuous_queue_index_path(status: "pending", page: 2))
    end
  end

  describe "Error Handling" do
    it "handles missing queue item gracefully" do
      visit "/raaf/rails/continuous/queue/99999"

      expect(page).to have_content(/not found|does not exist/i)
    end

    it "shows error when retry fails" do
      failed_item = EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-retry-error",
        status: "failed"
      )

      allow(RAAF::Eval::Continuous::EvaluationJob).to receive(:perform_later)
        .and_raise(StandardError, "Job queue unavailable")

      visit raaf_rails_continuous_queue_path(failed_item)

      click_button "Retry"

      expect(page).to have_content(/error|failed/i)
    end
  end

  describe "Accessibility" do
    it "provides accessible status indicators" do
      pending_item = EvaluationQueue.create!(
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-a11y",
        status: "pending"
      )

      visit raaf_rails_continuous_queue_index_path

      within "[data-queue-item-id='#{pending_item.id}']" do
        expect(page).to have_css("[aria-label*='status'], [title*='status'], .sr-only")
      end
    end

    it "announces action results to screen readers" do
      visit raaf_rails_continuous_queue_index_path

      expect(page).to have_css("[role='alert'], [aria-live='polite']", visible: false)
    end
  end
end
