# frozen_string_literal: true

require "rails_helper"

# An experiment run is the most expensive thing the console starts, and neither
# tokens nor spend appeared on the run, the list or the comparison. Cost is the
# usual reason to prefer one run over another when the scores are level.
RSpec.describe "experiment spend", type: :component do
  let(:screen) { RAAF::Rails::Eval::ExperimentShow }

  def experiment(model: "gpt-4o", tokens: nil)
    instance_double("Experiment", model: model, aggregate_metrics: tokens && { "tokens" => tokens })
  end

  def helper
    RAAF::Rails::Eval::ExperimentList.new(experiments: [])
  end

  def usage_of(one)
    helper.send(:experiment_usage, one)
  end

  def spend_of(one)
    helper.send(:experiment_spend, one)
  end

  let(:recorded) do
    { "total_tokens" => 1400, "total_input_tokens" => 1000, "total_output_tokens" => 400 }
  end

  it "reads the tokens the run recorded" do
    expect(usage_of(experiment(tokens: recorded)))
      .to eq(input: 1000, output: 400, total: 1400, model: "gpt-4o")
  end

  it "prices them against the model the run used" do
    expect(spend_of(experiment(tokens: recorded))).to be > 0
  end

  # A run that recorded nothing has no bill, and $0.00 claims a measurement
  # nobody took.
  it "makes no claim about a run that recorded no tokens" do
    expect(spend_of(experiment)).to be_nil
  end

  # Priced by SpanUsage, which returns nothing for a model it has no price
  # for. That is a different fact from spending nothing.
  it "makes no claim about a model it has no price for" do
    expect(spend_of(experiment(model: "some-unpriced-model", tokens: recorded))).to be_nil
  end

  it "reads jsonb's string keys and an in-memory record's symbols alike" do
    symbols = instance_double("Experiment", model: "gpt-4o",
                                            aggregate_metrics: { tokens: { total_tokens: 1400,
                                                                           total_input_tokens: 1000,
                                                                           total_output_tokens: 400 } })

    expect(usage_of(symbols)).to eq(input: 1000, output: 400, total: 1400, model: "gpt-4o")
  end

  describe "the run metrics" do
    it "reports what the run consumed and what that cost" do
      run = screen.new(experiment: experiment(tokens: recorded), results: [])

      expect(run.send(:tokens_metric)).to include(label: "Tokens", value: "1,400")
      expect(run.send(:spend_metric)[:label]).to eq("Spend")
    end

    # A run that recorded tokens but has no price is a different fact from one
    # that recorded nothing, and the note is where the difference fits.
    it "separates an unpriced model from a run with nothing on it" do
      unpriced = screen.new(experiment: experiment(model: "some-unpriced-model", tokens: recorded),
                            results: [])
      empty = screen.new(experiment: experiment, results: [])

      expect(unpriced.send(:spend_metric)[:note]).to eq("no price for some-unpriced-model")
      expect(empty.send(:spend_metric)[:note]).to eq("nothing billed yet")
    end
  end
end
