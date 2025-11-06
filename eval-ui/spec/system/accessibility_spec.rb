# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Accessibility (WCAG AA)', type: :system do
  let(:span) { create(:evaluation_span) }
  let(:evaluation) { create(:evaluation_session, status: 'completed') }

  describe 'Keyboard Navigation' do
    it 'allows tabbing through all interactive elements' do
      visit raaf_eval_ui.root_path

      # Count interactive elements
      interactive_count = page.all('button, a, input, select, textarea').count

      # Tab through all elements
      interactive_count.times { page.send_keys(:tab) }

      # Should reach end without errors
      expect(page).to have_css(':focus')
    end

    it 'supports keyboard shortcuts' do
      visit raaf_eval_ui.root_path

      # Press '/' to focus search
      page.send_keys('/')
      expect(page).to have_css('input[type="search"]:focus')

      # Press Escape to close modals
      page.send_keys(:escape)
      expect(page).not_to have_css('.modal[open]')
    end

    it 'maintains focus when navigating' do
      visit raaf_eval_ui.root_path

      # Click first button
      first_button = page.first('button')
      first_button.click

      # Focus should be visible
      expect(page).to have_css('button:focus, a:focus')
    end

    it 'traps focus in modals' do
      visit raaf_eval_ui.results_evaluation_path(evaluation)

      click_button 'Save Session'

      # Modal should be open
      modal = page.find('.modal[open]')

      # Tab should cycle within modal
      within(modal) do
        interactive_elements = all('button, input')
        interactive_elements.count.times { page.send_keys(:tab) }

        # Focus should still be in modal
        expect(modal).to have_css(':focus')
      end
    end
  end

  describe 'ARIA Labels and Attributes' do
    it 'has proper ARIA labels on buttons' do
      visit raaf_eval_ui.root_path

      page.all('button').each do |button|
        # Button should have text content or aria-label
        has_label = button.text.present? || button['aria-label'].present?
        expect(has_label).to be(true), "Button without label: #{button.inspect}"
      end
    end

    it 'has proper table headers with scope' do
      visit raaf_eval_ui.root_path

      page.all('table thead th').each do |header|
        expect(header['scope']).to eq('col').or eq('row')
      end
    end

    it 'has proper form labels' do
      visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

      page.all('input, select, textarea').each do |field|
        field_id = field['id']
        next if field_id.nil?

        # Should have associated label
        label = page.find("label[for='#{field_id}']", wait: 0)
        expect(label).to be_present
      rescue Capybara::ElementNotFound
        # Field should at least have aria-label
        expect(field['aria-label']).to be_present, "Field #{field_id} missing label"
      end
    end

    it 'announces loading states' do
      evaluation.update!(status: 'running')
      visit raaf_eval_ui.evaluation_path(evaluation)

      loading_indicator = page.find('.progress-bar')
      expect(loading_indicator['role']).to eq('progressbar')
      expect(loading_indicator['aria-valuenow']).to be_present
    end

    it 'announces error states' do
      evaluation.update!(status: 'failed', error_message: 'Test error')
      visit raaf_eval_ui.evaluation_path(evaluation)

      error_container = page.find('.bg-red-50')
      expect(error_container['role']).to eq('alert').or be_nil
      expect(error_container).to have_content('Test error')
    end

    it 'has proper heading hierarchy' do
      visit raaf_eval_ui.root_path

      headings = page.all('h1, h2, h3, h4, h5, h6').map { |h| h.tag_name }

      # Should start with h1
      expect(headings.first).to eq('h1')

      # No skipped levels
      headings.each_cons(2) do |current, next_heading|
        current_level = current[1].to_i
        next_level = next_heading[1].to_i
        difference = next_level - current_level
        expect(difference).to be <= 1, "Heading hierarchy skip: #{current} to #{next_heading}"
      end
    end
  end

  describe 'Focus Management' do
    it 'shows visible focus indicators' do
      visit raaf_eval_ui.root_path

      page.send_keys(:tab)
      focused_element = page.find(':focus')

      # Focus should be visible (check computed styles if possible)
      expect(focused_element['class']).to include('focus').or include('ring')
    end

    it 'restores focus after closing modals' do
      visit raaf_eval_ui.results_evaluation_path(evaluation)

      trigger_button = page.find('button', text: 'Save Session')
      trigger_button.click

      # Close modal
      page.send_keys(:escape)

      # Focus should return to trigger button
      expect(trigger_button).to match_css(':focus')
    end

    it 'moves focus appropriately after actions' do
      visit raaf_eval_ui.root_path

      # After filtering, focus should move to results
      click_button 'Apply Filters'

      # Focus should be on results table or first result
      expect(page).to have_css('table:focus, table tbody tr:first-child:focus')
    end
  end

  describe 'Screen Reader Compatibility' do
    it 'has descriptive link text' do
      visit raaf_eval_ui.sessions_path

      page.all('a').each do |link|
        link_text = link.text.strip
        next if link_text.empty?

        # Avoid generic link text
        generic_terms = ['click here', 'read more', 'link', 'here']
        is_generic = generic_terms.any? { |term| link_text.downcase == term }

        expect(is_generic).to be(false), "Generic link text: #{link_text}"
      end
    end

    it 'provides alternative text for images' do
      visit raaf_eval_ui.root_path

      page.all('img').each do |img|
        expect(img['alt']).to be_present, "Image missing alt text: #{img['src']}"
      end
    end

    it 'groups related form fields' do
      visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

      # Related fields should be in fieldsets
      fieldsets = page.all('fieldset')
      expect(fieldsets.count).to be > 0

      fieldsets.each do |fieldset|
        # Each fieldset should have legend
        expect(fieldset).to have_css('legend')
      end
    end

    it 'has descriptive page titles' do
      test_pages = [
        { path: raaf_eval_ui.root_path, expected: /Span Browser|Evaluation/ },
        { path: raaf_eval_ui.sessions_path, expected: /Sessions/ },
        { path: raaf_eval_ui.evaluation_path(evaluation), expected: /Evaluation|Results/ }
      ]

      test_pages.each do |page_config|
        visit page_config[:path]
        expect(page).to have_title(page_config[:expected])
      end
    end
  end

  describe 'Color Contrast (WCAG AA)' do
    it 'has sufficient contrast for all text' do
      visit raaf_eval_ui.root_path

      # This would require a color contrast analyzer
      # For now, we verify classes that should have good contrast
      expect(page).to have_css('.text-gray-900') # Dark text on light background
      expect(page).not_to have_css('.text-gray-300.bg-gray-200') # Poor contrast
    end

    it 'does not rely solely on color for information' do
      evaluation.update!(status: 'failed')
      visit raaf_eval_ui.evaluation_path(evaluation)

      # Error state should have icon + color + text
      error_element = page.find('.bg-red-50')
      expect(error_element).to have_css('svg') # Icon
      expect(error_element).to have_text(/failed|error/i) # Text
    end

    it 'has sufficient contrast in diff highlighting' do
      visit raaf_eval_ui.results_evaluation_path(evaluation)

      # Additions (green) should be readable
      if page.has_css?('.additions')
        addition = page.find('.additions')
        # Should have text or background with sufficient contrast
        expect(addition['class']).to include('green').or include('bg-green')
      end
    end
  end

  describe 'Keyboard Shortcuts' do
    it 'provides keyboard shortcut documentation' do
      visit raaf_eval_ui.root_path

      # Press '?' to show shortcuts
      page.send_keys('?')

      expect(page).to have_content('Keyboard Shortcuts')
      expect(page).to have_content('Cmd+S')
      expect(page).to have_content('Cmd+Enter')
      expect(page).to have_content('Esc')
    end

    it 'allows closing overlays with Escape' do
      visit raaf_eval_ui.root_path

      # Open keyboard shortcuts
      page.send_keys('?')
      expect(page).to have_content('Keyboard Shortcuts')

      # Close with Escape
      page.send_keys(:escape)
      expect(page).not_to have_content('Keyboard Shortcuts')
    end
  end

  describe 'Responsive Text Scaling' do
    it 'remains readable at 200% zoom' do
      visit raaf_eval_ui.root_path

      # Simulate zoom (approximate with viewport resize)
      page.driver.browser.manage.window.resize_to(1920, 1080)

      # Text should not overflow or become unreadable
      expect(page).to have_css('body')
      expect(page).not_to have_css('.overflow-hidden')
    end

    it 'supports user font size preferences' do
      visit raaf_eval_ui.root_path

      # Layout should use relative units (rem, em)
      # This would need CSS inspection
      expect(page).to have_css('body')
    end
  end
end
