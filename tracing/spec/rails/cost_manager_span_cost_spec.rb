# frozen_string_literal: true

require "spec_helper"
require "raaf-core"
require_relative "../../lib/raaf/cost_manager"

RSpec.describe RAAF::Tracing::CostManager, "#calculate_span_cost" do
  subject(:manager) { described_class.new }

  def span(kind: "agent", attributes: {}, **columns)
    Struct.new(:span_id, :kind, :span_attributes, :input_tokens, :output_tokens,
               :total_tokens, :agent_model)
          .new("span_#{"a" * 24}", kind, attributes,
               columns[:input_tokens], columns[:output_tokens],
               columns[:total_tokens], columns[:agent_model])
  end

  # Almost nothing emits an llm span in practice — the DSL agent records its
  # model and tokens on the agent span — so a costing pass that filtered on
  # kind reported an empty bill for a workload that had spent real money.
  it "costs an agent span, not only an llm span" do
    cost = manager.calculate_span_cost(
      span(attributes: { "agent.model" => "gpt-4o",
                         "input_tokens" => 1_000_000,
                         "output_tokens" => 1_000_000 })
    )

    expect(cost[:model]).to eq("gpt-4o")
    expect(cost[:total_cost]).to be_within(0.000001).of(12.50)
  end

  it "costs an llm span recorded under the llm.usage.* keys" do
    cost = manager.calculate_span_cost(
      span(kind: "llm", attributes: { "llm.request.model" => "gpt-4o",
                                      "llm.usage.prompt_tokens" => 1_000_000,
                                      "llm.usage.completion_tokens" => 0 })
    )

    expect(cost[:total_cost]).to be_within(0.000001).of(2.50)
  end

  it "charges for tokens the provider billed without itemising" do
    cost = manager.calculate_span_cost(
      span(input_tokens: 488, output_tokens: 70, total_tokens: 941,
           agent_model: "gemini-2.5-flash")
    )

    expect(cost[:total_cost]).to be_within(0.000001).of(0.001279)
  end

  # A dashboard adding output_tokens up beside a token count from anywhere
  # else has to get the same number, so the reported figure stays reported and
  # the billed one gets its own name.
  it "keeps the reported output separate from the billed one" do
    cost = manager.calculate_span_cost(
      span(input_tokens: 488, output_tokens: 70, total_tokens: 941,
           agent_model: "gemini-2.5-flash")
    )

    expect(cost[:output_tokens]).to eq(70)
    expect(cost[:billable_output_tokens]).to eq(453)
    expect(cost[:total_tokens]).to eq(941)
  end

  it "zeroes a span that recorded no usage" do
    cost = manager.calculate_span_cost(span(kind: "tool", attributes: { "function.name" => "x" }))

    expect(cost[:total_cost]).to eq(0.0)
    expect(cost[:model]).to be_nil
  end

  it "reports the tokens but no cost for a model with no pricing entry" do
    cost = manager.calculate_span_cost(
      span(input_tokens: 100, output_tokens: 40, agent_model: "some-unlisted-model")
    )

    expect(cost[:model]).to eq("some-unlisted-model")
    expect(cost[:input_tokens]).to eq(100)
    expect(cost[:total_cost]).to eq(0.0)
  end

  context "with a caller-supplied pricing table" do
    subject(:manager) do
      described_class.new(pricing: { "house-model" => { input: 0.001, output: 0.002 } })
    end

    # Overriding the rates is the reason to pass a table, so it wins.
    it "uses the override for a model it covers" do
      cost = manager.calculate_span_cost(
        span(attributes: { "agent.model" => "house-model",
                           "input_tokens" => 1000,
                           "output_tokens" => 500 })
      )

      expect(cost[:total_cost]).to be_within(0.000001).of(2.0)
    end

    it "falls through to the maintained table for a model it does not cover" do
      cost = manager.calculate_span_cost(
        span(attributes: { "agent.model" => "gpt-4o",
                           "input_tokens" => 1_000_000,
                           "output_tokens" => 0 })
      )

      expect(cost[:total_cost]).to be_within(0.000001).of(2.50)
    end
  end
end

RSpec.describe RAAF::Tracing::CostManager, "#calculate_cost_trend" do
  subject(:manager) { described_class.new }

  def trend(values)
    manager.send(:calculate_cost_trend, values)
  end

  # descriptive_statistics reopens Enumerable and replaces sum with one that
  # hands the block a single value, so a two-parameter each_with_index block
  # got nil for its index and the forecast died on "nil can't be coerced into
  # Integer" — taking the whole costs dashboard down with it. Nothing here
  # loads that gem, so this covers the arithmetic; the page itself is covered
  # by a request spec in the host application.
  it "measures a rising series as rising" do
    expect(trend([1.0, 2.0, 3.0, 4.0])).to be > 0
  end

  it "measures a falling series as falling" do
    expect(trend([4.0, 3.0, 2.0, 1.0])).to be < 0
  end

  it "measures a flat series as flat" do
    expect(trend([2.0, 2.0, 2.0, 2.0])).to eq(0)
  end

  it "is flat rather than a division by zero for a single day" do
    expect(trend([2.0])).to eq(0)
  end

  it "computes the least-squares slope" do
    # y = 2x + 1 sampled at x = 0..3.
    expect(trend([1.0, 3.0, 5.0, 7.0])).to be_within(0.000001).of(2.0)
  end
end
