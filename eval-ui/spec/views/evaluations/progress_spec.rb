# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'raaf/eval/ui/evaluations/_progress.html.erb', type: :view do
  let(:session) do
    RAAF::Eval::UI::Session.create!(
      name: "Test Evaluation",
      session_type: "draft",
      status: "running"
    )
  end

  before do
    assign(:evaluation, session)
  end

  describe 'progress bar' do
    it 'renders progress bar with percentage' do
      allow(session).to receive(:progress_percentage).and_return(45)
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_css('[role="progressbar"][aria-valuenow="45"]')
      expect(rendered).to have_text('45%')
    end

    it 'applies correct color for running status' do
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_css('.bg-blue-500')
    end

    it 'applies correct color for completed status' do
      session.update(status: 'completed')
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_css('.bg-green-500')
    end

    it 'applies correct color for failed status' do
      session.update(status: 'failed')
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_css('.bg-red-500')
    end
  end

  describe 'status messages' do
    it 'displays running message when status is running' do
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_text('Evaluation is currently running')
    end

    it 'displays pending message when status is pending' do
      session.update(status: 'pending')
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_text('Evaluation is queued')
    end

    it 'displays completed message when status is completed' do
      session.update(status: 'completed', started_at: 1.minute.ago, completed_at: Time.current)
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_text('Evaluation Completed Successfully')
    end

    it 'displays failed message when status is failed' do
      session.update(status: 'failed')
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_text('Evaluation failed')
    end
  end

  describe 'current step display' do
    it 'shows current step when available' do
      allow(session).to receive(:current_step).and_return('Calculating metrics...')
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_text('Calculating metrics...')
    end

    it 'does not show step section when no current step' do
      allow(session).to receive(:current_step).and_return(nil)
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).not_to have_css('p.text-xs.text-gray-600', text: /step/i)
    end
  end

  describe 'estimated time remaining' do
    it 'displays estimated time when available and running' do
      allow(session).to receive(:estimated_time_remaining).and_return(120)
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_text('Estimated time remaining')
      expect(rendered).to have_text('2 minutes')
    end

    it 'does not display time remaining when completed' do
      session.update(status: 'completed', started_at: 2.minutes.ago, completed_at: Time.current)
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).not_to have_text('Estimated time remaining')
    end

    it 'does not display time remaining when not available' do
      allow(session).to receive(:estimated_time_remaining).and_return(nil)
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).not_to have_text('Estimated time remaining')
    end
  end

  describe 'error display' do
    it 'shows error message when status is failed' do
      session.update(
        status: 'failed',
        error_message: 'API timeout error'
      )
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_css('.bg-red-50')
      expect(rendered).to have_text('Evaluation Failed')
      expect(rendered).to have_text('API timeout error')
    end

    it 'shows retry button when retry count is below limit' do
      session.update(
        status: 'failed',
        error_message: 'Temporary error',
        metadata: { 'retry_count' => 1 }
      )
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_button('Retry Evaluation')
    end

    it 'does not show retry button when retry limit reached' do
      session.update(
        status: 'failed',
        error_message: 'Persistent error',
        metadata: { 'retry_count' => 3 }
      )
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).not_to have_button('Retry Evaluation')
    end
  end

  describe 'completion display' do
    it 'shows success message and view results button when completed' do
      session.update(status: 'completed')
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_css('.bg-green-50')
      expect(rendered).to have_text('Evaluation Completed Successfully')
      expect(rendered).to have_link('View Results')
    end
  end

  describe 'cancel button' do
    it 'shows cancel button when running' do
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_button('Cancel')
    end

    it 'shows cancel button when pending' do
      session.update(status: 'pending')
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_button('Cancel')
    end

    it 'does not show cancel button when completed' do
      session.update(status: 'completed')
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).not_to have_button('Cancel')
    end

    it 'does not show cancel button when failed' do
      session.update(status: 'failed')
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).not_to have_button('Cancel')
    end
  end

  describe 'partial metrics' do
    it 'displays partial metrics when available and running' do
      allow(session).to receive(:partial_metrics).and_return({
        'tokens' => 50,
        'latency_ms' => 1200
      })
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_text('Interim Metrics')
      expect(rendered).to have_text('Tokens')
      expect(rendered).to have_text('50')
      expect(rendered).to have_text('Latency ms')
      expect(rendered).to have_text('1200')
    end

    it 'does not display metrics section when no partial metrics' do
      allow(session).to receive(:partial_metrics).and_return({})
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).not_to have_text('Interim Metrics')
    end
  end

  describe 'Turbo Stream support' do
    it 'includes Stimulus controller data attributes' do
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_css('[data-controller="evaluation-progress"]')
      expect(rendered).to have_css('[data-evaluation-progress-status-value="running"]')
    end

    it 'has evaluation_progress id for Turbo Stream targeting' do
      render partial: 'raaf/eval/ui/evaluations/progress', locals: { evaluation: session }

      expect(rendered).to have_css('#evaluation_progress')
    end
  end
end
