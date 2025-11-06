# frozen_string_literal: true

RSpec.describe "Evaluation Workflow Integration", type: :integration do
  let(:engine) { RAAF::Eval::EvaluationEngine.new }

  describe "complete evaluation workflow" do
    let(:baseline_span) do
      {
        span_id: SecureRandom.uuid,
        trace_id: SecureRandom.uuid,
        span_type: "agent",
        agent_name: "WeatherAgent",
        model: "gpt-4o",
        instructions: "You are a weather assistant",
        parameters: { temperature: 0.7, max_tokens: 100 },
        input_messages: [{ role: "user", content: "What's the weather?" }],
        output_messages: [{ role: "assistant", content: "It's sunny and 72F" }],
        metadata: {
          tokens: 50,
          input_tokens: 10,
          output_tokens: 40,
          latency_ms: 1000
        }
      }
    end

    let(:configurations) do
      [
        {
          name: "Higher Temperature",
          changes: { parameters: { temperature: 0.9 } }
        },
        {
          name: "Lower Temperature",
          changes: { parameters: { temperature: 0.3 } }
        }
      ]
    end

    before do
      # Mock RAAF::Runner to avoid actual API calls
      allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
        double(
          messages: [
            { role: "user", content: "What's the weather?" },
            { role: "assistant", content: "It's sunny and warm today!" }
          ],
          usage: {
            total_tokens: 55,
            input_tokens: 10,
            output_tokens: 45
          }
        )
      )
    end

    it "creates and executes evaluation run successfully" do
      # Step 1: Create evaluation run
      run = engine.create_run(
        name: "Temperature Parameter Test",
        description: "Testing impact of temperature parameter",
        baseline_span: baseline_span,
        configurations: configurations,
        initiated_by: "test_user"
      )

      expect(run).to be_persisted
      expect(run.status).to eq("pending")
      expect(run.evaluation_configurations.count).to eq(2)

      # Step 2: Execute evaluation
      results = engine.execute_run(run)

      expect(results.size).to eq(2)
      results.each do |result|
        expect(result.status).to eq("completed")
        expect(result.token_metrics).not_to be_empty
        expect(result.baseline_comparison).not_to be_empty
      end

      # Step 3: Verify run completed
      run.reload
      expect(run.status).to eq("completed")
      expect(run.started_at).not_to be_nil
      expect(run.completed_at).not_to be_nil
    end

    it "stores all metric categories" do
      run = engine.create_run(
        name: "Comprehensive Metrics Test",
        baseline_span: baseline_span,
        configurations: [configurations.first]
      )

      results = engine.execute_run(run)
      result = results.first

      expect(result.token_metrics).to include(:baseline, :result, :delta, :percentage_change)
      expect(result.baseline_comparison).to include(:token_delta, :latency_delta, :quality_change, :regression_detected)
    end

    it "detects regressions when metrics degrade significantly" do
      # Mock a result with significantly more tokens
      allow_any_instance_of(RAAF::Runner).to receive(:run).and_return(
        double(
          messages: [{ role: "assistant", content: "Long response" * 100 }],
          usage: {
            total_tokens: 200, # 4x increase
            input_tokens: 10,
            output_tokens: 190
          }
        )
      )

      run = engine.create_run(
        name: "Regression Detection Test",
        baseline_span: baseline_span,
        configurations: [configurations.first]
      )

      results = engine.execute_run(run)
      result = results.first

      expect(result.baseline_comparison[:regression_detected]).to be true
      expect(result.quality_change).to eq("degraded")
    end
  end
end
