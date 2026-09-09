# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Continuous::QueueController, type: :request do
  let(:policy) { create_policy }

  describe "GET /raaf/continuous/queue" do
    it "returns a successful response" do
      get continuous_queue_index_path
      expect(response).to have_http_status(:success)
    end

    it "counts the jobs a worker is waiting on" do
      create_queue_job

      get continuous_queue_index_path

      expect(response.body).to include("Queued")
      expect(response.body).to include("jobs awaiting a worker")
    end

    # The ledger is the audit trail. It says what RAAF decided to run, which is
    # not what this screen is about.
    it "counts nothing from RAAF's ledger" do
      create_queue_item(evaluation_policy: policy, span_id: "span-1", status: "failed")

      get continuous_queue_index_path(format: :json)

      expect(response.parsed_body["counts"]["failed"]).to eq(0)
    end
  end

  describe "GET /raaf/continuous/queue/:id" do
    let(:queue_item) do
      create_queue_item(
        evaluation_policy: policy,
        span_id: "span-1",
        status: "completed"
      )
    end

    it "returns a successful response" do
      get continuous_queue_path(queue_item)
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /raaf/continuous/queue/:id/retry" do
    let(:queue_item) do
      create_queue_item(
        evaluation_policy: policy,
        span_id: "span-1",
        status: "failed",
        attempts: 3,
        error_message: "Test error"
      )
    end

    it "requeues the failed item" do
      allow(RAAF::Rails::Continuous::EvaluationJob).to receive(:perform_later)

      post retry_continuous_queue_path(queue_item)
      queue_item.reload

      expect(queue_item.status).to eq("pending")
      expect(queue_item.attempts).to eq(0)
      expect(queue_item.error_message).to be_nil
    end

    it "enqueues a new job" do
      expect(RAAF::Rails::Continuous::EvaluationJob).to receive(:perform_later).with(
        span_id: queue_item.span_id,
        policy_id: queue_item.evaluation_policy_id
      )

      post retry_continuous_queue_path(queue_item)
    end

    it "redirects with success notice" do
      allow(RAAF::Rails::Continuous::EvaluationJob).to receive(:perform_later)

      post retry_continuous_queue_path(queue_item)
      expect(response).to redirect_to(continuous_queue_index_path)
      expect(flash[:notice]).to eq("Evaluation requeued.")
    end
  end

  describe "POST /raaf/continuous/queue/:id/cancel" do
    let(:queue_item) do
      create_queue_item(
        evaluation_policy: policy,
        span_id: "span-1",
        status: "pending"
      )
    end

    it "cancels the item" do
      post cancel_continuous_queue_path(queue_item)
      queue_item.reload
      expect(queue_item.status).to eq("cancelled")
    end

    it "redirects with success notice" do
      post cancel_continuous_queue_path(queue_item)
      expect(response).to redirect_to(continuous_queue_index_path)
      expect(flash[:notice]).to eq("Evaluation cancelled.")
    end
  end

  # The Failed card counts SolidQueue rows -- jobs a worker gave up on. Its
  # buttons used to move `EvaluationQueueItem` rows instead, so requeueing did
  # not act on the failures the card had just listed.
  describe "POST /raaf/continuous/queue/retry_failed" do
    it "puts back exactly the jobs the Failed card lists" do
      jobs = Array.new(3) { |index| create_failed_job(span_id: "span-#{index}") }

      post retry_failed_continuous_queue_index_path

      expect(SolidQueue::FailedExecution.count).to eq(0)
      expect(SolidQueue::ReadyExecution.where(job_id: jobs.map(&:id)).count).to eq(3)
    end

    it "leaves a failure in another application's queue alone" do
      create_failed_job(queue_name: "host_default")

      post retry_failed_continuous_queue_index_path

      expect(SolidQueue::FailedExecution.count).to eq(1)
    end

    it "does not touch RAAF's ledger, which is no longer what it acts on" do
      create_failed_job
      item = create_queue_item(evaluation_policy: policy, span_id: "span-1", status: "failed")

      post retry_failed_continuous_queue_index_path

      expect(item.reload.status).to eq("failed")
    end

    it "redirects with what it requeued" do
      2.times { create_failed_job }

      post retry_failed_continuous_queue_index_path

      expect(response).to redirect_to(continuous_queue_index_path)
      expect(flash[:notice]).to eq("2 failed jobs requeued.")
    end

    it "says so when there was nothing to requeue" do
      post retry_failed_continuous_queue_index_path

      expect(flash[:notice]).to eq("0 failed jobs requeued.")
    end
  end

  describe "DELETE /raaf/continuous/queue/discard_failed" do
    it "drops the failed jobs and the jobs behind them" do
      2.times { create_failed_job }

      delete discard_failed_continuous_queue_index_path

      expect(SolidQueue::FailedExecution.count).to eq(0)
      expect(SolidQueue::Job.count).to eq(0)
    end

    it "leaves a job that has not failed alone" do
      create_queue_job

      delete discard_failed_continuous_queue_index_path

      expect(SolidQueue::Job.count).to eq(1)
    end

    it "redirects with what it discarded" do
      create_failed_job

      delete discard_failed_continuous_queue_index_path

      expect(response).to redirect_to(continuous_queue_index_path)
      expect(flash[:notice]).to eq("1 failed job discarded.")
    end
  end

  describe "GET /raaf/continuous/queue.json" do
    it "answers from the source the screen draws" do
      create_failed_job(span_id: "span-json")

      get continuous_queue_index_path(format: :json)

      expect(response.parsed_body["counts"]["failed"]).to eq(1)
      expect(response.parsed_body["failed"].first["span_id"]).to eq("span-json")
    end
  end
end
