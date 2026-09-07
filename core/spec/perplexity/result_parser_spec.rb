# frozen_string_literal: true

require "spec_helper"
require "raaf/perplexity/result_parser"

RSpec.describe RAAF::Perplexity::ResultParser do
  let(:sample_result) do
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
      "search_results" => [
        {
          "title" => "Ruby 3.4 Released",
          "url" => "https://ruby-lang.org/news/2024/ruby-3-4-released",
          "snippet" => "Ruby 3.4 is now available with improved performance..."
        },
        {
          "title" => "Ruby GitHub Repository",
          "url" => "https://github.com/ruby/ruby",
          "snippet" => "The Ruby programming language"
        }
      ],
      "model" => "sonar-pro"
    }
  end

  describe ".extract_content" do
    it "extracts content from response" do
      content = described_class.extract_content(sample_result)

      expect(content).to eq("Ruby 3.4 includes significant performance improvements...")
    end

    it "returns nil when choices are missing" do
      result = { "citations" => [] }
      content = described_class.extract_content(result)

      expect(content).to be_nil
    end

    it "returns nil when message is missing" do
      result = { "choices" => [{ "finish_reason" => "stop" }] }
      content = described_class.extract_content(result)

      expect(content).to be_nil
    end

    it "returns nil when content is missing" do
      result = { "choices" => [{ "message" => {} }] }
      content = described_class.extract_content(result)

      expect(content).to be_nil
    end
  end

  describe ".extract_citations" do
    it "extracts citations array from response" do
      citations = described_class.extract_citations(sample_result)

      expect(citations).to eq([
                                "https://ruby-lang.org/news/2024/ruby-3-4-released",
                                "https://github.com/ruby/ruby"
                              ])
    end

    it "returns empty array when citations missing" do
      result = { "choices" => [] }
      citations = described_class.extract_citations(result)

      expect(citations).to eq([])
    end

    it "returns empty array when citations is nil" do
      result = { "citations" => nil }
      citations = described_class.extract_citations(result)

      expect(citations).to eq([])
    end

    it "handles single citation" do
      result = { "citations" => ["https://ruby-lang.org"] }
      citations = described_class.extract_citations(result)

      expect(citations).to eq(["https://ruby-lang.org"])
    end
  end

  describe ".extract_search_results" do
    it "extracts search_results array from response" do
      search_results = described_class.extract_search_results(sample_result)

      expect(search_results).to be_an(Array)
      expect(search_results.length).to eq(2)
      expect(search_results.first["title"]).to eq("Ruby 3.4 Released")
      expect(search_results.first["url"]).to eq("https://ruby-lang.org/news/2024/ruby-3-4-released")
    end

    it "returns empty array when search_results missing" do
      result = { "choices" => [] }
      search_results = described_class.extract_search_results(result)

      expect(search_results).to eq([])
    end

    it "returns empty array when search_results is nil" do
      result = { "search_results" => nil }
      search_results = described_class.extract_search_results(result)

      expect(search_results).to eq([])
    end

    it "handles single web result" do
      result = {
        "search_results" => [
          { "title" => "Test", "url" => "https://test.com" }
        ]
      }
      search_results = described_class.extract_search_results(result)

      expect(search_results.length).to eq(1)
      expect(search_results.first["title"]).to eq("Test")
    end
  end

  describe ".format_search_result" do
    it "formats complete result with all fields" do
      formatted = described_class.format_search_result(sample_result)

      expect(formatted).to be_a(Hash)
      expect(formatted[:success]).to be true
      expect(formatted[:content]).to eq("Ruby 3.4 includes significant performance improvements...")
      expect(formatted[:citations]).to eq([
                                            "https://ruby-lang.org/news/2024/ruby-3-4-released",
                                            "https://github.com/ruby/ruby"
                                          ])
      expect(formatted[:search_results].length).to eq(2)
      expect(formatted[:model]).to eq("sonar-pro")
    end

    it "formats result with missing citations" do
      result = sample_result.dup
      result.delete("citations")

      formatted = described_class.format_search_result(result)

      expect(formatted[:success]).to be true
      expect(formatted[:citations]).to eq([])
      expect(formatted[:content]).to be_a(String)
    end

    it "formats result with missing search_results" do
      result = sample_result.dup
      result.delete("search_results")

      formatted = described_class.format_search_result(result)

      expect(formatted[:success]).to be true
      expect(formatted[:search_results]).to eq([])
      expect(formatted[:content]).to be_a(String)
    end

    it "formats result with missing content" do
      result = {
        "choices" => [{ "message" => {} }],
        "citations" => [],
        "search_results" => [],
        "model" => "sonar"
      }

      formatted = described_class.format_search_result(result)

      expect(formatted[:success]).to be true
      expect(formatted[:content]).to be_nil
      expect(formatted[:citations]).to eq([])
      expect(formatted[:search_results]).to eq([])
    end

    it "includes model information" do
      formatted = described_class.format_search_result(sample_result)

      expect(formatted[:model]).to eq("sonar-pro")
    end

    it "always marks result as success" do
      result = { "citations" => [], "search_results" => [] }
      formatted = described_class.format_search_result(result)

      expect(formatted[:success]).to be true
    end
  end
end
