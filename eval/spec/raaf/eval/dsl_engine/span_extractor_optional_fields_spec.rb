# frozen_string_literal: true

require "spec_helper"
require "active_support/core_ext/object/blank"
require "raaf/eval/dsl/field_selector"
require "raaf/eval/dsl_engine/span_extractor"

# A selected field can be one whose presence depends on how the evaluated
# subject is configured -- a scoring dimension the product does not use, a tool
# the agent was not given. Extraction used to raise on the first such field and
# take the whole evaluation with it, including the checks on fields that were
# present.
RSpec.describe RAAF::Eval::DslEngine::SpanExtractor do
  subject(:extract) { described_class.extract_fields(span, selector) }

  let(:selector) { RAAF::Eval::DSL::FieldSelector.new }
  let(:span) { { "scores" => { "industry" => 80 }, "latency_ms" => 1_200 } }

  context "when an optional field is missing" do
    before do
      selector.add_field("scores.industry", as: :industry, optional: true)
      selector.add_field("scores.revenue_opportunity", as: :revenue, optional: true)
      selector.add_field("latency_ms", as: :latency)
    end

    it "omits it rather than raising" do
      expect { extract }.not_to raise_error
      expect(extract).not_to have_key("scores.revenue_opportunity")
    end

    it "still extracts every other field, so unrelated checks keep running" do
      expect(extract).to eq("scores.industry" => 80, "latency_ms" => 1_200)
    end
  end

  context "when a required field is missing" do
    before { selector.add_field("scores.typo_in_this_path", as: :typo) }

    it "raises, so a mistyped path is not mistaken for a configuration difference" do
      expect { extract }.to raise_error(RAAF::Eval::DSL::FieldNotFoundError, /typo_in_this_path/)
    end
  end

  describe "declaring optionality" do
    it "defaults to required" do
      selector.add_field("scores.industry", as: :industry)

      expect(selector).not_to be_optional("scores.industry")
    end

    it "records the fields declared optional" do
      selector.add_field("scores.industry", as: :industry, optional: true)

      expect(selector).to be_optional("scores.industry")
    end
  end
end
