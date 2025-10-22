# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/errors"

RSpec.describe RAAF::DSL::ToolResolutionError do
  describe "#initialize" do
    let(:identifier) { :web_search }
    let(:searched_namespaces) { ["RAAF::Tools", "Ai::Tools", "RAAF::Tools::Basic"] }
    let(:suggestions) { ["Did you mean: :web_searcher?", "Did you mean: :search_web?", "Try: tool WebSearchTool"] }

    subject(:error) { described_class.new(identifier, searched_namespaces, suggestions) }

    it "creates an error with the correct identifier" do
      expect(error.identifier).to eq(identifier)
    end

    it "stores searched namespaces" do
      expect(error.searched_namespaces).to eq(searched_namespaces)
    end

    it "stores suggestions" do
      expect(error.suggestions).to eq(suggestions)
    end

    it "formats the error message with emoji indicators" do
      message = error.message

      expect(message).to include("❌ Tool not found: #{identifier}")
      expect(message).to include("📂 Searched in:")
      expect(message).to include("💡 Suggestions:")
      expect(message).to include("🔧 To fix:")
    end

    it "includes all searched namespaces in the message" do
      message = error.message

      searched_namespaces.each do |namespace|
        expect(message).to include(namespace)
      end
    end

    it "includes all suggestions in the message" do
      message = error.message

      suggestions.each do |suggestion|
        expect(message).to include(suggestion)
      end
    end

    it "includes registry information" do
      message = error.message
      expect(message).to include("Registry: RAAF::ToolRegistry")
    end

    it "provides actionable fix instructions" do
      message = error.message

      expect(message).to include("1. Ensure the tool class exists")
      expect(message).to include("2. Register it:")
      expect(message).to include("RAAF::ToolRegistry.register(:#{identifier}")
      expect(message).to include("3. Or use direct class reference:")
      expect(message).to include("tool WebSearchTool")
    end
  end

  describe "error message formatting" do
    context "with no suggestions" do
      let(:error) { described_class.new(:unknown_tool, ["RAAF::Tools"], []) }

      it "still formats the message correctly" do
        message = error.message

        expect(message).to include("❌ Tool not found: unknown_tool")
        expect(message).to include("💡 Suggestions:")
        expect(message).to include("(No suggestions available)")
      end
    end

    context "with single namespace" do
      let(:error) { described_class.new(:my_tool, ["RAAF::Tools"], ["Try: tool MyTool"]) }

      it "formats namespace list correctly" do
        message = error.message
        expect(message).to include("Namespaces: RAAF::Tools")
      end
    end

    context "with multiple namespaces" do
      let(:error) { described_class.new(:my_tool, ["RAAF::Tools", "Ai::Tools"], ["Try: tool MyTool"]) }

      it "formats namespace list with commas" do
        message = error.message
        expect(message).to include("Namespaces: RAAF::Tools, Ai::Tools")
      end
    end

    context "with symbol identifier" do
      let(:error) { described_class.new(:web_search, [], []) }

      it "properly formats the symbol in fix instructions" do
        message = error.message
        expect(message).to include("RAAF::ToolRegistry.register(:web_search, WebSearchTool)")
      end
    end

    context "with string identifier" do
      let(:error) { described_class.new("web_search", [], []) }

      it "properly formats the string in fix instructions" do
        message = error.message
        expect(message).to include("RAAF::ToolRegistry.register(:web_search, WebSearchTool)")
      end
    end
  end

  describe "integration with ToolRegistry" do
    before do
      # Stub ToolRegistry to simulate resolution failure
      allow(RAAF::ToolRegistry).to receive(:resolve_with_details).and_return({
        success: false,
        identifier: :missing_tool,
        searched_namespaces: ["RAAF::Tools", "Ai::Tools"],
        suggestions: ["Did you mean: :existing_tool?"]
      })
    end

    it "can be raised with data from ToolRegistry" do
      result = RAAF::ToolRegistry.resolve_with_details(:missing_tool)

      expect {
        raise described_class.new(
          result[:identifier],
          result[:searched_namespaces],
          result[:suggestions]
        )
      }.to raise_error(described_class) do |error|
        expect(error.message).to include("❌ Tool not found: missing_tool")
        expect(error.message).to include("RAAF::Tools")
        expect(error.message).to include("Did you mean: :existing_tool?")
      end
    end
  end
end