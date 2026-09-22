# frozen_string_literal: true

require "spec_helper"
require "raaf-core"

# A decision call used to leave no trace at all: DecisionInterface carried no
# tracing, and the spans a run produced skipped straight over the probability
# it was decided by, and over what that cost.
RSpec.describe RAAF::Models::DecisionInterface, "tracing" do
  let(:collected) { [] }

  let(:processor) do
    spans = collected
    Class.new do
      define_method(:initialize) { @spans = spans }
      def on_span_start(_span) = nil
      def on_span_end(span) = @spans << span
      def force_flush = nil
      def shutdown = nil
    end.new
  end

  # This suite runs with RAAF_DISABLE_TRACING set, so the singleton is a
  # NoOpTracer. A provider given its own tracer sends there instead.
  let(:tracer) do
    RAAF::Tracing::SpanTracer.new.tap { |span_tracer| span_tracer.add_processor(processor) }
  end

  let(:provider_class) do
    Class.new(described_class) do
      def provider_name = "Recording"

      def default_model = "recording-1"

      # Each question type reads a different answer body, so a fake that
      # answers them all with a noul cannot serve a two-question call.
      def answer_body_for(question)
        case question.type.to_s
        when "choice" then { "choice" => question.criteria.keys.first, "confidence" => 0.9 }
        when "score" then { "score" => 1.0, "confidence" => 0.9 }
        else { "noul" => 0.75 }
        end
      end

      def perform_decision(state:, questions:, model:, **)
        RAAF::Models::Decision::Result.new(
          answers: questions.transform_values { |question| question.parse(answer_body_for(question)) },
          model: "recording-1-20260920",
          provider: provider_name,
          usage: { "input_tokens" => 120, "output_tokens" => 8, "cost" => 0.000_02 },
          request_id: "req_abc"
        )
      end
    end
  end

  let(:questions) do
    {
      urgent: RAAF::Models::Decision::Noul.new(instructions: "It is urgent"),
      team: RAAF::Models::Decision::Choice.new(instructions: "Which team?", criteria: %w[billing engineering])
    }
  end

  def build(klass = provider_class, **options)
    klass.new(tracer: tracer, **options)
  end

  def decide(provider, state: "Stripe has been failing for three days")
    provider.decide(state: state, questions: { urgent: questions[:urgent] })
  end

  describe "the span it opens" do
    subject(:span) { collected.last }

    before { decide(build) }

    it "records one span per call" do
      expect(collected.size).to eq(1)
    end

    it "records it as a decision, not as an llm call" do
      expect(span.kind).to eq(:decision)
    end

    it "names the span after the model, which is what a reader is looking for" do
      expect(span.name).to eq("run.workflow.decision.recording-1.decide")
    end

    it "records the provider and the model asked" do
      expect(span.attributes).to include("decision.provider" => "Recording", "decision.model" => "recording-1")
    end

    it "records the model that answered, which a vendor may resolve from an alias" do
      expect(span.attributes["decision.result.model"]).to eq("recording-1-20260920")
    end

    it "records the request id, for quoting back to the vendor" do
      expect(span.attributes["decision.request_id"]).to eq("req_abc")
    end
  end

  describe "what it records about the questions" do
    subject(:attributes) { collected.last.attributes }

    before { build.decide(state: "a ticket", questions: questions) }

    it "records how many were asked" do
      expect(attributes["decision.question_count"]).to eq(2)
    end

    it "records each question by name and type, without its instructions" do
      expect(JSON.parse(attributes["decision.questions"]))
        .to eq([{ "name" => "urgent", "type" => "noul" }, { "name" => "team", "type" => "choice" }])
    end

    it "records the answers, which is the decision the caller acted on" do
      answers = JSON.parse(attributes["decision.answers"])

      expect(answers.dig("urgent", "probability")).to eq(0.75)
    end
  end

  # The state is whatever the caller is deciding about, which in an application
  # is customer data. Copying it into a span payload is a decision somebody has
  # to make deliberately.
  describe "the state" do
    it "is left out by default" do
      decide(build)

      expect(collected.last.attributes).not_to have_key("decision.state")
    end

    it "is recorded when the provider was asked to trace it" do
      decide(build(trace_state: true))

      expect(collected.last.attributes["decision.state"]).to eq("Stripe has been failing for three days")
    end

    it "is recorded as JSON when it is not a String" do
      build(trace_state: true)
        .decide(state: { company: "Acme" }, questions: { urgent: questions[:urgent] })

      expect(collected.last.attributes["decision.state"]).to eq({ company: "Acme" }.to_json)
    end

    it "is left out when the environment does not ask for it" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("RAAF_TRACE_DECISION_STATE").and_return("false")

      decide(build)

      expect(collected.last.attributes).not_to have_key("decision.state")
    end
  end

  describe "what it costs" do
    subject(:attributes) { collected.last.attributes }

    before { decide(build) }

    it "records the tokens the provider reported" do
      expect(attributes).to include("decision.tokens.input" => "120", "decision.tokens.output" => "8")
    end

    # $0.00002 is 0.002 cents. Pricing this off a token table would find no
    # entry for a decision model, fall through to the gpt-4o default, and
    # report a hundredfold overstatement as if it were measured.
    it "records the cost the provider reported, in cents" do
      expect(attributes["decision.cost_cents"].to_f).to be_within(1e-9).of(0.002)
    end

    it "is billed per call rather than by the token" do
      span = collected.last
      record = Struct.new(:kind, :span_attributes, :call_fee_cents).new(span.kind.to_s, span.attributes, nil)

      expect(RAAF::Tracing::SpanUsage.billing_mode(record)).to eq(:cost)
      expect(RAAF::Tracing::SpanUsage.fee_for_span(record)).to be_within(1e-9).of(0.000_02)
    end
  end

  describe "when the provider raises" do
    let(:failing_provider) do
      Class.new(described_class) do
        def provider_name = "Failing"

        def default_model = "failing-1"

        def perform_decision(state:, questions:, model:, **)
          raise RAAF::APIError, "upstream is down"
        end
      end
    end

    it "still sends the span, marked as failed", :aggregate_failures do
      expect { decide(build(failing_provider)) }.to raise_error(RAAF::APIError)

      expect(collected.last.status).to eq(:error)
      expect(collected.last.attributes["error.type"]).to eq("RAAF::APIError")
    end
  end
end
