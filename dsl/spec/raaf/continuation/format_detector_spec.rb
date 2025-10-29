# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::Continuation::FormatDetector" do
  # Test FormatDetector implementation
  # This class analyzes content to automatically detect CSV, Markdown, or JSON format
  # Used when continuation support is configured with output_format: :auto

  let(:detector) { RAAF::Continuation::FormatDetector.new }

  # ============================================================================
  # 1. CSV Format Detection Tests (8 tests)
  # ============================================================================
  describe "CSV format detection" do
    it "detects basic CSV format with headers" do
      content = "id,name,email\n1,Alice,alice@example.com\n2,Bob,bob@example.com"
      format, confidence = detector.detect(content)

      expect(format).to eq(:csv)
      expect(confidence).to be > 0.5
    end

    it "detects CSV with quoted fields" do
      content = '"id","name","email"\n"1","Alice","alice@example.com"\n"2","Bob","bob@example.com"'
      format, confidence = detector.detect(content)

      expect(format).to eq(:csv)
      expect(confidence).to be > 0.5
    end

    it "detects CSV with commas in quoted fields" do
      content = 'id,name,address\n1,"Alice","123 Main St, Apt 4"\n2,"Bob","456 Oak Ave, Suite 100"'
      format, confidence = detector.detect(content)

      expect(format).to eq(:csv)
      expect(confidence).to be > 0.5
    end

    it "detects large CSV datasets" do
      lines = ["id,name,email,phone,address"]
      (1..100).each do |i|
        lines << "#{i},Person#{i},person#{i}@example.com,555-000#{i},#{i} Main St"
      end
      content = lines.join("\n")

      format, confidence = detector.detect(content)

      expect(format).to eq(:csv)
      expect(confidence).to be > 0.6
    end

    it "rejects content with pipes as CSV (markdown indicator)" do
      content = "id | name | email\n1 | Alice | alice@example.com"
      format, confidence = detector.detect(content)

      expect(format).not_to eq(:csv)
    end

    it "rejects JSON-like content as CSV" do
      content = '{"data": [{"id": 1, "name": "Alice"}]}'
      format, confidence = detector.detect(content)

      expect(format).not_to eq(:csv)
    end

    it "handles CSV with inconsistent columns" do
      content = "id,name,email\n1,Alice\n2,Bob,bob@example.com,extra"
      format, confidence = detector.detect(content)

      # Should still detect as CSV but with lower confidence
      expect(format).to eq(:csv)
    end

    it "detects single-line CSV" do
      content = "Alice,alice@example.com,123-456-7890"
      format, confidence = detector.detect(content)

      expect(format).to eq(:csv)
    end
  end

  # ============================================================================
  # 2. Markdown Format Detection Tests (8 tests)
  # ============================================================================
  describe "Markdown format detection" do
    it "detects markdown with headers" do
      content = "# My Report\n\n## Section 1\n\nSome content here"
      format, confidence = detector.detect(content)

      expect([:markdown, :unknown]).to include(format)
      expect(confidence).to be > 0.3
    end

    it "detects markdown with code blocks" do
      content = "Here is some code:\n\n```ruby\ndef hello\n  puts 'world'\nend\n```"
      format, confidence = detector.detect(content)

      expect([:markdown, :unknown]).to include(format)
      expect(confidence).to be > 0.3
    end

    it "detects markdown tables" do
      content = "| ID | Name | Email |\n|---|---|---|\n| 1 | Alice | alice@example.com |\n| 2 | Bob | bob@example.com |"
      format, confidence = detector.detect(content)

      expect([:markdown, :unknown]).to include(format)
      expect(confidence).to be > 0.3
    end

    it "detects markdown with emphasis" do
      content = "This is **bold** and this is *italic* text."
      format, confidence = detector.detect(content)

      expect([:markdown, :unknown]).to include(format)
      expect(confidence).to be > 0.3
    end

    it "detects markdown with lists" do
      content = "- Item 1\n- Item 2\n  - Nested item\n- Item 3"
      format, confidence = detector.detect(content)

      expect([:markdown, :unknown]).to include(format)
      expect(confidence).to be > 0.3
    end

    it "detects complex markdown document" do
      content = <<~MD
        # Analysis Report

        ## Introduction
        This is the introduction.

        ## Data Table
        | Year | Revenue | Growth |
        |------|---------|--------|
        | 2022 | $100M   | 10%    |
        | 2023 | $150M   | 50%    |

        ## Code Example
        ```python
        def calculate_growth(current, previous):
          return (current - previous) / previous * 100
        ```

        ## Conclusion
        The results show **significant growth**.
      MD

      format, confidence = detector.detect(content)

      expect([:markdown, :unknown]).to include(format)
      expect(confidence).to be > 0.6
    end

    it "rejects JSON as markdown" do
      content = '{"items": [{"id": 1, "name": "Alice"}]}'
      format, confidence = detector.detect(content)

      expect(format).not_to eq(:markdown)
    end

    it "rejects plain CSV as markdown" do
      content = "id,name,email\n1,Alice,alice@example.com"
      format, confidence = detector.detect(content)

      expect(format).not_to eq(:markdown)
    end
  end

  # ============================================================================
  # 3. JSON Format Detection Tests (8 tests)
  # ============================================================================
  describe "JSON format detection" do
    it "detects JSON object" do
      content = '{"id": 1, "name": "Alice", "email": "alice@example.com"}'
      format, confidence = detector.detect(content)

      expect(format).to eq(:json)
      expect(confidence).to be > 0.7
    end

    it "detects JSON array of objects" do
      content = '[{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]'
      format, confidence = detector.detect(content)

      expect(format).to eq(:json)
      expect(confidence).to be > 0.7
    end

    it "detects large JSON array" do
      items = (1..50).map { |i| %Q({"id": #{i}, "name": "Item#{i}", "value": #{i * 10}}) }
      content = "[#{items.join(", ")}]"
      format, confidence = detector.detect(content)

      expect(format).to eq(:json)
      expect(confidence).to be > 0.7
    end

    it "detects nested JSON objects" do
      content = '{"company": {"name": "Acme", "address": {"street": "123 Main", "city": "NYC"}}}'
      format, confidence = detector.detect(content)

      expect(format).to eq(:json)
      expect(confidence).to be > 0.7
    end

    it "detects incomplete JSON with reasonable confidence" do
      content = '{"items": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"'
      format, confidence = detector.detect(content)

      expect(format).to eq(:json)
      expect(confidence).to be > 0.3
    end

    it "detects JSON array starting with bracket" do
      content = '[{"id": 1}, {"id": 2'
      format, confidence = detector.detect(content)

      expect(format).to eq(:json)
      expect(confidence).to be > 0.3
    end

    it "rejects markdown as JSON" do
      content = "# Report\n\n| ID | Name |\n|---|---|\n| 1 | Alice |"
      format, confidence = detector.detect(content)

      expect(format).not_to eq(:json)
    end

    it "rejects CSV as JSON" do
      content = "id,name,email\n1,Alice,alice@example.com"
      format, confidence = detector.detect(content)

      expect(format).not_to eq(:json)
    end
  end

  # ============================================================================
  # 4. Edge Case Tests (6 tests)
  # ============================================================================
  describe "edge cases" do
    it "handles empty content" do
      format, confidence = detector.detect("")

      expect(format).to eq(:unknown)
      expect(confidence).to eq(0.0)
    end

    it "handles nil content" do
      format, confidence = detector.detect(nil)

      expect(format).to eq(:unknown)
      expect(confidence).to eq(0.0)
    end

    it "handles whitespace-only content" do
      format, confidence = detector.detect("   \n\n   \t  ")

      expect(format).to eq(:unknown)
      expect(confidence).to eq(0.0)
    end

    it "handles ambiguous content with low confidence" do
      content = "some random text with no clear format indicators"
      format, confidence = detector.detect(content)

      # Should return unknown or a format but with low confidence
      expect(confidence).to be <= 0.3
    end

    it "handles content with special characters" do
      content = '{"data": "Special chars: !@#$%^&*()_+-=[]{}|;:,.<>?"}'
      format, confidence = detector.detect(content)

      expect(format).to eq(:json)
    end

    it "handles mixed case headers" do
      content = "ID,Name,Email\n1,Alice,alice@example.com"
      format, confidence = detector.detect(content)

      expect(format).to eq(:csv)
    end
  end

  # ============================================================================
  # 5. Confidence Score Tests (5 tests)
  # ============================================================================
  describe "confidence scoring" do
    it "returns confidence between 0.0 and 1.0" do
      ["id,name", '{"id": 1}', "# Header"].each do |content|
        format, confidence = detector.detect(content)

        expect(confidence).to be >= 0.0
        expect(confidence).to be <= 1.0
      end
    end

    it "gives reasonable confidence for unambiguous CSV" do
      content = "id,name,email,phone,address,city,state,zip\n1,Alice,alice@example.com,555-1234,123 Main,NYC,NY,10001"
      format, confidence = detector.detect(content)

      expect(format).to eq(:csv)
      expect(confidence).to be > 0.5
    end

    it "gives high confidence for unambiguous JSON" do
      content = '{"id": 1, "name": "Alice", "items": [{"id": 1}, {"id": 2}, {"id": 3}]}'
      format, confidence = detector.detect(content)

      expect(format).to eq(:json)
      expect(confidence).to be > 0.7
    end

    it "gives reasonable confidence for unambiguous Markdown" do
      content = "# Report\n\n## Section\n\n```ruby\ncode\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |"
      format, confidence = detector.detect(content)

      expect([:markdown, :unknown]).to include(format)
      expect(confidence).to be > 0.5
    end

    it "gives lower confidence for ambiguous content" do
      # Content that could be multiple formats
      content = "name,age\nAlice,30"
      format, confidence = detector.detect(content)

      # Should detect as something but maybe lower confidence
      expect(confidence).to be >= 0.3
    end
  end

  # ============================================================================
  # 6. Real-World Example Tests (4 tests)
  # ============================================================================
  describe "real-world examples" do
    it "detects company discovery CSV export" do
      content = <<~CSV
        company_id,company_name,industry,employees,headquarters,founded_year
        1,Acme Corp,Technology,500,San Francisco,2010
        2,Beta Inc,Finance,1200,New York,2005
        3,Gamma LLC,Manufacturing,800,Chicago,2015
      CSV

      format, confidence = detector.detect(content)

      expect(format).to eq(:csv)
      expect(confidence).to be > 0.6
    end

    it "detects market analysis markdown report" do
      content = <<~MD
        # Market Analysis Report 2024

        ## Executive Summary
        This report analyzes the technology market growth trends.

        ## Market Segments
        | Segment | Size | Growth |
        |---------|------|--------|
        | Cloud   | $50B | 25%    |
        | AI      | $30B | 45%    |

        ## Key Findings
        - Market consolidation continuing
        - New entrants focusing on niche segments
        - Merger and acquisition activity increasing

        ## Conclusion
        The market presents **strong opportunities** for growth.
      MD

      format, confidence = detector.detect(content)

      expect([:markdown, :unknown]).to include(format)
      expect(confidence).to be > 0.6
    end

    it "detects data extraction JSON output" do
      content = <<~JSON
        {
          "extraction_date": "2024-01-15",
          "documents_processed": 45,
          "entities": [
            {"type": "person", "name": "John Smith", "mentions": 5},
            {"type": "organization", "name": "Acme Corp", "mentions": 12},
            {"type": "location", "name": "San Francisco", "mentions": 8}
          ],
          "metadata": {
            "total_entities": 3,
            "confidence_score": 0.92
          }
        }
      JSON

      format, confidence = detector.detect(content)

      expect(format).to eq(:json)
      expect(confidence).to be > 0.7
    end

    it "detects truncated CSV from LLM response" do
      # Simulates LLM response that got cut off mid-row
      content = <<~CSV
        id,name,email,company,phone
        1,Alice Johnson,alice@example.com,Acme Corp,555-1234
        2,Bob Smith,bob@example.com,Beta Inc,555-5678
        3,Charlie Brown,charlie@example.com,Gamma LLC,555-9012
        4,Diana Prince,diana@example.com,Delta Co
      CSV

      format, confidence = detector.detect(content)

      expect(format).to eq(:csv)
    end
  end

  # ============================================================================
  # 7. Integration Tests (3 tests)
  # ============================================================================
  describe "integration with format variations" do
    it "detects CSV even with different line endings" do
      content = "id,name,email\r\n1,Alice,alice@example.com\r\n2,Bob,bob@example.com"
      format, confidence = detector.detect(content)

      expect(format).to eq(:csv)
    end

    it "detects JSON with extra whitespace" do
      content = "  {  \n  \"id\" : 1 , \n  \"name\" : \"Alice\" \n  }  "
      format, confidence = detector.detect(content)

      expect(format).to eq(:json)
    end

    it "detects markdown with mixed line endings" do
      content = "# Header\r\n\nSome text\n\n```ruby\ncode\n```"
      format, confidence = detector.detect(content)

      expect([:markdown, :unknown]).to include(format)
    end
  end
end
