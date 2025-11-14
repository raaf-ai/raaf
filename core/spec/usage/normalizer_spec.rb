# frozen_string_literal: true

require 'spec_helper'
require 'raaf/usage/normalizer'

RSpec.describe RAAF::Usage::Normalizer do
  describe '.normalize' do
    context 'with OpenAI response format (prompt_tokens, completion_tokens)' do
      let(:response) do
        {
          usage: {
            prompt_tokens: 100,
            completion_tokens: 50,
            total_tokens: 150
          }
        }
      end

      it 'normalizes to canonical format' do
        result = described_class.normalize(response, provider_name: 'openai', model: 'gpt-4o')

        expect(result[:input_tokens]).to eq(100)
        expect(result[:output_tokens]).to eq(50)
        expect(result[:total_tokens]).to eq(150)
      end

      it 'includes provider metadata' do
        result = described_class.normalize(response, provider_name: 'openai', model: 'gpt-4o')

        expect(result[:provider_metadata][:provider_name]).to eq('openai')
        expect(result[:provider_metadata][:model]).to eq('gpt-4o')
        expect(result[:provider_metadata][:raw_usage]).to eq(response[:usage])
      end
    end

    context 'with Anthropic response format (input_tokens, output_tokens)' do
      let(:response) do
        {
          usage: {
            input_tokens: 200,
            output_tokens: 100
          }
        }
      end

      it 'normalizes to canonical format' do
        result = described_class.normalize(response, provider_name: 'anthropic', model: 'claude-3-5-sonnet-20241022')

        expect(result[:input_tokens]).to eq(200)
        expect(result[:output_tokens]).to eq(100)
      end

      it 'calculates total_tokens when not provided' do
        result = described_class.normalize(response, provider_name: 'anthropic', model: 'claude-3-5-sonnet-20241022')

        expect(result[:total_tokens]).to eq(300)
      end
    end

    context 'with string keys (not symbols)' do
      let(:response) do
        {
          'usage' => {
            'prompt_tokens' => 150,
            'completion_tokens' => 75,
            'total_tokens' => 225
          }
        }
      end

      it 'handles string keys correctly' do
        result = described_class.normalize(response, provider_name: 'openai', model: 'gpt-4o-mini')

        expect(result[:input_tokens]).to eq(150)
        expect(result[:output_tokens]).to eq(75)
        expect(result[:total_tokens]).to eq(225)
      end
    end

    context 'with output_tokens_details (reasoning tokens for o1 models)' do
      let(:response) do
        {
          usage: {
            input_tokens: 500,
            output_tokens: 1000,
            total_tokens: 1500,
            output_tokens_details: {
              reasoning_tokens: 400
            }
          }
        }
      end

      it 'extracts reasoning token details' do
        result = described_class.normalize(response, provider_name: 'openai', model: 'o1-preview')

        expect(result[:output_tokens_details][:reasoning_tokens]).to eq(400)
      end

      it 'excludes output_tokens_details if reasoning_tokens is 0' do
        response[:usage][:output_tokens_details][:reasoning_tokens] = 0

        result = described_class.normalize(response, provider_name: 'openai', model: 'o1-preview')

        expect(result[:output_tokens_details]).to be_nil
      end
    end

    context 'with input_tokens_details (cached tokens)' do
      let(:response) do
        {
          usage: {
            input_tokens: 1000,
            output_tokens: 500,
            total_tokens: 1500,
            input_tokens_details: {
              cached_tokens: 800
            }
          }
        }
      end

      it 'extracts cached token details' do
        result = described_class.normalize(response, provider_name: 'openai', model: 'gpt-4o')

        expect(result[:input_tokens_details][:cached_tokens]).to eq(800)
      end

      it 'excludes input_tokens_details if cached_tokens is 0' do
        response[:usage][:input_tokens_details][:cached_tokens] = 0

        result = described_class.normalize(response, provider_name: 'openai', model: 'gpt-4o')

        expect(result[:input_tokens_details]).to be_nil
      end
    end

    context 'with missing usage data' do
      it 'returns nil when usage is nil' do
        result = described_class.normalize({}, provider_name: 'openai', model: 'gpt-4o')

        expect(result).to be_nil
      end

      it 'returns nil when usage is empty' do
        result = described_class.normalize({ usage: {} }, provider_name: 'openai', model: 'gpt-4o')

        expect(result).to be_nil
      end
    end

    context 'with zero token counts' do
      let(:response) do
        {
          usage: {
            prompt_tokens: 0,
            completion_tokens: 0,
            total_tokens: 0
          }
        }
      end

      it 'returns normalized usage with zeros' do
        result = described_class.normalize(response, provider_name: 'openai', model: 'gpt-4o')

        expect(result[:input_tokens]).to eq(0)
        expect(result[:output_tokens]).to eq(0)
        expect(result[:total_tokens]).to eq(0)
      end
    end

    context 'with partial token data' do
      let(:response) do
        {
          usage: {
            prompt_tokens: 100
            # Missing completion_tokens and total_tokens
          }
        }
      end

      it 'fills in missing fields with defaults' do
        result = described_class.normalize(response, provider_name: 'openai', model: 'gpt-4o')

        expect(result[:input_tokens]).to eq(100)
        expect(result[:output_tokens]).to eq(0)
        expect(result[:total_tokens]).to eq(100) # Calculated from input + output
      end
    end

    context 'with total_tokens provided' do
      let(:response) do
        {
          usage: {
            input_tokens: 100,
            output_tokens: 50,
            total_tokens: 200 # Different from sum (edge case)
          }
        }
      end

      it 'preserves provided total_tokens if > 0' do
        result = described_class.normalize(response, provider_name: 'anthropic', model: 'claude-3-5-sonnet-20241022')

        expect(result[:total_tokens]).to eq(200) # Uses provided value
      end
    end

    context 'with total_tokens as 0 or nil' do
      it 'calculates total when total_tokens is 0' do
        response = {
          usage: {
            input_tokens: 100,
            output_tokens: 50,
            total_tokens: 0
          }
        }

        result = described_class.normalize(response, provider_name: 'anthropic', model: 'claude-3-5-sonnet-20241022')

        expect(result[:total_tokens]).to eq(150) # Calculated
      end

      it 'calculates total when total_tokens is nil' do
        response = {
          usage: {
            input_tokens: 100,
            output_tokens: 50,
            total_tokens: nil
          }
        }

        result = described_class.normalize(response, provider_name: 'anthropic', model: 'claude-3-5-sonnet-20241022')

        expect(result[:total_tokens]).to eq(150) # Calculated
      end
    end
  end
end
