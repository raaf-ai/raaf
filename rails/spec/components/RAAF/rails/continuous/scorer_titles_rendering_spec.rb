# frozen_string_literal: true

require "rails_helper"

# Every continuous table reads its scorer column off `evaluator_name`, which is
# the registry symbol a policy names an evaluator with. The evaluator declares a
# title for itself, and these are the three screens that have to show it.
module TitleRendering
  class Judge
    include RAAF::Eval::DSL::EvaluatorDefinition

    evaluator_name :title_rendering_judge
    display_name "Title Rendering Judge"

    select "output", as: :output
    select "latency", as: :latency

    evaluate_field :output do
      evaluate_with :semantic_similarity, name: "Output Reads Well",
                                          description: "The answer says something"
    end

    evaluate_field :latency do
      evaluate_with :latency, name: "Response Latency",
                              description: "A rep is waiting for this"
    end
  end
end

RSpec.describe "a scorer's declared title on the continuous screens" do
  let(:now) { Time.current }

  before do
    2.times do |index|
      RAAF::Eval::Models::ContinuousEvaluationResult.create!(
        span_id: "span_title_#{index}", trace_id: "trace_title", evaluation_type: "automated",
        evaluator_name: "title_rendering_judge", evaluator_type: "llm_judge",
        agent_name: "ProbeAgent", environment: "test", status: "good", score: 0.8,
        metrics: {}, evaluation_duration_ms: 100, created_at: now - 1.hour,
        details: { "field_name" => "output" }
      )
    end
  end

  # The symbol has to survive alongside the title on this screen: it is what a
  # policy is written in, and what every other table and the API still show.
  it "titles the Evaluator health table, keeping the recorded name beside it" do
    health = RAAF::Rails::Continuous::ScorerHealth.new(window: 7.days)
    html = render(RAAF::Rails::Continuous::HealthDashboard.new(health: health, range: "7d"))

    expect(html).to include("Title Rendering Judge")
    expect(html).to include("title_rendering_judge")
  end

  it "titles the scorer column on Results" do
    html = render(RAAF::Rails::Continuous::ResultsList.new(
                    results: RAAF::Eval::Models::ContinuousEvaluationResult.all,
                    agents: ["ProbeAgent"], policies: [], summary: { total: 2 }
                  ))

    expect(html).to include("Title Rendering Judge")
  end

  # The scorer column identified a row by the field the evaluator read. A field
  # is not a question: `confidence` says where the number came from and nothing
  # about what was asked of it, which is the thing a reader is scanning for.
  describe "the check a row was graded by" do
    before do
      RAAF::Eval::Models::ContinuousEvaluationResult.create!(
        span_id: "span_declared", trace_id: "trace_title", evaluation_type: "automated",
        evaluator_name: "title_rendering_judge", evaluator_type: "llm_judge",
        agent_name: "ProbeAgent", environment: "test", status: "good", score: 0.9,
        metrics: {}, evaluation_duration_ms: 100, created_at: now,
        details: { "field_name" => "output",
                   "declared_checks" => [{ "field_name" => "output",
                                           "evaluator_type" => "semantic_similarity",
                                           "display_name" => "Output Reads Well",
                                           "description" => "The answer says something" }] }
      )
    end

    let(:html) do
      render(RAAF::Rails::Continuous::ResultsList.new(
               results: RAAF::Eval::Models::ContinuousEvaluationResult.all,
               agents: ["ProbeAgent"], policies: [], summary: { total: 3 }
             ))
    end

    it "names the check rather than the field it read" do
      expect(html).to include("Output Reads Well")
    end

    it "carries what the check asks, for reading without leaving the table" do
      expect(html).to include("The answer says something")
    end

    # Rows written before the checks were stored on them still say which field
    # they are about, which is what distinguishes them from each other.
    it "leaves rows that recorded no check on their field name" do
      expect(html).to include("output")
    end
  end

  it "titles the rows on Score trends" do
    trends = RAAF::Rails::Continuous::ScoreTrendSeries.new(range: "7d").call
    html = render(RAAF::Rails::Continuous::ScoreTrends.new(trends: trends))

    expect(html).to include("Title Rendering Judge")
  end

  # The policy page's two prominent labels come from the check rather than the
  # evaluator: the Checks card is a list of `field:evaluator` keys, and a
  # result row is headed by the field it graded.
  describe "the policy screen" do
    let(:policy) do
      create_policy(name: "Title Policy", agent_name: "ProbeAgent",
                    evaluators: [{ "name" => "title_rendering_judge",
                                   "type" => "rule_based",
                                   "checks" => ["latency:latency"] }])
    end

    let(:result) do
      create_result(evaluator_name: "title_rendering_judge", agent_name: "ProbeAgent",
                    evaluation_policy: policy, score: 1.0,
                    details: { "field_name" => "latency" })
    end

    it "names each scorer as its author named it, keeping the key beneath" do
      html = render(RAAF::Rails::Continuous::PolicyShow.new(policy: policy))

      expect(html).to include("Response Latency")
      expect(html).to include("latency:latency")
    end

    it "heads a recent result with the check that produced it" do
      html = render(RAAF::Rails::Continuous::PolicyShow.new(policy: policy,
                                                            recent_results: [result]))

      expect(html).to include("Response Latency")
    end
  end

  # The result screen already heads itself with the check that graded it. The
  # other results for the same span are the same checks on the same run, and
  # listing them by field left one screen calling one thing two names.
  describe "the other results for a span" do
    let(:result) do
      create_result(evaluator_name: "title_rendering_judge", span_id: "span_neighbours",
                    agent_name: "ProbeAgent", score: 0.9,
                    details: { "field_name" => "output" })
    end

    let(:sibling) do
      create_result(evaluator_name: "title_rendering_judge", span_id: "span_neighbours",
                    agent_name: "ProbeAgent", score: 1.0,
                    details: { "field_name" => "latency" })
    end

    let(:html) do
      render(RAAF::Rails::Continuous::ResultShow.new(result: result,
                                                     sibling_results: [sibling]))
    end

    it "names each neighbour by its check rather than the field it read" do
      expect(html).to include("Response Latency")
    end

    it "names the evaluator behind it as the evaluator names itself" do
      expect(html).to include("Title Rendering Judge")
    end

    # An evaluator that has since been renamed or deleted answers for nothing,
    # and the name the row ran under is the honest one.
    it "keeps the name a neighbour recorded when its evaluator is gone" do
      gone = create_result(evaluator_name: "retired_judge", span_id: "span_neighbours",
                           agent_name: "ProbeAgent", score: 0.5,
                           details: { "field_name" => "output",
                                      "declared_checks" => [{ "field_name" => "output",
                                                              "evaluator_type" => "semantic_similarity",
                                                              "display_name" => "Retired Check" }] })
      html = render(RAAF::Rails::Continuous::ResultShow.new(result: result,
                                                            sibling_results: [gone]))

      expect(html).to include("Retired Check")
    end
  end
end
