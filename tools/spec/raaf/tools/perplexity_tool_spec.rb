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

      context "wildcard pattern validation" do
        it "rejects wildcard patterns with asterisk" do
          expect {
            tool.call(query: "test", search_domain_filter: ["*.nl"])
          }.to raise_error(ArgumentError, /Invalid domain pattern '\*\.nl': Wildcard patterns \(\*, \?\) are not supported/)
        end

        it "rejects wildcard patterns with question mark" do
          expect {
            tool.call(query: "test", search_domain_filter: ["ruby-?.org"])
          }.to raise_error(ArgumentError, /Invalid domain pattern 'ruby-\?\.org': Wildcard patterns/)
        end

        it "rejects TLD wildcard patterns" do
          expect {
            tool.call(query: "test", search_domain_filter: ["*.com"])
          }.to raise_error(ArgumentError, /Invalid domain pattern '\*\.com': Wildcard patterns/)
        end

        it "rejects prefix wildcard patterns" do
          expect {
            tool.call(query: "test", search_domain_filter: ["ruby-*"])
          }.to raise_error(ArgumentError, /Invalid domain pattern 'ruby-\*': Wildcard patterns/)
        end

        it "rejects suffix wildcard patterns" do
          expect {
            tool.call(query: "test", search_domain_filter: ["*github*"])
          }.to raise_error(ArgumentError, /Invalid domain pattern '\*github\*': Wildcard patterns/)
        end

        it "rejects multiple wildcard patterns in array" do
          expect {
            tool.call(query: "test", search_domain_filter: ["ruby-lang.org", "*.nl", "github.com"])
          }.to raise_error(ArgumentError, /Invalid domain pattern '\*\.nl': Wildcard patterns/)
        end

        it "provides helpful error message with examples" do
          expect {
            tool.call(query: "test", search_domain_filter: ["*.nl"])
          }.to raise_error(ArgumentError, /Use exact domain names like 'example\.com'/)
        end
      end

      context "TLD-only pattern validation" do
        it "rejects TLD-only patterns starting with dot" do
          expect {
            tool.call(query: "test", search_domain_filter: [".nl"])
          }.to raise_error(ArgumentError, /Invalid domain pattern '\.nl': TLD-only patterns are not supported/)
        end

        it "rejects .com TLD-only pattern" do
          expect {
            tool.call(query: "test", search_domain_filter: [".com"])
          }.to raise_error(ArgumentError, /Invalid domain pattern '\.com': TLD-only patterns are not supported/)
        end

        it "provides helpful error message for TLD-only patterns" do
          expect {
            tool.call(query: "test", search_domain_filter: [".nl"])
          }.to raise_error(ArgumentError, /Use complete domain names like 'example\.nl'/)
        end

        it "accepts domains that contain dots but aren't TLD-only" do
          result = tool.call(query: "test", search_domain_filter: ["example.nl"])
          expect(result[:success]).to be true
        end

        it "accepts subdomains with multiple dots" do
          result = tool.call(query: "test", search_domain_filter: ["news.bbc.co.uk"])
          expect(result[:success]).to be true
        end
      end

      context "valid domain patterns" do
        it "accepts simple domain names" do
          result = tool.call(query: "test", search_domain_filter: ["example.com"])
          expect(result[:success]).to be true
        end

        it "accepts domains with hyphens" do
          result = tool.call(query: "test", search_domain_filter: ["ruby-lang.org"])
          expect(result[:success]).to be true
        end

        it "accepts subdomains" do
          result = tool.call(query: "test", search_domain_filter: ["blog.example.com"])
          expect(result[:success]).to be true
        end

        it "accepts multi-level subdomains" do
          result = tool.call(query: "test", search_domain_filter: ["api.v2.example.com"])
          expect(result[:success]).to be true
        end

        it "accepts international TLDs" do
          result = tool.call(query: "test", search_domain_filter: ["example.co.uk", "example.fr"])
          expect(result[:success]).to be true
        end
      end
    end

    context "recency_filter validation (via SearchOptions)" do
      before do
        allow_any_instance_of(RAAF::Perplexity::HttpClient).to receive(:make_api_call).and_return({
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
    end

    context "default recency_filter fallback behavior" do
      before do
        allow_any_instance_of(RAAF::Perplexity::HttpClient).to receive(:make_api_call).and_return({
          "choices" => [{ "message" => { "content" => "test result" } }],
          "model" => "sonar"
        })
      end

      context "when default is nil (no recency filtering)" do
        let(:tool_no_default) { described_class.new(api_key: "test-key") }

        it "falls back to nil when agent provides invalid recency_filter" do
          expect(RAAF.logger).to receive(:warn).with(/Invalid recency_filter 'invalid' - falling back to default: nil/)

          result = tool_no_default.call(query: "test", search_recency_filter: "invalid")
          expect(result[:success]).to be true
        end

        it "uses valid agent-provided recency_filter even when default is nil" do
          expect(RAAF.logger).not_to receive(:warn)

          result = tool_no_default.call(query: "test", search_recency_filter: "week")
          expect(result[:success]).to be true
        end

        it "uses nil when agent provides nil (no recency filter)" do
          expect(RAAF.logger).not_to receive(:warn)

          result = tool_no_default.call(query: "test", search_recency_filter: nil)
          expect(result[:success]).to be true
        end
      end

      context "when default is 'week'" do
        let(:tool_with_default) { described_class.new(api_key: "test-key", search_recency_filter: "week") }

        it "falls back to 'week' when agent provides invalid recency_filter" do
          expect(RAAF.logger).to receive(:warn).with(/Invalid recency_filter 'invalid' - falling back to default: "week"/)

          result = tool_with_default.call(query: "test", search_recency_filter: "invalid")
          expect(result[:success]).to be true
        end

        it "uses valid agent-provided recency_filter ('day') instead of default ('week')" do
          expect(RAAF.logger).not_to receive(:warn)

          result = tool_with_default.call(query: "test", search_recency_filter: "day")
          expect(result[:success]).to be true
        end

        it "uses nil when agent explicitly provides nil (overrides default)" do
          expect(RAAF.logger).not_to receive(:warn)

          result = tool_with_default.call(query: "test", search_recency_filter: nil)
          expect(result[:success]).to be true
        end

        it "uses default 'week' when agent provides empty string" do
          expect(RAAF.logger).not_to receive(:warn)

          result = tool_with_default.call(query: "test", search_recency_filter: "")
          expect(result[:success]).to be true
        end
      end

      context "when default is 'month'" do
        let(:tool_month_default) { described_class.new(api_key: "test-key", search_recency_filter: "month") }

        it "falls back to 'month' when agent provides invalid recency_filter" do
          expect(RAAF.logger).to receive(:warn).with(/Invalid recency_filter 'bad' - falling back to default: "month"/)

          result = tool_month_default.call(query: "test", search_recency_filter: "bad")
          expect(result[:success]).to be true
        end

        it "falls back to 'month' for multiple invalid values" do
          %w[invalid wrong bad terrible].each do |invalid_filter|
            expect(RAAF.logger).to receive(:warn).with(/Invalid recency_filter '#{invalid_filter}' - falling back to default: "month"/)

            result = tool_month_default.call(query: "test", search_recency_filter: invalid_filter)
            expect(result[:success]).to be true
          end
        end
      end

      context "when invalid domain_filter is provided" do
        let(:tool_with_default) { described_class.new(api_key: "test-key", search_recency_filter: "week") }

        it "still raises ArgumentError for invalid domain_filter (not caught by fallback)" do
          expect {
            tool_with_default.call(query: "test", search_domain_filter: 123)
          }.to raise_error(ArgumentError, /search_domain_filter must be a String or Array/)
        end
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
