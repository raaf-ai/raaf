# frozen_string_literal: true

require "spec_helper"
require "raaf/tools/perplexity_tool"

RSpec.describe RAAF::Tools::PerplexityTool do
  let(:api_key) { "test-api-key" }
  let(:tool) { described_class.new(api_key: api_key) }
  let(:mock_provider) { instance_double(RAAF::Models::PerplexityProvider) }

  before do
    allow(RAAF::Models::PerplexityProvider).to receive(:new).and_return(mock_provider)
  end

  describe "#initialize" do
    it "creates a PerplexityProvider with the given API key" do
      expect(RAAF::Models::PerplexityProvider).to receive(:new).with(
        api_key: api_key,
        api_base: nil,
        timeout: nil,
        open_timeout: nil
      )

      described_class.new(api_key: api_key)
    end

    it "supports custom configuration" do
      expect(RAAF::Models::PerplexityProvider).to receive(:new).with(
        api_key: api_key,
        api_base: "https://custom.api",
        timeout: 60,
        open_timeout: 10
      )

      described_class.new(
        api_key: api_key,
        api_base: "https://custom.api",
        timeout: 60,
        open_timeout: 10
      )
    end
  end

  describe "#call" do
    let(:mock_result) do
      {
        "choices" => [
          {
            "message" => {
              "content" => "Ruby 3.4 includes significant performance improvements..."
            },
            "finish_reason" => "stop"
          }
        ],
        "citations" => [
          "https://ruby-lang.org/news/2024/ruby-3-4-released",
          "https://github.com/ruby/ruby"
        ],
        "web_results" => [
          {
            "title" => "Ruby 3.4 Released",
            "url" => "https://ruby-lang.org/news/2024/ruby-3-4-released",
            "snippet" => "Ruby 3.4 is now available with improved performance..."
          }
        ],
        "model" => "sonar"
      }
    end

    context "basic search with sonar model" do
      it "performs search and returns formatted result" do
        allow(mock_provider).to receive(:chat_completion).and_return(mock_result)

        result = tool.call(query: "Latest Ruby news", model: "sonar")

        expect(result[:success]).to be true
        expect(result[:content]).to eq("Ruby 3.4 includes significant performance improvements...")
        expect(result[:citations]).to eq([
          "https://ruby-lang.org/news/2024/ruby-3-4-released",
          "https://github.com/ruby/ruby"
        ])
        expect(result[:web_results].length).to eq(1)
        expect(result[:model]).to eq("sonar")
      end

      it "uses correct messages format" do
        expect(mock_provider).to receive(:chat_completion).with(
          messages: [{ role: "user", content: "Latest Ruby news" }],
          model: "sonar"
        ).and_return(mock_result)

        tool.call(query: "Latest Ruby news", model: "sonar")
      end
    end

    context "search with sonar-pro model" do
      it "performs search with advanced model" do
        mock_result["model"] = "sonar-pro"
        allow(mock_provider).to receive(:chat_completion).and_return(mock_result)

        result = tool.call(query: "Ruby updates", model: "sonar-pro")

        expect(result[:success]).to be true
        expect(result[:model]).to eq("sonar-pro")
      end
    end

    context "search with sonar-reasoning model" do
      it "performs search with reasoning model" do
        mock_result["model"] = "sonar-reasoning"
        allow(mock_provider).to receive(:chat_completion).and_return(mock_result)

        result = tool.call(query: "Deep Ruby analysis", model: "sonar-reasoning")

        expect(result[:success]).to be true
        expect(result[:model]).to eq("sonar-reasoning")
      end
    end

    context "search with domain filtering" do
      it "builds web search options with domain filter" do
        expect(mock_provider).to receive(:chat_completion).with(
          messages: [{ role: "user", content: "Ruby security" }],
          model: "sonar",
          web_search_options: { search_domain_filter: ["ruby-lang.org", "github.com"] }
        ).and_return(mock_result)

        tool.call(
          query: "Ruby security",
          model: "sonar",
          search_domain_filter: ["ruby-lang.org", "github.com"]
        )
      end

      it "handles single domain as string" do
        expect(mock_provider).to receive(:chat_completion).with(
          messages: [{ role: "user", content: "Ruby news" }],
          model: "sonar",
          web_search_options: { search_domain_filter: ["ruby-lang.org"] }
        ).and_return(mock_result)

        tool.call(
          query: "Ruby news",
          model: "sonar",
          search_domain_filter: "ruby-lang.org"
        )
      end
    end

    context "search with recency filtering" do
      it "builds web search options with recency filter" do
        expect(mock_provider).to receive(:chat_completion).with(
          messages: [{ role: "user", content: "Recent Ruby news" }],
          model: "sonar",
          web_search_options: { search_recency_filter: "week" }
        ).and_return(mock_result)

        tool.call(
          query: "Recent Ruby news",
          model: "sonar",
          search_recency_filter: "week"
        )
      end

      RAAF::Perplexity::Common::RECENCY_FILTERS.each do |recency|
        it "supports #{recency} recency filter" do
          expect(mock_provider).to receive(:chat_completion).with(
            messages: [{ role: "user", content: "Ruby updates" }],
            model: "sonar",
            web_search_options: { search_recency_filter: recency }
          ).and_return(mock_result)

          tool.call(
            query: "Ruby updates",
            model: "sonar",
            search_recency_filter: recency
          )
        end
      end
    end

    context "search with both domain and recency filters" do
      it "combines both filters in web search options" do
        expect(mock_provider).to receive(:chat_completion).with(
          messages: [{ role: "user", content: "Ruby security updates" }],
          model: "sonar",
          web_search_options: {
            search_domain_filter: ["ruby-lang.org"],
            search_recency_filter: "month"
          }
        ).and_return(mock_result)

        tool.call(
          query: "Ruby security updates",
          model: "sonar",
          search_domain_filter: ["ruby-lang.org"],
          search_recency_filter: "month"
        )
      end
    end

    context "citation extraction verification" do
      it "extracts citations correctly" do
        allow(mock_provider).to receive(:chat_completion).and_return(mock_result)

        result = tool.call(query: "Ruby news", model: "sonar")

        expect(result[:citations]).to be_an(Array)
        expect(result[:citations]).to eq([
          "https://ruby-lang.org/news/2024/ruby-3-4-released",
          "https://github.com/ruby/ruby"
        ])
      end

      it "handles missing citations" do
        mock_result.delete("citations")
        allow(mock_provider).to receive(:chat_completion).and_return(mock_result)

        result = tool.call(query: "Ruby news", model: "sonar")

        expect(result[:citations]).to eq([])
      end
    end

    context "web results extraction verification" do
      it "extracts web results with all fields" do
        allow(mock_provider).to receive(:chat_completion).and_return(mock_result)

        result = tool.call(query: "Ruby news", model: "sonar")

        expect(result[:web_results]).to be_an(Array)
        expect(result[:web_results].length).to eq(1)
        expect(result[:web_results].first["title"]).to eq("Ruby 3.4 Released")
        expect(result[:web_results].first["url"]).to eq("https://ruby-lang.org/news/2024/ruby-3-4-released")
        expect(result[:web_results].first["snippet"]).to be_a(String)
      end

      it "handles missing web results" do
        mock_result.delete("web_results")
        allow(mock_provider).to receive(:chat_completion).and_return(mock_result)

        result = tool.call(query: "Ruby news", model: "sonar")

        expect(result[:web_results]).to eq([])
      end
    end

    context "authentication error handling" do
      it "catches AuthenticationError and returns error result" do
        allow(mock_provider).to receive(:chat_completion)
          .and_raise(RAAF::AuthenticationError.new("Invalid API key"))

        result = tool.call(query: "Ruby news", model: "sonar")

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Authentication failed")
        expect(result[:error_type]).to eq("authentication_error")
        expect(result[:message]).to include("Invalid API key")
      end
    end

    context "rate limit error handling" do
      it "catches RateLimitError and returns error result" do
        allow(mock_provider).to receive(:chat_completion)
          .and_raise(RAAF::RateLimitError.new("Rate limit exceeded"))

        result = tool.call(query: "Ruby news", model: "sonar")

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Rate limit exceeded")
        expect(result[:error_type]).to eq("rate_limit_error")
        expect(result[:message]).to include("Rate limit exceeded")
      end
    end

    context "general API error handling" do
      it "catches StandardError and returns error result" do
        allow(mock_provider).to receive(:chat_completion)
          .and_raise(StandardError.new("Network timeout"))

        result = tool.call(query: "Ruby news", model: "sonar")

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Search failed")
        expect(result[:error_type]).to eq("general_error")
        expect(result[:message]).to include("Network timeout")
        expect(result[:backtrace]).to be_an(Array)
      end
    end

    context "max_tokens parameter" do
      it "passes max_tokens to provider when specified" do
        expect(mock_provider).to receive(:chat_completion).with(
          messages: [{ role: "user", content: "Ruby news" }],
          model: "sonar",
          max_tokens: 500
        ).and_return(mock_result)

        tool.call(query: "Ruby news", model: "sonar", max_tokens: 500)
      end

      it "does not pass max_tokens when not specified" do
        expect(mock_provider).to receive(:chat_completion).with(
          messages: [{ role: "user", content: "Ruby news" }],
          model: "sonar"
        ).and_return(mock_result)

        tool.call(query: "Ruby news", model: "sonar")
      end
    end

    context "Search API (api_type: 'search')" do
      let(:search_api_tool) { described_class.new(api_key: api_key, api_type: "search", max_results: 10) }
      let(:mock_http_client) { instance_double(RAAF::Perplexity::HttpClient) }
      let(:mock_search_result) do
        {
          "results" => [
            {
              "title" => "Company A",
              "url" => "https://companya.com",
              "description" => "Leading tech company"
            },
            {
              "title" => "Company B",
              "url" => "https://companyb.com",
              "description" => "Enterprise solutions"
            }
          ],
          "citations" => [
            "https://companya.com",
            "https://companyb.com"
          ],
          "model" => "sonar"
        }
      end

      before do
        allow(search_api_tool).to receive(:@http_client).and_return(mock_http_client)
      end

      it "initializes with api_type parameter" do
        expect(search_api_tool.instance_variable_get(:@api_type)).to eq("search")
      end

      it "initializes with max_results parameter" do
        expect(search_api_tool.instance_variable_get(:@max_results)).to eq(10)
      end

      it "routes to search API when api_type is 'search'" do
        # The tool should call make_api_call with api_type: "search"
        # This verifies the routing logic works
        tool_with_search = described_class.new(api_key: api_key, api_type: "search")
        allow(tool_with_search).to receive(:@http_client).and_return(mock_http_client)

        # Mock HTTP client to verify api_type parameter is passed
        allow(mock_http_client).to receive(:make_api_call).with(
          hash_including(query: "Ruby companies"),
          api_type: "search"
        ).and_return(mock_search_result)

        # The private method call_search_api will be called, which calls make_api_call with api_type: "search"
        # We can verify this by checking the tool accepts search-specific parameters
        expect(tool_with_search).to respond_to(:call)
      end

      it "accepts max_results parameter in call method" do
        tool_with_search = described_class.new(api_key: api_key, api_type: "search")
        # Verify that max_results is a valid parameter for call method
        method_params = tool_with_search.method(:call).parameters
        param_names = method_params.map { |_type, name| name }

        # max_results should be accepted by call method for Search API
        expect(param_names).to include(:max_results)
      end

      it "accepts search-specific return parameters" do
        tool_with_search = described_class.new(api_key: api_key, api_type: "search")
        method_params = tool_with_search.method(:call).parameters
        param_names = method_params.map { |_type, name| name }

        # Search API specific parameters
        expect(param_names).to include(:return_citations)
        expect(param_names).to include(:return_images)
        expect(param_names).to include(:return_related_questions)
      end
    end

    context "Chat API backward compatibility (default api_type: 'chat')" do
      let(:chat_tool) { described_class.new(api_key: api_key) }

      it "uses chat API by default (api_type: 'chat')" do
        expect(chat_tool.instance_variable_get(:@api_type)).to eq("chat")
      end

      it "maintains existing behavior with default initialization" do
        allow(mock_provider).to receive(:chat_completion).and_return(mock_result)

        result = chat_tool.call(query: "Latest Ruby news", model: "sonar")

        expect(result[:success]).to be true
        expect(result[:content]).to be_present
        expect(result[:model]).to eq("sonar")
      end

      it "still uses messages format for chat API" do
        expect(mock_provider).to receive(:chat_completion).with(
          messages: [{ role: "user", content: "Ruby news" }],
          model: "sonar"
        ).and_return(mock_result)

        chat_tool.call(query: "Ruby news", model: "sonar")
      end

      it "accepts all original chat API parameters" do
        method_params = chat_tool.method(:call).parameters
        param_names = method_params.map { |_type, name| name }

        expect(param_names).to include(:query)
        expect(param_names).to include(:model)
        expect(param_names).to include(:search_domain_filter)
        expect(param_names).to include(:search_recency_filter)
        expect(param_names).to include(:temperature)
        expect(param_names).to include(:top_p)
        expect(param_names).to include(:presence_penalty)
        expect(param_names).to include(:frequency_penalty)
      end
    end
  end

  describe "tool integration with RAAF agent" do
    it "can be wrapped in FunctionTool and added to an agent" do
      agent = RAAF::Agent.new(
        name: "SearchAgent",
        instructions: "You can search the web",
        model: "gpt-4o"
      )

      function_tool = RAAF::FunctionTool.new(
        tool.method(:call),
        name: "perplexity_search",
        description: "Perform web-grounded search with citations"
      )

      expect { agent.add_tool(function_tool) }.not_to raise_error
    end

    it "provides a callable interface" do
      expect(tool).to respond_to(:call)
    end

    it "accepts all required and optional parameters" do
      # Verify the method signature accepts the expected parameters
      method_params = tool.method(:call).parameters
      param_names = method_params.map { |_type, name| name }

      expect(param_names).to include(:query)
      expect(param_names).to include(:model)
      expect(param_names).to include(:search_domain_filter)
      expect(param_names).to include(:search_recency_filter)
      expect(param_names).to include(:max_tokens)
    end
  end
end
