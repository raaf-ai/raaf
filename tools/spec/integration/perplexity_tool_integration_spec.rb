# frozen_string_literal: true

require "spec_helper"

RSpec.describe "PerplexityTool End-to-End Integration", :integration do
  let(:api_key) { "test-perplexity-api-key" }

  # Mock Perplexity provider class for testing
  let(:mock_perplexity_provider_class) do
    Class.new do
      attr_reader :chat_completion_calls

      def initialize(*_args, **_kwargs)
        @chat_completion_calls = []
        @responses = []
      end

      def add_response(response)
        @responses << response
      end

      def chat_completion(**kwargs)
        @chat_completion_calls << kwargs
        @responses.shift || default_response
      end

      private

      def default_response
        {
          "choices" => [
            {
              "message" => { "content" => "Default test response" },
              "finish_reason" => "stop"
            }
          ],
          "citations" => [],
          "web_results" => [],
          "model" => "sonar"
        }
      end
    end
  end

  let(:mock_perplexity_provider_instance) { mock_perplexity_provider_class.new }
  let(:perplexity_tool) do
    tool = RAAF::Tools::PerplexityTool.new(api_key: api_key)
    # Inject mock provider instance
    tool.instance_variable_set(:@provider, mock_perplexity_provider_instance)
    tool
  end

  let(:standard_perplexity_response) do
    {
      "choices" => [
        {
          "message" => {
            "content" => "Ruby 3.4 introduces significant performance improvements including YJIT enhancements, better memory management, and faster method dispatch. The release includes new syntax features and improved developer experience."
          },
          "finish_reason" => "stop"
        }
      ],
      "citations" => [
        "https://ruby-lang.org/en/news/2024/12/25/ruby-3-4-0-released/",
        "https://github.com/ruby/ruby/releases/tag/v3_4_0"
      ],
      "web_results" => [
        {
          "title" => "Ruby 3.4.0 Released",
          "url" => "https://ruby-lang.org/en/news/2024/12/25/ruby-3-4-0-released/",
          "snippet" => "We are pleased to announce the release of Ruby 3.4.0. This version includes significant performance improvements..."
        },
        {
          "title" => "Ruby 3.4.0 on GitHub",
          "url" => "https://github.com/ruby/ruby/releases/tag/v3_4_0",
          "snippet" => "Ruby 3.4.0 release notes and changelog"
        }
      ],
      "model" => "sonar"
    }
  end

  describe "14.1: OpenAI agent using PerplexityTool for web search" do
    it "integrates PerplexityTool with OpenAI gpt-4o agent" do
      # Setup agent with PerplexityTool
      agent = RAAF::Agent.new(
        name: "ResearchAgent",
        instructions: "You are a research assistant that searches the web for current information using the perplexity_search tool.",
        model: "gpt-4o"
      )

      # Wrap tool for agent use
      function_tool = RAAF::FunctionTool.new(
        perplexity_tool.method(:call),
        name: "perplexity_search",
        description: "Search the web for current, factual information with citations"
      )

      agent.add_tool(function_tool)

      # Mock OpenAI provider
      mock_openai_provider = RAAF::Testing::MockProvider.new

      # OpenAI decides to use the tool
      mock_openai_provider.add_response(
        "I'll search for the latest Ruby news.",
        tool_calls: [{
          function: {
            name: "perplexity_search",
            arguments: '{"query": "latest Ruby 3.4 features", "model": "sonar"}'
          }
        }]
      )

      # OpenAI synthesizes the tool result
      mock_openai_provider.add_response(
        "According to recent sources, Ruby 3.4 introduces significant performance improvements including YJIT enhancements and better memory management [1][2]."
      )

      # Mock Perplexity search
      mock_perplexity_provider_instance.add_response(standard_perplexity_response)

      # Run conversation
      runner = RAAF::Runner.new(agent: agent, provider: mock_openai_provider)
      result = runner.run("What are the latest Ruby 3.4 features?")

      # Verify successful integration
      expect(result.success?).to be true
      expect(result.messages.last[:content]).to include("Ruby 3.4")
      expect(result.messages.last[:content]).to include("performance improvements")

      # Verify Perplexity was called
      expect(mock_perplexity_provider_instance.chat_completion_calls.length).to be > 0
    end
  end

  describe "14.2: Anthropic agent using PerplexityTool for research" do
    it "integrates PerplexityTool with Anthropic Claude agent" do
      # Setup agent with PerplexityTool
      agent = RAAF::Agent.new(
        name: "ClaudeResearcher",
        instructions: "You are a research assistant using Claude. Use perplexity_search to find current information.",
        model: "claude-3-5-sonnet-20241022"
      )

      # Wrap tool for agent use
      function_tool = RAAF::FunctionTool.new(
        perplexity_tool.method(:call),
        name: "perplexity_search",
        description: "Search the web for current information"
      )

      agent.add_tool(function_tool)

      # Mock Anthropic provider (mimicking ResponsesProvider format)
      mock_anthropic_provider = RAAF::Testing::MockProvider.new

      # Claude decides to use the tool
      mock_anthropic_provider.add_response(
        "Let me search for Ruby security information.",
        tool_calls: [{
          function: {
            name: "perplexity_search",
            arguments: '{"query": "Ruby security updates 2024", "model": "sonar", "search_recency_filter": "month"}'
          }
        }]
      )

      # Claude synthesizes results
      mock_anthropic_provider.add_response(
        "Based on current web sources, Ruby has released several security updates in 2024."
      )

      # Mock Perplexity search
      security_response = standard_perplexity_response.dup
      security_response["choices"][0]["message"]["content"] = "Ruby security updates include patches for CVE-2024-XXXX..."
      mock_perplexity_provider_instance.add_response(security_response)

      # Run conversation
      runner = RAAF::Runner.new(agent: agent, provider: mock_anthropic_provider)
      result = runner.run("Find recent Ruby security updates")

      # Verify successful integration
      expect(result.success?).to be true
      expect(result.messages.last[:content]).to include("security")

      # Verify Perplexity was called with recency filter
      expect(mock_perplexity_provider_instance.chat_completion_calls.length).to be > 0
      expect(mock_perplexity_provider_instance.chat_completion_calls.first).to include(
        web_search_options: hash_including(search_recency_filter: "month")
      )
    end
  end

  describe "14.3: Agent workflow with multiple Perplexity searches" do
    it "handles sequential searches in one conversation" do
      agent = RAAF::Agent.new(
        name: "MultiSearchAgent",
        instructions: "You perform multiple web searches to answer questions thoroughly.",
        model: "gpt-4o"
      )

      function_tool = RAAF::FunctionTool.new(
        perplexity_tool.method(:call),
        name: "perplexity_search",
        description: "Search the web for information"
      )

      agent.add_tool(function_tool)

      mock_provider = RAAF::Testing::MockProvider.new

      # First search: Ruby features
      mock_provider.add_response(
        "Searching for Ruby features...",
        tool_calls: [{
          function: {
            name: "perplexity_search",
            arguments: '{"query": "Ruby 3.4 new features", "model": "sonar"}'
          }
        }]
      )

      # Second search: Performance comparisons
      mock_provider.add_response(
        "Now let me search for performance comparisons...",
        tool_calls: [{
          function: {
            name: "perplexity_search",
            arguments: '{"query": "Ruby 3.4 vs 3.3 performance", "model": "sonar"}'
          }
        }]
      )

      # Final synthesis
      mock_provider.add_response(
        "Based on my research, Ruby 3.4 includes both new features and performance improvements compared to 3.3."
      )

      # Mock Perplexity responses for both searches
      first_response = standard_perplexity_response.dup
      second_response = standard_perplexity_response.dup
      second_response["choices"][0]["message"]["content"] = "Ruby 3.4 shows 20% better performance than 3.3..."

      allow(mock_perplexity_provider).to receive(:chat_completion)
        .and_return(first_response, second_response)

      # Run conversation
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      result = runner.run("Compare Ruby 3.4 features and performance with 3.3")

      # Verify multiple searches
      expect(result.success?).to be true
      expect(mock_perplexity_provider_instance.chat_completion_calls.length).to be > 0.twice
    end
  end

  describe "14.4: Tool with all Perplexity models" do
    it "works with sonar model" do
      agent = RAAF::Agent.new(
        name: "SonarAgent",
        instructions: "Use sonar model for fast searches",
        model: "gpt-4o"
      )

      function_tool = RAAF::FunctionTool.new(
        perplexity_tool.method(:call),
        name: "perplexity_search",
        description: "Fast web search"
      )

      agent.add_tool(function_tool)

      mock_provider = RAAF::Testing::MockProvider.new
      mock_provider.add_response(
        "Searching...",
        tool_calls: [{
          function: {
            name: "perplexity_search",
            arguments: '{"query": "Ruby news", "model": "sonar"}'
          }
        }]
      )
      mock_provider.add_response("Found Ruby news")

      mock_perplexity_provider_instance.add_response(standard_perplexity_response)

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      result = runner.run("Find Ruby news")

      expect(result.success?).to be true
      expect(mock_perplexity_provider_instance.chat_completion_calls.length).to be > 0.with(
        hash_including(model: "sonar")
      )
    end

    it "works with sonar-pro model" do
      agent = RAAF::Agent.new(
        name: "SonarProAgent",
        instructions: "Use sonar-pro for deep research",
        model: "gpt-4o"
      )

      function_tool = RAAF::FunctionTool.new(
        perplexity_tool.method(:call),
        name: "perplexity_search",
        description: "Deep web search"
      )

      agent.add_tool(function_tool)

      mock_provider = RAAF::Testing::MockProvider.new
      mock_provider.add_response(
        "Performing deep search...",
        tool_calls: [{
          function: {
            name: "perplexity_search",
            arguments: '{"query": "Ruby performance analysis", "model": "sonar-pro"}'
          }
        }]
      )
      mock_provider.add_response("Deep analysis complete")

      pro_response = standard_perplexity_response.dup
      pro_response["model"] = "sonar-pro"
      mock_perplexity_provider_instance.add_response(pro_response)

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      result = runner.run("Deep analysis of Ruby performance")

      expect(result.success?).to be true
      expect(mock_perplexity_provider_instance.chat_completion_calls.length).to be > 0.with(
        hash_including(model: "sonar-pro")
      )
    end

    it "works with sonar-reasoning model" do
      agent = RAAF::Agent.new(
        name: "SonarReasoningAgent",
        instructions: "Use sonar-reasoning for complex analysis",
        model: "gpt-4o"
      )

      function_tool = RAAF::FunctionTool.new(
        perplexity_tool.method(:call),
        name: "perplexity_search",
        description: "Reasoning-based search"
      )

      agent.add_tool(function_tool)

      mock_provider = RAAF::Testing::MockProvider.new
      mock_provider.add_response(
        "Analyzing...",
        tool_calls: [{
          function: {
            name: "perplexity_search",
            arguments: '{"query": "Ruby vs Python comparison", "model": "sonar-reasoning"}'
          }
        }]
      )
      mock_provider.add_response("Analysis complete")

      reasoning_response = standard_perplexity_response.dup
      reasoning_response["model"] = "sonar-reasoning"
      mock_perplexity_provider_instance.add_response(reasoning_response)

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      result = runner.run("Compare Ruby and Python")

      expect(result.success?).to be true
      expect(mock_perplexity_provider_instance.chat_completion_calls.length).to be > 0.with(
        hash_including(model: "sonar-reasoning")
      )
    end
  end

  describe "14.5: Tool with domain filtering in agent context" do
    it "applies domain filtering from agent tool call arguments" do
      agent = RAAF::Agent.new(
        name: "DomainFilterAgent",
        instructions: "Search with domain restrictions",
        model: "gpt-4o"
      )

      function_tool = RAAF::FunctionTool.new(
        perplexity_tool.method(:call),
        name: "perplexity_search",
        description: "Search with domain filtering"
      )

      agent.add_tool(function_tool)

      mock_provider = RAAF::Testing::MockProvider.new
      mock_provider.add_response(
        "Searching official Ruby sources...",
        tool_calls: [{
          function: {
            name: "perplexity_search",
            arguments: '{"query": "Ruby 3.4 release", "model": "sonar", "search_domain_filter": ["ruby-lang.org", "github.com"]}'
          }
        }]
      )
      mock_provider.add_response("Found official information")

      mock_perplexity_provider_instance.add_response(standard_perplexity_response)

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      result = runner.run("Find Ruby 3.4 info from official sources")

      expect(result.success?).to be true
      expect(mock_perplexity_provider_instance.chat_completion_calls.length).to be > 0.with(
        hash_including(
          web_search_options: hash_including(
            search_domain_filter: ["ruby-lang.org", "github.com"]
          )
        )
      )
    end
  end

  describe "14.6: Tool with recency filtering in agent context" do
    it "applies recency filtering from agent tool call arguments" do
      agent = RAAF::Agent.new(
        name: "RecencyFilterAgent",
        instructions: "Search for recent information",
        model: "gpt-4o"
      )

      function_tool = RAAF::FunctionTool.new(
        perplexity_tool.method(:call),
        name: "perplexity_search",
        description: "Search with recency filtering"
      )

      agent.add_tool(function_tool)

      mock_provider = RAAF::Testing::MockProvider.new
      mock_provider.add_response(
        "Searching recent news...",
        tool_calls: [{
          function: {
            name: "perplexity_search",
            arguments: '{"query": "Ruby security updates", "model": "sonar", "search_recency_filter": "week"}'
          }
        }]
      )
      mock_provider.add_response("Found recent updates")

      mock_perplexity_provider_instance.add_response(standard_perplexity_response)

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      result = runner.run("Find Ruby security updates from the past week")

      expect(result.success?).to be true
      expect(mock_perplexity_provider_instance.chat_completion_calls.length).to be > 0.with(
        hash_including(
          web_search_options: hash_including(
            search_recency_filter: "week"
          )
        )
      )
    end
  end

  describe "14.7: Verify citations returned correctly to agent" do
    it "extracts and passes citations to agent" do
      agent = RAAF::Agent.new(
        name: "CitationAgent",
        instructions: "Always include citations from search results",
        model: "gpt-4o"
      )

      function_tool = RAAF::FunctionTool.new(
        perplexity_tool.method(:call),
        name: "perplexity_search",
        description: "Search with citations"
      )

      agent.add_tool(function_tool)

      mock_provider = RAAF::Testing::MockProvider.new
      mock_provider.add_response(
        "Searching...",
        tool_calls: [{
          function: {
            name: "perplexity_search",
            arguments: '{"query": "Ruby 3.4", "model": "sonar"}'
          }
        }]
      )

      # Agent receives tool result with citations
      mock_provider.add_response(
        "According to sources [1][2], Ruby 3.4 includes new features."
      )

      mock_perplexity_provider_instance.add_response(standard_perplexity_response)

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      result = runner.run("Tell me about Ruby 3.4")

      expect(result.success?).to be true

      # Verify tool result contains citations
      tool_messages = result.messages.select { |m| m[:role] == "tool" }
      expect(tool_messages).not_to be_empty

      # Tool result should include citations in the content
      tool_result = tool_messages.first
      expect(tool_result[:content]).to be_a(String)
      parsed_content = JSON.parse(tool_result[:content])
      expect(parsed_content["citations"]).to be_an(Array)
      expect(parsed_content["citations"]).to include("https://ruby-lang.org/en/news/2024/12/25/ruby-3-4-0-released/")
    end
  end

  describe "14.8: Verify web_results returned correctly to agent" do
    it "extracts and passes web_results to agent" do
      agent = RAAF::Agent.new(
        name: "WebResultsAgent",
        instructions: "Use web results for detailed information",
        model: "gpt-4o"
      )

      function_tool = RAAF::FunctionTool.new(
        perplexity_tool.method(:call),
        name: "perplexity_search",
        description: "Search with web results"
      )

      agent.add_tool(function_tool)

      mock_provider = RAAF::Testing::MockProvider.new
      mock_provider.add_response(
        "Searching...",
        tool_calls: [{
          function: {
            name: "perplexity_search",
            arguments: '{"query": "Ruby 3.4 performance", "model": "sonar"}'
          }
        }]
      )

      mock_provider.add_response(
        "Based on the web results, Ruby 3.4 shows significant improvements."
      )

      mock_perplexity_provider_instance.add_response(standard_perplexity_response)

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      result = runner.run("Research Ruby 3.4 performance")

      expect(result.success?).to be true

      # Verify tool result contains web_results
      tool_messages = result.messages.select { |m| m[:role] == "tool" }
      expect(tool_messages).not_to be_empty

      tool_result = tool_messages.first
      parsed_content = JSON.parse(tool_result[:content])
      expect(parsed_content["web_results"]).to be_an(Array)
      expect(parsed_content["web_results"].length).to be > 0

      # Verify web_results have required fields
      first_result = parsed_content["web_results"].first
      expect(first_result).to have_key("title")
      expect(first_result).to have_key("url")
      expect(first_result).to have_key("snippet")
    end
  end
end
