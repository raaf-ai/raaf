# frozen_string_literal: true

require "spec_helper"
require "raaf/tools/perplexity_tool"

RSpec.describe RAAF::Tools::PerplexityTool do
  let(:tool) { described_class.new(api_key: "test-key") }

  describe "#call" do
    context "query validation" do
      it "raises ArgumentError when query is nil" do
        expect {
          tool.call(query: nil)
        }.to raise_error(ArgumentError, "Query parameter is required")
      end

      it "raises ArgumentError when query is not a String" do
        expect {
          tool.call(query: 123)
        }.to raise_error(ArgumentError, "Query must be a String, got Integer")
      end

      it "raises ArgumentError when query is empty string" do
        expect {
          tool.call(query: "")
        }.to raise_error(ArgumentError, "Query cannot be empty")
      end

      it "raises ArgumentError when query is whitespace only" do
        expect {
          tool.call(query: "   ")
        }.to raise_error(ArgumentError, "Query cannot be empty")
      end

      it "raises ArgumentError when query exceeds 4000 characters" do
        long_query = "a" * 4001
        expect {
          tool.call(query: long_query)
        }.to raise_error(ArgumentError, "Query is too long (maximum 4000 characters)")
      end

      it "accepts valid query" do
        allow_any_instance_of(RAAF::Models::PerplexityProvider).to receive(:chat_completion).and_return({
          "choices" => [{ "message" => { "content" => "test result" } }],
          "model" => "sonar"
        })

        result = tool.call(query: "Valid query")
        expect(result[:success]).to be true
      end
    end

    context "model configuration (at initialization)" do
      before do
        allow_any_instance_of(RAAF::Models::PerplexityProvider).to receive(:chat_completion).and_return({
          "choices" => [{ "message" => { "content" => "test result" } }],
          "model" => "sonar"
        })
      end

      it "uses default sonar model when not specified" do
        default_tool = described_class.new(api_key: "test-key")
        result = default_tool.call(query: "test")
        expect(result[:success]).to be true
      end

      it "uses sonar-pro model when specified at initialization" do
        pro_tool = described_class.new(api_key: "test-key", model: "sonar-pro")
        result = pro_tool.call(query: "test")
        expect(result[:success]).to be true
      end

      it "uses sonar-reasoning model when specified at initialization" do
        reasoning_tool = described_class.new(api_key: "test-key", model: "sonar-reasoning")
        result = reasoning_tool.call(query: "test")
        expect(result[:success]).to be true
      end

      it "uses sonar-reasoning-pro model when specified at initialization" do
        reasoning_pro_tool = described_class.new(api_key: "test-key", model: "sonar-reasoning-pro")
        result = reasoning_pro_tool.call(query: "test")
        expect(result[:success]).to be true
      end

      it "uses sonar-deep-research model when specified at initialization" do
        deep_tool = described_class.new(api_key: "test-key", model: "sonar-deep-research")
        result = deep_tool.call(query: "test")
        expect(result[:success]).to be true
      end
    end

    context "max_tokens configuration (at initialization)" do
      before do
        allow_any_instance_of(RAAF::Models::PerplexityProvider).to receive(:chat_completion).and_return({
          "choices" => [{ "message" => { "content" => "test result" } }],
          "model" => "sonar"
        })
      end

      it "uses nil max_tokens when not specified (no limit)" do
        default_tool = described_class.new(api_key: "test-key")
        result = default_tool.call(query: "test")
        expect(result[:success]).to be true
      end

      it "uses max_tokens when specified at initialization" do
        limited_tool = described_class.new(api_key: "test-key", max_tokens: 500)
        result = limited_tool.call(query: "test")
        expect(result[:success]).to be true
      end

      it "accepts max_tokens of 1" do
        tool_1 = described_class.new(api_key: "test-key", max_tokens: 1)
        result = tool_1.call(query: "test")
        expect(result[:success]).to be true
      end

      it "accepts max_tokens of 4000" do
        tool_4000 = described_class.new(api_key: "test-key", max_tokens: 4000)
        result = tool_4000.call(query: "test")
        expect(result[:success]).to be true
      end
    end

    context "domain_filter validation" do
      before do
        allow_any_instance_of(RAAF::Models::PerplexityProvider).to receive(:chat_completion).and_return({
          "choices" => [{ "message" => { "content" => "test result" } }],
          "model" => "sonar"
        })
      end

      it "raises ArgumentError when domain_filter is not String or Array" do
        expect {
          tool.call(query: "test", search_domain_filter: 123)
        }.to raise_error(ArgumentError, "search_domain_filter must be a String or Array, got Integer")
      end

      it "accepts domain_filter as String" do
        result = tool.call(query: "test", search_domain_filter: "ruby-lang.org")
        expect(result[:success]).to be true
      end

      it "accepts domain_filter as Array" do
        result = tool.call(query: "test", search_domain_filter: ["ruby-lang.org", "github.com"])
        expect(result[:success]).to be true
      end

      it "accepts empty string for domain_filter (normalized to nil)" do
        result = tool.call(query: "test", search_domain_filter: "")
        expect(result[:success]).to be true
      end

      it "accepts empty array for domain_filter (normalized to nil)" do
        result = tool.call(query: "test", search_domain_filter: [])
        expect(result[:success]).to be true
      end
    end

    context "recency_filter validation (via SearchOptions)" do
      before do
        allow_any_instance_of(RAAF::Models::PerplexityProvider).to receive(:chat_completion).and_return({
          "choices" => [{ "message" => { "content" => "test result" } }],
          "model" => "sonar"
        })
      end

      it "accepts valid recency filters" do
        %w[hour day week month year].each do |filter|
          result = tool.call(query: "test", search_recency_filter: filter)
          expect(result[:success]).to be true
        end
      end

      it "accepts empty string for recency_filter (normalized to nil)" do
        result = tool.call(query: "test", search_recency_filter: "")
        expect(result[:success]).to be true
      end

      it "accepts whitespace for recency_filter (normalized to nil)" do
        result = tool.call(query: "test", search_recency_filter: "  ")
        expect(result[:success]).to be true
      end

      it "raises ArgumentError for invalid recency_filter" do
        expect {
          tool.call(query: "test", search_recency_filter: "invalid")
        }.to raise_error(ArgumentError, /Invalid recency filter/)
      end
    end

    context "combined configuration and parameters" do
      before do
        allow_any_instance_of(RAAF::Models::PerplexityProvider).to receive(:chat_completion).and_return({
          "choices" => [{ "message" => { "content" => "test result" } }],
          "model" => "sonar-pro"
        })
      end

      it "accepts query with filters when model and max_tokens configured at initialization" do
        configured_tool = described_class.new(
          api_key: "test-key",
          model: "sonar-pro",
          max_tokens: 500
        )

        result = configured_tool.call(
          query: "Ruby news",
          search_domain_filter: ["ruby-lang.org"],
          search_recency_filter: "week"
        )

        expect(result[:success]).to be true
      end

      it "stops on first validation error" do
        expect {
          tool.call(query: nil)
        }.to raise_error(ArgumentError, "Query parameter is required")
      end
    end

    context "error handling" do
      it "catches authentication errors" do
        allow_any_instance_of(RAAF::Models::PerplexityProvider).to receive(:chat_completion)
          .and_raise(RAAF::AuthenticationError.new("Invalid API key"))

        result = tool.call(query: "test")

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Authentication failed")
        expect(result[:error_type]).to eq("authentication_error")
      end

      it "catches rate limit errors" do
        allow_any_instance_of(RAAF::Models::PerplexityProvider).to receive(:chat_completion)
          .and_raise(RAAF::RateLimitError.new("Rate limit exceeded"))

        result = tool.call(query: "test")

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Rate limit exceeded")
        expect(result[:error_type]).to eq("rate_limit_error")
      end

      it "catches general errors" do
        allow_any_instance_of(RAAF::Models::PerplexityProvider).to receive(:chat_completion)
          .and_raise(StandardError.new("Network error"))

        result = tool.call(query: "test")

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Search failed")
        expect(result[:error_type]).to eq("general_error")
        expect(result[:message]).to eq("Network error")
      end
    end
  end
end
