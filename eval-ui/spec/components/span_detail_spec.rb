# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RAAF::Eval::UI::SpanDetail, type: :component do
  let(:span_data) do
    {
      'agent_name' => 'TestAgent',
      'model' => 'gpt-4o',
      'instructions' => 'Test instructions',
      'input_messages' => [
        { 'role' => 'user', 'content' => 'Test input message' }
      ],
      'output_messages' => [
        { 'role' => 'assistant', 'content' => 'Test output message' }
      ],
      'tool_calls' => [
        {
          'name' => 'test_tool',
          'arguments' => { 'param' => 'value' },
          'result' => 'Tool execution result'
        }
      ],
      'handoffs' => [
        {
          'to_agent' => 'AnotherAgent',
          'context' => { 'reason' => 'handoff test' }
        }
      ],
      'metadata' => {
        'tokens' => { 'input' => 50, 'output' => 75, 'total' => 125 },
        'cost' => { 'input' => 0.001, 'output' => 0.0015, 'total' => 0.0025 },
        'latency_ms' => 1500,
        'ttft_ms' => 200
      },
      'status' => 'completed'
    }
  end

  let(:span) do
    RAAF::Eval::Models::EvaluationSpan.create!(
      span_id: 'test-span-123',
      trace_id: 'test-trace-456',
      span_type: 'agent',
      source: 'production',
      span_data: span_data
    )
  end

  subject(:component) { described_class.new(span: span) }

  describe '#template' do
    it 'renders three-section layout' do
      output = render_inline(component)

      expect(output).to have_css('.span-detail')
      expect(output).to have_css('.grid-cols-1.lg\\:grid-cols-3')
    end

    it 'renders header with span metadata' do
      output = render_inline(component)

      expect(output).to have_text('Span Details: test-span-123')
      expect(output).to have_text('TestAgent')
      expect(output).to have_text('gpt-4o')
    end

    it 'renders input section with syntax highlighting' do
      output = render_inline(component)

      expect(output).to have_text('Input')
      expect(output).to have_css('code.language-json')
      expect(output).to have_text('50 tokens')
    end

    it 'renders output section with syntax highlighting' do
      output = render_inline(component)

      expect(output).to have_text('Output')
      expect(output).to have_css('code.language-json')
      expect(output).to have_text('75 tokens')
    end

    it 'renders metadata section' do
      output = render_inline(component)

      expect(output).to have_text('Metadata')
      expect(output).to have_text('Token Usage')
      expect(output).to have_text('Cost')
      expect(output).to have_text('Performance')
    end

    it 'renders token breakdown correctly' do
      output = render_inline(component)

      expect(output).to have_text('Input:')
      expect(output).to have_text('50')
      expect(output).to have_text('Output:')
      expect(output).to have_text('75')
      expect(output).to have_text('Total:')
      expect(output).to have_text('125')
    end

    it 'renders cost breakdown correctly' do
      output = render_inline(component)

      expect(output).to have_text('$0.0010')
      expect(output).to have_text('$0.0015')
      expect(output).to have_text('$0.0025')
    end

    it 'renders performance metrics' do
      output = render_inline(component)

      expect(output).to have_text('Latency:')
      expect(output).to have_text('1500ms')
      expect(output).to have_text('TTFT:')
      expect(output).to have_text('200ms')
    end

    it 'renders copy-to-clipboard buttons' do
      output = render_inline(component)

      expect(output).to have_button('Copy ID')
      expect(output).to have_button('Copy', count: 2) # Input and output sections
    end

    it 'renders status badge with correct styling' do
      output = render_inline(component)

      expect(output).to have_css('.bg-green-100.text-green-800', text: 'Completed')
    end
  end

  describe 'expandable tool calls section' do
    it 'renders tool calls when present' do
      output = render_inline(component)

      expect(output).to have_css('details')
      expect(output).to have_text('Tool Calls (1)')
      expect(output).to have_text('test_tool')
      expect(output).to have_text('Tool execution result')
    end

    it 'renders tool call arguments as JSON' do
      output = render_inline(component)

      expect(output).to have_text('Arguments:')
      expect(output).to have_text('"param"')
      expect(output).to have_text('"value"')
    end

    it 'does not render tool calls section when empty' do
      span.span_data = span_data.except('tool_calls')
      span.save!

      output = render_inline(component)

      expect(output).not_to have_text('Tool Calls')
    end
  end

  describe 'expandable handoffs section' do
    it 'renders handoffs when present' do
      output = render_inline(component)

      expect(output).to have_text('Handoffs (1)')
      expect(output).to have_text('→ AnotherAgent')
    end

    it 'renders handoff context as JSON' do
      output = render_inline(component)

      expect(output).to have_text('Context:')
      expect(output).to have_text('"reason"')
      expect(output).to have_text('"handoff test"')
    end

    it 'does not render handoffs section when empty' do
      span.span_data = span_data.except('handoffs')
      span.save!

      output = render_inline(component)

      expect(output).not_to have_text('Handoffs')
    end
  end

  describe 'timeline visualization' do
    context 'with multi-turn conversation' do
      let(:multi_turn_data) do
        span_data.merge(
          'output_messages' => [
            { 'role' => 'user', 'content' => 'First user message' },
            { 'role' => 'assistant', 'content' => 'First assistant response' },
            { 'role' => 'user', 'content' => 'Second user message' },
            { 'role' => 'assistant', 'content' => 'Second assistant response' }
          ]
        )
      end

      before do
        span.span_data = multi_turn_data
        span.save!
      end

      it 'renders timeline when show_timeline is true' do
        component = described_class.new(span: span, show_timeline: true)
        output = render_inline(component)

        expect(output).to have_text('Conversation Timeline')
        expect(output).to have_text('First user message')
        expect(output).to have_text('Second assistant response')
      end

      it 'does not render timeline when show_timeline is false' do
        component = described_class.new(span: span, show_timeline: false)
        output = render_inline(component)

        expect(output).not_to have_text('Conversation Timeline')
      end
    end

    context 'with single-turn conversation' do
      it 'does not render timeline' do
        output = render_inline(component)

        expect(output).not_to have_text('Conversation Timeline')
      end
    end
  end

  describe 'expanded sections' do
    it 'expands sections when expanded is true' do
      component = described_class.new(span: span, expanded: true)
      output = render_inline(component)

      expect(output).to have_css('details[open]', count: 2) # Tool calls and handoffs
    end

    it 'does not expand sections by default' do
      output = render_inline(component)

      expect(output).not_to have_css('details[open]')
    end
  end

  describe 'error handling' do
    it 'handles missing span data gracefully' do
      span.span_data = {}
      span.save!

      expect { render_inline(component) }.not_to raise_error
      output = render_inline(component)

      expect(output).to have_text('0 tokens')
      expect(output).to have_text('$0.0000')
    end

    it 'handles nil span data gracefully' do
      span.span_data = nil
      span.save!

      expect { render_inline(component) }.not_to raise_error
    end

    it 'handles missing metadata gracefully' do
      span.span_data = span_data.except('metadata')
      span.save!

      output = render_inline(component)

      expect(output).to have_text('0 tokens')
      expect(output).to have_text('0ms')
    end
  end
end
