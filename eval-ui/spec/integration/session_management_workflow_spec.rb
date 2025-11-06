# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Session Management Workflow', type: :system do
  let(:user) { create(:user) if defined?(User) }
  let(:span) { create(:evaluation_span) }

  before do
    # Assume user is logged in
    # login_as(user) if user
  end

  it 'allows saving evaluation as named session' do
    evaluation = create(:evaluation_session,
      name: 'Temp Evaluation',
      session_type: 'draft',
      status: 'completed'
    )

    visit raaf_eval_ui.results_evaluation_path(evaluation)

    click_button 'Save Session'

    fill_in 'Session Name', with: 'My Important Evaluation'
    fill_in 'Description', with: 'Testing temperature variations'
    click_button 'Save'

    expect(page).to have_content('Session saved successfully')

    evaluation.reload
    expect(evaluation.name).to eq('My Important Evaluation')
    expect(evaluation.session_type).to eq('saved')
  end

  it 'displays list of saved sessions' do
    sessions = create_list(:evaluation_session, 3,
      session_type: 'saved',
      status: 'completed'
    )

    visit raaf_eval_ui.sessions_path

    expect(page).to have_content('Saved Sessions')
    sessions.each do |session|
      expect(page).to have_content(session.name)
    end
  end

  it 'allows filtering sessions by type' do
    saved_sessions = create_list(:evaluation_session, 2, session_type: 'saved')
    draft_sessions = create_list(:evaluation_session, 2, session_type: 'draft')

    visit raaf_eval_ui.sessions_path

    # Filter by saved
    select 'Saved', from: 'session_type_filter'
    click_button 'Filter'

    saved_sessions.each { |s| expect(page).to have_content(s.name) }
    draft_sessions.each { |s| expect(page).not_to have_content(s.name) }
  end

  it 'allows loading a saved session' do
    session = create(:evaluation_session,
      name: 'Saved Evaluation',
      session_type: 'saved',
      status: 'completed'
    )

    visit raaf_eval_ui.sessions_path

    click_link session.name

    expect(page).to have_current_path(raaf_eval_ui.session_path(session))
    expect(page).to have_content(session.name)
    expect(page).to have_content('Results')
  end

  it 'allows deleting a session' do
    session = create(:evaluation_session,
      name: 'To Delete',
      session_type: 'saved'
    )

    visit raaf_eval_ui.sessions_path

    accept_confirm do
      within("#session_#{session.id}") do
        click_button 'Delete'
      end
    end

    expect(page).to have_content('Session deleted')
    expect(page).not_to have_content('To Delete')
  end

  it 'allows archiving a session' do
    session = create(:evaluation_session,
      name: 'To Archive',
      session_type: 'saved'
    )

    visit raaf_eval_ui.session_path(session)

    click_button 'Archive'

    expect(page).to have_content('Session archived')

    session.reload
    expect(session.session_type).to eq('archived')
  end

  it 'displays session creation date and last updated' do
    session = create(:evaluation_session,
      name: 'Test Session',
      created_at: 2.days.ago,
      updated_at: 1.hour.ago
    )

    visit raaf_eval_ui.sessions_path

    expect(page).to have_content('2 days ago')
    expect(page).to have_content('1 hour ago')
  end

  it 'allows updating session name and description' do
    session = create(:evaluation_session,
      name: 'Original Name',
      description: 'Original description',
      session_type: 'saved'
    )

    visit raaf_eval_ui.session_path(session)

    click_button 'Edit'

    fill_in 'Session Name', with: 'Updated Name'
    fill_in 'Description', with: 'Updated description'
    click_button 'Save Changes'

    expect(page).to have_content('Session updated')
    expect(page).to have_content('Updated Name')

    session.reload
    expect(session.name).to eq('Updated Name')
    expect(session.description).to eq('Updated description')
  end

  it 'shows session details including configurations' do
    session = create(:evaluation_session,
      name: 'Multi-Config Session',
      session_type: 'saved'
    )

    config1 = create(:session_configuration,
      session: session,
      name: 'High Temp',
      configuration: { temperature: 0.9 }
    )

    config2 = create(:session_configuration,
      session: session,
      name: 'Low Temp',
      configuration: { temperature: 0.3 }
    )

    visit raaf_eval_ui.session_path(session)

    expect(page).to have_content('High Temp')
    expect(page).to have_content('Low Temp')
    expect(page).to have_content('0.9')
    expect(page).to have_content('0.3')
  end
end
