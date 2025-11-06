# frozen_string_literal: true

RSpec.describe RAAF::Eval::EvaluationEngine do
  let(:engine) { described_class.new }

  describe "#create_run" do
    let(:baseline_span) do
      {
        span_id: "span_123",
        trace_id: "trace_456",
        span_type: "agent",
        agent_name: "TestAgent",
        model: "gpt-4o",
        instructions: "You are a test assistant",
        parameters: { temperature: 0.7 },
        input_messages: [{ role: "user", content: "Hello" }],
        metadata: { tokens: 50 }
      }
    end

    let(:configurations) do
      [
        { name: "GPT-4", changes: { model: "gpt-4o" } },
        { name: "Claude", changes: { model: "claude-3-5-sonnet-20241022", provider: "anthropic" } }
      ]
    end

    it "creates evaluation run with baseline span" do
      run = engine.create_run(
        name: "Test Run",
        baseline_span: baseline_span,
        configurations: configurations
      )

      expect(run).to be_persisted
      expect(run.name).to eq("Test Run")
      expect(run.status).to eq("pending")
      expect(run.evaluation_configurations.count).to eq(2)
    end

    it "stores baseline span" do
      run = engine.create_run(
        name: "Test Run",
        baseline_span: baseline_span,
        configurations: configurations
      )

      stored_span = RAAF::Eval::Models::EvaluationSpan.find_by(span_id: run.baseline_span_id)
      expect(stored_span).not_to be_nil
      expect(stored_span.span_data["agent_name"]).to eq("TestAgent")
    end

    it "creates configurations in order" do
      run = engine.create_run(
        name: "Test Run",
        baseline_span: baseline_span,
        configurations: configurations
      )

      configs = run.evaluation_configurations.ordered
      expect(configs.first.name).to eq("GPT-4")
      expect(configs.last.name).to eq("Claude")
    end
  end

  describe "#execute_run" do
    let(:run) { create(:evaluation_run) }
    let(:baseline_span) { create(:evaluation_span, span_id: run.baseline_span_id) }
    let(:config) do
      create(:evaluation_configuration,
             evaluation_run: run,
             changes: { model: "gpt-4o" })
    end

    before do
      # Mock RAAF::Runner to avoid actual API calls
      allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
        double(messages: [{ role: "assistant", content: "Response" }],
               usage: { total_tokens: 55, input_tokens: 10, output_tokens: 45 })
      )
    end

    it "executes configurations and creates results" do
      results = engine.execute_run(run)

      expect(results.size).to eq(1)
      expect(results.first.status).to eq("completed")
      expect(results.first.token_metrics).not_to be_empty
    end

    it "marks run as completed" do
      engine.execute_run(run)

      run.reload
      expect(run.status).to eq("completed")
    end

    it "handles execution failures gracefully" do
      allow_any_instance_of(RAAF::Runner).to receive(:run).and_raise(StandardError, "API Error")

      expect { engine.execute_run(run) }.to raise_error(StandardError)
      
      run.reload
      expect(run.status).to eq("failed")
    end
  end
end
