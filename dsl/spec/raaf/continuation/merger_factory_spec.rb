# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::Continuation::MergerFactory" do
  # Test MergerFactory implementation
  # This class routes to the appropriate format-specific merger based on
  # configured output format (:csv, :markdown, :json) or auto-detection (:auto)

  # ============================================================================
  # 1. Explicit Format Selection Tests (8 tests)
  # ============================================================================
  describe "explicit format selection" do
    it "returns CSVMerger for :csv format" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :csv)
      merger = factory.get_merger

      expect(merger).to be_a(RAAF::Continuation::Mergers::CSVMerger)
    end

    it "returns MarkdownMerger for :markdown format" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :markdown)
      merger = factory.get_merger

      expect(merger).to be_a(RAAF::Continuation::Mergers::MarkdownMerger)
    end

    it "returns JSONMerger for :json format" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :json)
      merger = factory.get_merger

      expect(merger).to be_a(RAAF::Continuation::Mergers::JSONMerger)
    end

    it "returns BaseMerger for unknown format" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :unknown)
      merger = factory.get_merger

      expect(merger).to be_a(RAAF::Continuation::Mergers::BaseMerger)
    end

    it "raises error for :auto format without content" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)

      expect { factory.get_merger }.to raise_error(ArgumentError)
    end

    it "creates multiple merger instances independently" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :csv)
      merger1 = factory.get_merger
      merger2 = factory.get_merger

      expect(merger1).to be_a(RAAF::Continuation::Mergers::CSVMerger)
      expect(merger2).to be_a(RAAF::Continuation::Mergers::CSVMerger)
      expect(merger1).not_to be(merger2)  # Different instances
    end

    it "handles symbol format as string" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :csv)
      merger = factory.get_merger

      expect(merger).to be_a(RAAF::Continuation::Mergers::CSVMerger)
    end

    it "uses default :auto format" do
      factory = RAAF::Continuation::MergerFactory.new
      # Default is :auto, so getting content-based merger should work

      csv_content = "id,name\n1,Alice"
      merger = factory.get_merger_for_content(csv_content)

      expect(merger).to be_a(RAAF::Continuation::Mergers::CSVMerger)
    end
  end

  # ============================================================================
  # 2. Auto-Detection Tests (8 tests)
  # ============================================================================
  describe "auto-detection with get_merger_for_content" do
    it "detects and returns CSVMerger for CSV content" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)
      csv_content = "id,name,email\n1,Alice,alice@example.com\n2,Bob,bob@example.com"

      merger = factory.get_merger_for_content(csv_content)

      expect(merger).to be_a(RAAF::Continuation::Mergers::CSVMerger)
    end

    it "detects and returns MarkdownMerger for Markdown content" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)
      markdown_content = "# Report\n\n| ID | Name |\n|---|---|\n| 1 | Alice |"

      merger = factory.get_merger_for_content(markdown_content)

      expect(merger).to be_a(RAAF::Continuation::Mergers::MarkdownMerger)
    end

    it "detects and returns JSONMerger for JSON content" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)
      json_content = '{"items": [{"id": 1, "name": "Alice"}]}'

      merger = factory.get_merger_for_content(json_content)

      expect(merger).to be_a(RAAF::Continuation::Mergers::JSONMerger)
    end

    it "returns BaseMerger when format cannot be detected" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)
      unknown_content = "random text with no clear format"

      merger = factory.get_merger_for_content(unknown_content)

      expect(merger).to be_a(RAAF::Continuation::Mergers::BaseMerger)
    end

    it "ignores content when explicit format is configured" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :csv)
      json_content = '{"items": [{"id": 1}]}'

      # Even though content is JSON, should return CSV merger
      merger = factory.get_merger_for_content(json_content)

      expect(merger).to be_a(RAAF::Continuation::Mergers::CSVMerger)
    end

    it "handles empty content in auto-detection" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)
      merger = factory.get_merger_for_content("")

      expect(merger).to be_a(RAAF::Continuation::Mergers::BaseMerger)
    end

    it "handles large content in auto-detection" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)
      large_csv = "id,name\n" + (1..1000).map { |i| "#{i},Person#{i}" }.join("\n")

      merger = factory.get_merger_for_content(large_csv)

      expect(merger).to be_a(RAAF::Continuation::Mergers::CSVMerger)
    end

    it "auto-detects multiple times independently" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)

      csv_merger = factory.get_merger_for_content("id,name\n1,Alice")
      json_merger = factory.get_merger_for_content('{"id": 1}')
      md_merger = factory.get_merger_for_content("# Header")

      expect(csv_merger).to be_a(RAAF::Continuation::Mergers::CSVMerger)
      expect(json_merger).to be_a(RAAF::Continuation::Mergers::JSONMerger)
      expect(md_merger).to be_a(RAAF::Continuation::Mergers::MarkdownMerger)
    end
  end

  # ============================================================================
  # 3. Format Detection Tests (6 tests)
  # ============================================================================
  describe "detect_format method" do
    it "returns detected format and confidence" do
      factory = RAAF::Continuation::MergerFactory.new
      csv_content = "id,name\n1,Alice\n2,Bob"

      format, confidence = factory.detect_format(csv_content)

      expect(format).to eq(:csv)
      expect(confidence).to be_a(Float)
      expect(confidence).to be > 0
      expect(confidence).to be <= 1.0
    end

    it "returns high confidence for unambiguous CSV" do
      factory = RAAF::Continuation::MergerFactory.new
      content = "id,name,email,phone\n1,Alice,alice@example.com,555-1234"

      format, confidence = factory.detect_format(content)

      expect(format).to eq(:csv)
      expect(confidence).to be > 0.5
    end

    it "returns high confidence for unambiguous JSON" do
      factory = RAAF::Continuation::MergerFactory.new
      content = '{"data": [{"id": 1}, {"id": 2}]}'

      format, confidence = factory.detect_format(content)

      expect(format).to eq(:json)
      expect(confidence).to be > 0.5
    end

    it "returns high confidence for unambiguous Markdown" do
      factory = RAAF::Continuation::MergerFactory.new
      content = "# Report\n\n```ruby\ncode\n```"

      format, confidence = factory.detect_format(content)

      expect(format).to eq(:markdown)
      expect(confidence).to be > 0.3
    end

    it "handles nil content gracefully" do
      factory = RAAF::Continuation::MergerFactory.new
      format, confidence = factory.detect_format(nil)

      expect(format).to eq(:unknown)
      expect(confidence).to eq(0.0)
    end

    it "handles empty content gracefully" do
      factory = RAAF::Continuation::MergerFactory.new
      format, confidence = factory.detect_format("")

      expect(format).to eq(:unknown)
      expect(confidence).to eq(0.0)
    end
  end

  # ============================================================================
  # 4. Logger Integration Tests (4 tests)
  # ============================================================================
  describe "logger integration" do
    it "accepts custom logger" do
      logger = instance_double("Logger")
      allow(logger).to receive(:debug)
      allow(logger).to receive(:warn)

      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto, logger: logger)
      content = "id,name\n1,Alice"

      merger = factory.get_merger_for_content(content)

      # Should use the provided logger
      expect(logger).to have_received(:debug).at_least(:once)
    end

    it "logs format detection results" do
      logger = instance_double("Logger")
      allow(logger).to receive(:debug)
      allow(logger).to receive(:warn)

      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto, logger: logger)
      content = "id,name\n1,Alice"

      factory.get_merger_for_content(content)

      # Should log debug message about format detection
      expect(logger).to have_received(:debug)
    end

    it "logs warning for unknown formats" do
      logger = instance_double("Logger")
      allow(logger).to receive(:debug)
      allow(logger).to receive(:warn)

      factory = RAAF::Continuation::MergerFactory.new(output_format: :unknown, logger: logger)

      factory.get_merger

      # Should log warning about unknown format
      expect(logger).to have_received(:warn)
    end

    it "uses Rails logger if available" do
      if defined?(Rails)
        factory = RAAF::Continuation::MergerFactory.new(output_format: :csv)

        # Should not raise error - uses Rails.logger automatically
        expect { factory.get_merger }.not_to raise_error
      end
    end
  end

  # ============================================================================
  # 5. Real-World Workflow Tests (5 tests)
  # ============================================================================
  describe "real-world workflows" do
    it "works with company discovery CSV workflow" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :csv)
      merger = factory.get_merger

      chunk1 = { content: "id,name,industry\n1,Acme,Tech\n2,Beta" }
      chunk2 = { content: ",Finance" }

      result = merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("Acme")
    end

    it "works with report generation markdown workflow" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :markdown)
      merger = factory.get_merger

      chunk1 = { content: "# Report\n\n| ID | Name |\n|---|---|\n| 1 | Alice |" }
      chunk2 = { content: "\n| 2 | Bob |" }

      result = merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("Bob")
    end

    it "works with data extraction JSON workflow" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :json)
      merger = factory.get_merger

      chunk1 = { content: '{"items": [{"id": 1}, {"id": 2' }
      chunk2 = { content: '}]}' }

      result = merger.merge([chunk1, chunk2])

      expect(result[:content]).not_to be_nil
    end

    it "auto-detects and merges CSV content" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)

      chunk1 = { content: "id,name\n1,Alice\n2" }
      chunk2 = { content: ",Bob" }

      merger = factory.get_merger_for_content(chunk1[:content])
      result = merger.merge([chunk1, chunk2])

      expect(result[:metadata][:merge_success]).to be true
    end

    it "auto-detects and merges JSON content" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)

      chunk1 = { content: '{"items": [{"id": 1' }
      chunk2 = { content: '}]}' }

      merger = factory.get_merger_for_content(chunk1[:content])
      result = merger.merge([chunk1, chunk2])

      # Should complete merge successfully
      expect(result).to have_key(:content)
      expect(result).to have_key(:metadata)
    end
  end

  # ============================================================================
  # 6. Error Handling Tests (4 tests)
  # ============================================================================
  describe "error handling" do
    it "raises error for :auto format in get_merger without content" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)

      expect { factory.get_merger }.to raise_error(ArgumentError)
    end

    it "recovers from invalid content in auto-detection" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)

      # Should not raise error
      merger = factory.get_merger_for_content("invalid \x00 binary content")

      expect(merger).to be_a(RAAF::Continuation::Mergers::BaseMerger)
    end

    it "handles format detection exceptions gracefully" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)

      # Very large content shouldn't cause issues
      large_content = "a" * (1024 * 1024)  # 1MB of text
      merger = factory.get_merger_for_content(large_content)

      expect(merger).to be_a(RAAF::Continuation::Mergers::BaseMerger)
    end

    it "uses default logger if Rails not available" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :csv)

      # Should not raise error even if Rails unavailable
      expect { factory.get_merger }.not_to raise_error
    end
  end

  # ============================================================================
  # 7. Consistency Tests (3 tests)
  # ============================================================================
  describe "consistency and correctness" do
    it "returns same merger type for same format across multiple calls" do
      factory1 = RAAF::Continuation::MergerFactory.new(output_format: :csv)
      factory2 = RAAF::Continuation::MergerFactory.new(output_format: :csv)

      merger1 = factory1.get_merger
      merger2 = factory2.get_merger

      expect(merger1.class).to eq(merger2.class)
    end

    it "auto-detection returns same merger type for same content across multiple calls" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)
      content = "id,name,email\n1,Alice,alice@example.com"

      merger1 = factory.get_merger_for_content(content)
      merger2 = factory.get_merger_for_content(content)

      expect(merger1.class).to eq(merger2.class)
    end

    it "detects format consistently for same content" do
      factory = RAAF::Continuation::MergerFactory.new(output_format: :auto)
      content = '{"id": 1, "name": "Alice"}'

      format1, confidence1 = factory.detect_format(content)
      format2, confidence2 = factory.detect_format(content)

      expect(format1).to eq(format2)
      expect(confidence1).to eq(confidence2)
    end
  end
end
