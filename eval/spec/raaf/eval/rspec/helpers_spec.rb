# frozen_string_literal: true

RSpec.describe RAAF::Eval::RSpec::Helpers do
  include described_class

  let(:test_span) do
    {
      id: "test_span_123",
      agent_name: "TestAgent",
      output: "This is a test output",
      usage: { input_tokens: 10, output_tokens: 5 },
      latency_ms: 100,
      metadata: {
        model: "gpt-4o",
        temperature: 0.7
      }
    }
  end

  before do
    RAAF::Eval::SpanRepository.store("test_span_123", test_span)
  end

  describe "#evaluate_span" do
    context "with span ID" do
      it "returns a SpanEvaluator" do
        evaluator = evaluate_span("test_span_123")
        expect(evaluator).to be_a(RAAF::Eval::RSpec::SpanEvaluator)
      end

      it "loads the span data" do
        evaluator = evaluate_span("test_span_123")
        expect(evaluator.span[:id]).to eq("test_span_123")
      end
    end

    context "with span object" do
      it "accepts span via keyword argument" do
        evaluator = evaluate_span(span: test_span)
        expect(evaluator).to be_a(RAAF::Eval::RSpec::SpanEvaluator)
        expect(evaluator.span[:id]).to eq("test_span_123")
      end

      it "accepts span as first argument" do
        evaluator = evaluate_span(test_span)
        expect(evaluator).to be_a(RAAF::Eval::RSpec::SpanEvaluator)
        expect(evaluator.span[:id]).to eq("test_span_123")
      end
    end

    context "with invalid input" do
      it "raises error for invalid span type" do
        expect { evaluate_span(123) }.to raise_error(ArgumentError, /Expected span ID.*or span object/)
      end
    end
  end

  describe "#evaluate_latest_span" do
    it "finds the latest span for an agent" do
      evaluator = evaluate_latest_span(agent: "TestAgent")
      expect(evaluator).to be_a(RAAF::Eval::RSpec::SpanEvaluator)
      expect(evaluator.span[:agent_name]).to eq("TestAgent")
    end

    it "raises error if no span found" do
      expect {
        evaluate_latest_span(agent: "NonexistentAgent")
      }.to raise_error(RAAF::Eval::SpanNotFoundError)
    end
  end

  describe "#find_span" do
    it "finds a span by ID" do
      span = find_span("test_span_123")
      expect(span[:id]).to eq("test_span_123")
    end

    it "raises error if span not found" do
      expect { find_span("nonexistent") }.to raise_error(RAAF::Eval::SpanNotFoundError)
    end
  end

  describe "#query_spans" do
    it "queries spans with filters" do
      spans = query_spans(agent: "TestAgent")
      expect(spans).to be_an(Array)
      expect(spans.first[:agent_name]).to eq("TestAgent")
    end
  end

  describe "#latest_span_for" do
    it "is an alias for evaluate_latest_span" do
      span = latest_span_for("TestAgent")
      expect(span[:agent_name]).to eq("TestAgent")
    end
  end
end
