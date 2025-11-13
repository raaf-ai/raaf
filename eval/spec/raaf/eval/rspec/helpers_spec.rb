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

  describe "#evaluate_run_result" do
    let(:agent) do
      RAAF::Agent.new(
        name: "TestAgent",
        instructions: "You are a test assistant",
        model: "gpt-4o",
        temperature: 0.7
      )
    end

    let(:run_result) do
      RAAF::RunResult.new(
        agent_name: "TestAgent",
        messages: [
          { role: "user", content: "What is 2+2?" },
          { role: "assistant", content: "4" }
        ],
        usage: { total_tokens: 50, input_tokens: 10, output_tokens: 40 },
        final_output: "4"
      )
    end

    it "returns a SpanEvaluator" do
      evaluator = evaluate_run_result(run_result, agent: agent)
      expect(evaluator).to be_a(RAAF::Eval::RSpec::SpanEvaluator)
    end

    it "converts RunResult to span format" do
      evaluator = evaluate_run_result(run_result, agent: agent)

      expect(evaluator.span[:agent_name]).to eq("TestAgent")
      expect(evaluator.span[:model]).to eq("gpt-4o")
      expect(evaluator.span[:instructions]).to eq("You are a test assistant")
      expect(evaluator.span[:source]).to eq("run_result")
    end

    it "works without agent reference" do
      evaluator = evaluate_run_result(run_result)

      expect(evaluator).to be_a(RAAF::Eval::RSpec::SpanEvaluator)
      expect(evaluator.span[:agent_name]).to eq("TestAgent")
      expect(evaluator.span[:model]).to eq("unknown")
    end

    it "supports method chaining" do
      evaluator = evaluate_run_result(run_result, agent: agent)
        .with_configuration(temperature: 0.9)

      expect(evaluator.configurations).to have_key(:default)
      expect(evaluator.configurations[:default]).to include(temperature: 0.9)
    end
  end

  describe "#evaluate_span with RunResult" do
    let(:agent) do
      RAAF::Agent.new(
        name: "TestAgent",
        instructions: "Test instructions",
        model: "gpt-4o"
      )
    end

    let(:run_result) do
      RAAF::RunResult.new(
        agent_name: "TestAgent",
        messages: [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi" }
        ],
        usage: { total_tokens: 20 }
      )
    end

    it "auto-converts RunResult via evaluate_span" do
      evaluator = evaluate_span(run_result, agent: agent)

      expect(evaluator).to be_a(RAAF::Eval::RSpec::SpanEvaluator)
      expect(evaluator.span[:source]).to eq("run_result")
      expect(evaluator.span[:agent_name]).to eq("TestAgent")
    end

    it "requires agent parameter for proper conversion" do
      evaluator = evaluate_span(run_result, agent: agent)

      expect(evaluator.span[:model]).to eq("gpt-4o")
      expect(evaluator.span[:instructions]).to eq("Test instructions")
    end

    it "still supports span ID" do
      evaluator = evaluate_span("test_span_123")

      expect(evaluator).to be_a(RAAF::Eval::RSpec::SpanEvaluator)
      expect(evaluator.span[:id]).to eq("test_span_123")
    end

    it "still supports span hash" do
      evaluator = evaluate_span(test_span)

      expect(evaluator).to be_a(RAAF::Eval::RSpec::SpanEvaluator)
      expect(evaluator.span[:id]).to eq("test_span_123")
    end
  end
end
