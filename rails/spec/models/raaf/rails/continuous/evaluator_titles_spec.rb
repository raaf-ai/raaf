# frozen_string_literal: true

require "rails_helper"

# An evaluator that names itself, and one that does not: the two answers the
# lookup has to give.
module TitleProbe
  class Named
    include RAAF::Eval::DSL::EvaluatorDefinition

    evaluator_name :title_probe_named
    display_name "Named Probe"

    select "output", as: :output

    evaluate_field :output do
      evaluate_with :semantic_similarity
    end
  end

  class Anonymous
    include RAAF::Eval::DSL::EvaluatorDefinition

    evaluator_name :title_probe_anonymous

    select "output", as: :output

    evaluate_field :output do
      evaluate_with :semantic_similarity
    end
  end
end

RSpec.describe RAAF::Rails::Continuous::EvaluatorTitles, type: :model do
  subject(:titles) { described_class.new }

  it "gives the title the evaluator declares for itself" do
    expect(titles["title_probe_named"]).to eq("Named Probe")
  end

  it "accepts the name as a symbol, which is how the registry holds it" do
    expect(titles[:title_probe_named]).to eq("Named Probe")
  end

  it "has no title for an evaluator that declares none" do
    expect(titles["title_probe_anonymous"]).to be_nil
  end

  # A result row outlives the class that wrote it. The slug is still what ran.
  it "has no title for a name nothing is registered under" do
    expect(titles["scorer_deleted_last_march"]).to be_nil
  end

  it "has no title for a blank name" do
    expect(titles[nil]).to be_nil
    expect(titles[""]).to be_nil
  end

  describe "#label" do
    it "prefers the declared title" do
      expect(titles.label("title_probe_named")).to eq("Named Probe")
    end

    it "falls back to the recorded name spelled as words" do
      expect(titles.label("title_probe_anonymous")).to eq("title probe anonymous")
    end
  end

  # A title is a nicety. No screen that shows one should fail without it.
  it "answers nil rather than raising when the registry breaks" do
    allow(RAAF::Eval::DSL::EvaluatorRegistry.instance)
      .to receive(:get).and_raise(StandardError, "registry on fire")

    expect(titles["title_probe_named"]).to be_nil
  end

  it "looks an evaluator up once" do
    registry = RAAF::Eval::DSL::EvaluatorRegistry.instance
    allow(registry).to receive(:get).and_call_original

    3.times { titles["title_probe_named"] }

    expect(registry).to have_received(:get).once
  end
end
