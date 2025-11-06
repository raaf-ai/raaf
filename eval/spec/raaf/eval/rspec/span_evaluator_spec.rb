# frozen_string_literal: true

RSpec.describe RAAF::Eval::RSpec::SpanEvaluator do
  let(:test_span) do
    {
      id: "span_456",
      agent_name: "EvaluatorTestAgent",
      output: "Test output",
      usage: { input_tokens: 20, output_tokens: 10 },
      metadata: { model: "gpt-4o" }
    }
  end

  subject(:evaluator) { described_class.new(test_span) }

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
        expect {
          evaluator.with_configurations("invalid")
        }.to raise_error(ArgumentError, /Expected Array or Hash/)
      end
    end
  end

  describe "#run" do
    before do
      evaluator.with_configuration({ temperature: 0.5 }, name: :test_config)
    end

    it "returns an EvaluationResult" do
      result = evaluator.run
      expect(result).to be_a(RAAF::Eval::EvaluationResult)
    end

    it "executes all configurations" do
      result = evaluator.run
      expect(result[:test_config]).to be_a(Hash)
    end

    context "with async flag" do
      it "supports async execution" do
        result = evaluator.run(async: true)
        expect(result).to be_a(RAAF::Eval::EvaluationResult)
      end
    end
  end
end
