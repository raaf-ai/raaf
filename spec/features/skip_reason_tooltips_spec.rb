# frozen_string_literal: true

require_relative '../rails/spec/spec_helper'

RSpec.describe 'Skip Reason Tooltips', type: :feature, js: true do
  # Use Playwright for modern browser automation (replaces Puppeteer)
  # This test verifies that skip reason tooltips work correctly across all RAAF tracing views

  let(:trace_record) { create_trace_with_skipped_spans }
  let(:skipped_span) { trace_record.spans.find { |span| span.status == 'skipped' } }

  before do
    # Set up test data with actual skip reasons stored in the database
    setup_skip_reason_data
  end

  describe 'Spans List View' do
    before { visit '/raaf/tracing/spans' }

    it 'shows skip reason tooltip on hover over skipped badge', :focus do
      # Find the skipped badge
      skipped_badge = page.find('.bg-orange-100', text: 'Skipped', match: :first)
      expect(skipped_badge).to be_present

      # Hover over the badge to trigger tooltip
      skipped_badge.hover

      # Wait for Preline UI tooltip to appear with proper timing
      expect(page).to have_css('.hs-tooltip-content', visible: true, wait: 2)

      # Verify tooltip content shows the actual skip reason
      tooltip_content = page.find('.hs-tooltip-content', visible: true)
      expect(tooltip_content).to have_text('Agent requirements not met')
    end

    it 'hides tooltip when mouse moves away' do
      skipped_badge = page.find('.bg-orange-100', text: 'Skipped', match: :first)

      # Show tooltip
      skipped_badge.hover
      expect(page).to have_css('.hs-tooltip-content', visible: true, wait: 2)

      # Move mouse away
      page.find('body').hover

      # Tooltip should hide (with delay as configured)
      expect(page).not_to have_css('.hs-tooltip-content', visible: true, wait: 3)
    end

    it 'does not show tooltips for non-skipped badges' do
      # Find a completed badge (should not have tooltip)
      completed_badge = page.find('.bg-green-100', text: 'Completed', match: :first)
      completed_badge.hover

      # Should not show any tooltip
      expect(page).not_to have_css('.hs-tooltip-content', visible: true, wait: 1)
    end
  end

  describe 'Traces Table View' do
    before { visit '/raaf/tracing/traces' }

    it 'shows skip reason tooltips in traces table' do
      # Find trace with skipped spans
      trace_row = page.find("[data-trace-id='#{trace_record.trace_id}']")
      skipped_badge = trace_row.find('.bg-orange-100', text: 'Skipped')

      skipped_badge.hover

      expect(page).to have_css('.hs-tooltip-content', visible: true, wait: 2)
      tooltip = page.find('.hs-tooltip-content', visible: true)
      expect(tooltip).to have_text('Agent requirements not met')
    end

    it 'expands spans and shows tooltips in nested view' do
      # Find and click the expand button for the trace
      expand_button = page.find('.toggle-spans', match: :first)
      expand_button.click

      # Wait for spans to expand
      expect(page).to have_css('.collapse-row', visible: true, wait: 2)

      # Find skipped badge in the expanded spans
      expanded_span = page.find('.collapse-row', visible: true)
      skipped_badge = expanded_span.find('.bg-orange-100', text: 'Skipped')

      skipped_badge.hover

      expect(page).to have_css('.hs-tooltip-content', visible: true, wait: 2)
    end
  end

  describe 'Dashboard View' do
    before { visit '/raaf/dashboard' }

    it 'shows skip reason tooltips in dashboard recent traces' do
      # Dashboard shows recent traces with status badges
      within('.recent-traces') do
        skipped_badge = page.find('.badge.bg-warning', text: 'Skipped', match: :first)
        skipped_badge.hover

        expect(page).to have_css('.hs-tooltip-content', visible: true, wait: 2)
      end
    end
  end

  describe 'Timeline View' do
    before { visit '/raaf/tracing/timeline' }

    it 'shows skip reason tooltips in timeline span details' do
      # Timeline view shows span details with status badges
      skip '# TODO: Implement when timeline view is available'

      skipped_badge = page.find('.bg-orange-100', text: 'Skipped', match: :first)
      skipped_badge.hover

      expect(page).to have_css('.hs-tooltip-content', visible: true, wait: 2)
    end
  end

  describe 'Trace Detail View' do
    before { visit "/raaf/tracing/traces/#{trace_record.trace_id}" }

    it 'shows skip reason tooltips with detailed badge style' do
      # Trace detail uses the :detailed badge style with icons
      skipped_badge = page.find('.border-orange-200', text: 'Skipped')

      # Should have skip-forward icon
      expect(skipped_badge).to have_css('i.bi-skip-forward')

      skipped_badge.hover

      expect(page).to have_css('.hs-tooltip-content', visible: true, wait: 2)
      tooltip = page.find('.hs-tooltip-content', visible: true)
      expect(tooltip).to have_text('Agent requirements not met')
    end
  end

  describe 'Tooltip Functionality' do
    before { visit '/raaf/tracing/spans' }

    it 'truncates long skip reasons correctly' do
      # Create a span with a very long skip reason
      long_reason = 'A' * 150  # Longer than 100 character limit
      skipped_span.update!(
        span_attributes: skipped_span.span_attributes.merge(
          'skip_reason' => long_reason
        )
      )

      page.refresh

      skipped_badge = page.find('.bg-orange-100', text: 'Skipped', match: :first)
      skipped_badge.hover

      expect(page).to have_css('.hs-tooltip-content', visible: true, wait: 2)
      tooltip = page.find('.hs-tooltip-content', visible: true)

      # Should be truncated with ellipsis
      expect(tooltip.text).to end_with('...')
      expect(tooltip.text.length).to be <= 103  # 100 chars + "..."
    end

    it 'shows tooltips quickly with correct timing' do
      skipped_badge = page.find('.bg-orange-100', text: 'Skipped', match: :first)

      # Record start time
      start_time = Time.current

      skipped_badge.hover

      # Tooltip should appear within 500ms (configured delay + buffer)
      expect(page).to have_css('.hs-tooltip-content', visible: true, wait: 0.5)

      end_time = Time.current
      duration = (end_time - start_time) * 1000  # Convert to milliseconds

      # Should appear quickly (within reasonable bounds)
      expect(duration).to be < 500
    end

    it 'positions tooltips correctly above badges' do
      skipped_badge = page.find('.bg-orange-100', text: 'Skipped', match: :first)
      skipped_badge.hover

      expect(page).to have_css('.hs-tooltip-content', visible: true, wait: 2)
      tooltip = page.find('.hs-tooltip-content', visible: true)

      # Tooltip should have proper positioning classes
      expect(tooltip['class']).to include('bottom-full')  # Positioned above
      expect(tooltip['class']).to include('left-1/2')     # Horizontally centered
      expect(tooltip['class']).to include('transform')    # With transform
      expect(tooltip['class']).to include('-translate-x-1/2')  # Centered transform
    end

    it 'applies proper styling and visibility classes' do
      skipped_badge = page.find('.bg-orange-100', text: 'Skipped', match: :first)
      skipped_badge.hover

      expect(page).to have_css('.hs-tooltip-content', visible: true, wait: 2)
      tooltip = page.find('.hs-tooltip-content', visible: true)

      # Should have proper Preline UI classes
      expect(tooltip['class']).to include('hs-tooltip-content')
      expect(tooltip['class']).to include('bg-gray-900')  # Dark background
      expect(tooltip['class']).to include('text-white')   # White text
      expect(tooltip['class']).to include('rounded-lg')   # Rounded corners
      expect(tooltip['class']).to include('shadow-lg')    # Drop shadow
    end
  end

  describe 'Accessibility' do
    before { visit '/raaf/tracing/spans' }

    it 'includes proper ARIA attributes' do
      skipped_badge = page.find('.hs-tooltip-toggle', match: :first)

      # Should have cursor-help for accessibility
      expect(skipped_badge['class']).to include('cursor-help')

      # Tooltip content should have proper role
      skipped_badge.hover
      expect(page).to have_css('.hs-tooltip-content[role="tooltip"]', visible: true, wait: 2)
    end

    it 'works with keyboard navigation' do
      # Tab to the badge
      page.execute_script('document.querySelector(".hs-tooltip-toggle").focus()')

      # Should be focusable and show tooltip on focus
      focused_element = page.evaluate_script('document.activeElement.classList.contains("hs-tooltip-toggle")')
      expect(focused_element).to be true
    end
  end

  private

  def create_trace_with_skipped_spans
    # Create a trace record with skipped spans for testing
    trace = RAAF::Rails::Tracing::TraceRecord.create!(
      trace_id: "trace_#{SecureRandom.hex(16)}",
      workflow_name: "Test Workflow",
      status: "completed",
      started_at: 1.hour.ago,
      duration_ms: 5000
    )

    # Create a skipped span with proper skip reason
    skipped_span = RAAF::Rails::Tracing::SpanRecord.create!(
      span_id: "span_#{SecureRandom.hex(16)}",
      trace_id: trace.trace_id,
      name: "Test Skipped Agent",
      kind: "agent",
      status: "skipped",
      start_time: 1.hour.ago,
      duration_ms: 100,
      span_attributes: {
        "agent.skip_reason" => "Agent requirements not met",
        "description" => "Test agent that was skipped"
      }
    )

    # Create a completed span for comparison
    RAAF::Rails::Tracing::SpanRecord.create!(
      span_id: "span_#{SecureRandom.hex(16)}",
      trace_id: trace.trace_id,
      name: "Test Completed Agent",
      kind: "agent",
      status: "completed",
      start_time: 1.hour.ago,
      duration_ms: 2000,
      span_attributes: {
        "description" => "Test agent that completed successfully"
      }
    )

    trace
  end

  def setup_skip_reason_data
    # Ensure we have the test trace and spans created
    trace_record

    # Verify skip reason is accessible
    skip_reason = skipped_span.skip_reason
    expect(skip_reason).to eq("Agent requirements not met")

    Rails.logger.info "✅ Test data setup complete - Skip reason: #{skip_reason}"
  end
end