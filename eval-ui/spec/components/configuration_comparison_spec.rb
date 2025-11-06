# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RAAF::Eval::UI::ConfigurationComparison, type: :component do
  let(:baseline_config) do
    {
      id: 1,
      name: "Baseline GPT-4",
      settings: {
        model: "gpt-4o",
        provider: "openai",
        temperature: 0.7,
        max_tokens: 1000,
        top_p: 1.0,
        frequency_penalty: 0.0,
        presence_penalty: 0.0
      },
      metrics: {
        cost: 0.0025,
        latency_ms: 1500,
        tokens: 125
      }
    }
  end

  let(:config_2) do
    {
      id: 2,
      name: "High Temp GPT-4",
      settings: {
        model: "gpt-4o",
        provider: "openai",
        temperature: 0.9,
        max_tokens: 1000,
        top_p: 1.0,
        frequency_penalty: 0.0,
        presence_penalty: 0.0
      },
      metrics: {
        cost: 0.0028,
        latency_ms: 1600,
        tokens: 130
      }
    }
  end

  let(:config_3) do
    {
      id: 3,
      name: "Claude Sonnet",
      settings: {
        model: "claude-3-5-sonnet-20241022",
        provider: "anthropic",
        temperature: 0.7,
        max_tokens: 1500,
        top_p: 1.0,
        frequency_penalty: 0.0,
        presence_penalty: 0.0
      },
      metrics: {
        cost: 0.0020,
        latency_ms: 1200,
        tokens: 120
      }
    }
  end

  let(:configurations) { [baseline_config, config_2, config_3] }

  let(:metrics) do
    {
      cost: "Cost",
      latency_ms: "Latency",
      tokens: "Token Count"
    }
  end

  subject(:component) do
    described_class.new(
      configurations: configurations,
      baseline: baseline_config,
      metrics: metrics
    )
  end

  describe '#template' do
    it 'renders configuration comparison container' do
      output = render_inline(component)

      expect(output).to have_css('.configuration-comparison')
    end

    it 'renders header with comparison count' do
      output = render_inline(component)

      expect(output).to have_text('Configuration Comparison')
      expect(output).to have_text('Comparing 3 configuration(s)')
    end

    it 'renders configuration selector' do
      output = render_inline(component)

      expect(output).to have_css('select#config-selector[multiple]')
      expect(output).to have_css('option', count: 3)
    end
  end

  describe 'tabbed interface' do
    it 'renders all tabs' do
      output = render_inline(component)

      expect(output).to have_css('[role="tab"]', text: 'Overview')
      expect(output).to have_css('[role="tab"]', text: 'Model Settings')
      expect(output).to have_css('[role="tab"]', text: 'Parameters')
      expect(output).to have_css('[role="tab"]', text: 'Metrics')
    end

    it 'marks first tab as active' do
      output = render_inline(component)

      expect(output).to have_css('[role="tab"].border-blue-600', text: 'Overview')
    end

    it 'does not render metrics tab when metrics are empty' do
      component = described_class.new(configurations: configurations, metrics: {})
      output = render_inline(component)

      expect(output).not_to have_css('[role="tab"]', text: 'Metrics')
    end
  end

  describe 'overview panel' do
    it 'renders configuration cards in grid' do
      output = render_inline(component)

      expect(output).to have_css('[data-tab-panel="overview"]')
      expect(output).to have_text('Baseline GPT-4')
      expect(output).to have_text('High Temp GPT-4')
      expect(output).to have_text('Claude Sonnet')
    end

    it 'displays model information' do
      output = render_inline(component)

      expect(output).to have_text('Model:')
      expect(output).to have_text('gpt-4o')
      expect(output).to have_text('claude-3-5-sonnet-20241022')
    end

    it 'displays provider information' do
      output = render_inline(component)

      expect(output).to have_text('Provider:')
      expect(output).to have_text('openai')
      expect(output).to have_text('anthropic')
    end

    it 'displays temperature' do
      output = render_inline(component)

      expect(output).to have_text('Temperature:')
      expect(output).to have_text('0.700')
      expect(output).to have_text('0.900')
    end
  end

  describe 'performance badges' do
    it 'marks baseline configuration' do
      output = render_inline(component)

      expect(output).to have_css('.bg-blue-100.text-blue-800', text: 'Baseline')
    end

    it 'marks best configuration' do
      output = render_inline(component)

      # Claude Sonnet should be best (lowest cost + fastest)
      expect(output).to have_css('.bg-green-100.text-green-800', text: 'Best')
    end

    it 'marks worst configuration' do
      output = render_inline(component)

      # High Temp GPT-4 should be worst (highest cost + slowest)
      expect(output).to have_css('.bg-red-100.text-red-800', text: 'Worst')
    end
  end

  describe 'difference highlighting' do
    it 'highlights configurations different from baseline' do
      output = render_inline(component)

      expect(output).to have_text('1 difference(s) from baseline')
      expect(output).to have_text('4 difference(s) from baseline')
    end

    it 'does not show differences for baseline itself' do
      output = render_inline(component)

      baseline_card = output.css('.border-blue-500').first
      expect(baseline_card).not_to have_text('difference(s) from baseline')
    end
  end

  describe 'model settings panel' do
    it 'renders comparison table' do
      output = render_inline(component)

      expect(output).to have_css('[data-tab-panel="model"]')
      expect(output).to have_css('table')
    end

    it 'displays all setting rows' do
      output = render_inline(component)

      expect(output).to have_text('Model')
      expect(output).to have_text('Provider')
      expect(output).to have_text('Temperature')
      expect(output).to have_text('Max Tokens')
      expect(output).to have_text('Top P')
      expect(output).to have_text('Frequency Penalty')
      expect(output).to have_text('Presence Penalty')
    end

    it 'highlights differences from baseline' do
      output = render_inline(component)

      # Temperature row should have highlighted cell for config_2
      expect(output).to have_css('.bg-yellow-50', minimum: 1)
    end
  end

  describe 'parameters panel' do
    it 'renders parameter sections for each configuration' do
      output = render_inline(component)

      expect(output).to have_css('[data-tab-panel="parameters"]')
      expect(output).to have_text('Baseline GPT-4')
      expect(output).to have_text('High Temp GPT-4')
      expect(output).to have_text('Claude Sonnet')
    end

    it 'displays all parameters' do
      output = render_inline(component)

      expect(output).to have_text('Model')
      expect(output).to have_text('Provider')
      expect(output).to have_text('Temperature')
    end
  end

  describe 'metrics panel' do
    it 'renders metrics comparison table' do
      output = render_inline(component)

      expect(output).to have_css('[data-tab-panel="metrics"]')
      expect(output).to have_text('Cost')
      expect(output).to have_text('Latency')
      expect(output).to have_text('Token Count')
    end

    it 'formats cost values correctly' do
      output = render_inline(component)

      expect(output).to have_text('$0.0025')
      expect(output).to have_text('$0.0028')
      expect(output).to have_text('$0.0020')
    end

    it 'formats latency values correctly' do
      output = render_inline(component)

      expect(output).to have_text('1500ms')
      expect(output).to have_text('1600ms')
      expect(output).to have_text('1200ms')
    end
  end

  describe 'configuration selection' do
    it 'renders only selected configurations' do
      component = described_class.new(
        configurations: configurations,
        selected_indices: [0, 2], # Only baseline and Claude
        metrics: metrics
      )
      output = render_inline(component)

      expect(output).to have_text('Comparing 2 configuration(s)')
      expect(output).to have_text('Baseline GPT-4')
      expect(output).to have_text('Claude Sonnet')
      expect(output).not_to have_text('High Temp GPT-4')
    end
  end

  describe 'footer actions' do
    it 'renders export and save buttons' do
      output = render_inline(component)

      expect(output).to have_button('Export Comparison')
      expect(output).to have_button('Save Comparison')
    end
  end

  describe 'edge cases' do
    it 'handles configurations without names' do
      unnamed_configs = configurations.map { |c| c.except(:name) }
      component = described_class.new(configurations: unnamed_configs, metrics: {})
      output = render_inline(component)

      expect(output).to have_text('Configuration 1')
      expect(output).to have_text('Configuration 2')
      expect(output).to have_text('Configuration 3')
    end

    it 'handles configurations without metrics' do
      no_metrics_configs = configurations.map { |c| c.except(:metrics) }
      component = described_class.new(configurations: no_metrics_configs, metrics: {})
      output = render_inline(component)

      expect(output).not_to have_css('.bg-green-100.text-green-800', text: 'Best')
      expect(output).not_to have_css('.bg-red-100.text-red-800', text: 'Worst')
    end

    it 'handles missing settings values' do
      partial_config = [{
        id: 1,
        name: "Partial Config",
        settings: { model: "gpt-4o" }
      }]
      component = described_class.new(configurations: partial_config, metrics: {})
      output = render_inline(component)

      expect(output).to have_text('Not specified', minimum: 1)
    end

    it 'handles empty configurations array' do
      component = described_class.new(configurations: [], metrics: {})

      expect { render_inline(component) }.not_to raise_error
      output = render_inline(component)

      expect(output).to have_text('Comparing 0 configuration(s)')
    end
  end
end
