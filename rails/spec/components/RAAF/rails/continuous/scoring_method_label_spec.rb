# frozen_string_literal: true

require "rails_helper"

# Every eval screen prints scores and none of them said what did the scoring. A
# judge's 0.80 is an opinion that cost a model call and can be argued with; a
# rule's 0.80 is arithmetic that will say the same thing tomorrow. The bar looks
# identical either way, so the method is now named beside it.
RSpec.describe "the scoring method on the continuous screens" do
  def judged_check(field: "quality", display: "Reads Well")
    { "field_name" => field, "evaluator_type" => "llm_judge", "check_type" => "llm_judge",
      "display_name" => display }
  end

  def rule_check(field: "quality", display: "In Range")
    { "field_name" => field, "evaluator_type" => "value_range", "check_type" => "rule_based",
      "display_name" => display }
  end

  describe RAAF::Rails::ScoringMethod do
    it "types a row by the checks it recorded, not by what its policy declared" do
      result = create_result(evaluator_type: "rule_based",
                             details: { "declared_checks" => [judged_check] })

      expect(described_class.for_result(result)).to eq("llm_judge")
    end

    it "calls a row mixed when its checks are not all of one kind" do
      result = create_result(details: { "declared_checks" => [judged_check, rule_check] })

      expect(described_class.for_result(result)).to eq("mixed")
    end

    # Most rows predate checks being stored on them. The policy's own word for
    # the evaluator is coarse — an evaluator running one judge among four rules
    # is still declared rule_based — but it is what there is.
    it "falls back to the type the evaluator was configured under" do
      expect(described_class.for_result(create_result(evaluator_type: "statistical")))
        .to eq("statistical")
    end

    # A transcript is proof a model was asked. Nothing a policy declares can
    # outrank it, but the checks the row itself recorded are more specific, so
    # they are read first.
    it "takes a recorded judge call over an evaluator declared otherwise" do
      result = create_result(evaluator_type: "rule_based")

      expect(described_class.for_result(result, judged: true)).to eq("llm_judge")
    end

    # Not reachable through the model, which requires one of four types on
    # every row — but the screens read rows this module is handed, and a blank
    # must produce no label rather than an empty pill.
    it "says nothing where nothing was recorded" do
      bare = instance_double("Result", details: nil, evaluator_type: nil)

      expect(described_class.for_result(bare)).to be_nil
    end
  end

  describe "the Results table" do
    def html_for(result)
      render(RAAF::Rails::Continuous::ResultsList.new(
               results: RAAF::Eval::Models::ContinuousEvaluationResult.where(id: result.id),
               agents: ["TestAgent"], policies: [], summary: { total: 1 }
             ))
    end

    it "names the method beside the score" do
      result = create_result(details: { "field_name" => "quality",
                                        "declared_checks" => [judged_check] })

      expect(html_for(result)).to include("LLM judge")
    end

    it "keeps a rule apart from a judge" do
      result = create_result(details: { "field_name" => "quality",
                                        "declared_checks" => [rule_check] })
      html = html_for(result)

      expect(html).to include("Rule-based")
      expect(html).not_to include("LLM judge")
    end

    # The fourth type a policy may declare has no wording of its own, and is
    # spelled out rather than left blank.
    it "names a custom evaluator's rows too" do
      expect(html_for(create_result(evaluator_type: "custom"))).to include("Custom")
    end
  end

  describe "one result's own screen" do
    let(:details) do
      { "field_name" => "quality",
        "declared_checks" => [judged_check],
        "result" => { "label" => "good", "score" => 0.8 } }
    end

    let(:result) do
      create_result(evaluator_type: "rule_based", score: 0.8,
                    scores: { "quality" => 0.8 }, details: details)
    end

    let(:html) { render(RAAF::Rails::Continuous::ResultShow.new(result: result)) }

    it "carries the method in the header, beside the verdict" do
      expect(html).to include("LLM judge")
    end

    # The pane has said "Type: …" all along, from the policy's declaration. Two
    # answers to one question on one screen is worse than the coarse one alone.
    it "does not contradict itself in the metadata pane" do
      expect(html).not_to include("Rule-based")
    end

    context "when several checks of different kinds produced the number" do
      let(:details) do
        { "field_name" => "quality",
          "declared_checks" => [judged_check, rule_check],
          "checks" => { "llm_judge" => { "score" => 0.8, "message" => "reads well" },
                        "value_range" => { "score" => 1.0, "message" => "1/1 in range" } } }
      end

      it "says so once at the top" do
        expect(html).to include("Mixed")
      end

      it "names the method on each bar, so the odd one out can be seen" do
        expect(html).to include("raaf-meter-lead")
        expect(html).to include("LLM judge")
        expect(html).to include("Rule-based")
      end
    end

    # Four rules under a header already reading "Rule-based" repeat it four
    # times and tell nobody anything.
    context "when every check was the same kind" do
      let(:details) do
        { "field_name" => "quality",
          "declared_checks" => [rule_check, rule_check(display: "Present")],
          "checks" => { "value_range" => { "score" => 1.0 } } }
      end

      it "leaves the bars unlabelled, the header having said it" do
        expect(html).to include("Rule-based")
        expect(html).not_to include("raaf-meter-lead")
      end
    end
  end
end
