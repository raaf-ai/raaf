# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::Continuation::Mergers::MarkdownMerger" do
  # Test Markdown Merger implementation
  # This class handles merging markdown chunks from continuation responses
  # with intelligent detection of incomplete tables, lists, and code blocks

  let(:config) { RAAF::Continuation::Config.new }
  let(:markdown_merger) { RAAF::Continuation::Mergers::MarkdownMerger.new(config) }

  # ============================================================================
  # 1. Table Continuation Tests (8 tests)
  # ============================================================================
  describe "table continuation" do
    it "merges markdown tables across two chunks" do
      chunk1 = {
        content: "| ID | Name | Status |\n|---|---|---|\n| 1 | Alice | Active |\n| 2 | Bob | Inactive |"
      }
      chunk2 = {
        content: "\n| 3 | Charlie | Active |\n| 4 | Diana | Active |"
      }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("| 1 | Alice | Active |")
      expect(result[:content]).to include("| 2 | Bob | Inactive |")
      expect(result[:content]).to include("| 3 | Charlie | Active |")
      expect(result[:content]).to include("| 4 | Diana | Active |")
    end

    it "detects incomplete table rows" do
      content = "| ID | Name | Status |\n|---|---|---|\n| 1 | Alice | Active |\n| 2 | Bob |"
      expect(markdown_merger.send(:has_incomplete_table_row?, content)).to be true
    end

    it "preserves table headers across chunks" do
      chunk1 = { content: "| Product | Price | Stock |\n|---|---|---|\n| Widget | $9.99 | 100 |" }
      chunk2 = { content: "\n| Gadget | $19.99 | 50 |" }

      result = markdown_merger.merge([chunk1, chunk2])

      # Count header occurrences
      header_count = result[:content].scan(/\| Product \| Price \| Stock \|/).count
      expect(header_count).to eq(1)
    end

    it "handles column alignment across continuations" do
      chunk1 = { content: "| Left | Center | Right |\n|:---|:---:|---:|\n| A | B | C |" }
      chunk2 = { content: "\n| D | E | F |" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("| Left | Center | Right |")
      expect(result[:content]).to include(":---|:---:|---:")
      expect(result[:content]).to include("| A | B | C |")
      expect(result[:content]).to include("| D | E | F |")
    end

    it "merges large tables (50+ rows)" do
      header = "| ID | Name | Email | Status |\n|---|---|---|---|\n"
      rows_chunk1 = (1..25).map { |i| "| #{i} | User#{i} | user#{i}@example.com | Active |" }.join("\n")
      rows_chunk2 = (26..50).map { |i| "| #{i} | User#{i} | user#{i}@example.com | Active |" }.join("\n")

      chunk1 = { content: "#{header}#{rows_chunk1}" }
      chunk2 = { content: "\n#{rows_chunk2}" }

      result = markdown_merger.merge([chunk1, chunk2])

      row_count = result[:content].scan(/^\|\s*\d+\s*\|/).count
      expect(row_count).to eq(50)
    end

    it "handles tables with complex cell content" do
      chunk1 = {
        content: "| Description | Value |\n|---|---|\n| Code block | `function() {}` |\n| Link | [Ruby](https://ruby-lang.org) |"
      }
      chunk2 = {
        content: "\n| Bold text | **Important** |\n| Italic | *Emphasized* |"
      }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("`function() {}`")
      expect(result[:content]).to include("[Ruby](https://ruby-lang.org)")
      expect(result[:content]).to include("**Important**")
      expect(result[:content]).to include("*Emphasized*")
    end

    it "detects split rows at chunk boundary" do
      content = "| ID | Name | Email |\n|---|---|---|\n| 1 | Alice | alice@example.com |\n| 2 | Bob | bob@"
      expect(markdown_merger.send(:has_incomplete_table_row?, content)).to be true
    end

    it "validates complete table structures" do
      complete_table = "| ID | Name |\n|---|---|\n| 1 | Alice |\n| 2 | Bob |\n"
      expect(markdown_merger.send(:has_incomplete_table_row?, complete_table)).to be false
    end
  end

  # ============================================================================
  # 2. List Continuation Tests (6 tests)
  # ============================================================================
  describe "list continuation" do
    it "continues numbered lists with correct numbering" do
      chunk1 = { content: "1. First item\n2. Second item\n3. Third item" }
      chunk2 = { content: "\n4. Fourth item\n5. Fifth item" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("1. First item")
      expect(result[:content]).to include("4. Fourth item")
      expect(result[:content]).to include("5. Fifth item")
    end

    it "handles nested lists" do
      chunk1 = { content: "- Item 1\n  - Sub-item 1a\n  - Sub-item 1b\n- Item 2" }
      chunk2 = { content: "\n  - Sub-item 2a\n- Item 3" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("- Item 1")
      expect(result[:content]).to include("  - Sub-item 1a")
      expect(result[:content]).to include("  - Sub-item 2a")
      expect(result[:content]).to include("- Item 3")
    end

    it "preserves bullet list formatting" do
      chunk1 = { content: "- First\n- Second\n- Third" }
      chunk2 = { content: "\n- Fourth\n- Fifth" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("- First")
      expect(result[:content]).to include("- Fourth")
    end

    it "handles mixed list types (bullets and numbers)" do
      chunk1 = { content: "1. Numbered item 1\n- Bullet item 1\n2. Numbered item 2" }
      chunk2 = { content: "\n- Bullet item 2\n3. Numbered item 3" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content]).to include("1. Numbered item 1")
      expect(result[:content]).to include("- Bullet item 1")
      expect(result[:content]).to include("3. Numbered item 3")
    end

    it "continues long lists (30+ items)" do
      items_chunk1 = (1..15).map { |i| "#{i}. Item #{i}" }.join("\n")
      items_chunk2 = (16..30).map { |i| "#{i}. Item #{i}" }.join("\n")

      chunk1 = { content: items_chunk1 }
      chunk2 = { content: "\n#{items_chunk2}" }

      result = markdown_merger.merge([chunk1, chunk2])

      item_count = result[:content].scan(/^\d+\. Item/).count
      expect(item_count).to eq(30)
    end

    it "handles list items with multiple paragraphs" do
      chunk1 = { content: "- Item 1\n  Paragraph continuation\n  More text\n- Item 2" }
      chunk2 = { content: "\n  Additional info\n- Item 3" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content]).to include("- Item 1")
      expect(result[:content]).to include("Paragraph continuation")
      expect(result[:content]).to include("- Item 3")
    end
  end

  # ============================================================================
  # 3. Code Block Handling Tests (6 tests)
  # ============================================================================
  describe "code block handling" do
    it "preserves complete code blocks" do
      code1 = "```ruby\ndef hello\n  puts 'world'\nend\n```"
      code2 = "```python\nprint('hello')\n```"

      chunk1 = { content: code1 }
      chunk2 = { content: "\n\n#{code2}" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("def hello")
      expect(result[:content]).to include("print('hello')")
    end

    it "detects incomplete code blocks" do
      incomplete = "```ruby\ndef incomplete\n  puts 'oops"
      expect(markdown_merger.send(:has_incomplete_code_block?, incomplete)).to be true
    end

    it "merges split code blocks" do
      chunk1 = { content: "```javascript\nfunction hello() {\n  console.log(" }
      chunk2 = { content: "'world');\n}\n```" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content]).to include("function hello()")
      expect(result[:content]).to include("console.log")
    end

    it "preserves language syntax highlighting" do
      chunk1 = { content: "```sql\nSELECT id, name FROM users WHERE active" }
      chunk2 = { content: " = true\n```" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("```sql")
      expect(result[:content]).to include("SELECT id, name FROM users")
    end

    it "handles inline code mixed with code blocks" do
      chunk1 = { content: "Use `inline_code()` like this:\n```\nblock code\n```" }
      chunk2 = { content: "\nMore `inline` text" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("`inline_code()`")
      expect(result[:content]).to include("```")
      expect(result[:content]).to include("block code")
    end

    it "handles code blocks with leading spaces (indented)" do
      chunk1 = { content: "    indented code\n    line 2" }
      chunk2 = { content: "\n    line 3" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content]).to include("indented code")
    end
  end

  # ============================================================================
  # 4. Header Deduplication Tests (5 tests)
  # ============================================================================
  describe "header deduplication" do
    it "removes duplicate top-level headers" do
      chunk1 = { content: "# Main Title\n\nContent here" }
      chunk2 = { content: "# Main Title\n\nMore content" }

      result = markdown_merger.merge([chunk1, chunk2])

      header_count = result[:content].scan(/^# Main Title$/).count
      expect(header_count).to eq(1)
    end

    it "preserves different header levels" do
      chunk1 = { content: "# Title\n## Subtitle\n### Sub-subtitle" }
      chunk2 = { content: "## Another Section\n### Details" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("# Title")
      expect(result[:content]).to include("## Subtitle")
      expect(result[:content]).to include("## Another Section")
    end

    it "handles headers with special characters" do
      chunk1 = { content: "# Title: Main Heading\n\nContent" }
      chunk2 = { content: "# Title: Main Heading\n\nMore content" }

      result = markdown_merger.merge([chunk1, chunk2])

      header_count = result[:content].scan(/^# Title: Main Heading$/).count
      expect(header_count).to eq(1)
    end

    it "deduplicates section headers across chunks" do
      chunk1 = { content: "## Results\n\nData 1\nData 2" }
      chunk2 = { content: "\n## Results\n\nData 3" }

      result = markdown_merger.merge([chunk1, chunk2])

      result_header_count = result[:content].scan(/^## Results$/).count
      expect(result_header_count).to eq(1)
    end

    it "preserves headers with inline formatting" do
      chunk1 = { content: "# **Bold** Title\n\nContent" }
      chunk2 = { content: "# **Bold** Title\n\nMore" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("# **Bold** Title")
    end
  end

  # ============================================================================
  # 5. Mixed Content Tests (8 tests)
  # ============================================================================
  describe "mixed content" do
    it "merges document with tables, lists, and paragraphs" do
      chunk1 = {
        content: "# Report\n\n## Summary\n- Point 1\n- Point 2\n\n| Key | Value |\n|---|---|\n| A | 1 |"
      }
      chunk2 = {
        content: "\n| B | 2 |\n\n## Details\n\nParagraph text here."
      }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("# Report")
      expect(result[:content]).to include("- Point 1")
      expect(result[:content]).to include("| Key | Value |")
      expect(result[:content]).to include("| B | 2 |")
      expect(result[:content]).to include("Paragraph text here")
    end

    it "preserves formatting in mixed content" do
      chunk1 = {
        content: "**Bold text** and *italic text*\n\n> Blockquote\n\n- List item"
      }
      chunk2 = {
        content: "\n- Another item\n\nFinal paragraph"
      }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("**Bold text**")
      expect(result[:content]).to include("*italic text*")
      expect(result[:content]).to include("> Blockquote")
      expect(result[:content]).to include("- Another item")
    end

    it "handles complex document structure" do
      chunk1 = {
        content: "# Title\n\n## Section 1\n\nText\n\n| Col1 | Col2 |\n|---|---|\n| A | B |"
      }
      chunk2 = {
        content: "\n\n## Section 2\n\n1. Item 1\n2. Item 2"
      }
      chunk3 = {
        content: "\n\n```ruby\ncode\n```\n\nConclusion"
      }

      result = markdown_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:content]).to include("# Title")
      expect(result[:content]).to include("## Section 1")
      expect(result[:content]).to include("## Section 2")
      expect(result[:content]).to include("| Col1 | Col2 |")
      expect(result[:content]).to include("1. Item 1")
      expect(result[:content]).to include("```ruby")
    end

    it "handles links and references in mixed content" do
      chunk1 = {
        content: "# Documentation\n\nCheck [this link](https://example.com)\n\n| Reference | URL |\n|---|---|\n| Google | https://google.com |"
      }
      chunk2 = {
        content: "\n| Ruby | https://ruby-lang.org |\n\nFor more info, see [docs](https://docs.example.com)"
      }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("[this link](https://example.com)")
      expect(result[:content]).to include("| Ruby | https://ruby-lang.org |")
      expect(result[:content]).to include("[docs](https://docs.example.com)")
    end

    it "preserves nested structures across boundaries" do
      chunk1 = {
        content: "- Item 1\n  - Sub 1a\n  - Sub 1b\n  \n  Nested paragraph"
      }
      chunk2 = {
        content: "\n\n- Item 2\n  - Sub 2a"
      }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("- Item 1")
      expect(result[:content]).to include("  - Sub 1a")
      expect(result[:content]).to include("  - Sub 2a")
      expect(result[:content]).to include("- Item 2")
    end

    it "handles horizontal rules in mixed content" do
      chunk1 = {
        content: "## Section 1\n\nContent\n\n---\n\n## Section 2"
      }
      chunk2 = {
        content: "\n\nMore content\n\n---\n\nFinal section"
      }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      horizontal_rule_count = result[:content].scan(/^---$/).count
      expect(horizontal_rule_count).to be >= 1
    end

    it "preserves blockquotes with complex content" do
      chunk1 = {
        content: "> This is a blockquote\n> with multiple lines\n> and **formatting**"
      }
      chunk2 = {
        content: "\n> More blockquote content\n\nRegular paragraph"
      }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("> This is a blockquote")
      expect(result[:content]).to include("> More blockquote content")
      expect(result[:content]).to include("**formatting**")
    end
  end

  # ============================================================================
  # 6. Edge Cases Tests (5 tests)
  # ============================================================================
  describe "edge cases" do
    it "handles unicode and special characters" do
      chunk1 = { content: "# 日本語 Title\n\n| Name | City |\n|---|---|\n| José | São Paulo |" }
      chunk2 = { content: "\n| Müller | München |\n\n中文 text" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("日本語")
      expect(result[:content]).to include("José")
      expect(result[:content]).to include("Müller")
      expect(result[:content]).to include("中文")
    end

    it "handles very large tables (100+ rows)" do
      header = "| ID | Name | Email | Status |\n|---|---|---|---|\n"
      rows = (1..100).map { |i| "| #{i} | User#{i} | user#{i}@example.com | Active |" }.join("\n")

      chunk1 = { content: "#{header}#{rows[0..2000]}" }
      chunk2 = { content: "#{rows[2001..-1]}" }

      result = markdown_merger.merge([chunk1, chunk2])

      row_count = result[:content].scan(/^\|\s*\d+\s*\|/).count
      expect(row_count).to eq(100)
      expect(result[:metadata][:merge_success]).to be true
    end

    it "handles escaped characters in markdown" do
      chunk1 = { content: "Text with \\* escaped \\[ characters" }
      chunk2 = { content: " and \\_ more" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content]).to include("\\*")
      expect(result[:content]).to include("\\[")
    end

    it "handles empty chunks and whitespace-only chunks" do
      chunk1 = { content: "# Title\n\nContent" }
      chunk2 = { content: "" }
      chunk3 = { content: "   \n  \n" }
      chunk4 = { content: "\nMore content" }

      result = markdown_merger.merge([chunk1, chunk2, chunk3, chunk4])

      expect(result[:content]).to include("# Title")
      expect(result[:content]).to include("Content")
      expect(result[:content]).to include("More content")
    end

    it "handles extremely long single lines" do
      long_line = "A" * 10_000
      chunk1 = { content: "# Title\n\n#{long_line}" }
      chunk2 = { content: "\n\nMore text" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content].length).to be > 10_000
    end
  end

  # ============================================================================
  # 7. Metadata Tests (4 tests)
  # ============================================================================
  describe "metadata structure" do
    it "builds correct metadata for successful merge" do
      chunk1 = { content: "# Title\n\nContent" }
      chunk2 = { content: "\n\nMore content" }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:metadata]).to be_a(Hash)
      expect(result[:metadata][:merge_success]).to be true
      expect(result[:metadata][:chunk_count]).to eq(2)
      expect(result[:metadata][:timestamp]).to be_a(String)
    end

    it "includes merge_success flag" do
      chunk = { content: "# Title\n\nContent" }
      result = markdown_merger.merge([chunk])

      expect(result[:metadata]).to have_key(:merge_success)
      expect([true, false]).to include(result[:metadata][:merge_success])
    end

    it "includes chunk_count in metadata" do
      chunks = (1..5).map { |i| { content: "# Part #{i}\n\nContent #{i}" } }
      result = markdown_merger.merge(chunks)

      expect(result[:metadata][:chunk_count]).to eq(5)
    end

    it "includes timestamp in metadata" do
      chunk = { content: "# Title\n\nContent" }
      result = markdown_merger.merge([chunk])

      expect(result[:metadata][:timestamp]).to be_a(String)
      expect(result[:metadata][:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end
  end

  # ============================================================================
  # 8. Integration Tests (7 tests)
  # ============================================================================
  describe "markdown merger integration" do
    it "merges real-world markdown report" do
      chunk1 = {
        content: "# Quarterly Report\n\n## Executive Summary\n\n- Revenue increased 25%\n- Customer satisfaction at 95%\n\n## Financial Results\n\n| Quarter | Revenue | Growth |\n|---|---|---|\n| Q1 | $1M | 10% |\n| Q2 | $1.25M | 25% |"
      }
      chunk2 = {
        content: "\n| Q3 | $1.56M | 25% |\n\n## Technical Achievements\n\n```\nDeployed 15 features\n```\n\nConclusion: Successful quarter."
      }

      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("# Quarterly Report")
      expect(result[:content]).to include("Revenue increased 25%")
      expect(result[:content]).to include("| Q3 | $1.56M | 25% |")
      expect(result[:content]).to include("Deployed 15 features")
      expect(result[:metadata][:merge_success]).to be true
    end

    it "handles markdown with multiple incomplete structures" do
      chunk1 = {
        content: "# Title\n\n## Incomplete Table\n\n| Col1 | Col2 |\n|---|---|\n| A | B |\n| C |"
      }
      chunk2 = {
        content: " D |\n\n## Incomplete Code\n\n```ruby\ndef method"
      }
      chunk3 = {
        content: "\nend\n```"
      }

      result = markdown_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content]).to include("| A | B |")
      expect(result[:content]).to include("def method")
    end

    it "preserves markdown structure across multiple chunks" do
      parts = (1..5).map do |i|
        "## Section #{i}\n\nContent #{i}\n\n- Item 1\n- Item 2"
      end

      chunks = parts.each_with_index.map do |content, idx|
        { content: content }
      end

      result = markdown_merger.merge(chunks)

      (1..5).each do |i|
        expect(result[:content]).to include("## Section #{i}")
        expect(result[:content]).to include("Content #{i}")
      end
    end

    it "handles chunks with mixed ending styles" do
      chunk1 = { content: "# Title\n\nContent" }
      chunk2 = { content: "\n## Section" }
      chunk3 = { content: "\n\nMore content\n" }

      result = markdown_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:content]).to include("# Title")
      expect(result[:content]).to include("## Section")
      expect(result[:content]).to include("More content")
    end

    it "validates proper merging with data integrity" do
      # Create markdown with specific data patterns
      data = (1..10).map do |i|
        "| #{i} | Row #{i} | Status Active |"
      end.join("\n")

      chunk1 = { content: "| ID | Description | Status |\n|---|---|---|\n#{data[0..200]}" }
      chunk2 = { content: "#{data[201..-1]}" }

      result = markdown_merger.merge([chunk1, chunk2])

      # Verify all rows present
      row_count = result[:content].scan(/^\|\s*\d+\s*\|/).count
      expect(row_count).to eq(10)
      expect(result[:metadata][:merge_success]).to be true
    end

    it "extracts content from hash chunks with various keys" do
      chunk1 = { "content" => "# Title\n\nContent" }
      chunk2 = { content: "## Section\n\nMore" }
      chunk3 = { message: { content: "Final content" } }

      result = markdown_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:content]).to include("# Title")
      expect(result[:content]).to include("## Section")
      expect(result[:content]).to include("Final content")
    end

    it "handles merge with nil and empty content in chunks" do
      chunk1 = { content: "# Title\n\nContent" }
      chunk2 = nil
      chunk3 = { content: "" }
      chunk4 = { content: "\n\n## Section\n\nMore" }

      result = markdown_merger.merge([chunk1, chunk2, chunk3, chunk4])

      expect(result[:content]).to include("# Title")
      expect(result[:content]).to include("## Section")
      expect(result[:metadata][:merge_success]).to be true
    end
  end
end
