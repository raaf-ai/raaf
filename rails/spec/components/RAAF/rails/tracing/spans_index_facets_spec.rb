# frozen_string_literal: true

require "rails_helper"

# The rail's job is to name what you can narrow to. `kind` alone cannot: every
# span the console shows under "component" is really a search or an ecosystem
# lookup, and those are the two sets somebody wants.
RSpec.describe RAAF::Rails::Tracing::SpansIndex, type: :component do
  def facets(kind_counts:, type_counts:, params: {})
    described_class.new(spans: [], paginated_spans: [], kind_counts: kind_counts,
                        type_counts: type_counts, params: params)
                   .send(:facets)
  end

  it "offers a kind as its types when they name something the kind does not" do
    result = facets(
      kind_counts: { "component" => 6303 },
      type_counts: { %w[component search] => 5364, %w[component ecosystem_source] => 939 }
    )

    expect(result.map { |facet| [facet[:label], facet[:count]] })
      .to contain_exactly(["search", 5364], ["ecosystem_source", 939])
  end

  it "splits a kind holding a single named type, since the name is the point" do
    result = facets(kind_counts: { "custom" => 1172 }, type_counts: { %w[custom http] => 1172 })

    expect(result.map { |facet| facet[:label] }).to eq(["http"])
  end

  it "leaves a kind whose type only repeats it alone" do
    result = facets(kind_counts: { "job" => 5721 }, type_counts: { %w[job job] => 5721 })

    expect(result.map { |facet| [facet[:label], facet[:type]] }).to eq([["job", nil]])
  end

  # A handful of llm spans are typed "agent" by the collector. A second chip
  # reading "agent" would describe neither set.
  it "does not split on a type that carries another kind's name" do
    result = facets(kind_counts: { "llm" => 5, "agent" => 4041 },
                    type_counts: { %w[llm agent] => 5, %w[agent agent] => 4041 })

    expect(result.map { |facet| facet[:label] }).to contain_exactly("llm", "agent")
  end

  # The parent is worth keeping only while it holds something its children do
  # not; otherwise it is the same filter under a longer name.
  it "keeps the parent chip when the split leaves spans over" do
    result = facets(kind_counts: { "component" => 100 }, type_counts: { %w[component search] => 60 })

    expect(result.map { |facet| [facet[:label], facet[:count]] })
      .to eq([["search", 60], ["component", 100]])
  end

  it "drops the parent chip when its types account for all of it" do
    result = facets(kind_counts: { "component" => 60 }, type_counts: { %w[component search] => 60 })

    expect(result.map { |facet| facet[:label] }).to eq(["search"])
  end

  it "counts spans with no type at all under their kind" do
    result = facets(kind_counts: { "tool" => 672 }, type_counts: { ["tool", nil] => 672 })

    expect(result.map { |facet| [facet[:label], facet[:type]] }).to eq([["tool", nil]])
  end
end
