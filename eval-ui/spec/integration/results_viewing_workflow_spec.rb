# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Results Viewing Workflow', type: :system do
  let(:baseline_data) do
    {
      'agent_name' => 'TestAgent',
      'model' => 'gpt-4o',
      'output_messages' => [
        { 'role' => 'assistant', 'content' => 'Original response from baseline' }
      ],
      'metadata' => {
        'tokens' => { 'total' => 100, 'input' => 50, 'output' => 50 },
        'cost' => { 'total' => 0.002 },
        'latency_ms' => 1500
      }
    }
  end

  let(:new_result_data) do
    {
      'agent_name' => 'TestAgent',
      'model' => 'gpt-4o',
      'output_messages' => [
        { 'role' => 'assistant', 'content' => 'Modified response with new settings' }
      ],
      'metadata' => {
        'tokens' => { 'total' => 120, 'input' => 50, 'output' => 70 },
        'cost' => { 'total' => 0.0024 },
        'latency_ms' => 1300
      }
    }
  end

  let(:baseline_span) do
    create(:evaluation_span, span_data: baseline_data)
  end

  let(:evaluation) do
    create(:evaluation_session,
      name: 'Temperature Comparison',
      baseline_span_id: baseline_span.id,
      status: 'completed',
      metadata: { 'new_result' => new_result_data }
    )
  end

  it 'displays side-by-side comparison with three columns' do
    visit raaf_eval_ui.results_evaluation_path(evaluation)

    expect(page).to have_css('.results-comparison')
    expect(page).to have_content('Baseline')
    expect(page).to have_content('New Result')
    expect(page).to have_content('Metrics')
  end

  it 'highlights differences between baseline and new result' do
    visit raaf_eval_ui.results_evaluation_path(evaluation)

    # Additions should be highlighted in green
    expect(page).to have_css('.additions', text: /Modified response/)

    # Deletions should be highlighted in red
    expect(page).to have_css('.deletions', text: /Original response/)
  end

  it 'displays metrics comparison with delta indicators' do
    visit raaf_eval_ui.results_evaluation_path(evaluation)

    # Token count increased
    expect(page).to have_content('100 → 120')
    expect(page).to have_css('.text-orange-600', text: '↑')

    # Cost increased
    expect(page).to have_content('$0.0020 → $0.0024')
    expect(page).to have_css('.text-red-600', text: '↑')

    # Latency decreased (improvement)
    expect(page).to have_content('1500ms → 1300ms')
    expect(page).to have_css('.text-green-600', text: '↓')
  end

  it 'allows toggling between line-by-line and unified diff' do
    visit raaf_eval_ui.results_evaluation_path(evaluation)

    # Default is line-by-line
    expect(page).to have_css('.diff-line-by-line')

    # User toggles to unified diff
    click_button 'Unified View'

    expect(page).to have_css('.diff-unified')
  end

  it 'allows expanding and collapsing sections' do
    visit raaf_eval_ui.results_evaluation_path(evaluation)

    # Messages section is expanded by default
    expect(page).to have_css('details[open]', text: /Messages/)

    # User collapses messages section
    find('summary', text: /Messages/).click

    expect(page).not_to have_css('details[open]', text: /Messages/)
  end

  it 'displays expandable tool calls if present' do
    baseline_span.update!(
      span_data: baseline_data.merge(
        'tool_calls' => [
          {
            'name' => 'search_tool',
            'arguments' => { 'query' => 'test' },
            'result' => 'Search results'
          }
        ]
      )
    )

    visit raaf_eval_ui.results_evaluation_path(evaluation)

    expect(page).to have_content('Tool Calls (1)')

    # User expands tool calls
    find('summary', text: /Tool Calls/).click

    expect(page).to have_content('search_tool')
    expect(page).to have_content('Search results')
  end

  it 'allows copying outputs to clipboard' do
    visit raaf_eval_ui.results_evaluation_path(evaluation)

    # User clicks copy button for baseline
    find('.baseline-output').find('button', text: 'Copy').click

    # Success message appears (would need JS test for full verification)
    expect(page).to have_css('[data-action*="clipboard"]')
  end

  it 'allows saving evaluation as session' do
    visit raaf_eval_ui.results_evaluation_path(evaluation)

    click_button 'Save Session'

    # Modal appears
    expect(page).to have_content('Save Evaluation Session')

    fill_in 'Session Name', with: 'My Saved Evaluation'
    click_button 'Save'

    # Success message
    expect(page).to have_content('Session saved successfully')
  end

  it 'displays regression indicators for metrics' do
    # Make the new result worse than baseline
    worse_result = new_result_data.deep_dup
    worse_result['metadata']['cost']['total'] = 0.005
    worse_result['metadata']['latency_ms'] = 3000

    evaluation.update!(metadata: { 'new_result' => worse_result })

    visit raaf_eval_ui.results_evaluation_path(evaluation)

    # Warning indicators for regressions
    expect(page).to have_css('.regression-indicator', count: 2) # Cost and latency
    expect(page).to have_content('⚠️')
  end

  it 'allows exporting results as JSON' do
    visit raaf_eval_ui.results_evaluation_path(evaluation)

    click_button 'Export Results'

    # Export modal appears
    expect(page).to have_content('Export Format')

    choose 'JSON'
    click_button 'Download'

    # Download is triggered (would need more specific test for file download)
  end

  it 'shows statistical significance badges when applicable' do
    visit raaf_eval_ui.results_evaluation_path(evaluation)

    # If difference is statistically significant
    expect(page).to have_css('.significance-badge')
  end
end
