# frozen_string_literal: true

require "rails_helper"

# An experiment run is the most expensive thing the console starts, and neither
# tokens nor spend appeared on the run, the list or the comparison. Cost is the
# usual reason to prefer one run over another when the scores are level.
#
# The figure was then derived as each screen drew it, against today's pricing
# table. It is recorded when the run finishes now, so the list can order by it
# and an old run keeps the number it was billed.
RSpec.describe "experiment spend", type: :component do
  let(:screen) { RAAF::Rails::Eval::ExperimentShow }
  let(:dataset) { RAAF::Eval::Models::Dataset.create!(name: "Briefings #{SecureRandom.hex(3)}") }

  let(:recorded) do
    { "total_tokens" => 1400, "total_input_tokens" => 1000, "total_output_tokens" => 400 }
  end

  def experiment(model: "gpt-4o", tokens: nil, **attributes)
    RAAF::Eval::Models::Experiment.create!(
      { name: "Run #{SecureRandom.hex(3)}", dataset: dataset, model: model,
        aggregate_metrics: tokens && { "tokens" => tokens } }.merge(attributes)
    )
  end

  describe "the tokens it is priced from" do
    it "reads the tokens the run recorded" do
      expect(experiment(tokens: recorded).usage)
        .to eq(input: 1000, output: 400, total: 1400, model: "gpt-4o")
    end

    it "reads jsonb's string keys and an in-memory record's symbols alike" do
      symbols = RAAF::Eval::Models::Experiment.new(
        name: "In memory", dataset: dataset, model: "gpt-4o",
        aggregate_metrics: { tokens: { total_tokens: 1400, total_input_tokens: 1000,
                                       total_output_tokens: 400 } }
      )

      expect(symbols.usage).to eq(input: 1000, output: 400, total: 1400, model: "gpt-4o")
    end
  end

  describe "what a finished run records" do
    # The whole point of the column: the figure is a fact about the run, not a
    # re-derivation at whatever the pricing table says on the day it is read.
    it "prices the run when it completes" do
      run = experiment(tokens: recorded)
      item = dataset.dataset_items.create!(input: { "ask" => "hello" })
      run.experiment_results.create!(dataset_item: item, status: "completed",
                                     token_metrics: recorded, scores: {})

      run.complete!

      expect(run.reload.cost).to be > 0
      expect(run).to be_spend_recorded
    end

    it "does not re-price a recorded run when the pricing table moves" do
      run = experiment(tokens: recorded, cost: 0.42)

      allow(::RAAF::Tracing::SpanUsage).to receive(:cost).and_return(99.0)

      expect(run.spend).to eq(0.42)
    end

    # Runs that finished before the column existed have nothing recorded, and
    # a dash where a figure used to be would be a regression of its own.
    it "still prices a run recorded before the column existed" do
      run = experiment(tokens: recorded)

      expect(run.spend).to be > 0
      expect(run).not_to be_spend_recorded
    end
  end

  describe "what it does not claim" do
    # A run that recorded nothing has no bill, and $0.00 claims a measurement
    # nobody took.
    it "makes no claim about a run that recorded no tokens" do
      expect(experiment.spend).to be_nil
    end

    # Priced by SpanUsage, which returns nothing for a model it has no price
    # for. That is a different fact from spending nothing.
    it "makes no claim about a model it has no price for" do
      expect(experiment(model: "some-unpriced-model", tokens: recorded).spend).to be_nil
    end
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

    # Which kind of figure it is, since one of them moves and the other does
    # not.
    it "says whether the figure was recorded or priced today" do
      stored = screen.new(experiment: experiment(tokens: recorded, cost: 0.42), results: [])
      derived = screen.new(experiment: experiment(tokens: recorded), results: [])

      expect(stored.send(:spend_metric)[:note]).to eq("priced at gpt-4o when it ran")
      expect(derived.send(:spend_metric)[:note]).to eq("priced at today's rate for gpt-4o")
    end
  end
end
