# frozen_string_literal: true

require 'spec_helper'
require 'raaf/eval/reporting'

RSpec.describe RAAF::Eval::Reporting::ConsoleReporter do
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
      }
    ]
  end

  let(:aggregator) { RAAF::Eval::Reporting::MultiRunAggregator.new(run_results) }
  let(:analyzer) { RAAF::Eval::Reporting::ConsistencyAnalyzer.new(aggregator, tolerance: 12) }

  subject { described_class.new(aggregator, analyzer) }

  describe '#initialize' do
    it 'stores aggregator and analyzer' do
      expect(subject.aggregator).to eq(aggregator)
      expect(subject.analyzer).to eq(analyzer)
    end
  end

  describe '#generate' do
    it 'prints formatted report to stdout' do
      expect { subject.generate }.to output(/CONSISTENCY ANALYSIS/).to_stdout
    end

    it 'includes header section' do
      expect { subject.generate }.to output(/Across 2 runs/).to_stdout
    end

    it 'includes field analysis' do
      expect { subject.generate }.to output(/individual_scores/).to_stdout
      expect { subject.generate }.to output(/reasoning_texts/).to_stdout
    end

    it 'includes performance summary' do
      expect { subject.generate }.to output(/Performance Summary/).to_stdout
      expect { subject.generate }.to output(/Latency/).to_stdout
      expect { subject.generate }.to output(/Tokens/).to_stdout
    end

    it 'includes overall assessment' do
      expect { subject.generate }.to output(/Overall/).to_stdout
      expect { subject.generate }.to output(/ALL RUNS PASSED/).to_stdout
    end
  end

  describe 'emoji indicators' do
    it 'uses success emoji for passed runs' do
      expect { subject.generate }.to output(/✅/).to_stdout
    end

    it 'uses appropriate variance status emojis' do
      output = capture_stdout { subject.generate }

      # Should include emojis for variance status
      expect(output).to match(/[✅⚠️❌]/)
    end
  end

  describe 'formatting' do
    it 'includes score ranges with standard deviation' do
      expect { subject.generate }.to output(/Score Range.*std dev/).to_stdout
    end

    it 'includes average values' do
      expect { subject.generate }.to output(/Average:/).to_stdout
    end

    it 'includes variance explanations' do
      output = capture_stdout { subject.generate }

      # Should explain variance status
      expect(output).to match(/consistency|variance/i)
    end
  end

  describe 'performance metrics' do
    context 'with latency data' do
      it 'shows average, min, and max latency' do
        output = capture_stdout { subject.generate }

        expect(output).to include('Latency')
        expect(output).to match(/\d+ms/)
      end
    end

    context 'with token data' do
      it 'shows average, min, and max tokens' do
        output = capture_stdout { subject.generate }

        expect(output).to include('Tokens')
        expect(output).to match(/\d+/)
      end
    end

    context 'without performance data' do
      let(:run_results) do
        [
          { evaluation: mock_evaluation1, latency_ms: nil, agent_result: {} }
        ]
      end

      it 'handles missing latency data' do
        expect { subject.generate }.to output(/No data available/).to_stdout
      end
    end

    it 'shows success rate' do
      expect { subject.generate }.to output(/Success Rate: 100%/).to_stdout
    end
  end

  describe 'overall assessment' do
    context 'when all runs passed' do
      it 'shows success status' do
        expect { subject.generate }.to output(/✅.*ALL RUNS PASSED/).to_stdout
      end
    end

    context 'when some runs failed' do
      let(:mock_evaluation3) do
        double('evaluation3',
               field_results: {},
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
            evaluation: mock_evaluation3,
            latency_ms: 35000,
            agent_result: { usage: { total_tokens: 5200 } }
          }
        ]
      end

      it 'shows failure status' do
        expect { subject.generate }.to output(/❌.*SOME RUNS FAILED/).to_stdout
      end
    end
  end

  # Helper method to capture stdout
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
