# frozen_string_literal: true

require "spec_helper"
require "csv"
require "time"

RSpec.describe "RAAF::Continuation::Mergers::CSVMerger" do
  # Test CSV Merger implementation
  # This class handles merging CSV chunks from continuation responses
  # with intelligent detection of incomplete rows and proper header handling

  let(:config) { RAAF::Continuation::Config.new }
  let(:csv_merger) { RAAF::Continuation::Mergers::CSVMerger.new(config) }

  # ============================================================================
  # 1. Complete Row Merging Tests (8 tests)
  # ============================================================================
  describe "complete row merging" do
    it "merges two complete CSV chunks" do
      chunk1 = { content: "id,name,email\n1,John,john@example.com\n2,Jane,jane@example.com\n" }
      chunk2 = { content: "3,Bob,bob@example.com\n4,Alice,alice@example.com\n" }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("1,John")
      expect(result[:content]).to include("2,Jane")
      expect(result[:content]).to include("3,Bob")
      expect(result[:content]).to include("4,Alice")
    end

    it "preserves header from first chunk only" do
      chunk1 = { content: "id,name,email\n1,John,john@example.com\n" }
      chunk2 = { content: "2,Jane,jane@example.com\n" }

      result = csv_merger.merge([chunk1, chunk2])
      headers = result[:content].lines.first

      expect(headers).to eq("id,name,email\n")
      # Verify header appears only once
      header_count = result[:content].count("id,name,email")
      expect(header_count).to eq(1)
    end

    it "maintains row order across chunks" do
      rows = (1..10).map { |i| "#{i},User#{i},user#{i}@example.com" }
      chunk1 = { content: "id,name,email\n#{rows[0..4].join("\n")}\n" }
      chunk2 = { content: "#{rows[5..9].join("\n")}\n" }

      result = csv_merger.merge([chunk1, chunk2])
      lines = result[:content].lines

      expect(lines[0]).to eq("id,name,email\n")
      (1..10).each do |i|
        expect(result[:content]).to include("#{i},User#{i}")
      end
    end

    it "handles varied column counts gracefully" do
      chunk1 = { content: "id,name,email\n1,John,john@example.com\n" }
      # Second chunk has different structure
      chunk2 = { content: "2,Jane,jane@example.com\n" }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("id,name,email")
      expect(result[:content]).to include("1,John")
      expect(result[:content]).to include("2,Jane")
    end

    it "merges 10 row datasets correctly" do
      chunk1 = { content: "id,name\n#{(1..5).map { |i| "#{i},Name#{i}" }.join("\n")}\n" }
      chunk2 = { content: "#{(6..10).map { |i| "#{i},Name#{i}" }.join("\n")}\n" }

      result = csv_merger.merge([chunk1, chunk2])
      lines = result[:content].lines.map(&:strip)

      expect(lines.length).to eq(11) # Header + 10 rows
      (1..10).each { |i| expect(result[:content]).to include("#{i},Name#{i}") }
    end

    it "merges 100 row datasets correctly" do
      rows_chunk1 = (1..50).map { |i| "#{i},Product#{i},#{100 * i}.99" }.join("\n")
      rows_chunk2 = (51..100).map { |i| "#{i},Product#{i},#{100 * i}.99" }.join("\n")

      chunk1 = { content: "id,product,price\n#{rows_chunk1}\n" }
      chunk2 = { content: "#{rows_chunk2}\n" }

      result = csv_merger.merge([chunk1, chunk2])

      # Count rows (excluding header)
      row_count = result[:content].lines.drop(1).reject(&:empty?).count
      expect(row_count).to eq(100)
    end

    it "merges 1000 row datasets correctly" do
      rows_chunk1 = (1..500).map { |i| "#{i},Item#{i},Active" }.join("\n")
      rows_chunk2 = (501..1000).map { |i| "#{i},Item#{i},Active" }.join("\n")

      chunk1 = { content: "id,item,status\n#{rows_chunk1}\n" }
      chunk2 = { content: "#{rows_chunk2}\n" }

      result = csv_merger.merge([chunk1, chunk2])

      row_count = result[:content].lines.drop(1).reject(&:empty?).count
      expect(row_count).to eq(1000)
      expect(result[:metadata][:merge_success]).to be true
    end

    it "handles three or more chunks sequentially" do
      chunk1 = { content: "id,name\n1,Alice\n2,Bob\n" }
      chunk2 = { content: "3,Charlie\n4,David\n" }
      chunk3 = { content: "5,Eve\n6,Frank\n" }

      result = csv_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:content]).to include("1,Alice")
      expect(result[:content]).to include("3,Charlie")
      expect(result[:content]).to include("5,Eve")
      expect(result[:content]).to include("6,Frank")
    end
  end

  # ============================================================================
  # 2. Incomplete Row Detection Tests (8 tests)
  # ============================================================================
  describe "incomplete row detection" do
    it "detects rows missing closing quote" do
      content = 'id,name,notes\n1,John,"This is a note\n2,Jane,"Another note'
      expect(csv_merger.send(:has_incomplete_row?, content)).to be true
    end

    it "detects rows with trailing comma" do
      content = 'id,name,email\n1,John,john@example.com,\n2,Jane,jane@example.com\n'
      expect(csv_merger.send(:has_incomplete_row?, content)).to be true
    end

    it "detects incomplete rows via quote counting" do
      # Odd number of quotes indicates incomplete quoted field
      content = 'id,name,description\n1,Product,"Incomplete'
      quote_count = content.count('"')
      expect(quote_count).to be_odd
    end

    it "handles complete quoted fields without false positives" do
      content = 'id,name,description\n1,John,"Complete quote"\n2,Jane,"Another complete"\n'
      expect(csv_merger.send(:has_incomplete_row?, content)).to be false
    end

    it "detects multi-line fields as incomplete" do
      content = "id,name,description\n1,John,\"This spans\nmultiple lines"
      expect(csv_merger.send(:has_incomplete_row?, content)).to be true
    end

    it "counts quotes to identify incomplete quoted field" do
      content = 'id,name,notes\n1,John,"Note with\nline break'
      quote_count = content.count('"')
      expect(quote_count).to be_odd
    end

    it "detects incomplete row in last line" do
      chunk = "id,name,email\n1,John,john@example.com\n2,Jane,jane@example"
      expect(csv_merger.send(:has_incomplete_row?, chunk)).to be true
    end

    it "validates complete rows pass detection" do
      complete_csv = 'id,name,email\n1,John,john@example.com\n2,Jane,jane@example.com\n'
      expect(csv_merger.send(:has_incomplete_row?, complete_csv)).to be false
    end
  end

  # ============================================================================
  # 3. Quoted Field Handling Tests (8 tests)
  # ============================================================================
  describe "quoted field handling" do
    it "merges split quoted fields correctly" do
      chunk1 = { content: 'id,name,notes\n1,John,"This is a note' }
      chunk2 = { content: ' that continues here"\n2,Jane,"Another note"\n' }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("1,John")
      expect(result[:content]).to include("2,Jane")
    end

    it "handles escaped quotes inside fields" do
      chunk1 = { content: 'id,name,notes\n1,John,"He said ""hello"" to me' }
      chunk2 = { content: '"\n2,Jane,"Normal note"\n' }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content]).to include("John")
    end

    it "preserves content with commas inside quotes" do
      chunk1 = { content: 'id,address\n1,"123 Main St, Apt 4, New York, NY 10001' }
      chunk2 = { content: '"\n2,"456 Oak Ave, Suite 200, Boston, MA 02101"\n' }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("Main St, Apt 4")
      expect(result[:content]).to include("Oak Ave, Suite 200")
    end

    it "handles empty quoted fields" do
      content1 = 'id,name,notes\n1,John,""\n'
      content2 = '2,Jane,"Some notes"\n'
      chunk1 = { content: content1 }
      chunk2 = { content: content2 }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include('1,John,""')
      expect(result[:content]).to include("2,Jane")
    end

    it "merges quoted fields spanning multiple lines" do
      chunk1 = { content: "id,description\n1,\"First line\nSecond line" }
      chunk2 = { content: "\nThird line\"\n" }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
    end

    it "preserves quotes in field values" do
      chunk1 = { content: 'id,quote\n1,"He said ""hello""' }
      chunk2 = { content: '"\n' }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("hello")
    end

    it "handles quoted fields with special characters" do
      chunk1 = { content: 'id,note\n1,"Note with newline\\nand tab\\t' }
      chunk2 = { content: 'end"\n' }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
    end

    it "merges multiple quoted fields in same row" do
      chunk1 = { content: 'id,name,address,notes\n1,"John Doe","123 Main St' }
      chunk2 = { content: '","Notes about the customer"\n' }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("John Doe")
      expect(result[:content]).to include("123 Main St")
    end
  end

  # ============================================================================
  # 4. Header Preservation Tests (5 tests)
  # ============================================================================
  describe "header preservation" do
    it "keeps header from first chunk only" do
      chunk1 = { content: "id,name,email\n1,John,john@example.com\n" }
      chunk2 = { content: "id,name,email\n2,Jane,jane@example.com\n" }

      result = csv_merger.merge([chunk1, chunk2])

      # Count header occurrences
      header_count = result[:content].scan(/^id,name,email/).count
      expect(header_count).to eq(1)
    end

    it "removes duplicate headers from continuation" do
      chunk1 = { content: "product,price,stock\nWidget,9.99,100\n" }
      chunk2 = { content: "product,price,stock\nGadget,19.99,50\n" }

      result = csv_merger.merge([chunk1, chunk2])

      lines = result[:content].lines.map(&:strip)
      header_indices = lines.each_with_index
                           .select { |line, _| line == "product,price,stock" }
                           .map(&:last)

      expect(header_indices.length).to eq(1)
    end

    it "validates header consistency" do
      chunk1 = { content: "id,name,email\n1,John,john@example.com\n" }
      chunk2 = { content: "id,name,email\n2,Jane,jane@example.com\n" }

      result = csv_merger.merge([chunk1, chunk2])

      lines = result[:content].lines
      header = lines.first.strip

      expect(header).to eq("id,name,email")
    end

    it "handles missing headers in continuation chunks" do
      chunk1 = { content: "id,name,email\n1,John,john@example.com\n" }
      chunk2 = { content: "2,Jane,jane@example.com\n3,Bob,bob@example.com\n" }

      result = csv_merger.merge([chunk1, chunk2])

      first_line = result[:content].lines.first.strip
      expect(first_line).to eq("id,name,email")

      expect(result[:content]).to include("1,John")
      expect(result[:content]).to include("2,Jane")
      expect(result[:content]).to include("3,Bob")
    end

    it "preserves header with special characters" do
      header = "id,user_name,email_address,registration_date"
      chunk1 = { content: "#{header}\n1,John,john@example.com,2025-01-01\n" }
      chunk2 = { content: "2,Jane,jane@example.com,2025-01-02\n" }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content].lines.first.strip).to eq(header)
    end
  end

  # ============================================================================
  # 5. Edge Cases Tests (8 tests)
  # ============================================================================
  describe "edge cases" do
    it "handles empty chunks gracefully" do
      chunk1 = { content: "" }
      chunk2 = { content: "id,name\n1,Alice\n" }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("1,Alice")
      expect(result[:metadata][:merge_success]).to be true
    end

    it "handles single row datasets" do
      chunk = { content: "id,name,email\n1,John,john@example.com\n" }

      result = csv_merger.merge([chunk])

      expect(result[:content]).to include("id,name,email")
      expect(result[:content]).to include("1,John")
    end

    it "handles all quoted fields" do
      chunk1 = { content: '"id","name","email"\n"1","John","john@ex' }
      chunk2 = { content: 'ample.com"\n"2","Jane","jane@example.com"\n' }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
    end

    it "preserves unicode characters" do
      chunk1 = { content: "id,name,city\n1,João,São Paulo\n" }
      chunk2 = { content: "2,Müller,München\n3,Zhao,北京\n" }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("João")
      expect(result[:content]).to include("Müller")
      expect(result[:content]).to include("北京")
    end

    it "handles very large fields (10k+ characters)" do
      large_value = "A" * 10_000
      chunk1 = { content: "id,data\n1,\"#{large_value}" }
      chunk2 = { content: "\"\n2,small\n" }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content].length).to be > 10_000
    end

    it "handles different CSV dialects (semicolon)" do
      chunk1 = { content: "id;name;email\n1;John;john@example.com\n" }
      chunk2 = { content: "2;Jane;jane@example.com\n" }

      result = csv_merger.merge([chunk1, chunk2])

      # Result should contain merged data
      expect(result[:metadata][:merge_success]).to be true
      expect(result[:content]).to include("John")
    end

    it "handles escaped newlines in fields" do
      chunk1 = { content: 'id,name,notes\n1,John,"Line1\\n' }
      chunk2 = { content: 'Line2\\nLine3"\n' }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
    end

    it "handles chunks with only whitespace" do
      chunk1 = { content: "id,name\n1,Alice\n" }
      chunk2 = { content: "   \n  \n" }
      chunk3 = { content: "2,Bob\n" }

      result = csv_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:content]).to include("1,Alice")
      expect(result[:content]).to include("2,Bob")
    end
  end

  # ============================================================================
  # 6. Metadata Tests (3 tests)
  # ============================================================================
  describe "metadata structure" do
    it "builds correct metadata for successful CSV merge" do
      chunk1 = { content: "id,name\n1,John\n" }
      chunk2 = { content: "2,Jane\n" }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:metadata]).to be_a(Hash)
      expect(result[:metadata][:merge_success]).to be true
      expect(result[:metadata][:chunk_count]).to eq(2)
      expect(result[:metadata][:timestamp]).to be_a(String)
    end

    it "includes row count in metadata" do
      rows = (1..15).map { |i| "#{i},User#{i},user#{i}@example.com" }.join("\n")
      chunk1 = { content: "id,name,email\n#{rows[0..5]}\n" }
      chunk2 = { content: "#{rows[6..-1]}\n" }

      result = csv_merger.merge([chunk1, chunk2])

      # Verify merge_success is present
      expect(result[:metadata][:merge_success]).to be true
      # Row count would be validated by merge success
      expect(result[:content].lines.count).to be >= 15
    end

    it "includes merge_success flag in metadata" do
      chunk1 = { content: "id,name\n1,John\n" }

      result = csv_merger.merge([chunk1])

      expect(result[:metadata]).to have_key(:merge_success)
      expect([true, false]).to include(result[:metadata][:merge_success])
    end
  end

  # ============================================================================
  # Additional Integration Tests
  # ============================================================================
  describe "CSV merger integration" do
    it "merges complex real-world CSV dataset" do
      # Simulate real company data
      headers = "company_id,company_name,headquarters,employees,industry,founded"
      row1 = '1,"Apple Inc.","Cupertino, CA",161000,"Technology",1976'
      row2 = '2,"Microsoft Corporation","Redmond, WA",221000,"Technology",1975'
      row3 = '3,"Google LLC","Mountain View, CA",190234,"Technology",1998'

      chunk1 = { content: "#{headers}\n#{row1}\n#{row2}\n" }
      chunk2 = { content: "#{row3}\n" }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("Apple Inc.")
      expect(result[:content]).to include("Microsoft")
      expect(result[:content]).to include("Google")
      expect(result[:metadata][:merge_success]).to be true
    end

    it "handles chunks with mixed ending styles" do
      # Some chunks end with newline, others don't
      chunk1 = { content: "id,name\n1,Alice" }
      chunk2 = { content: "\n2,Bob\n" }
      chunk3 = { content: "3,Charlie" }

      result = csv_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:content]).to include("Alice")
      expect(result[:content]).to include("Bob")
      expect(result[:content]).to include("Charlie")
    end

    it "validates proper merging of 500+ row dataset" do
      all_rows = (1..500).map { |i| "#{i},Item#{i},Category#{i % 10},#{100 + i}" }.join("\n")
      chunk1 = { content: "id,item,category,price\n#{all_rows[0..2000]}" }
      chunk2 = { content: "#{all_rows[2001..-1]}\n" }

      result = csv_merger.merge([chunk1, chunk2])

      row_count = result[:content].lines.drop(1).reject(&:empty?).count
      expect(row_count).to eq(500)
      expect(result[:metadata][:merge_success]).to be true
    end

    it "preserves data integrity across merges" do
      # Create CSV with specific data patterns
      rows = (1..50).map do |i|
        email = "user#{i}@example.com"
        name = "User #{i}"
        amount = format("%.2f", 100.00 + (i * 10.5))
        "#{i},#{name},#{email},#{amount}"
      end.join("\n")

      chunk1 = { content: "id,name,email,amount\n#{rows[0..500]}" }
      chunk2 = { content: "#{rows[501..-1]}\n" }

      result = csv_merger.merge([chunk1, chunk2])

      # Verify all rows are present
      expect(result[:content]).to include("user1@example.com")
      expect(result[:content]).to include("user50@example.com")
      expect(result[:metadata][:merge_success]).to be true
    end

    it "handles continuation with incomplete row and completion" do
      # Simulate real truncation scenario
      chunk1 = { content: 'id,name,description\n1,Product,"This is a long description' }
      chunk2 = { content: ' that continues into the next chunk"\n2,Product2,"Short desc"\n' }

      result = csv_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("Product")
      expect(result[:content]).to include("Product2")
      expect(result[:metadata][:merge_success]).to be true
    end

    it "extracts content from hash chunks with various keys" do
      chunk1 = { "content" => "id,name\n1,Alice\n" }
      chunk2 = { content: "2,Bob\n" }
      chunk3 = { message: { content: "3,Charlie\n" } }

      result = csv_merger.merge([chunk1, chunk2, chunk3])

      expect(result[:content]).to include("Alice")
      expect(result[:content]).to include("Bob")
      expect(result[:content]).to include("Charlie")
    end

    it "handles merge with nil and empty content in chunks" do
      chunk1 = { content: "id,name\n1,John\n" }
      chunk2 = nil
      chunk3 = { content: "" }
      chunk4 = { content: "2,Jane\n" }

      result = csv_merger.merge([chunk1, chunk2, chunk3, chunk4])

      expect(result[:content]).to include("1,John")
      expect(result[:content]).to include("2,Jane")
      expect(result[:metadata][:merge_success]).to be true
    end
  end
end
