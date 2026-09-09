# frozen_string_literal: true

require "rails_helper"

# The Spans rail offers kind and type chips, but the screen also honours
# `search` and `status` — and those are how its two main entry points arrive:
# an Agents row links here with search=<agent name>, a Tools card with
# search=<tool name>.
RSpec.describe RAAF::Rails::Tracing::SpansIndex, type: :component do
  def screen(params)
    described_class.new(spans: [], paginated_spans: [], kind_counts: { "llm" => 3 },
                        params: params)
  end

  describe "an active search" do
    it "names the term the list was narrowed by" do
      applied = screen({ search: "Company::EnrichAgent" }).send(:applied_filters)

      expect(applied.map { |filter| filter[:label] })
        .to eq(["search: Company::EnrichAgent ✕"])
    end

    # The empty state offers a reset, so before this the only way to find the
    # filter was to narrow it until nothing matched.
    it "offers a link that drops it while keeping the rest" do
      applied = screen({ search: "Scout", kind: "llm", range: "7d" }).send(:applied_filters)

      expect(applied.first[:href]).to include("kind=llm", "range=7d")
      expect(applied.first[:href]).not_to include("search")
    end
  end

  describe "an active status" do
    it "is named beside the search it was applied with" do
      applied = screen({ search: "Scout", status: "error" }).send(:applied_filters)

      expect(applied.map { |filter| filter[:label] })
        .to eq(["search: Scout ✕", "status: error ✕"])
    end
  end

  it "shows no filter line where nothing is filtered" do
    expect(screen({ kind: "llm" }).send(:applied_filters)).to be_empty
  end

  it "renders the term and a way out of it" do
    render_inline screen({ search: "Scout" })

    expect(page).to have_content("search: Scout")
    expect(page).to have_content("Clear all")
  end
end
