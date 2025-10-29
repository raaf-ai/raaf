# CSV Merger Specification

> Part of: Automatic Continuation Support
> Component: CSV Format Merger
> Success Target: 95%+ accuracy

## Overview

The CSV merger handles continuation of CSV data by detecting incomplete rows at chunk boundaries, properly completing split rows, and maintaining data integrity across chunks.

## CSV-Specific Challenges

1. **Incomplete Rows**: Rows may be split mid-field when token limit is reached
2. **Quoted Fields**: Commas within quoted fields must not be treated as delimiters
3. **Multi-line Fields**: Fields containing newlines can span multiple lines
4. **Header Preservation**: Headers from first chunk must not be duplicated
5. **Column Alignment**: All rows must maintain consistent column count

## Implementation

### CSVMerger Class

```ruby
module RAAF
  module Continuation
    module Mergers
      class CSVMerger < BaseMerger
        require 'csv'

        def merge(chunks)
          merged_data = []
          truncation_points = []

          chunks.each_with_index do |chunk, index|
            content = extract_content(chunk)

            if index == 0
              # First chunk - use as-is
              merged_data = parse_csv_safely(content)
              truncation_points << "row:#{merged_data.length}" if chunk["finish_reason"] == "length"
            else
              # Continuation chunks
              lines = content.split("\n")

              # Check if first line completes previous incomplete row
              if incomplete_row?(merged_data.last)
                Rails.logger.debug(
                  "[RAAF CSV Merger] Completing incomplete row",
                  row_index: merged_data.length - 1,
                  partial_content: merged_data.last.slice(0, 50)
                )

                # Merge incomplete row with continuation
                completed_row = complete_row(merged_data.last, lines.shift)
                merged_data[-1] = completed_row
              end

              # Append remaining complete rows
              lines.each do |line|
                next if line.strip.empty?
                next if is_header_duplicate?(line, merged_data.first)

                if valid_csv_row?(line)
                  merged_data << parse_csv_row(line)
                end
              end

              truncation_points << "row:#{merged_data.length}" if chunk["finish_reason"] == "length"
            end
          end

          {
            success: true,
            data: format_as_csv(merged_data),
            _continuation_metadata: build_metadata(
              chunks,
              merge_success: true,
              record_count: merged_data.length,
              truncation_points: truncation_points
            )
          }
        rescue StandardError => e
          Rails.logger.error(
            "[RAAF CSV Merger] Merge failed: #{e.message}",
            error_class: e.class.name,
            chunks: chunks.length
          )

          raise
        end

        private

        def parse_csv_safely(content)
          CSV.parse(content, liberal_parsing: true)
        rescue CSV::MalformedCSVError => e
          Rails.logger.warn(
            "[RAAF CSV Merger] Malformed CSV, attempting line-by-line parse",
            error: e.message
          )

          # Fallback: parse line by line, skip malformed rows
          content.split("\n").filter_map do |line|
            begin
              CSV.parse_line(line, liberal_parsing: true)
            rescue CSV::MalformedCSVError
              nil
            end
          end
        end

        def incomplete_row?(row)
          return false if row.nil? || row.empty?

          # Count quotes to detect incomplete quoted fields
          quote_count = row.join('').count('"')
          has_odd_quotes = quote_count.odd?

          # Check for trailing comma (incomplete row)
          has_trailing_comma = row.last.to_s =~ /,\s*$/

          has_odd_quotes || has_trailing_comma
        end

        def complete_row(partial_row, continuation_line)
          # Merge the partial row's last field with continuation
          completed_last_field = partial_row.last.to_s + continuation_line

          # Parse the completed content
          completed_fields = CSV.parse_line(completed_last_field, liberal_parsing: true)

          # Combine with previous fields
          partial_row[0..-2] + completed_fields
        end

        def parse_csv_row(line)
          CSV.parse_line(line, liberal_parsing: true)
        rescue CSV::MalformedCSVError => e
          Rails.logger.debug(
            "[RAAF CSV Merger] Skipping malformed row",
            line: line.slice(0, 100),
            error: e.message
          )
          nil
        end

        def valid_csv_row?(line)
          return false if line.strip.empty?

          # Basic validation: contains delimiter
          line.include?(',')
        end

        def is_header_duplicate?(line, header_row)
          return false if header_row.nil?

          # Compare first few fields to detect duplicate headers
          parsed = parse_csv_row(line)
          return false if parsed.nil?

          parsed.take(3) == header_row.take(3)
        end

        def format_as_csv(data)
          CSV.generate do |csv|
            data.each do |row|
              csv << row
            end
          end
        end

        def build_metadata(chunks, merge_success:, record_count:, truncation_points:)
          super(chunks, merge_success: merge_success).merge(
            final_record_count: record_count,
            truncation_points: truncation_points
          )
        end
      end
    end
  end
end
```

## CSV-Specific Edge Cases

### Case 1: Split Quoted Field

**Input Chunk 1 (truncated):**
```csv
name,description,url
Company A,"This is a long description that gets cut off in the m
```

**Input Chunk 2 (continuation):**
```csv
iddle of the sentence",https://example.com
Company B,"Another company",https://example2.com
```

**Expected Output:**
```csv
name,description,url
Company A,"This is a long description that gets cut off in the middle of the sentence",https://example.com
Company B,"Another company",https://example2.com
```

### Case 2: Multi-line Quoted Field

**Input Chunk 1 (truncated):**
```csv
name,address,city
Company A,"123 Main St
Suite
```

**Input Chunk 2 (continuation):**
```csv
 200",Boston
Company B,"456 Oak Ave",Seattle
```

**Expected Output:**
```csv
name,address,city
Company A,"123 Main St
Suite 200",Boston
Company B,"456 Oak Ave",Seattle
```

### Case 3: Duplicate Header Detection

**Input Chunk 1:**
```csv
name,city,employees
Company A,Boston,100
```

**Input Chunk 2 (incorrectly includes header):**
```csv
name,city,employees
Company B,Seattle,200
Company C,Portland,150
```

**Expected Output:**
```csv
name,city,employees
Company A,Boston,100
Company B,Seattle,200
Company C,Portland,150
```

### Case 4: Trailing Comma (Incomplete Row)

**Input Chunk 1 (truncated):**
```csv
name,city,employees
Company A,Boston,
```

**Input Chunk 2 (continuation):**
```csv
100
Company B,Seattle,200
```

**Expected Output:**
```csv
name,city,employees
Company A,Boston,100
Company B,Seattle,200
```

## CSV Continuation Prompt

Specific prompt for CSV continuation that provides context about incomplete rows:

```ruby
def build_csv_continuation_prompt(last_chunk)
  content = extract_content(last_chunk)
  last_lines = content.split("\n").last(3).join("\n")

  {
    role: "user",
    content: <<~PROMPT
      Continue from where you left off. The last few lines were:

      #{last_lines}

      Complete any incomplete rows and continue generating more CSV data.
      Output ONLY the CSV data continuation, no explanations or headers.
      Do NOT repeat the header row.
    PROMPT
  }
end
```

## Testing Strategy

### Unit Tests

```ruby
describe RAAF::Continuation::Mergers::CSVMerger do
  let(:merger) { described_class.new }

  describe "#incomplete_row?" do
    it "detects rows with odd quote count" do
      row = ["Company", "Description with \"quote"]
      expect(merger.send(:incomplete_row?, row)).to be true
    end

    it "detects rows with trailing comma" do
      row = ["Company", "Boston,"]
      expect(merger.send(:incomplete_row?, row)).to be true
    end

    it "returns false for complete rows" do
      row = ["Company", "Boston", "100"]
      expect(merger.send(:incomplete_row?, row)).to be false
    end
  end

  describe "#merge" do
    it "completes split quoted fields" do
      chunk1 = build_chunk('name,desc\nCo,"Long text')
      chunk2 = build_chunk(' continued",url')

      result = merger.merge([chunk1, chunk2])

      expect(result[:data]).to include('Co,"Long text continued",url')
    end

    it "removes duplicate headers" do
      chunk1 = build_chunk("name,city\nCo A,Boston")
      chunk2 = build_chunk("name,city\nCo B,Seattle")

      result = merger.merge([chunk1, chunk2])

      expect(result[:data].scan(/^name,city/).length).to eq(1)
    end

    it "preserves column alignment" do
      chunk1 = build_chunk("a,b,c\n1,2,3")
      chunk2 = build_chunk("4,5,6\n7,8,9")

      result = merger.merge([chunk1, chunk2])

      rows = CSV.parse(result[:data])
      expect(rows.all? { |r| r.length == 3 }).to be true
    end
  end
end
```

### Integration Tests

```ruby
describe "CSV Continuation Integration" do
  it "handles large company datasets" do
    agent = create_csv_agent(expected_records: 500)

    result = agent.run("Find 500 tech companies")

    expect(result[:_continuation_metadata][:was_continued]).to be true
    expect(result[:_continuation_metadata][:final_record_count]).to be >= 500
    expect(CSV.parse(result[:data]).length).to be >= 500
  end

  it "maintains data integrity across continuations" do
    agent = create_csv_agent(expected_records: 1000)

    result = agent.run("Find 1000 companies with detailed info")

    csv_data = CSV.parse(result[:data], headers: true)

    # Verify no duplicate records
    names = csv_data.map { |row| row["name"] }
    expect(names.uniq.length).to eq(names.length)

    # Verify all rows have same column count
    column_counts = csv_data.map { |row| row.fields.length }
    expect(column_counts.uniq.length).to eq(1)
  end
end
```

## Success Metrics

- **Target Success Rate**: 95%+
- **Incomplete Row Detection**: 100% of split rows detected and completed
- **Header Deduplication**: 100% of duplicate headers removed
- **Column Alignment**: 100% of rows maintain consistent column count
- **Performance**: < 50ms merge time for 1000 rows
- **Memory**: < 10MB additional memory for 1000-row dataset

## Known Limitations

1. **Complex CSV Dialects**: Only supports standard comma-delimited CSV (not tab-delimited or custom delimiters)
2. **Very Long Fields**: Fields exceeding 10KB may impact performance
3. **Encoding Issues**: Assumes UTF-8 encoding, may fail with other encodings
4. **Extremely Malformed CSV**: If LLM generates highly malformed CSV, fallback parsing may skip rows

## Future Enhancements

- Support for custom delimiters (tab, semicolon, pipe)
- Configurable encoding detection
- Advanced validation rules (e.g., email format, numeric ranges)
- Automatic data type inference
- Schema validation against expected columns
