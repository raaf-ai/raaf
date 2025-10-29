# Markdown Merger Specification

> Part of: Automatic Continuation Support
> Component: Markdown Format Merger
> Success Target: 85-95% accuracy

## Overview

The Markdown merger handles continuation of markdown documents by detecting incomplete table structures, preserving formatting, and intelligently merging sections while maintaining document coherence.

## Markdown-Specific Challenges

1. **Incomplete Tables**: Tables may be split mid-row when token limit is reached
2. **Table Header Duplication**: Continuation may incorrectly repeat table headers
3. **List Numbering**: Numbered lists must maintain sequential numbering across chunks
4. **Code Block Integrity**: Code blocks must not be split or corrupted
5. **Section Boundaries**: Headers and sections must align properly across chunks

## Implementation

### MarkdownMerger Class

```ruby
module RAAF
  module Continuation
    module Mergers
      class MarkdownMerger < BaseMerger
        def merge(chunks)
          merged_content = ""
          in_table = false
          in_code_block = false
          truncation_points = []

          chunks.each_with_index do |chunk, index|
            content = extract_content(chunk)

            if index == 0
              merged_content = content
              in_table = contains_incomplete_table?(content)
              in_code_block = contains_incomplete_code_block?(content)
              truncation_points << detect_truncation_point(content) if chunk["finish_reason"] == "length"
            else
              Rails.logger.debug(
                "[RAAF Markdown Merger] Processing chunk #{index + 1}",
                in_table: in_table,
                in_code_block: in_code_block
              )

              # Handle table continuation
              if in_table
                content = remove_duplicate_table_header(content, merged_content)
              end

              # Handle code block continuation
              if in_code_block
                content = continue_code_block(content)
              end

              # Smart concatenation
              merged_content = smart_concat(merged_content, content)
              in_table = contains_incomplete_table?(merged_content)
              in_code_block = contains_incomplete_code_block?(merged_content)

              truncation_points << detect_truncation_point(merged_content) if chunk["finish_reason"] == "length"
            end
          end

          {
            success: true,
            content: merged_content,
            _continuation_metadata: build_metadata(
              chunks,
              merge_success: true,
              truncation_points: truncation_points
            )
          }
        rescue StandardError => e
          Rails.logger.error(
            "[RAAF Markdown Merger] Merge failed: #{e.message}",
            error_class: e.class.name,
            chunks: chunks.length
          )

          raise
        end

        private

        def contains_incomplete_table?(content)
          lines = content.split("\n")

          # Find last line that could be part of a table
          last_table_line_index = lines.rindex { |l| l.strip.start_with?("|") }
          return false unless last_table_line_index

          # Find the table header (line with |---|---|)
          table_start_index = lines.rindex { |l| l.strip.match?(/^\|[\s\-:]+\|$/) }
          return false unless table_start_index

          # Get expected column count from header
          header_line = lines[table_start_index - 1]
          expected_columns = header_line.count("|") - 1

          # Check last table row for completeness
          last_row = lines[last_table_line_index]
          actual_columns = last_row.count("|") - 1

          # Incomplete if column count doesn't match or row doesn't end with |
          (actual_columns < expected_columns) || !last_row.strip.end_with?("|")
        end

        def contains_incomplete_code_block?(content)
          # Count opening and closing code block markers
          opening_markers = content.scan(/^```/).count
          closing_markers = content.scan(/^```$/).count

          # Incomplete if odd number of markers or opening > closing
          (opening_markers - closing_markers).odd? || (opening_markers > closing_markers)
        end

        def remove_duplicate_table_header(content, existing_content)
          lines = content.split("\n")

          # Extract table header from existing content
          existing_lines = existing_content.split("\n")
          existing_header = existing_lines.reverse.find { |l| l.strip.start_with?("|") && !l.include?("---") }
          return content unless existing_header

          # Check if continuation starts with duplicate header
          if lines[0..1].any? { |l| l.strip == existing_header.strip }
            Rails.logger.debug(
              "[RAAF Markdown Merger] Removing duplicate table header",
              header: existing_header.slice(0, 50)
            )

            # Remove header and separator line
            lines = lines.drop(2)
          end

          lines.join("\n")
        end

        def continue_code_block(content)
          # Don't add opening ``` if continuing an incomplete code block
          lines = content.split("\n")

          if lines.first&.strip&.start_with?("```")
            lines.shift
          end

          lines.join("\n")
        end

        def smart_concat(base, continuation)
          # Add appropriate spacing based on context
          base_ends_with_newline = base.end_with?("\n")
          continuation_starts_with_newline = continuation.start_with?("\n")

          case
          when base_ends_with_newline && continuation_starts_with_newline
            # Both have newlines, merge directly
            base + continuation
          when !base_ends_with_newline && !continuation_starts_with_newline
            # Neither has newline, add single newline
            base + "\n" + continuation
          else
            # One has newline, merge directly
            base + continuation
          end
        end

        def detect_truncation_point(content)
          lines = content.split("\n")
          last_line = lines.last

          case
          when last_line&.strip&.start_with?("|")
            "table_row:#{lines.count { |l| l.strip.start_with?("|") }}"
          when last_line&.strip&.start_with?("```")
            "code_block:#{content.scan(/^```/).count}"
          when last_line&.strip&.match?(/^\d+\./)
            "list_item:#{last_line[/^\d+/]}"
          when last_line&.strip&.match?(/^#+/)
            "header:#{last_line.strip}"
          else
            "line:#{lines.length}"
          end
        end

        def build_metadata(chunks, merge_success:, truncation_points:)
          super(chunks, merge_success: merge_success).merge(
            truncation_points: truncation_points
          )
        end
      end
    end
  end
end
```

## Markdown-Specific Edge Cases

### Case 1: Split Table Mid-Row

**Input Chunk 1 (truncated):**
```markdown
# Company Analysis

| Name | City | Employees |
|------|------|-----------|
| Company A | Boston | 100 |
| Company B | Seattle |
```

**Input Chunk 2 (continuation):**
```markdown
 200 |
| Company C | Portland | 150 |
```

**Expected Output:**
```markdown
# Company Analysis

| Name | City | Employees |
|------|------|-----------|
| Company A | Boston | 100 |
| Company B | Seattle | 200 |
| Company C | Portland | 150 |
```

### Case 2: Duplicate Table Header

**Input Chunk 1:**
```markdown
| Name | City |
|------|------|
| Company A | Boston |
```

**Input Chunk 2 (incorrectly includes header):**
```markdown
| Name | City |
|------|------|
| Company B | Seattle |
| Company C | Portland |
```

**Expected Output:**
```markdown
| Name | City |
|------|------|
| Company A | Boston |
| Company B | Seattle |
| Company C | Portland |
```

### Case 3: Incomplete Code Block

**Input Chunk 1 (truncated):**
```markdown
# Code Example

```ruby
class Company
  def initialize(name)
    @name = name
```

**Input Chunk 2 (continuation):**
```markdown
  end

  def display
    puts @name
  end
end
```
```

**Expected Output:**
```markdown
# Code Example

```ruby
class Company
  def initialize(name)
    @name = name
  end

  def display
    puts @name
  end
end
```
```

### Case 4: List Numbering Continuation

**Input Chunk 1:**
```markdown
Top Companies:

1. Company A - Leading tech firm
2. Company B - Growing startup
```

**Input Chunk 2:**
```markdown
3. Company C - Enterprise solution
4. Company D - Innovation leader
```

**Expected Output:**
```markdown
Top Companies:

1. Company A - Leading tech firm
2. Company B - Growing startup
3. Company C - Enterprise solution
4. Company D - Innovation leader
```

## Markdown Continuation Prompt

Specific prompt for Markdown continuation with formatting context:

```ruby
def build_markdown_continuation_prompt(last_chunk)
  content = extract_content(last_chunk)
  last_lines = content.split("\n").last(5).join("\n")

  {
    role: "user",
    content: <<~PROMPT
      Continue from where you left off. The last few lines were:

      #{last_lines}

      Continue maintaining the same formatting and structure.
      If you were in a table, continue the table without repeating headers.
      If you were in a code block, continue the code.
      If you were in a numbered list, continue the numbering.

      Output ONLY the continuation content, no preamble or explanations.
    PROMPT
  }
end
```

## Testing Strategy

### Unit Tests

```ruby
describe RAAF::Continuation::Mergers::MarkdownMerger do
  let(:merger) { described_class.new }

  describe "#contains_incomplete_table?" do
    it "detects incomplete table rows" do
      content = "| Name | City |\n|------|------|\n| Company | Bos"
      expect(merger.send(:contains_incomplete_table?, content)).to be true
    end

    it "returns false for complete tables" do
      content = "| Name | City |\n|------|------|\n| Company | Boston |"
      expect(merger.send(:contains_incomplete_table?, content)).to be false
    end
  end

  describe "#contains_incomplete_code_block?" do
    it "detects unclosed code blocks" do
      content = "```ruby\nclass Test\n"
      expect(merger.send(:contains_incomplete_code_block?, content)).to be true
    end

    it "returns false for complete code blocks" do
      content = "```ruby\nclass Test\nend\n```"
      expect(merger.send(:contains_incomplete_code_block?, content)).to be false
    end
  end

  describe "#merge" do
    it "completes split table rows" do
      chunk1 = build_chunk("| A | B |\n|---|---|\n| 1 | ")
      chunk2 = build_chunk("2 |\n| 3 | 4 |")

      result = merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("| 1 | 2 |")
      expect(result[:content]).to include("| 3 | 4 |")
    end

    it "removes duplicate headers" do
      chunk1 = build_chunk("| A | B |\n|---|---|\n| 1 | 2 |")
      chunk2 = build_chunk("| A | B |\n|---|---|\n| 3 | 4 |")

      result = merger.merge([chunk1, chunk2])

      expect(result[:content].scan(/\| A \| B \|/).length).to eq(1)
    end

    it "preserves code block integrity" do
      chunk1 = build_chunk("```ruby\ncode1")
      chunk2 = build_chunk("code2\n```")

      result = merger.merge([chunk1, chunk2])

      expect(result[:content]).to match(/```ruby\ncode1code2\n```/)
    end
  end
end
```

### Integration Tests

```ruby
describe "Markdown Continuation Integration" do
  it "handles large reports with tables" do
    agent = create_markdown_agent(expected_rows: 100)

    result = agent.run("Generate market analysis report with 100-row comparison table")

    expect(result[:_continuation_metadata][:was_continued]).to be true

    # Verify table integrity
    table_rows = result[:content].scan(/^\|.*\|$/).length
    expect(table_rows).to be >= 100
  end

  it "maintains document structure across continuations" do
    agent = create_markdown_agent(expected_sections: 10)

    result = agent.run("Create comprehensive company profile with 10 sections")

    content = result[:content]

    # Verify headers are properly formatted
    headers = content.scan(/^#+\s+.+$/)
    expect(headers.length).to be >= 10

    # Verify no duplicate sections
    expect(headers.uniq.length).to eq(headers.length)
  end
end
```

## Success Metrics

- **Target Success Rate**: 85-95%
- **Table Completion**: 90%+ of split tables properly completed
- **Header Deduplication**: 95%+ of duplicate headers removed
- **Code Block Integrity**: 85%+ of code blocks properly closed
- **Performance**: < 30ms merge time for 50KB document
- **Memory**: < 5MB additional memory for typical report

## Known Limitations

1. **Complex Nested Tables**: Tables within tables may not merge correctly
2. **Custom Markdown Extensions**: Only supports standard CommonMark/GitHub-flavored markdown
3. **Inline HTML**: HTML blocks may not be properly handled at chunk boundaries
4. **LaTeX/Math Blocks**: Mathematical notation blocks may be disrupted
5. **Deeply Nested Lists**: Lists with more than 4 levels of nesting may have formatting issues

## Success Rate by Content Type

- **Tables Only**: 95%+ success rate
- **Code Blocks**: 90%+ success rate
- **Mixed Content (tables + code + text)**: 85-90% success rate
- **Complex Formatting (nested lists, HTML)**: 70-80% success rate

## Future Enhancements

- Support for custom markdown extensions (e.g., footnotes, definition lists)
- Better handling of inline HTML at chunk boundaries
- LaTeX/math block preservation
- Table of contents regeneration after merge
- Anchor link validation across chunks
- Image reference integrity checking
