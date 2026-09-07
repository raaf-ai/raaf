# frozen_string_literal: true

require "spec_helper"

# Pricing lives in raaf-core and logs through RAAF.logger, which the core entry
# point defines — so load the gem rather than the one file.
require "raaf-core"
require_relative "../../lib/raaf/tracing/span_usage"

RSpec.describe RAAF::Tracing::SpanUsage do
  # A span record stands in for either persisted model: what the module needs
  # is the four native columns and an attributes payload.
  def span(attributes: {}, **columns)
    Struct.new(:span_attributes, :input_tokens, :output_tokens, :total_tokens, :agent_model)
          .new(attributes,
               columns[:input_tokens],
               columns[:output_tokens],
               columns[:total_tokens],
               columns[:agent_model])
  end

  describe ".from_attributes" do
    it "reads the top-level keys an agent span emits" do
      usage = described_class.from_attributes(
        "agent.model" => "gemini-2.5-flash",
        "input_tokens" => 488,
        "output_tokens" => 70,
        "total_tokens" => 941
      )

      expect(usage).to eq(input: 488, output: 70, total: 941, model: "gemini-2.5-flash")
    end

    it "reads the llm.usage.* keys in the input/output vocabulary" do
      usage = described_class.from_attributes(
        "llm.request.model" => "gpt-4o",
        "llm.usage.input_tokens" => 100,
        "llm.usage.output_tokens" => 40,
        "llm.usage.total_tokens" => 140
      )

      expect(usage).to eq(input: 100, output: 40, total: 140, model: "gpt-4o")
    end

    it "reads the llm.usage.* keys in the prompt/completion vocabulary" do
      usage = described_class.from_attributes(
        "llm.request.model" => "gpt-4o",
        "llm.usage.prompt_tokens" => 10,
        "llm.usage.completion_tokens" => 20
      )

      expect(usage).to eq(input: 10, output: 20, total: nil, model: "gpt-4o")
    end

    it "reads the stringified llm.tokens.* keys LLMCollector emits" do
      usage = described_class.from_attributes(
        "llm.model" => "gpt-4o",
        "llm.tokens.input" => "1250",
        "llm.tokens.output" => "342",
        "llm.tokens.total" => "1592"
      )

      expect(usage).to eq(input: 1250, output: 342, total: 1592, model: "gpt-4o")
    end

    it "reads counts nested under a usage hash" do
      usage = described_class.from_attributes(
        "model" => "claude-3-haiku-20240307",
        "usage" => { "prompt_tokens" => 30, "completion_tokens" => 12 }
      )

      expect(usage).to eq(input: 30, output: 12, total: nil, model: "claude-3-haiku-20240307")
    end

    it "treats the tracer's N/A placeholders as absent rather than as data" do
      usage = described_class.from_attributes(
        "agent.model" => "N/A",
        "agent.max_tokens" => "N/A",
        "llm.tokens.input" => "N/A"
      )

      expect(usage).to eq(input: nil, output: nil, total: nil, model: nil)
    end

    it "reports nothing for a span that recorded no usage" do
      expect(described_class.from_attributes("agent.name" => "Researcher"))
        .to eq(input: nil, output: nil, total: nil, model: nil)
    end

    it "tolerates a nil payload" do
      expect(described_class.from_attributes(nil))
        .to eq(input: nil, output: nil, total: nil, model: nil)
    end
  end

  describe ".for_span" do
    it "prefers the native columns" do
      record = span(input_tokens: 10, output_tokens: 5, total_tokens: 15, agent_model: "gpt-4o",
                    attributes: { "input_tokens" => 999, "agent.model" => "gpt-3.5-turbo" })

      expect(described_class.for_span(record))
        .to eq(input: 10, output: 5, total: 15, model: "gpt-4o")
    end

    # The columns arrived after most spans were written and no backfill can be
    # assumed, so a nil column means "not copied yet", not "no tokens".
    it "falls back to the payload for a column that was never filled" do
      record = span(input_tokens: 488, output_tokens: 70, agent_model: "gemini-2.5-flash",
                    attributes: { "total_tokens" => 941 })

      expect(described_class.for_span(record))
        .to eq(input: 488, output: 70, total: 941, model: "gemini-2.5-flash")
    end
  end

  describe ".total_tokens" do
    it "prefers the reported total over input + output" do
      expect(described_class.total_tokens(input: 488, output: 70, total: 941)).to eq(941)
    end

    it "falls back to the sum when no total was reported" do
      expect(described_class.total_tokens(input: 100, output: 40, total: nil)).to eq(140)
    end

    it "is nil rather than zero when nothing was recorded" do
      expect(described_class.total_tokens(input: nil, output: nil, total: nil)).to be_nil
    end
  end

  describe ".billable_output" do
    # Gemini 2.5 charges thinking tokens at the output rate but reports them
    # only inside the total, so the gap is the sole evidence they existed.
    it "counts tokens the provider billed for but did not itemise" do
      expect(described_class.billable_output(input: 488, output: 70, total: 941)).to eq(453)
    end

    it "is the reported output when the total accounts for input and output alone" do
      expect(described_class.billable_output(input: 100, output: 40, total: 140)).to eq(40)
    end

    it "is the reported output when no total was recorded" do
      expect(described_class.billable_output(input: 100, output: 40, total: nil)).to eq(40)
    end

    # A total below input + output means the provider itemised more than it
    # totalled; trusting the gap would subtract tokens that were really billed.
    it "does not go below the reported output when the total is smaller" do
      expect(described_class.billable_output(input: 100, output: 40, total: 120)).to eq(40)
    end
  end

  describe ".cost" do
    it "prices input and output at the model's per-million rates" do
      # gemini-2.5-flash: $0.30 in, $2.50 out per 1M tokens.
      cost = described_class.cost(input: 1_000_000, output: 1_000_000, total: nil,
                                  model: "gemini-2.5-flash")

      expect(cost).to eq(2.8)
    end

    it "charges for unitemised tokens at the output rate" do
      priced = described_class.cost(input: 488, output: 70, total: 941, model: "gemini-2.5-flash")
      ignoring_the_total = described_class.cost(input: 488, output: 70, total: nil,
                                                model: "gemini-2.5-flash")

      expect(priced).to be > ignoring_the_total
      expect(priced).to eq(((488 / 1_000_000.0) * 0.30).round(6) + ((453 / 1_000_000.0) * 2.50).round(6))
    end

    # Nil, not zero: a dashboard has to be able to say "unknown" rather than
    # print $0.00 over a run that certainly cost something.
    it "is nil for a model with no pricing entry" do
      expect(described_class.cost(input: 100, output: 40, total: nil, model: "some-new-model"))
        .to be_nil
    end

    it "is nil when the span recorded no model" do
      expect(described_class.cost(input: 100, output: 40, total: nil, model: nil)).to be_nil
    end

    it "is nil when the span recorded no tokens" do
      expect(described_class.cost(input: nil, output: nil, total: nil, model: "gpt-4o")).to be_nil
    end
  end

  # A span that carries a kind, for the billing rules — which the token
  # readers above deliberately do not need.
  def billed_span(kind:, attributes: {}, **columns)
    Struct.new(:kind, :span_attributes, :input_tokens, :output_tokens, :total_tokens, :agent_model)
          .new(kind, attributes,
               columns[:input_tokens], columns[:output_tokens],
               columns[:total_tokens], columns[:agent_model])
  end

  describe ".billing_mode" do
    it "bills a model call by the token" do
      expect(described_class.billing_mode(billed_span(kind: "llm"))).to eq(:tokens)
    end

    it "bills a search by the call, however it named itself" do
      by_kind = billed_span(kind: "search")
      by_type = billed_span(kind: "component", attributes: { "component.type" => "search" })

      expect(described_class.billing_mode(by_kind)).to eq(:cost)
      expect(described_class.billing_mode(by_type)).to eq(:cost)
    end

    # A job brackets a run; the money belongs to the spans inside it, and
    # billing it as well would count the same spend twice.
    it "bills a job not at all" do
      expect(described_class.billing_mode(billed_span(kind: "job"))).to eq(:none)
    end

    # The token readers take a span with no kind at all, and used to be the
    # only callers; they must not start resolving to :none.
    it "falls back to tokens for a shape that carries no kind" do
      expect(described_class.billing_mode(span)).to eq(:tokens)
    end
  end

  describe ".fee_for_span" do
    it "reads a per-call charge in cents, whichever key recorded it" do
      %w[cost_cents search.cost_cents component.cost_cents].each do |key|
        recorded = billed_span(kind: "search", attributes: { key => 0.5 })

        expect(described_class.fee_for_span(recorded)).to be_within(1e-9).of(0.005)
      end
    end

    it "is nil for a span that recorded none" do
      expect(described_class.fee_for_span(billed_span(kind: "search"))).to be_nil
    end
  end

  describe ".spend_for_span" do
    it "charges a search its recorded fee" do
      recorded = billed_span(kind: "search", attributes: { "cost_cents" => 0.5 })

      expect(described_class.spend_for_span(recorded)).to be_within(1e-9).of(0.005)
    end

    # Perplexity answers with a model rather than a price list, so the call it
    # made is what it charged for.
    it "falls back to the token cost for a search priced by a model" do
      recorded = billed_span(kind: "search",
                             attributes: { "component.type" => "search" },
                             input_tokens: 1_000_000, output_tokens: 0, agent_model: "gpt-4o")

      expect(described_class.spend_for_span(recorded)).to be > 0
    end

    it "charges a model call for its tokens" do
      recorded = billed_span(kind: "llm", input_tokens: 1_000_000, output_tokens: 0,
                             agent_model: "gpt-4o")

      expect(described_class.spend_for_span(recorded)).to eq(described_class.cost_for_span(recorded))
    end

    it "charges a job nothing, even when a child's counts landed on it" do
      recorded = billed_span(kind: "job", input_tokens: 1_000_000, agent_model: "gpt-4o")

      expect(described_class.spend_for_span(recorded)).to be_nil
    end
  end

  describe ".billed_as" do
    it "files a model call under its model" do
      recorded = billed_span(kind: "llm", agent_model: "gpt-4o", input_tokens: 10)

      expect(described_class.billed_as(recorded)).to eq("gpt-4o")
    end

    # A search has no model to group a spend breakdown by, and a row labelled
    # nothing gets dropped from one.
    it "files a search under whoever charged it" do
      named = billed_span(kind: "search", attributes: { "provider" => "scraping_bee" })
      unnamed = billed_span(kind: "component",
                            attributes: { "component.type" => "search",
                                          "component.name" => "Ai::SearchProviders::ScrapingBee" })

      expect(described_class.billed_as(named)).to eq("scraping_bee")
      expect(described_class.billed_as(unnamed)).to eq("ScrapingBee")
    end
  end

  describe ".priced?" do
    it "separates a known model from one nobody has rates for" do
      expect(described_class.priced?(model: "gpt-4o")).to be(true)
      expect(described_class.priced?(model: "some-new-model")).to be(false)
      expect(described_class.priced?(model: nil)).to be(false)
    end
  end
end
