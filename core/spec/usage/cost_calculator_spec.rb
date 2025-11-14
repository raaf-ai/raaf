# frozen_string_literal: true

require 'spec_helper'
require 'raaf/usage/cost_calculator'

RSpec.describe RAAF::Usage::CostCalculator do
  describe '.calculate_cost' do
    context 'with gpt-4o model' do
      let(:usage) { { input_tokens: 1000, output_tokens: 500 } }

      it 'calculates cost correctly' do
        result = described_class.calculate_cost(usage, model: 'gpt-4o')

        # gpt-4o: $2.50 per 1M input, $10.00 per 1M output
        expect(result[:input_cost]).to eq(0.0025)  # 1000 * 2.50 / 1M
        expect(result[:output_cost]).to eq(0.005)  # 500 * 10.00 / 1M
        expect(result[:total_cost]).to eq(0.0075)
        expect(result[:currency]).to eq('USD')
        expect(result[:pricing_date]).to eq('2025-01')
      end
    end

    context 'with gpt-4o-mini model' do
      let(:usage) { { input_tokens: 10_000, output_tokens: 5_000 } }

      it 'calculates cost correctly' do
        result = described_class.calculate_cost(usage, model: 'gpt-4o-mini')

        # gpt-4o-mini: $0.15 per 1M input, $0.60 per 1M output
        expect(result[:input_cost]).to eq(0.0015)   # 10K * 0.15 / 1M
        expect(result[:output_cost]).to eq(0.003)   # 5K * 0.60 / 1M
        expect(result[:total_cost]).to eq(0.0045)
      end
    end

    context 'with claude-3-5-sonnet model' do
      let(:usage) { { input_tokens: 2000, output_tokens: 1000 } }

      it 'calculates cost correctly' do
        result = described_class.calculate_cost(usage, model: 'claude-3-5-sonnet-20241022')

        # claude-3-5-sonnet: $3.00 per 1M input, $15.00 per 1M output
        expect(result[:input_cost]).to eq(0.006)    # 2K * 3.00 / 1M
        expect(result[:output_cost]).to eq(0.015)   # 1K * 15.00 / 1M
        expect(result[:total_cost]).to eq(0.021)
      end
    end

    context 'with gemini-2.5-flash model' do
      let(:usage) { { input_tokens: 5000, output_tokens: 2500 } }

      it 'calculates cost correctly' do
        result = described_class.calculate_cost(usage, model: 'gemini-2.5-flash')

        # gemini-2.5-flash: $0.15 per 1M input, $0.60 per 1M output
        expect(result[:input_cost]).to eq(0.00075)  # 5K * 0.15 / 1M
        expect(result[:output_cost]).to eq(0.0015)  # 2.5K * 0.60 / 1M
        expect(result[:total_cost]).to eq(0.00225)
      end
    end

    context 'with unknown model' do
      let(:usage) { { input_tokens: 1000, output_tokens: 500 } }

      it 'returns nil when pricing unavailable' do
        result = described_class.calculate_cost(usage, model: 'unknown-model')

        expect(result).to be_nil
      end
    end

    context 'with zero tokens' do
      let(:usage) { { input_tokens: 0, output_tokens: 0 } }

      it 'returns zero costs' do
        result = described_class.calculate_cost(usage, model: 'gpt-4o')

        expect(result[:input_cost]).to eq(0.0)
        expect(result[:output_cost]).to eq(0.0)
        expect(result[:total_cost]).to eq(0.0)
      end
    end

    context 'with missing token fields' do
      it 'treats missing input_tokens as 0' do
        usage = { output_tokens: 500 }
        result = described_class.calculate_cost(usage, model: 'gpt-4o')

        expect(result[:input_cost]).to eq(0.0)
        expect(result[:output_cost]).to eq(0.005)
      end

      it 'treats missing output_tokens as 0' do
        usage = { input_tokens: 1000 }
        result = described_class.calculate_cost(usage, model: 'gpt-4o')

        expect(result[:input_cost]).to eq(0.0025)
        expect(result[:output_cost]).to eq(0.0)
      end
    end

    context 'with large token counts' do
      let(:usage) { { input_tokens: 1_000_000, output_tokens: 500_000 } }

      it 'handles large numbers correctly' do
        result = described_class.calculate_cost(usage, model: 'gpt-4o')

        # 1M input tokens * $2.50 = $2.50
        # 500K output tokens * $10.00 = $5.00
        expect(result[:input_cost]).to eq(2.5)
        expect(result[:output_cost]).to eq(5.0)
        expect(result[:total_cost]).to eq(7.5)
      end
    end

    context 'with fractional costs' do
      let(:usage) { { input_tokens: 123, output_tokens: 456 } }

      it 'rounds to 6 decimal places' do
        result = described_class.calculate_cost(usage, model: 'gpt-4o')

        # 123 * 2.50 / 1M = 0.0003075 → 0.000308 (rounded)
        # 456 * 10.00 / 1M = 0.00456 → 0.00456
        expect(result[:input_cost]).to eq(0.000308)
        expect(result[:output_cost]).to eq(0.00456)
        expect(result[:total_cost]).to eq(0.004868)
      end
    end
  end

  describe '.calculate_total_cost' do
    context 'with multiple usage records from same model' do
      let(:usages) do
        [
          {
            input_tokens: 1000,
            output_tokens: 500,
            provider_metadata: { model: 'gpt-4o' }
          },
          {
            input_tokens: 2000,
            output_tokens: 1000,
            provider_metadata: { model: 'gpt-4o' }
          }
        ]
      end

      it 'aggregates costs correctly' do
        result = described_class.calculate_total_cost(usages)

        # First: 1K input ($0.0025) + 500 output ($0.005) = $0.0075
        # Second: 2K input ($0.005) + 1K output ($0.01) = $0.015
        # Total: $0.0225
        expect(result[:input_cost]).to eq(0.0075)   # $0.0025 + $0.005
        expect(result[:output_cost]).to eq(0.015)   # $0.005 + $0.01
        expect(result[:total_cost]).to eq(0.0225)
        expect(result[:currency]).to eq('USD')
      end
    end

    context 'with multiple usage records from different models' do
      let(:usages) do
        [
          {
            input_tokens: 1000,
            output_tokens: 500,
            provider_metadata: { model: 'gpt-4o' }
          },
          {
            input_tokens: 10_000,
            output_tokens: 5_000,
            provider_metadata: { model: 'gpt-4o-mini' }
          }
        ]
      end

      it 'aggregates costs across models' do
        result = described_class.calculate_total_cost(usages)

        # gpt-4o: $0.0025 + $0.005 = $0.0075
        # gpt-4o-mini: $0.0015 + $0.003 = $0.0045
        # Total: $0.012
        expect(result[:total_cost]).to eq(0.012)
      end
    end

    context 'with empty usage list' do
      it 'returns zero costs' do
        result = described_class.calculate_total_cost([])

        expect(result[:input_cost]).to eq(0.0)
        expect(result[:output_cost]).to eq(0.0)
        expect(result[:total_cost]).to eq(0.0)
      end
    end

    context 'with usages missing model metadata' do
      let(:usages) do
        [
          { input_tokens: 1000, output_tokens: 500 },  # No provider_metadata
          {
            input_tokens: 2000,
            output_tokens: 1000,
            provider_metadata: { model: 'gpt-4o' }
          }
        ]
      end

      it 'skips usages without model info' do
        result = described_class.calculate_total_cost(usages)

        # Only second usage counted: $0.005 + $0.01 = $0.015
        expect(result[:total_cost]).to eq(0.015)
      end
    end

    context 'with usages from unknown models' do
      let(:usages) do
        [
          {
            input_tokens: 1000,
            output_tokens: 500,
            provider_metadata: { model: 'unknown-model' }
          },
          {
            input_tokens: 2000,
            output_tokens: 1000,
            provider_metadata: { model: 'gpt-4o' }
          }
        ]
      end

      it 'skips usages from unknown models' do
        result = described_class.calculate_total_cost(usages)

        # Only gpt-4o usage counted: $0.005 + $0.01 = $0.015
        expect(result[:total_cost]).to eq(0.015)
      end
    end
  end

  describe '.pricing_available?' do
    context 'with hardcoded pricing only' do
      it 'returns true for known models' do
        expect(described_class.pricing_available?('gpt-4o')).to be true
        expect(described_class.pricing_available?('claude-3-5-sonnet-20241022')).to be true
        expect(described_class.pricing_available?('gemini-2.5-flash')).to be true
      end

      it 'returns false for unknown models' do
        expect(described_class.pricing_available?('unknown-model')).to be false
        expect(described_class.pricing_available?('gpt-5')).to be false
      end
    end

    context 'with dynamic pricing from PricingDataManager' do
      let(:pricing_manager) { instance_double(RAAF::Usage::PricingDataManager) }

      before do
        allow(RAAF::Usage::PricingDataManager).to receive(:instance).and_return(pricing_manager)
      end

      it 'returns true when dynamic pricing available' do
        # Model has dynamic pricing but not in hardcoded PRICING
        dynamic_pricing = { input: 1.00, output: 2.00, domain: 'example.com' }
        allow(pricing_manager).to receive(:get_pricing).with('custom-model').and_return(dynamic_pricing)

        expect(described_class.pricing_available?('custom-model')).to be true
      end

      it 'returns true when only hardcoded pricing available' do
        # PricingDataManager returns nil but model in PRICING
        allow(pricing_manager).to receive(:get_pricing).with('gpt-4o').and_return(nil)

        expect(described_class.pricing_available?('gpt-4o')).to be true
      end

      it 'returns false when neither source has pricing' do
        # PricingDataManager returns nil and model not in PRICING
        allow(pricing_manager).to receive(:get_pricing).with('unknown-model').and_return(nil)

        expect(described_class.pricing_available?('unknown-model')).to be false
      end

      it 'prefers dynamic pricing over hardcoded' do
        # Both sources have data, should check dynamic first
        dynamic_pricing = { input: 3.00, output: 12.00, domain: 'openai.com' }
        allow(pricing_manager).to receive(:get_pricing).with('gpt-4o').and_return(dynamic_pricing)

        expect(described_class.pricing_available?('gpt-4o')).to be true
        expect(pricing_manager).to have_received(:get_pricing).with('gpt-4o')
      end
    end
  end

  describe '.get_pricing' do
    context 'with hardcoded pricing only' do
      it 'returns pricing hash for known models' do
        pricing = described_class.get_pricing('gpt-4o')

        expect(pricing[:input]).to eq(2.50)
        expect(pricing[:output]).to eq(10.00)
      end

      it 'returns nil for unknown models' do
        pricing = described_class.get_pricing('unknown-model')

        expect(pricing).to be_nil
      end
    end

    context 'with dynamic pricing from PricingDataManager' do
      let(:pricing_manager) { instance_double(RAAF::Usage::PricingDataManager) }

      before do
        allow(RAAF::Usage::PricingDataManager).to receive(:instance).and_return(pricing_manager)
      end

      it 'uses dynamic pricing when available' do
        # PricingDataManager has data for gpt-4o
        dynamic_pricing = {
          input: 3.00,
          output: 12.00,
          domain: 'openai.com'
        }
        allow(pricing_manager).to receive(:get_pricing).with('gpt-4o').and_return(dynamic_pricing)
        allow(RAAF.logger).to receive(:debug)

        pricing = described_class.get_pricing('gpt-4o')

        expect(pricing).to eq(dynamic_pricing)
        expect(RAAF.logger).to have_received(:debug).with('Using dynamic pricing for gpt-4o from Helicone')
      end

      it 'falls back to hardcoded pricing when dynamic unavailable' do
        # PricingDataManager returns nil (no data)
        allow(pricing_manager).to receive(:get_pricing).with('gpt-4o').and_return(nil)
        allow(RAAF.logger).to receive(:debug)

        pricing = described_class.get_pricing('gpt-4o')

        expect(pricing[:input]).to eq(2.50)  # Hardcoded PRICING
        expect(pricing[:output]).to eq(10.00)
        expect(RAAF.logger).to have_received(:debug).with('Using hardcoded pricing for gpt-4o (Helicone data unavailable)')
      end

      it 'returns nil when neither source has pricing' do
        # PricingDataManager returns nil and model not in PRICING
        allow(pricing_manager).to receive(:get_pricing).with('unknown-model').and_return(nil)
        allow(RAAF.logger).to receive(:warn)

        pricing = described_class.get_pricing('unknown-model')

        expect(pricing).to be_nil
        expect(RAAF.logger).to have_received(:warn).with('No pricing available for model: unknown-model')
      end

      it 'includes domain from dynamic pricing' do
        dynamic_pricing = {
          input: 3.00,
          output: 15.00,
          domain: 'anthropic.com'
        }
        allow(pricing_manager).to receive(:get_pricing).with('claude-3-5-sonnet-20241022').and_return(dynamic_pricing)

        pricing = described_class.get_pricing('claude-3-5-sonnet-20241022')

        expect(pricing[:domain]).to eq('anthropic.com')
      end

      it 'includes cache costs from dynamic pricing when present' do
        dynamic_pricing = {
          input: 2.50,
          output: 10.00,
          domain: 'openai.com',
          prompt_cache_read: 0.25,
          prompt_cache_write: 1.25
        }
        allow(pricing_manager).to receive(:get_pricing).with('gpt-4o').and_return(dynamic_pricing)

        pricing = described_class.get_pricing('gpt-4o')

        expect(pricing[:prompt_cache_read]).to eq(0.25)
        expect(pricing[:prompt_cache_write]).to eq(1.25)
      end
    end
  end

  describe 'PRICING constant' do
    it 'includes all major OpenAI models' do
      expect(described_class::PRICING).to have_key('gpt-4o')
      expect(described_class::PRICING).to have_key('gpt-4o-mini')
      expect(described_class::PRICING).to have_key('o1-preview')
      expect(described_class::PRICING).to have_key('gpt-4-turbo')
    end

    it 'includes all major Anthropic models' do
      expect(described_class::PRICING).to have_key('claude-3-5-sonnet-20241022')
      expect(described_class::PRICING).to have_key('claude-3-opus-20240229')
      expect(described_class::PRICING).to have_key('claude-3-haiku-20240307')
    end

    it 'includes all major Gemini models' do
      expect(described_class::PRICING).to have_key('gemini-2.5-flash')
      expect(described_class::PRICING).to have_key('gemini-2.5-pro')
      expect(described_class::PRICING).to have_key('gemini-1.5-pro')
    end

    it 'includes Perplexity models' do
      expect(described_class::PRICING).to have_key('perplexity')
      expect(described_class::PRICING).to have_key('sonar')
      expect(described_class::PRICING).to have_key('sonar-pro')
    end
  end
end
