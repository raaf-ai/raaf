# frozen_string_literal: true

require 'spec_helper'
require 'raaf/eval/reporting'

RSpec.describe RAAF::Eval::Reporting::ConsistencyReport do
  let(:mock_evaluation1) do
    double('evaluation1',
           field_results: {
             individual_scores: { current_value: [95, 90], score: 0.87 },
             reasoning_texts: { score: 0.75, details: {} }
           },
           passed?: true)
  end

  let(:mock_evaluation2) do
    double('evaluation2',
           field_results: {
             individual_scores: { current_value: [97, 92], score: 0.92 },
             reasoning_texts: { score: 0.78, details: {} }
           },
           passed?: true)
  end

  let(:mock_evaluation3) do
    double('evaluation3',
           field_results: {
             individual_scores: { current_value: [100, 95], score: 0.90 },
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

  subject { described_class.new(run_results, tolerance: 12) }

  describe '#initialize' do
    it 'creates aggregator with run results' do
      expect(subject.aggregator).to be_a(RAAF::Eval::Reporting::MultiRunAggregator)
      expect(subject.aggregator.runs).to eq(run_results)
    end

    it 'creates analyzer with aggregator and tolerance' do
      expect(subject.analyzer).to be_a(RAAF::Eval::Reporting::ConsistencyAnalyzer)
      expect(subject.analyzer.tolerance).to eq(12)
    end

    it 'creates console reporter by default' do
      expect(subject.reporter).to be_a(RAAF::Eval::Reporting::ConsoleReporter)
    end

    it 'accepts custom tolerance' do
      report = described_class.new(run_results, tolerance: 15)
      expect(report.analyzer.tolerance).to eq(15)
    end

    it 'accepts custom reporter type' do
      report = described_class.new(run_results, reporter: :console)
      expect(report.reporter).to be_a(RAAF::Eval::Reporting::ConsoleReporter)
    end
  end

  describe '#generate' do
    it 'delegates to reporter generate' do
      expect(subject.reporter).to receive(:generate)
      subject.generate
    end

    it 'prints formatted output' do
      expect { subject.generate }.to output(/CONSISTENCY ANALYSIS/).to_stdout
    end
  end

  describe '#to_json' do
    let(:json_output) { JSON.parse(subject.to_json) }

    it 'returns valid JSON' do
      expect { JSON.parse(subject.to_json) }.not_to raise_error
    end

    it 'includes metadata section' do
      expect(json_output['metadata']).to be_a(Hash)
      expect(json_output['metadata']['total_runs']).to eq(3)
      expect(json_output['metadata']['tolerance']).to eq(12)
      expect(json_output['metadata']['generated_at']).to be_present
    end

    it 'includes consistency analysis' do
      expect(json_output['consistency_analysis']).to be_a(Hash)
      expect(json_output['consistency_analysis']['individual_scores']).to be_present
      expect(json_output['consistency_analysis']['reasoning_texts']).to be_present
    end

    it 'includes performance summary' do
      expect(json_output['performance_summary']).to be_a(Hash)
      expect(json_output['performance_summary']['latencies']).to eq([30000, 25000, 28000])
      expect(json_output['performance_summary']['tokens']).to eq([5000, 4800, 5200])
    end

    it 'includes consistency metrics in analysis' do
      analysis = json_output['consistency_analysis']['individual_scores']

      expect(analysis['mean']).to be_present
      expect(analysis['min']).to be_present
      expect(analysis['max']).to be_present
      expect(analysis['std_dev']).to be_present
      expect(analysis['variance_status']).to be_present
    end
  end

  describe '#to_csv' do
    let(:csv_output) { subject.to_csv }
    let(:csv_lines) { csv_output.split("\n") }

    it 'returns CSV formatted string' do
      expect(csv_output).to be_a(String)
      expect(csv_output).to include(',')
    end

    it 'includes header row' do
      header = csv_lines.first
      expect(header).to include('field_name')
      expect(header).to include('mean')
      expect(header).to include('min')
      expect(header).to include('max')
      expect(header).to include('variance_status')
    end

    it 'includes data rows for each field' do
      # Header + 2 data rows (individual_scores, reasoning_texts)
      expect(csv_lines.count).to eq(3)
    end

    it 'includes field analysis data' do
      data_row = csv_lines[1]
      expect(data_row).to include('individual_scores')
      expect(data_row).to match(/\d+\.\d+/) # Mean value
    end

    it 'rounds numeric values appropriately' do
      csv_data = CSV.parse(csv_output, headers: true)
      first_row = csv_data.first

      # Mean and std_dev should be rounded to 2 decimals
      expect(first_row['mean'].to_f).to eq(first_row['mean'].to_f.round(2))
      expect(first_row['std_dev'].to_f).to eq(first_row['std_dev'].to_f.round(2))
    end
  end

  describe '#summary' do
    let(:summary) { subject.summary }

    it 'returns summary hash' do
      expect(summary).to be_a(Hash)
    end

    it 'includes total runs' do
      expect(summary[:total_runs]).to eq(3)
    end

    it 'includes success rate' do
      expect(summary[:success_rate]).to eq(2.0 / 3.0)
    end

    it 'includes fields analyzed count' do
      expect(summary[:fields_analyzed]).to eq(2) # individual_scores, reasoning_texts
    end

    it 'includes high variance fields count' do
      expect(summary[:high_variance_fields]).to be_an(Integer)
    end
  end

  describe 'reporter selection' do
    it 'creates console reporter for :console type' do
      report = described_class.new(run_results, reporter: :console)
      expect(report.reporter).to be_a(RAAF::Eval::Reporting::ConsoleReporter)
    end

    it 'uses console reporter as fallback for :json type' do
      report = described_class.new(run_results, reporter: :json)
      expect(report.reporter).to be_a(RAAF::Eval::Reporting::ConsoleReporter)
    end

    it 'uses console reporter as fallback for :csv type' do
      report = described_class.new(run_results, reporter: :csv)
      expect(report.reporter).to be_a(RAAF::Eval::Reporting::ConsoleReporter)
    end

    it 'uses console reporter as fallback for unknown types' do
      report = described_class.new(run_results, reporter: :unknown)
      expect(report.reporter).to be_a(RAAF::Eval::Reporting::ConsoleReporter)
    end
  end

  describe 'integration with analyzer' do
    it 'analyzer can access aggregated data' do
      analysis = subject.analyzer.analyze_field(:individual_scores)

      expect(analysis[:mean]).to be_within(0.1).of(93.5) # (95+90+97+92+100+95)/6
      expect(analysis[:sample_size]).to eq(6)
    end

    it 'analyzer respects custom tolerance' do
      report = described_class.new(run_results, tolerance: 5)
      analysis = report.analyzer.analyze_field(:individual_scores)

      # With range of 10 (100-90) and tolerance of 5, should be high_variance
      expect(analysis[:variance_status]).to eq(:high_variance)
    end
  end

  describe 'usage examples' do
    it 'supports basic usage pattern' do
      report = described_class.new(run_results)

      # Generate console report
      expect { report.generate }.to output(/CONSISTENCY/).to_stdout

      # Export as JSON
      json_data = report.to_json
      expect(JSON.parse(json_data)).to be_a(Hash)

      # Export as CSV
      csv_data = report.to_csv
      expect(csv_data).to include('field_name')
    end

    it 'supports custom configuration' do
      report = described_class.new(
        run_results,
        tolerance: 15,
        reporter: :console
      )

      expect(report.analyzer.tolerance).to eq(15)
      expect(report.aggregator.runs.size).to eq(3)
    end
  end
end
