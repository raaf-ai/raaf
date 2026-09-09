# frozen_string_literal: true

require "rails_helper"

# Two checks on one field used to draw two bars reporting the same number: a
# check is keyed `field:evaluator` and a result was recorded under the field
# alone, so the bars had to fall back to the field's combined figure. A result
# is recorded per check now, and the bar reports the score its own check
# produced.
RSpec.describe RAAF::Rails::Continuous::PolicyShow, type: :component do
  let(:policy) do
    create_policy(
      name: "Confidence",
      evaluators: [{ "name" => "confidence_checks", "type" => "rule_based",
                     "checks" => %w[confidence:llm_judge confidence:value_range] }]
    )
  end

  def screen(check_scores)
    described_class.new(policy: policy, check_scores: check_scores)
  end

  let(:per_check) do
    { "confidence:llm_judge" => { average: 0.9, count: 4 },
      "confidence:value_range" => { average: 0.4, count: 4 } }
  end

  it "gives each check the score its own evaluator produced" do
    page = screen(per_check)

    expect(page.send(:measured_for, "confidence:llm_judge")[:average]).to eq(0.9)
    expect(page.send(:measured_for, "confidence:value_range")[:average]).to eq(0.4)
  end

  # The fallback is what made two independent measurements agree exactly and
  # read as corroboration.
  it "does not fall back to the field's figure" do
    expect(screen("confidence" => { average: 0.7, count: 8 })
             .send(:measured_for, "confidence:llm_judge")).to be_nil
  end

  it "draws both scores rather than one twice" do
    render_inline screen(per_check)

    expect(page).to have_content("0.90")
    expect(page).to have_content("0.40")
  end

  it "no longer explains that a score is shared" do
    render_inline screen(per_check)

    expect(page).to have_no_content("score shared with")
  end

  describe "evaluations no evaluator can be credited with" do
    let(:mixed) do
      per_check.merge("confidence" => { average: 0.7, count: 8 })
    end

    # They cannot be split -- the parts were never written down -- so they are
    # counted where a reader can see what they are.
    it "counts them as what they are rather than crediting one evaluator" do
      render_inline screen(mixed)

      expect(page).to have_content("8 evaluations scored this field's checks together")
    end

    it "leaves the bar itself reading the check's own score" do
      expect(screen(mixed).send(:measured_for, "confidence:llm_judge")[:average]).to eq(0.9)
    end
  end
end
