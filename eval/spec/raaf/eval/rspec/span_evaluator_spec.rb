# frozen_string_literal: true

RSpec.describe RAAF::Eval::RSpec::SpanEvaluator do
  subject(:evaluator) { described_class.new(test_span) }

  let(:test_span) do
    {
      id: "span_456",
      agent_name: "EvaluatorTestAgent",
      output: "Test output",
      usage: { input_tokens: 20, output_tokens: 10 },
      metadata: { model: "gpt-4o" }
    }
  end

  describe "#with_configuration" do
    it "adds a configuration" do
      evaluator.with_configuration({ temperature: 0.9 }, name: :high_temp)
      expect(evaluator.configurations[:high_temp]).to eq({ temperature: 0.9 })
    end

    it "uses :default name if not specified" do
      evaluator.with_configuration({ temperature: 0.5 })
      expect(evaluator.configurations[:default]).to eq({ temperature: 0.5 })
    end

    it "returns self for chaining" do
      result = evaluator.with_configuration({ model: "gpt-4" })
      expect(result).to eq(evaluator)
    end
  end

  describe "#with_configurations" do
    context "with array of configs" do
      it "adds multiple configurations" do
        configs = [
          { name: :config1, model: "gpt-4o" },
          { name: :config2, model: "claude-3-5-sonnet" }
        ]

        evaluator.with_configurations(configs)

        expect(evaluator.configurations[:config1]).to eq({ name: :config1, model: "gpt-4o" })
        expect(evaluator.configurations[:config2]).to eq({ name: :config2, model: "claude-3-5-sonnet" })
      end

      it "generates names if not provided" do
        configs = [{ model: "gpt-4o" }, { model: "claude-3-5-sonnet" }]

        evaluator.with_configurations(configs)

        expect(evaluator.configurations).to have_key(:config_0)
        expect(evaluator.configurations).to have_key(:config_1)
      end
    end

    context "with hash of configs" do
      it "merges configurations" do
        configs = {
          gpt4: { model: "gpt-4o" },
          claude: { model: "claude-3-5-sonnet" }
        }

        evaluator.with_configurations(configs)

        expect(evaluator.configurations[:gpt4]).to eq({ model: "gpt-4o" })
        expect(evaluator.configurations[:claude]).to eq({ model: "claude-3-5-sonnet" })
      end
    end

    context "with invalid input" do
      it "raises error for invalid type" do
        expect do
          evaluator.with_configurations("invalid")
        end.to raise_error(ArgumentError, /Expected Array or Hash/)
      end
    end
  end

  describe "#run" do
    # #run re-runs the span's agent, which is the one thing here that would reach
    # a model. The engine rescues any failure into a result of its own, so without
    # this stub every example below passes on `success: false` and never sees the
    # configuration it asked about.
    let(:replayed) do
      instance_double(
        RAAF::RunResult,
        messages: [{ role: "user", content: "Test message" }, { role: "assistant", content: "Replayed output" }],
        usage: { input_tokens: 18, output_tokens: 7 }
      )
    end

    before do
      runner = instance_double(RAAF::Runner, run: replayed)
      allow(RAAF::Runner).to receive(:new).and_return(runner)

      evaluator.with_configuration({ temperature: 0.5 }, name: :test_config)
    end

    it "returns an EvaluationResult carrying the span it replayed" do
      result = evaluator.run

      expect(result).to be_a(RAAF::Eval::EvaluationResult)
      expect(result[:test_config]).to include(success: true, output: "Replayed output")
    end

    it "runs the agent once per configuration, under each one's overrides" do
      evaluator.with_configuration({ temperature: 0.9 }, name: :hot)

      result = evaluator.run

      expect(result[:test_config]).to include(configuration: { temperature: 0.5 })
      expect(result[:hot]).to include(configuration: { temperature: 0.9 })
      expect(RAAF::Runner).to have_received(:new).twice
    end

    it "keeps the original span's output and usage beside the new ones" do
      result = evaluator.run[:test_config]

      expect(result).to include(
        baseline_output: "Test output",
        baseline_usage: { input_tokens: 20, output_tokens: 10 },
        usage: { input_tokens: 18, output_tokens: 7 }
      )
    end

    context "with async flag" do
      it "evaluates every configuration, one thread each" do
        evaluator.with_configuration({ temperature: 0.9 }, name: :hot)

        result = evaluator.run(async: true)

        expect(result[:test_config]).to include(success: true)
        expect(result[:hot]).to include(success: true)
      end
    end
  end
end
