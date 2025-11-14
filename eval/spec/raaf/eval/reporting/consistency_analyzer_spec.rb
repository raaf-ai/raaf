# frozen_string_literal: true

require 'spec_helper'
require 'raaf/eval/reporting'

RSpec.describe RAAF::Eval::Reporting::ConsistencyAnalyzer do
  let(:aggregator) { instance_double(RAAF::Eval::Reporting::MultiRunAggregator) }

  subject { described_class.new(aggregator, tolerance: 12) }

  describe '#initialize' do
    it 'stores aggregator and tolerance' do
      expect(subject.aggregator).to eq(aggregator)
      expect(subject.tolerance).to eq(12)
    end

    it 'uses default tolerance of 12' do
      analyzer = described_class.new(aggregator)
      expect(analyzer.tolerance).to eq(12)
    end
  end

  describe '#analyze_field' do
    context 'with valid values' do
      before do
        allow(aggregator).to receive(:field_values)
          .with(:individual_scores)
          .and_return([95, 97, 96, 98, 95])
      end

      let(:analysis) { subject.analyze_field(:individual_scores) }

      it 'calculates mean' do
        expect(analysis[:mean]).to be_within(0.1).of(96.2)
      end

      it 'finds min and max' do
        expect(analysis[:min]).to eq(95)
        expect(analysis[:max]).to eq(98)
      end

      it 'calculates range' do
        expect(analysis[:range]).to eq(3)
      end

      it 'calculates standard deviation' do
        expect(analysis[:std_dev]).to be_within(0.1).of(1.2)
      end

      it 'includes variance status' do
        expect(analysis[:variance_status]).to eq(:acceptable)
      end

      it 'includes sample size' do
        expect(analysis[:sample_size]).to eq(5)
      end
    end

    context 'with empty values' do
      before do
        allow(aggregator).to receive(:field_values)
          .with(:empty_field)
          .and_return([])
      end

      it 'returns nil analysis' do
        analysis = subject.analyze_field(:empty_field)

        expect(analysis[:mean]).to eq(0.0)
        expect(analysis[:sample_size]).to eq(0)
        expect(analysis[:variance_status]).to eq(:unknown)
      end
    end
  end

  describe '#variance_status' do
    it 'returns :perfect for zero range' do
      expect(subject.variance_status(0)).to eq(:perfect)
    end

    it 'returns :acceptable for range within tolerance' do
      expect(subject.variance_status(10)).to eq(:acceptable)
      expect(subject.variance_status(12)).to eq(:acceptable)
    end

    it 'returns :high_variance for range above tolerance' do
      expect(subject.variance_status(13)).to eq(:high_variance)
      expect(subject.variance_status(20)).to eq(:high_variance)
    end
  end

  describe '#analyze_all_fields' do
    before do
      allow(aggregator).to receive(:results_by_field).and_return({
        individual_scores: [
          { individual_scores: { current_value: [95, 90] } },
          { individual_scores: { current_value: [97, 92] } }
        ],
        reasoning_texts: [
          { reasoning_texts: { score: 0.75 } },
          { reasoning_texts: { score: 0.78 } }
        ]
      })

      allow(aggregator).to receive(:field_values)
        .with(:individual_scores)
        .and_return([95, 90, 97, 92])

      allow(aggregator).to receive(:field_values)
        .with(:reasoning_texts)
        .and_return([0.75, 0.78])
    end

    it 'analyzes all fields' do
      analysis = subject.analyze_all_fields

      expect(analysis.keys).to match_array([:individual_scores, :reasoning_texts])
    end

    it 'provides analysis for each field' do
      analysis = subject.analyze_all_fields

      expect(analysis[:individual_scores]).to be_a(Hash)
      expect(analysis[:individual_scores]).to include(:mean, :min, :max, :variance_status)
    end
  end
end
