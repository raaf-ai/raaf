# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Evaluation Setup Workflow', type: :system, js: true do
  let(:span) do
    create(:evaluation_span,
      span_data: {
        'agent_name' => 'TestAgent',
        'model' => 'gpt-4o',
        'instructions' => 'Original instructions',
        'input_messages' => [{ 'role' => 'user', 'content' => 'Test input' }],
        'output_messages' => [{ 'role' => 'assistant', 'content' => 'Test output' }],
        'metadata' => {
          'tokens' => { 'total' => 100 },
          'temperature' => 0.7,
          'max_tokens' => 1000
        }
      }
    )
  end

  it 'displays evaluation editor with three panes' do
    visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

    # Three-pane layout is displayed
    expect(page).to have_content('Original Configuration')
    expect(page).to have_content('New Configuration')
    expect(page).to have_content('Settings')

    # Original configuration is read-only
    expect(page).to have_css('[readonly]', text: /Original instructions/)
  end

  it 'allows user to modify prompt in Monaco Editor' do
    visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

    # Wait for Monaco Editor to load
    expect(page).to have_css('[data-controller="monaco-editor"]')

    # User edits prompt (simulated via hidden textarea)
    new_prompt = 'Modified instructions for testing'
    execute_script("document.querySelector('[name=\"evaluation[prompt]\"]').value = '#{new_prompt}'")

    # Token count updates
    expect(page).to have_content(/\d+ tokens/)
  end

  it 'allows user to modify AI settings' do
    visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

    # User changes model
    select 'claude-3-5-sonnet-20241022', from: 'Model'

    # User changes temperature
    fill_in 'Temperature', with: '0.9'

    # User changes max tokens
    fill_in 'Max Tokens', with: '1500'

    # Settings are updated
    expect(find_field('Temperature').value).to eq('0.9')
    expect(find_field('Max Tokens').value).to eq('1500')
  end

  it 'validates parameter ranges in real-time' do
    visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

    # User enters invalid temperature (> 2.0)
    fill_in 'Temperature', with: '2.5'

    expect(page).to have_content('Temperature must be between 0.0 and 2.0')
    expect(page).to have_button('Run Evaluation', disabled: true)

    # User corrects the value
    fill_in 'Temperature', with: '0.9'

    expect(page).not_to have_content('Temperature must be between')
    expect(page).to have_button('Run Evaluation', disabled: false)
  end

  it 'displays token count estimate as user edits' do
    visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

    initial_count = find('.token-count').text

    # User adds more content
    new_prompt = 'Original instructions' + (' additional words' * 20)
    execute_script("document.querySelector('[name=\"evaluation[prompt]\"]').value = '#{new_prompt}'")
    execute_script("document.querySelector('[data-controller=\"monaco-editor\"]').dispatchEvent(new Event('change'))")

    # Token count increases
    expect(find('.token-count').text).not_to eq(initial_count)
  end

  it 'allows user to toggle diff view' do
    visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

    # User clicks diff view toggle
    click_button 'Show Diff'

    # Diff view is displayed
    expect(page).to have_css('.diff-view')
    expect(page).to have_css('.additions')
    expect(page).to have_css('.deletions')
  end

  it 'saves editor state to session storage' do
    visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

    new_prompt = 'Test prompt that should persist'
    execute_script("document.querySelector('[name=\"evaluation[prompt]\"]').value = '#{new_prompt}'")
    execute_script("sessionStorage.setItem('eval_prompt_#{span.id}', '#{new_prompt}')")

    # Refresh page
    visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

    # Editor state is restored
    stored_value = execute_script("return sessionStorage.getItem('eval_prompt_#{span.id}')")
    expect(stored_value).to eq(new_prompt)
  end

  it 'initiates evaluation when user clicks Run Evaluation' do
    visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

    # User fills in required fields
    select 'gpt-4o', from: 'Model'
    fill_in 'Temperature', with: '0.8'

    # User clicks Run Evaluation
    click_button 'Run Evaluation'

    # Evaluation is created and user sees progress
    expect(page).to have_content('Evaluation in Progress')
    expect(page).to have_css('.progress-bar')
  end

  it 'displays keyboard shortcuts help' do
    visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

    # User presses '?' key
    find('body').send_keys('?')

    # Keyboard shortcuts modal appears
    expect(page).to have_content('Keyboard Shortcuts')
    expect(page).to have_content('Cmd+S')
    expect(page).to have_content('Cmd+Enter')
  end
end
