# frozen_string_literal: true

RSpec.describe RAAF::Eval::Metrics::TokenMetrics do
  describe ".calculate" do
    let(:baseline_span) do
      create(:evaluation_span,
             span_data: {
               metadata: {
                 tokens: 100,
                 input_tokens: 30,
                 output_tokens: 70
               }
             })
    end

    let(:result_span) do
      create(:evaluation_span,
             span_data: {
               metadata: {
                 tokens: 120,
                 input_tokens: 30,
                 output_tokens: 90
               }
             })
    end

    it "calculates token metrics" do
      metrics = described_class.calculate(baseline_span, result_span)

      expect(metrics[:baseline][:total]).to eq(100)
      expect(metrics[:result][:total]).to eq(120)
      expect(metrics[:delta][:total]).to eq(20)
      expect(metrics[:percentage_change]).to eq(20.0)
    end

    it "calculates percentage change correctly" do
      metrics = described_class.calculate(baseline_span, result_span)

      expect(metrics[:percentage_change]).to eq(20.0)
    end

    it "handles zero baseline tokens" do
      baseline_span.span_data["metadata"]["tokens"] = 0
      baseline_span.save!

      metrics = described_class.calculate(baseline_span, result_span)

      expect(metrics[:percentage_change]).to eq(0)
    end
  end
end
