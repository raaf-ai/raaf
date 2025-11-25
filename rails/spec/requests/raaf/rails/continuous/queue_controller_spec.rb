# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RAAF::Rails::Continuous::QueueController, type: :request do
  let(:policy) { EvaluationPolicy.create!(name: 'Test Policy', agent_name: 'TestAgent', evaluators: []) }

  describe "GET /raaf/rails/continuous/queue" do
    it "returns a successful response" do
      get raaf_rails_continuous_queue_index_path
      expect(response).to have_http_status(:success)
    end

    it "filters by status" do
      pending_item = EvaluationQueue.create!(
        evaluation_policy: policy,
        span_id: 'span-1',
        status: 'pending'
      )
      failed_item = EvaluationQueue.create!(
        evaluation_policy: policy,
        span_id: 'span-2',
        status: 'failed'
      )

      get raaf_rails_continuous_queue_index_path(status: 'failed')
      expect(response).to have_http_status(:success)
    end

    it "displays queue stats" do
      EvaluationQueue.create!(evaluation_policy: policy, span_id: 'span-1', status: 'pending')
      EvaluationQueue.create!(evaluation_policy: policy, span_id: 'span-2', status: 'running')
      EvaluationQueue.create!(evaluation_policy: policy, span_id: 'span-3', status: 'failed')

      get raaf_rails_continuous_queue_index_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /raaf/rails/continuous/queue/:id" do
    let(:queue_item) do
      EvaluationQueue.create!(
        evaluation_policy: policy,
        span_id: 'span-1',
        status: 'completed'
      )
    end

    it "returns a successful response" do
      get raaf_rails_continuous_queue_path(queue_item)
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /raaf/rails/continuous/queue/:id/retry" do
    let(:queue_item) do
      EvaluationQueue.create!(
        evaluation_policy: policy,
        span_id: 'span-1',
        status: 'failed',
        attempts: 3,
        error_message: 'Test error'
      )
    end

    it "requeues the failed item" do
      allow(RAAF::Eval::Continuous::EvaluationJob).to receive(:perform_later)

      post retry_raaf_rails_continuous_queue_path(queue_item)
      queue_item.reload

      expect(queue_item.status).to eq('pending')
      expect(queue_item.attempts).to eq(0)
      expect(queue_item.error_message).to be_nil
    end

    it "enqueues a new job" do
      expect(RAAF::Eval::Continuous::EvaluationJob).to receive(:perform_later).with(
        span_id: queue_item.span_id,
        policy_id: queue_item.evaluation_policy_id
      )

      post retry_raaf_rails_continuous_queue_path(queue_item)
    end

    it "redirects with success notice" do
      allow(RAAF::Eval::Continuous::EvaluationJob).to receive(:perform_later)

      post retry_raaf_rails_continuous_queue_path(queue_item)
      expect(response).to redirect_to(raaf_rails_continuous_queue_index_path)
      expect(flash[:notice]).to eq('Evaluation requeued.')
    end
  end

  describe "POST /raaf/rails/continuous/queue/:id/cancel" do
    let(:queue_item) do
      EvaluationQueue.create!(
        evaluation_policy: policy,
        span_id: 'span-1',
        status: 'pending'
      )
    end

    it "cancels the item" do
      post cancel_raaf_rails_continuous_queue_path(queue_item)
      queue_item.reload
      expect(queue_item.status).to eq('cancelled')
    end

    it "redirects with success notice" do
      post cancel_raaf_rails_continuous_queue_path(queue_item)
      expect(response).to redirect_to(raaf_rails_continuous_queue_index_path)
      expect(flash[:notice]).to eq('Evaluation cancelled.')
    end
  end

  describe "POST /raaf/rails/continuous/queue/retry_failed" do
    before do
      3.times do |i|
        EvaluationQueue.create!(
          evaluation_policy: policy,
          span_id: "span-#{i}",
          status: 'failed'
        )
      end
    end

    it "requeues all failed items" do
      allow(RAAF::Eval::Continuous::EvaluationJob).to receive(:perform_later)

      post retry_failed_raaf_rails_continuous_queue_index_path

      expect(EvaluationQueue.where(status: 'pending').count).to eq(3)
      expect(EvaluationQueue.where(status: 'failed').count).to eq(0)
    end

    it "redirects with count in notice" do
      allow(RAAF::Eval::Continuous::EvaluationJob).to receive(:perform_later)

      post retry_failed_raaf_rails_continuous_queue_index_path
      expect(response).to redirect_to(raaf_rails_continuous_queue_index_path)
      expect(flash[:notice]).to eq('3 evaluations requeued.')
    end
  end

  describe "DELETE /raaf/rails/continuous/queue/clear_completed" do
    before do
      2.times do |i|
        EvaluationQueue.create!(
          evaluation_policy: policy,
          span_id: "completed-#{i}",
          status: 'completed'
        )
      end
      EvaluationQueue.create!(evaluation_policy: policy, span_id: 'cancelled-1', status: 'cancelled')
      EvaluationQueue.create!(evaluation_policy: policy, span_id: 'pending-1', status: 'pending')
    end

    it "deletes completed and cancelled items" do
      expect {
        delete clear_completed_raaf_rails_continuous_queue_index_path
      }.to change(EvaluationQueue, :count).by(-3)
    end

    it "does not delete pending or running items" do
      delete clear_completed_raaf_rails_continuous_queue_index_path

      expect(EvaluationQueue.where(status: 'pending').count).to eq(1)
    end

    it "redirects with count in notice" do
      delete clear_completed_raaf_rails_continuous_queue_index_path
      expect(response).to redirect_to(raaf_rails_continuous_queue_index_path)
      expect(flash[:notice]).to eq('3 completed items cleared.')
    end
  end
end
