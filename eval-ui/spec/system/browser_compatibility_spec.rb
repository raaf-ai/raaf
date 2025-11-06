# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Browser Compatibility', type: :system do
  let(:span) { create(:evaluation_span) }
  let(:evaluation) { create(:evaluation_session, status: 'completed') }

  # Test with different browser configurations
  browsers = [
    { name: 'Chrome', driver: :selenium_chrome },
    { name: 'Firefox', driver: :selenium_firefox },
    { name: 'Safari', driver: :selenium_safari },
    { name: 'Edge', driver: :selenium_edge }
  ]

  browsers.each do |browser_config|
    context "in #{browser_config[:name]}", driver: browser_config[:driver] do
      before(:each) do
        # Skip if driver not available
        skip "#{browser_config[:name]} not available" unless browser_available?(browser_config[:driver])
        driven_by browser_config[:driver]
      end

      it 'renders span browser correctly' do
        visit raaf_eval_ui.root_path

        expect(page).to have_content('Span Browser')
        expect(page).to have_css('table')
        expect(page).to have_button('Apply Filters')
      end

      it 'renders Monaco Editor correctly', js: true do
        visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

        expect(page).to have_css('[data-controller="monaco-editor"]')
        expect(page).to have_css('.monaco-editor', wait: 5)
      end

      it 'handles Turbo Streams updates', js: true do
        evaluation.update!(status: 'running')
        visit raaf_eval_ui.evaluation_path(evaluation)

        expect(page).to have_css('#evaluation_progress')
        expect(page).to have_css('[data-controller="evaluation-progress"]')
      end

      it 'supports responsive layouts' do
        page.driver.browser.manage.window.resize_to(375, 667) # Mobile size

        visit raaf_eval_ui.root_path

        expect(page).to have_css('.responsive-container')
        expect(page).to have_css('table') # Table should adapt
      end

      it 'renders diff highlighting correctly' do
        visit raaf_eval_ui.results_evaluation_path(evaluation)

        expect(page).to have_css('.results-comparison')
        expect(page).to have_css('.additions, .deletions, .modifications')
      end

      it 'handles JavaScript form validation' do
        visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

        fill_in 'Temperature', with: '2.5'

        expect(page).to have_content(/must be between/i)
        expect(page).to have_button('Run Evaluation', disabled: true)
      end

      it 'supports keyboard navigation' do
        visit raaf_eval_ui.root_path

        # Tab through interactive elements
        page.send_keys(:tab)
        expect(page).to have_css(':focus')
      end

      it 'renders progress bars with animations' do
        evaluation.update!(status: 'running')
        visit raaf_eval_ui.evaluation_path(evaluation)

        expect(page).to have_css('.progress-bar')
        expect(page).to have_css('[role="progressbar"]')
      end

      it 'handles AJAX requests correctly' do
        visit raaf_eval_ui.root_path

        fill_in 'search', with: 'test'

        # AJAX search should work
        expect(page).to have_css('table tbody tr', wait: 2)
      end
    end
  end

  def browser_available?(driver)
    case driver
    when :selenium_chrome
      system('which chromedriver > /dev/null 2>&1') || system('which google-chrome > /dev/null 2>&1')
    when :selenium_firefox
      system('which geckodriver > /dev/null 2>&1') || system('which firefox > /dev/null 2>&1')
    when :selenium_safari
      RUBY_PLATFORM.include?('darwin') # Safari only on macOS
    when :selenium_edge
      system('which msedgedriver > /dev/null 2>&1') || system('which microsoft-edge > /dev/null 2>&1')
    else
      false
    end
  end
end
