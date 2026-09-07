# frozen_string_literal: true

require "rails_helper"

# The registry's job is to name each thing the agents called and count its
# calls. Which spans reach it is decided by `SpanRecord::TOOL_KINDS`; what they
# are called once they arrive is decided here, and the two have to agree or a
# card counts calls the screen behind it cannot find.
RSpec.describe RAAF::Rails::Tracing::ToolSpans, type: :component do
  def span(name:, kind:, status: "ok", duration_ms: 100, attributes: {})
    RAAF::Rails::Tracing::SpanRecord.new(name: name, kind: kind, status: status,
                                         duration_ms: duration_ms, span_attributes: attributes)
  end

  def aggregates(spans)
    described_class.new(tool_spans: spans, total_tool_spans: spans, params: {}).send(:aggregates)
  end

  it "names an LLM tool call by the function the model asked for" do
    result = aggregates([span(name: "tool.web_search", kind: "tool",
                              attributes: { "function" => { "name" => "web_search" } })])

    expect(result.map(&:first)).to eq(["web_search"])
  end

  # An application whose agents call plain service objects records them as
  # components, and the only place their name survives is the span name.
  it "names a component call by the class that made it" do
    result = aggregates([
                          span(name: "run.workflow.component.Ai::SearchProviders::Perplexity.search",
                               kind: "component")
                        ])

    expect(result.map(&:first)).to eq(["Ai::SearchProviders::Perplexity"])
  end

  it "keeps two providers apart rather than folding them into their namespace" do
    result = aggregates([
                          span(name: "run.workflow.component.Ai::SearchProviders::Perplexity.search",
                               kind: "component"),
                          span(name: "run.workflow.component.Ai::SearchProviders::ScrapingBee.search",
                               kind: "component")
                        ])

    expect(result.map(&:first))
      .to contain_exactly("Ai::SearchProviders::Perplexity", "Ai::SearchProviders::ScrapingBee")
  end

  it "orders the busiest tool first, since that is the one costing us" do
    result = aggregates([
                          span(name: "run.workflow.custom.Ecosystem::TedClient.search", kind: "custom"),
                          span(name: "run.workflow.component.Ai::SearchProviders::Google.search",
                               kind: "component"),
                          span(name: "run.workflow.component.Ai::SearchProviders::Google.search",
                               kind: "component")
                        ])

    expect(result.map { |name, agg| [name, agg[:calls]] })
      .to eq([["Ai::SearchProviders::Google", 2], ["Ecosystem::TedClient", 1]])
  end

  it "reports what failed as a share of the calls it counted" do
    result = aggregates([
                          span(name: "run.workflow.component.Ai::SearchProviders::Google.search",
                               kind: "component", status: "error"),
                          span(name: "run.workflow.component.Ai::SearchProviders::Google.search",
                               kind: "component"),
                          span(name: "run.workflow.component.Ai::SearchProviders::Google.search",
                               kind: "component"),
                          span(name: "run.workflow.component.Ai::SearchProviders::Google.search",
                               kind: "component")
                        ])
    _name, agg = result.first

    expect(agg).to include(calls: 4, errors: 1, error_rate: 25.0)
  end

  # The card's link used to come back to this screen filtered to the tool,
  # which showed the reader the same card again once the calls table moved to
  # Spans.
  it "sends a card to its own calls, keeping the range it was counted over" do
    component = described_class.new(tool_spans: [], total_tool_spans: [], params: { range: "7d" })

    expect(component.send(:calls_path, "Ai::SearchProviders::Google"))
      .to include("search=Ai", "range=7d")
  end
end
