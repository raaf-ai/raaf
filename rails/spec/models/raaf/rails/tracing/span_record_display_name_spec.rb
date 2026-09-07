# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Tracing::SpanRecord, type: :model do
  describe "#display_name" do
    def span(name:, kind: "tool", attributes: {})
      described_class.new(name: name, kind: kind, span_attributes: attributes)
    end

    context "with a span name in the tracer's dotted form" do
      it "keeps the whole constant path rather than its first segment" do
        record = span(name: "run.workflow.custom.Ecosystem::TedClient.search")

        expect(record.display_name).to eq("Ecosystem::TedClient")
      end

      it "keeps every segment of a deeply namespaced constant" do
        record = span(name: "run.workflow.component.Ai::SearchProviders::Google.search",
                      kind: "component")

        expect(record.display_name).to eq("Ai::SearchProviders::Google")
      end

      it "strips the trailing method from an unnamespaced class" do
        record = span(name: "run.workflow.job.SignalsScanJob.perform", kind: "job")

        expect(record.display_name).to eq("SignalsScanJob")
      end

      it "leaves a path with no trailing method alone" do
        record = span(name: "run.workflow.component.Ai::SearchProviders::Google",
                      kind: "component")

        expect(record.display_name).to eq("Ai::SearchProviders::Google")
      end
    end

    # Pipelines are labelled by their last segment on purpose — the Flows
    # screen lists them beside each other, where the shared namespace is noise.
    # They do not go through the constant-path rule above.
    context "with a pipeline span" do
      it "shortens the name to its last segment" do
        record = span(name: "run.workflow.pipeline.Ai::Agents::Prospect::Discovery",
                      kind: "pipeline")

        expect(record.display_name).to eq("Discovery")
      end
    end

    context "with a name that is already readable" do
      it "returns it whole" do
        record = span(name: "Overture::CompanyMatchService/hallucination_gate")

        expect(record.display_name).to eq("Overture::CompanyMatchService/hallucination_gate")
      end

      # Two tools of one namespace must not share a display name: the Tools
      # screen groups its registry by it, so collapsing them hides a tool.
      it "distinguishes two tools sharing a namespace" do
        one = span(name: "Overture::CompanyMatchService/match")
        two = span(name: "Overture::ExistenceVerifier/verify")

        expect(one.display_name).not_to eq(two.display_name)
      end
    end

    context "when the span carries an explicit name attribute" do
      it "prefers the attribute over the span name" do
        record = span(name: "run.workflow.custom.Ecosystem::TedClient.search",
                      attributes: { "function" => { "name" => "ted_search" } })

        expect(record.display_name).to eq("ted_search")
      end
    end
  end

  # The listing names the class, which is the same for every row a provider
  # ever wrote. The subject is the line that tells those rows apart.
  describe "#display_subject" do
    def span(kind: "component", attributes: {})
      described_class.new(name: "run.workflow.#{kind}.Some::Class.call", kind: kind,
                          span_attributes: attributes)
    end

    it "reads a search's query, and counts its hits in the counter's own word" do
      record = span(attributes: { "component.type" => "search", "query" => "acme latex",
                                  "result_count" => 9 })

      expect(record.display_subject).to eq("acme latex · 9 results")
    end

    it "says a search found nothing rather than dropping the count" do
      record = span(attributes: { "query" => "acme latex", "result_count" => 0 })

      expect(record.display_subject).to eq("acme latex · 0 results")
    end

    it "takes the URL of an HTTP span" do
      record = span(kind: "custom", attributes: { "http.url" => "https://api.example.com/v3/search",
                                                  "http.method" => "POST" })

      expect(record.display_subject).to eq("https://api.example.com/v3/search")
    end

    it "takes the service a job was given, not the whole argument list" do
      record = span(kind: "job",
                    attributes: { "job.arguments" => '["EnrichmentService", {"id": 4}]' })

      expect(record.display_subject).to eq("EnrichmentService")
    end

    it "unwraps an argument list written with inspect rather than as JSON" do
      record = span(kind: "job", attributes: { "job.arguments" => '[{period_type: "daily"}]' })

      expect(record.display_subject).to eq('period_type: "daily"')
    end

    it "falls back to a suffix when the exact key is one it has never seen" do
      record = span(attributes: { "ecosystem.company" => "C2N", "ecosystem.edge_count" => 30 })

      expect(record.display_subject).to eq("C2N · 30 edges")
    end

    it "is nil for a span that recorded nothing about its subject" do
      record = span(kind: "agent", attributes: { "component.type" => "agent" })

      expect(record.display_subject).to be_nil
    end

    it "truncates a subject too long for one line of a table" do
      record = span(attributes: { "query" => "a" * 400 })

      expect(record.display_subject.length).to eq(described_class::SUBJECT_LIMIT + 1)
      expect(record.display_subject).to end_with("…")
    end
  end
end
