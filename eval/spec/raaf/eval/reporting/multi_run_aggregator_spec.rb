# frozen_string_literal: true

require 'spec_helper'
require 'raaf/eval/reporting'

RSpec.describe RAAF::Eval::Reporting::MultiRunAggregator do
  let(:mock_evaluation1) do
    double('evaluation1',
           field_results: {
             individual_scores: { current_value: [95, 90, 75], score: 0.87 },
             reasoning_texts: { score: 0.75, details: {} }
           },
           passed?: true)
  end

  let(:mock_evaluation2) do
    double('evaluation2',
           field_results: {
             individual_scores: { current_value: [95, 95, 85], score: 0.92 },
             reasoning_texts: { score: 0.78, details: {} }
           },
           passed?: true)
  end

  let(:mock_evaluation3) do
    double('evaluation3',
           field_results: {
             individual_scores: { current_value: [100, 95, 75], score: 0.90 },
             reasoning_texts: { score: 0.76, details: {} }
           },
           passed?: false)
  end

  let(:run_results) do
    [
      {
        evaluation: mock_evaluation1,
        latency_ms: 30000,
        agent_result: { usage: { total_tokens: 5000 } }
      },
      {
        evaluation: mock_evaluation2,
        latency_ms: 25000,
        agent_result: { usage: { total_tokens: 4800 } }
      },
      {
        evaluation: mock_evaluation3,
        latency_ms: 28000,
        agent_result: { usage: { total_tokens: 5200 } }
      }
    ]
  end

  subject { described_class.new(run_results) }

  describe '#initialize' do
    it 'stores evaluation results' do
      expect(subject.runs).to eq(run_results)
    end

    it 'accepts empty results' do
      aggregator = described_class.new
      expect(aggregator.runs).to be_empty
    end
  end

  describe '#add_run' do
    it 'adds a run result to the collection' do
      aggregator = described_class.new
      aggregator.add_run(run_results.first)

      expect(aggregator.runs.size).to eq(1)
      expect(aggregator.runs.first).to eq(run_results.first)
    end
  end

  describe '#field_values' do
    it 'extracts array values from field results' do
      values = subject.field_values(:individual_scores)

      expect(values).to eq([95, 90, 75, 95, 95, 85, 100, 95, 75])
    end

    it 'extracts scalar values from field results' do
      values = subject.field_values(:reasoning_texts)

      expect(values).to eq([0.75, 0.78, 0.76])
    end

    it 'returns empty array for non-existent fields' do
      values = subject.field_values(:non_existent_field)

      expect(values).to be_empty
    end

    it 'handles symbol and string field names' do
      symbol_values = subject.field_values(:individual_scores)
      string_values = subject.field_values('individual_scores')

      expect(symbol_values).to eq(string_values)
    end
  end

  describe '#performance_summary' do
    let(:summary) { subject.performance_summary }

    it 'collects latency data' do
      expect(summary[:latencies]).to eq([30000, 25000, 28000])
    end

    it 'collects token data' do
      expect(summary[:tokens]).to eq([5000, 4800, 5200])
    end

    it 'calculates success rate correctly with evaluation objects' do
      # Mock evaluations should respond to passed? method
      allow(mock_evaluation1).to receive(:passed?).and_return(true)
      allow(mock_evaluation2).to receive(:passed?).and_return(true)
      allow(mock_evaluation3).to receive(:passed?).and_return(false)

      expect(summary[:success_rate]).to eq(2.0 / 3.0)
    end

    it 'includes total runs' do
      expect(summary[:total_runs]).to eq(3)
    end

    it 'includes successful runs count' do
      # Mock evaluations should respond to passed? method
      allow(mock_evaluation1).to receive(:passed?).and_return(true)
      allow(mock_evaluation2).to receive(:passed?).and_return(true)
      allow(mock_evaluation3).to receive(:passed?).and_return(false)

      expect(summary[:successful_runs]).to eq(2)
    end
  end

  describe '#results_by_field' do
    let(:grouped) { subject.results_by_field }

    it 'groups field results by field name' do
      expect(grouped.keys).to match_array([:individual_scores, :reasoning_texts])
    end

    it 'includes all runs for each field' do
      expect(grouped[:individual_scores].size).to eq(3)
      expect(grouped[:reasoning_texts].size).to eq(3)
    end
  end
end
