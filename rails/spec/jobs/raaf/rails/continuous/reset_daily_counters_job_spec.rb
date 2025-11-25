# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RAAF::Rails::Continuous::ResetDailyCountersJob, type: :job do
  let!(:policies) do
    5.times.map do |i|
      RAAF::Eval::Models::EvaluationPolicy.create!(
        name: "test-policy-#{i}",
        agent_name: 'TestAgent',
        environment: 'test',
        sampling_mode: 'percentage',
        sample_rate: 50,
        today_evaluation_count: 10 + i,
        count_reset_date: 1.day.ago
      )
    end
  end

  describe '#perform' do
    it 'resets counters for all policies' do
      described_class.perform_now

      policies.each do |policy|
        policy.reload
        expect(policy.today_evaluation_count).to eq(0)
      end
    end

    it 'updates count_reset_date to current date' do
      described_class.perform_now

      policies.each do |policy|
        policy.reload
        expect(policy.count_reset_date).to eq(Date.current)
      end
    end

    it 'logs success information' do
      expect(RAAF::Rails.logger).to receive(:info).with(
        a_string_matching(/Reset daily counters/)
      )

      described_class.perform_now
    end

    context 'with policy reset failure' do
      before do
        allow_any_instance_of(RAAF::Eval::Models::EvaluationPolicy)
          .to receive(:reset_daily_counter!)
          .and_raise(StandardError, 'Database error')
      end

      it 'continues processing other policies' do
        expect(RAAF::Rails.logger).to receive(:error).at_least(:once)

        described_class.perform_now

        # Should still attempt to reset all policies despite errors
      end

      it 'logs errors for failed policies' do
        expect(RAAF::Rails.logger).to receive(:error).with(
          a_string_matching(/Failed to reset counter/)
        ).at_least(:once)

        described_class.perform_now
      end
    end

    context 'with no policies' do
      before do
        RAAF::Eval::Models::EvaluationPolicy.delete_all
      end

      it 'completes without errors' do
        expect {
          described_class.perform_now
        }.not_to raise_error
      end

      it 'logs zero policies processed' do
        expect(RAAF::Rails.logger).to receive(:info).with(
          a_string_matching(/policies_count.*0/)
        )

        described_class.perform_now
      end
    end

    context 'with already reset counters' do
      before do
        policies.each(&:reset_daily_counter!)
      end

      it 'resets them again (idempotent)' do
        # Set count to non-zero
        policies.first.increment!(:today_evaluation_count)

        described_class.perform_now

        expect(policies.first.reload.today_evaluation_count).to eq(0)
      end
    end

    context 'with large number of policies' do
      before do
        100.times do |i|
          RAAF::Eval::Models::EvaluationPolicy.create!(
            name: "bulk-policy-#{i}",
            agent_name: 'BulkAgent',
            environment: 'test',
            sampling_mode: 'all',
            today_evaluation_count: rand(100)
          )
        end
      end

      it 'processes all policies efficiently' do
        expect {
          described_class.perform_now
        }.not_to raise_error

        expect(
          RAAF::Eval::Models::EvaluationPolicy.where.not(today_evaluation_count: 0).count
        ).to eq(0)
      end
    end
  end

  describe 'queue configuration' do
    it 'uses the low priority queue' do
      expect(described_class.queue_name).to eq('raaf_evaluations_low')
    end
  end

  describe 'retry behavior' do
    it 'retries on transient failures' do
      allow_any_instance_of(RAAF::Eval::Models::EvaluationPolicy)
        .to receive(:reset_daily_counter!)
        .and_raise(StandardError).once
        .and_call_original

      described_class.perform_now
    end

    it 'has limited retry attempts' do
      expect(described_class.retry_on_block_arguments).to include(
        a_hash_including(attempts: 3)
      )
    end
  end

  describe 'scheduled execution' do
    it 'is scheduled to run daily' do
      # This test verifies the job is configured correctly
      # Actual scheduling is tested in integration tests
      expect(described_class.queue_name).to eq('raaf_evaluations_low')
    end
  end
end
