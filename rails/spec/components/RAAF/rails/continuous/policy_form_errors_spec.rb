# frozen_string_literal: true

require "rails_helper"

# A policy that will not save is exactly where a message has to be readable,
# and this screen printed its errors as bare text: it asked Alert for `:danger`,
# whose vocabulary is `error`, and the unrecognised variant was dropped — so the
# panel rendered as `.raaf-alert` alone, which is a transparent border and no
# background.
RSpec.describe RAAF::Rails::Continuous::PolicyForm, type: :component do
  let(:policy) do
    RAAF::Eval::Models::EvaluationPolicy.new(name: nil).tap(&:valid?)
  end

  let(:evaluators) { [{ name: "quality", type: "rule_based", checks: [] }] }

  it "renders its errors in the error tone" do
    render_inline described_class.new(policy: policy, evaluators: evaluators)

    expect(page).to have_css(".raaf-alert.raaf-alert--error")
  end

  it "names how many problems stopped the save" do
    render_inline described_class.new(policy: policy, evaluators: evaluators)

    expect(page).to have_content(/problem.? stopped this policy being saved/)
  end
end
