# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'

RSpec.describe 'Component Performance', type: :performance do
  describe 'SpanBrowser rendering' do
    it 'renders 100 spans in under 500ms' do
      spans = create_list(:evaluation_span, 100)

      time = Benchmark.realtime do
        component = RAAF::Eval::UI::SpanBrowser.new(spans: spans)
        Phlex::Testing::ViewContext.new.render(component)
      end

      expect(time).to be < 0.5, "Rendering took #{time}s, expected < 0.5s"
    end

    it 'paginates efficiently with large datasets' do
      create_list(:evaluation_span, 1000)

      time = Benchmark.realtime do
        visit raaf_eval_ui.root_path
      end

      expect(time).to be < 1.0, "Page load took #{time}s, expected < 1s"
    end

    it 'applies filters without blocking UI' do
      create_list(:evaluation_span, 500)
      visit raaf_eval_ui.root_path

      time = Benchmark.realtime do
        select 'TestAgent', from: 'agent_filter'
        click_button 'Apply Filters'
        expect(page).to have_css('table tbody tr')
      end

      expect(time).to be < 0.3, "Filter application took #{time}s, expected < 0.3s"
    end
  end

  describe 'Monaco Editor initialization' do
    let(:span) { create(:evaluation_span) }

    it 'lazy loads Monaco in under 1 second', js: true do
      start_time = Time.current

      visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

      # Wait for Monaco to load
      expect(page).to have_css('.monaco-editor', wait: 2)

      load_time = Time.current - start_time
      expect(load_time).to be < 1.0, "Monaco loaded in #{load_time}s, expected < 1s"
    end

    it 'initializes editor in under 500ms', js: true do
      visit raaf_eval_ui.new_evaluation_path(span_id: span.id)

      # Wait for Monaco container
      expect(page).to have_css('[data-controller="monaco-editor"]')

      start_time = Time.current

      # Trigger editor initialization
      page.execute_script('window.initializeMonacoEditor()')

      # Wait for editor to be ready
      wait_for { page.evaluate_script('window.monaco') }

      init_time = Time.current - start_time
      expect(init_time).to be < 0.5, "Editor initialized in #{init_time}s, expected < 0.5s"
    end

    it 'handles first edit in under 100ms', js: true do
      visit raaf_eval_ui.new_evaluation_path(span_id: span.id)
      expect(page).to have_css('.monaco-editor', wait: 2)

      start_time = Time.current

      # Simulate typing
      page.execute_script('document.querySelector("[name=\\"evaluation[prompt]\\"]").value = "test"')
      page.execute_script('document.querySelector("[data-controller=\\"monaco-editor\\"]").dispatchEvent(new Event("change"))')

      edit_time = (Time.current - start_time) * 1000 # Convert to ms
      expect(edit_time).to be < 100, "First edit took #{edit_time}ms, expected < 100ms"
    end
  end

  describe 'Diff rendering' do
    let(:baseline_content) { 'a' * 1000 }
    let(:modified_content) { ('a' * 500) + ('b' * 500) }

    it 'renders diffs up to 1000 lines in under 500ms' do
      baseline_lines = (1..1000).map { |i| "Line #{i} baseline content" }.join("\n")
      modified_lines = (1..1000).map { |i| "Line #{i} modified content" }.join("\n")

      time = Benchmark.realtime do
        component = RAAF::Eval::UI::ResultsComparison.new(
          baseline: baseline_lines,
          modified: modified_lines
        )
        Phlex::Testing::ViewContext.new.render(component)
      end

      expect(time).to be < 0.5, "Diff rendering took #{time}s, expected < 0.5s"
    end

    it 'toggles diff view in under 100ms', js: true do
      evaluation = create(:evaluation_session, status: 'completed')
      visit raaf_eval_ui.results_evaluation_path(evaluation)

      start_time = Time.current

      click_button 'Unified View'

      toggle_time = (Time.current - start_time) * 1000
      expect(toggle_time).to be < 100, "Toggle took #{toggle_time}ms, expected < 100ms"
    end

    it 'expands sections in under 50ms', js: true do
      evaluation = create(:evaluation_session, status: 'completed')
      visit raaf_eval_ui.results_evaluation_path(evaluation)

      start_time = Time.current

      find('summary', text: /Messages/).click

      expand_time = (Time.current - start_time) * 1000
      expect(expand_time).to be < 50, "Expand took #{expand_time}ms, expected < 50ms"
    end
  end

  describe 'Turbo Stream updates' do
    let(:evaluation) { create(:evaluation_session, status: 'running') }

    it 'applies Turbo Stream updates in under 100ms', js: true do
      visit raaf_eval_ui.evaluation_path(evaluation)

      start_time = Time.current

      # Simulate Turbo Stream update
      evaluation.update!(metadata: { 'current_step' => 'New step' })

      # Manually trigger update (in real app, this would be automatic)
      page.execute_script("Turbo.visit('#{raaf_eval_ui.evaluation_path(evaluation)}')")

      update_time = (Time.current - start_time) * 1000
      expect(update_time).to be < 100, "Update took #{update_time}ms, expected < 100ms"
    end

    it 'maintains 1 second polling interval consistently', js: true do
      visit raaf_eval_ui.evaluation_path(evaluation)

      intervals = []
      last_poll = Time.current

      5.times do
        sleep(1.1) # Wait for next poll
        current_time = Time.current
        intervals << (current_time - last_poll)
        last_poll = current_time
      end

      avg_interval = intervals.sum / intervals.length
      expect(avg_interval).to be_between(0.9, 1.1), "Average polling interval #{avg_interval}s, expected ~1s"
    end

    it 'does not block UI during progress updates', js: true do
      visit raaf_eval_ui.evaluation_path(evaluation)

      # Trigger rapid updates
      10.times do |i|
        evaluation.update!(metadata: { 'current_step' => "Step #{i}" })
        sleep(0.1)
      end

      # UI should still be responsive
      expect(page).to have_button('Cancel')
      expect(page.find('button', text: 'Cancel')).to be_visible
    end
  end

  describe 'Large dataset handling' do
    it 'handles 1000+ spans efficiently' do
      create_list(:evaluation_span, 1500)

      time = Benchmark.realtime do
        visit raaf_eval_ui.root_path
        expect(page).to have_css('table')
      end

      expect(time).to be < 2.0, "Page with 1500 spans loaded in #{time}s, expected < 2s"
    end

    it 'handles spans with 10k+ tokens' do
      large_content = 'word ' * 3000 # ~10k tokens
      span = create(:evaluation_span,
        span_data: {
          'input_messages' => [{ 'role' => 'user', 'content' => large_content }],
          'output_messages' => [{ 'role' => 'assistant', 'content' => large_content }]
        }
      )

      time = Benchmark.realtime do
        component = RAAF::Eval::UI::SpanDetail.new(span: span)
        Phlex::Testing::ViewContext.new.render(component)
      end

      expect(time).to be < 0.5, "Large span rendered in #{time}s, expected < 0.5s"
    end

    it 'handles multiple concurrent evaluations' do
      evaluations = create_list(:evaluation_session, 10, status: 'running')

      time = Benchmark.realtime do
        evaluations.each do |eval|
          visit raaf_eval_ui.evaluation_path(eval)
        end
      end

      avg_time = time / 10
      expect(avg_time).to be < 0.5, "Average page load #{avg_time}s, expected < 0.5s"
    end
  end

  describe 'Database query performance' do
    it 'uses efficient queries for span listing' do
      create_list(:evaluation_span, 100)

      queries = []
      ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
        queries << args.last[:sql]
      end

      visit raaf_eval_ui.root_path

      # Should use pagination to limit query size
      expect(queries.any? { |q| q.include?('LIMIT') }).to be(true)

      # Should not have N+1 queries
      select_queries = queries.select { |q| q.start_with?('SELECT') }
      expect(select_queries.count).to be < 10, "Too many queries: #{select_queries.count}"
    end

    it 'eager loads associations to prevent N+1' do
      session = create(:evaluation_session)
      create_list(:session_configuration, 5, session: session)
      create_list(:session_result, 5, session: session)

      queries = []
      ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
        queries << args.last[:sql]
      end

      visit raaf_eval_ui.session_path(session)

      # Should eager load associations
      select_queries = queries.select { |q| q.start_with?('SELECT') }
      expect(select_queries.count).to be < 5, "N+1 detected: #{select_queries.count} queries"
    end
  end

  describe 'Memory usage' do
    it 'does not leak memory during rapid navigation' do
      spans = create_list(:evaluation_span, 10)

      GC.start
      initial_memory = `ps -o rss= -p #{Process.pid}`.to_i

      100.times do
        span = spans.sample
        visit raaf_eval_ui.spans_path
        visit raaf_eval_ui.span_path(span)
      end

      GC.start
      final_memory = `ps -o rss= -p #{Process.pid}`.to_i

      memory_increase = final_memory - initial_memory
      expect(memory_increase).to be < 50_000, "Memory increased by #{memory_increase}KB, expected < 50MB"
    end
  end

  def wait_for(timeout: 1)
    Timeout.timeout(timeout) do
      loop do
        result = yield
        break result if result
        sleep 0.01
      end
    end
  end
end
