# frozen_string_literal: true

require "spec_helper"
require "raaf/tool_registry"

RSpec.describe "RAAF::ToolRegistry error handling" do
  before do
    # Clear registry before each test
    RAAF::ToolRegistry.clear!
  end

  describe ".resolve_with_details" do
    context "when tool is found" do
      before do
        # Register a test tool
        stub_const("TestSearchTool", Class.new)
        RAAF::ToolRegistry.register(:test_search, TestSearchTool)
      end

      it "returns success with the resolved class" do
        result = RAAF::ToolRegistry.resolve_with_details(:test_search)

        expect(result[:success]).to be true
        expect(result[:tool_class]).to eq(TestSearchTool)
        expect(result[:identifier]).to eq(:test_search)
        expect(result[:searched_namespaces]).to be_empty
        expect(result[:suggestions]).to be_empty
      end

      it "works with string identifiers" do
        result = RAAF::ToolRegistry.resolve_with_details("test_search")

        expect(result[:success]).to be true
        expect(result[:tool_class]).to eq(TestSearchTool)
      end
    end

    context "when tool is not found" do
      before do
        # Register some similar tools for suggestion testing
        stub_const("WebSearchTool", Class.new)
        stub_const("SearchWebTool", Class.new)
        stub_const("WebCrawlerTool", Class.new)

        RAAF::ToolRegistry.register(:web_search, WebSearchTool)
        RAAF::ToolRegistry.register(:search_web, SearchWebTool)
        RAAF::ToolRegistry.register(:web_crawler, WebCrawlerTool)
      end

      it "returns failure with searched namespaces" do
        result = RAAF::ToolRegistry.resolve_with_details(:web_serach) # typo intentional

        expect(result[:success]).to be false
        expect(result[:tool_class]).to be_nil
        expect(result[:identifier]).to eq(:web_serach)
        expect(result[:searched_namespaces]).to include("RAAF::Tools", "Ai::Tools")
      end

      it "includes suggestions based on identifier similarity" do
        result = RAAF::ToolRegistry.resolve_with_details(:web_serach) # typo intentional

        expect(result[:suggestions]).to be_an(Array)
        expect(result[:suggestions]).not_to be_empty
        expect(result[:suggestions].any? { |s| s.include?("web_search") }).to be true
      end

      it "generates registration suggestion" do
        result = RAAF::ToolRegistry.resolve_with_details(:missing_tool)

        expect(result[:suggestions]).to include(
          "Register it: RAAF::ToolRegistry.register(:missing_tool, MissingToolTool)"
        )
      end

      it "generates class reference suggestion" do
        result = RAAF::ToolRegistry.resolve_with_details(:missing_tool)

        expect(result[:suggestions]).to include(
          "Use direct class: tool MissingToolTool"
        )
      end

      it "tracks all searched namespaces during auto-discovery" do
        result = RAAF::ToolRegistry.resolve_with_details(:nonexistent_tool)

        # Should have tried multiple namespaces
        expect(result[:searched_namespaces]).to include("RAAF::Tools")
        expect(result[:searched_namespaces]).to include("Ai::Tools")
        expect(result[:searched_namespaces].size).to be >= 2
      end
    end

    context "with direct class reference" do
      before do
        stub_const("MyCustomTool", Class.new)
      end

      it "returns success for valid class" do
        result = RAAF::ToolRegistry.resolve_with_details(MyCustomTool)

        expect(result[:success]).to be true
        expect(result[:tool_class]).to eq(MyCustomTool)
        expect(result[:identifier]).to eq(MyCustomTool)
      end
    end
  end

  describe "DidYouMean integration" do
    before do
      # Register tools with similar names
      stub_const("PerplexitySearchTool", Class.new)
      stub_const("PerplexityTool", Class.new)
      stub_const("TavilySearchTool", Class.new)

      RAAF::ToolRegistry.register(:perplexity_search, PerplexitySearchTool)
      RAAF::ToolRegistry.register(:perplexity, PerplexityTool)
      RAAF::ToolRegistry.register(:tavily_search, TavilySearchTool)
    end

    it "suggests similar tool names for typos" do
      result = RAAF::ToolRegistry.resolve_with_details(:perplexty) # typo

      suggestions = result[:suggestions]
      expect(suggestions.any? { |s| s.include?("perplexity") }).to be true
    end

    it "suggests multiple similar options" do
      result = RAAF::ToolRegistry.resolve_with_details(:search) # partial match

      suggestions = result[:suggestions]
      expect(suggestions.any? { |s| s.include?("perplexity_search") }).to be true
      expect(suggestions.any? { |s| s.include?("tavily_search") }).to be true
    end

    it "limits suggestions to reasonable number" do
      # Register many tools
      10.times do |i|
        stub_const("Tool#{i}", Class.new)
        RAAF::ToolRegistry.register("tool_#{i}".to_sym, Object.const_get("Tool#{i}"))
      end

      result = RAAF::ToolRegistry.resolve_with_details(:tool) # partial match

      # Should limit to top 3-5 suggestions
      did_you_mean_suggestions = result[:suggestions].select { |s| s.start_with?("Did you mean:") }
      expect(did_you_mean_suggestions.size).to be <= 3
    end
  end

  describe "error propagation to Agent" do
    # This will be tested in the Agent integration specs
    it "provides structured data for Agent to create ToolResolutionError" do
      result = RAAF::ToolRegistry.resolve_with_details(:unknown_tool)

      expect(result).to have_key(:success)
      expect(result).to have_key(:identifier)
      expect(result).to have_key(:searched_namespaces)
      expect(result).to have_key(:suggestions)

      # All keys needed for ToolResolutionError
      expect(result[:success]).to be false
      expect(result[:identifier]).to eq(:unknown_tool)
      expect(result[:searched_namespaces]).to be_an(Array)
      expect(result[:suggestions]).to be_an(Array)
    end
  end
end