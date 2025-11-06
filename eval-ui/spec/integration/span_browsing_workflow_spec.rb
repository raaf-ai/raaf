# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Span Browsing Workflow', type: :system do
  before do
    # Set up test data
    @agent1_spans = create_list(:evaluation_span, 5,
      span_data: {
        'agent_name' => 'TestAgent',
        'model' => 'gpt-4o',
        'status' => 'completed'
      }
    )

    @agent2_spans = create_list(:evaluation_span, 3,
      span_data: {
        'agent_name' => 'AnotherAgent',
        'model' => 'claude-3-5-sonnet-20241022',
        'status' => 'completed'
      }
    )

    @failed_span = create(:evaluation_span,
      span_data: {
        'agent_name' => 'TestAgent',
        'model' => 'gpt-4o',
        'status' => 'failed'
      }
    )
  end

  it 'allows user to browse and filter spans' do
    visit raaf_eval_ui.root_path

    # User sees table of recent spans
    expect(page).to have_content('Span Browser')
    expect(page).to have_css('table tbody tr', count: 9)

    # User applies agent filter
    select 'TestAgent', from: 'agent_filter'
    click_button 'Apply Filters'

    expect(page).to have_css('table tbody tr', count: 6)
    expect(page).to have_content('TestAgent')
    expect(page).not_to have_content('AnotherAgent')

    # User applies status filter
    select 'Failed', from: 'status_filter'
    click_button 'Apply Filters'

    expect(page).to have_css('table tbody tr', count: 1)
    expect(page).to have_css('.bg-red-100', text: 'Failed')
  end

  it 'allows user to search for specific spans' do
    span = @agent1_spans.first
    visit raaf_eval_ui.root_path

    # User searches for specific span ID
    fill_in 'search', with: span.span_id[0..8]
    # Debounced AJAX search triggers

    expect(page).to have_content(span.span_id)
    expect(page).to have_css('table tbody tr', count: 1)
  end

  it 'allows user to view span details' do
    span = @agent1_spans.first
    visit raaf_eval_ui.root_path

    # User clicks on span row to expand details
    find('tr', text: span.span_id[0..8]).click

    expect(page).to have_css('.span-detail')
    expect(page).to have_content('Span Details')
    expect(page).to have_content(span.span_id)
  end

  it 'allows user to select span for evaluation' do
    span = @agent1_spans.first
    visit raaf_eval_ui.root_path

    # User views span details
    find('tr', text: span.span_id[0..8]).click

    # User clicks "Evaluate This Span" button
    click_button 'Evaluate This Span'

    # User is redirected to evaluation setup
    expect(page).to have_current_path(raaf_eval_ui.new_evaluation_path(span_id: span.id))
    expect(page).to have_content('Evaluation Setup')
    expect(page).to have_content(span.span_id)
  end

  it 'allows user to paginate through spans' do
    create_list(:evaluation_span, 30, span_data: { 'agent_name' => 'TestAgent' })
    visit raaf_eval_ui.root_path

    # Default page shows 25 spans
    expect(page).to have_css('table tbody tr', maximum: 25)

    # User navigates to next page
    click_link 'Next'

    expect(page).to have_css('table tbody tr', minimum: 1)
    expect(page).to have_current_path(/page=2/)
  end

  it 'shows empty state when no spans match filters' do
    visit raaf_eval_ui.root_path

    select 'NonExistentAgent', from: 'agent_filter'
    click_button 'Apply Filters'

    expect(page).to have_content('No spans found')
    expect(page).to have_content('Try adjusting your filters')
  end
end
