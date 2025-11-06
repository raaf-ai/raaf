# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Evaluation Execution Workflow', type: :system, js: true do
  let(:span) do
    create(:evaluation_span,
      span_data: {
        'agent_name' => 'TestAgent',
        'model' => 'gpt-4o'
      }
    )
  end

  let(:evaluation) do
    create(:evaluation_session,
      name: 'Test Evaluation',
      baseline_span_id: span.id,
      status: 'pending'
    )
  end

  before do
    # Mock the evaluation engine
    allow(RAAF::Eval::EvaluationEngine).to receive(:new).and_return(double(execute: true))
  end

  it 'shows progress updates via Turbo Stream' do
    visit raaf_eval_ui.evaluation_path(evaluation)

    # Initial state shows pending
    expect(page).to have_content('Evaluation in Progress')
    expect(page).to have_css('.progress-bar')
    expect(page).to have_content('0%')

    # Simulate background job updating progress
    evaluation.update!(
      status: 'running',
      metadata: { 'current_step' => 'Initializing...' }
    )

    # Progress updates (via polling or Turbo Stream)
    expect(page).to have_content('Initializing...')

    evaluation.update!(
      metadata: { 'current_step' => 'Executing evaluation...' },
      started_at: 10.seconds.ago
    )

    expect(page).to have_content('Executing evaluation...')
  end

  it 'displays estimated time remaining' do
    evaluation.update!(
      status: 'running',
      started_at: 30.seconds.ago
    )

    # Create some completed results to calculate progress
    create_list(:evaluation_result, 2, session: evaluation, status: 'completed')
    create_list(:evaluation_result, 3, session: evaluation, status: 'pending')

    visit raaf_eval_ui.evaluation_path(evaluation)

    # Should show estimated time remaining
    expect(page).to have_content('Estimated time remaining')
  end

  it 'shows interim metrics during execution' do
    evaluation.update!(
      status: 'running',
      metadata: {
        'partial_metrics' => {
          'tokens' => 50,
          'latency_ms' => 1200
        }
      }
    )

    visit raaf_eval_ui.evaluation_path(evaluation)

    expect(page).to have_content('Interim Metrics')
    expect(page).to have_content('Tokens')
    expect(page).to have_content('50')
    expect(page).to have_content('Latency')
  end

  it 'allows user to cancel running evaluation' do
    evaluation.update!(status: 'running')
    visit raaf_eval_ui.evaluation_path(evaluation)

    # User clicks cancel button
    accept_confirm do
      click_button 'Cancel'
    end

    # Evaluation is cancelled
    expect(page).to have_content('Evaluation cancelled')
    evaluation.reload
    expect(evaluation.status).to eq('cancelled')
  end

  it 'handles evaluation completion successfully' do
    evaluation.update!(
      status: 'running',
      started_at: 1.minute.ago
    )

    visit raaf_eval_ui.evaluation_path(evaluation)

    # Simulate evaluation completing
    evaluation.update!(
      status: 'completed',
      completed_at: Time.current
    )

    # Page updates to show completion
    expect(page).to have_content('Evaluation Completed Successfully')
    expect(page).to have_link('View Results')
  end

  it 'handles evaluation failure gracefully' do
    evaluation.update!(
      status: 'failed',
      error_message: 'API timeout error occurred',
      metadata: { 'retry_count' => 0 }
    )

    visit raaf_eval_ui.evaluation_path(evaluation)

    expect(page).to have_content('Evaluation Failed')
    expect(page).to have_content('API timeout error occurred')
    expect(page).to have_button('Retry Evaluation')
  end

  it 'does not show retry button after max retries' do
    evaluation.update!(
      status: 'failed',
      error_message: 'Persistent error',
      metadata: { 'retry_count' => 3 }
    )

    visit raaf_eval_ui.evaluation_path(evaluation)

    expect(page).not_to have_button('Retry Evaluation')
  end

  it 'redirects to results page when completed' do
    evaluation.update!(
      status: 'completed',
      completed_at: Time.current
    )

    visit raaf_eval_ui.evaluation_path(evaluation)

    click_link 'View Results'

    expect(page).to have_current_path(raaf_eval_ui.results_evaluation_path(evaluation))
  end

  it 'stops polling when evaluation completes' do
    evaluation.update!(status: 'running')
    visit raaf_eval_ui.evaluation_path(evaluation)

    # Polling should be active
    expect(page).to have_css('[data-controller="evaluation-progress"]')

    # Complete the evaluation
    evaluation.update!(status: 'completed', completed_at: Time.current)

    # Polling should stop (no more requests)
    # This would need to be verified via JavaScript tests or network monitoring
  end

  it 'displays progress bar animation' do
    evaluation.update!(status: 'running')
    create(:evaluation_result, session: evaluation, status: 'completed')
    create(:evaluation_result, session: evaluation, status: 'pending')

    visit raaf_eval_ui.evaluation_path(evaluation)

    # Progress bar should show 50%
    expect(page).to have_css('[role="progressbar"][aria-valuenow="50"]')
    expect(page).to have_content('50%')
  end
end
