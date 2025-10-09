# frozen_string_literal: true

require "spec_helper"
require "raaf/perplexity/search_options"

RSpec.describe RAAF::Perplexity::SearchOptions do
  describe ".build" do
    context "with no options" do
      it "returns nil when no filters specified" do
        result = described_class.build
        expect(result).to be_nil
      end

      it "returns nil when both filters are nil" do
        result = described_class.build(domain_filter: nil, recency_filter: nil)
        expect(result).to be_nil
      end

      it "returns nil when domain_filter is empty array" do
        result = described_class.build(domain_filter: [], recency_filter: nil)
        expect(result).to be_nil
      end
    end

    context "with domain filter only" do
      it "builds options with single domain" do
        result = described_class.build(domain_filter: ["ruby-lang.org"])

        expect(result).to eq({
          search_domain_filter: ["ruby-lang.org"]
        })
      end

      it "builds options with multiple domains" do
        result = described_class.build(domain_filter: ["ruby-lang.org", "github.com"])

        expect(result).to eq({
          search_domain_filter: ["ruby-lang.org", "github.com"]
        })
      end

      it "wraps single domain in array" do
        result = described_class.build(domain_filter: "ruby-lang.org")

        expect(result).to eq({
          search_domain_filter: ["ruby-lang.org"]
        })
      end

      it "handles array with multiple elements" do
        domains = ["ruby-lang.org", "github.com", "stackoverflow.com"]
        result = described_class.build(domain_filter: domains)

        expect(result).to eq({
          search_domain_filter: domains
        })
      end
    end

    context "with recency filter only" do
      it "builds options with hour filter" do
        result = described_class.build(recency_filter: "hour")

        expect(result).to eq({
          search_recency_filter: "hour"
        })
      end

      it "builds options with day filter" do
        result = described_class.build(recency_filter: "day")

        expect(result).to eq({
          search_recency_filter: "day"
        })
      end

      it "builds options with week filter" do
        result = described_class.build(recency_filter: "week")

        expect(result).to eq({
          search_recency_filter: "week"
        })
      end

      it "builds options with month filter" do
        result = described_class.build(recency_filter: "month")

        expect(result).to eq({
          search_recency_filter: "month"
        })
      end

      it "builds options with year filter" do
        result = described_class.build(recency_filter: "year")

        expect(result).to eq({
          search_recency_filter: "year"
        })
      end

      it "validates recency filter" do
        expect { described_class.build(recency_filter: "invalid") }
          .to raise_error(ArgumentError, /Invalid recency filter/)
      end
    end

    context "with both filters" do
      it "builds options with domain and recency" do
        result = described_class.build(
          domain_filter: ["ruby-lang.org"],
          recency_filter: "week"
        )

        expect(result).to eq({
          search_domain_filter: ["ruby-lang.org"],
          search_recency_filter: "week"
        })
      end

      it "builds options with multiple domains and recency" do
        result = described_class.build(
          domain_filter: ["ruby-lang.org", "github.com"],
          recency_filter: "month"
        )

        expect(result).to eq({
          search_domain_filter: ["ruby-lang.org", "github.com"],
          search_recency_filter: "month"
        })
      end
    end

    context "validation" do
      it "delegates recency validation to Common" do
        expect(RAAF::Perplexity::Common).to receive(:validate_recency_filter).with("week")

        described_class.build(recency_filter: "week")
      end

      it "raises ArgumentError for invalid recency filter" do
        expect { described_class.build(recency_filter: "invalid") }
          .to raise_error(ArgumentError)
      end

      it "does not validate when recency_filter is nil" do
        expect(RAAF::Perplexity::Common).not_to receive(:validate_recency_filter)

        described_class.build(domain_filter: ["ruby-lang.org"])
      end
    end
  end
end
