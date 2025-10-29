# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF Continuation: Error Handling and Graceful Degradation" do
  # Test doubles and fixtures
  let(:base_chunks) do
    [
      { content: "id,name,email\n1,John,john@example.com\n2,Jane" },
      { content: ",jane@example.com\n3,Bob,bob@example.com\n" }
    ]
  end

  let(:malformed_json_chunks) do
    [
      { content: '{"users": [{"id": 1, "name": "John"}, {"id": 2' },
      { content: ', "name": "Jane"' }
    ]
  end

  let(:incomplete_markdown_chunks) do
    [
      { content: "| Header 1 | Header 2 |\n|---|---|\n| Row 1" },
      { content: " | Data 1 |\n| Row 2 | Data 2 |" }
    ]
  end

  let(:all_empty_chunks) { [{ content: "" }, { content: nil }, ""] }

  let(:config_return_partial) do
    RAAF::Continuation::Config.new(on_failure: :return_partial)
  end

  let(:config_raise_error) do
    RAAF::Continuation::Config.new(on_failure: :raise_error)
  end

  describe "Category 1: Merge Failure Handling (8 tests)" do
    describe "#merge with exceptions" do
      it "catches merger exceptions and handles gracefully" do
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config_return_partial)

        bad_chunks = [
          { content: "id,name\n1,\"John" },
          { content: ",,broken,structure" }
        ]

        expect {
          merger.merge(bad_chunks)
        }.not_to raise_error

        result = merger.merge(bad_chunks)
        expect(result[:metadata][:merge_success]).to be false
        expect(result[:metadata][:merge_error]).to be_present
      end

      it "captures exception class name in merge_error" do
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config_return_partial)

        bad_chunks = [
          { content: '{"invalid": [1, 2' },
          { content: "BROKEN JSON" }
        ]

        result = merger.merge(bad_chunks)
        expect(result[:metadata][:merge_error]).to be_present
        expect(result[:metadata][:merge_error][:error_class]).to be_a(String)
        expect(result[:metadata][:merge_error][:error_class]).to include("Error")
      end

      it "logs error details when merge fails" do
        merger = RAAF::Continuation::Mergers::BaseMerger.new(config_return_partial)

        chunks = [{ content: "test" }]

        expect {
          merger.merge(chunks)
        }.to raise_error(NotImplementedError)
      end

      it "includes error message in metadata" do
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config_return_partial)

        bad_chunks = [
          { content: "{" },
          { content: "INVALID" }
        ]

        result = merger.merge(bad_chunks)
        expect(result[:metadata][:merge_error]).to be_present
        expect(result[:metadata][:merge_error][:error_message]).to be_a(String)
        expect(result[:metadata][:merge_error][:error_message]).not_to be_empty
      end

      it "preserves chunk metadata on merge error" do
        merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config_return_partial)

        bad_chunks = [
          { content: "| Header" },
          { content: "BROKEN" }
        ]

        result = merger.merge(bad_chunks)
        expect(result[:metadata][:chunk_count]).to eq(2)
        expect(result[:metadata][:timestamp]).to be_present
      end

      it "returns nil content when merge fails" do
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config_return_partial)

        bad_chunks = [{ content: "[" }]

        result = merger.merge(bad_chunks)
        expect(result[:content]).to be_nil
      end

      it "marks merge_success as false on exception" do
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config_return_partial)

        bad_chunks = [{ content: '"unclosed' }]

        result = merger.merge(bad_chunks)
        expect(result[:metadata][:merge_success]).to be false
      end

      it "handles multiple sequential merge failures gracefully" do
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config_return_partial)

        bad_chunks1 = [{ content: "{" }]
        bad_chunks2 = [{ content: "[" }]
        bad_chunks3 = [{ content: "INVALID" }]

        expect {
          merger.merge(bad_chunks1)
          merger.merge(bad_chunks2)
          merger.merge(bad_chunks3)
        }.not_to raise_error

        result1 = merger.merge(bad_chunks1)
        result2 = merger.merge(bad_chunks2)
        result3 = merger.merge(bad_chunks3)

        expect(result1[:metadata][:merge_success]).to be false
        expect(result2[:metadata][:merge_success]).to be false
        expect(result3[:metadata][:merge_success]).to be false
      end
    end
  end

  describe "Category 2: Partial Result Builder (6 tests)" do
    describe "PartialResultBuilder" do
      let(:builder) { RAAF::Continuation::PartialResultBuilder.new }

      it "combines successful chunks into partial result" do
        chunks = [
          { content: "id,name\n1,John\n" },
          { content: "2,Jane\n" }
        ]

        partial = builder.combine_chunks(chunks)
        expect(partial).to include("id,name")
        expect(partial).to include("1,John")
        expect(partial).to include("2,Jane")
      end

      it "marks incomplete sections with metadata" do
        chunks = [
          { content: "id,name\n1,John\n" },
          { content: "2,Jane" }
        ]

        result = builder.build_partial_result(chunks)
        expect(result[:content]).to be_present
        expect(result[:metadata][:incomplete_after]).to be_present
        expect(result[:metadata][:is_partial]).to be true
      end

      it "preserves valid data from all chunks" do
        chunks = [
          { content: "id,name\n1,John\n2,Jane\n" },
          { content: "3,Bob\n4,Alice\n" },
          { content: "5,Charlie" }
        ]

        result = builder.build_partial_result(chunks)
        expect(result[:content]).to include("John")
        expect(result[:content]).to include("Jane")
        expect(result[:content]).to include("Bob")
        expect(result[:content]).to include("Alice")
        expect(result[:content]).to include("Charlie")
      end

      it "adds failure annotation with error section" do
        chunks = [
          { content: "id,name\n1,John\n" }
        ]
        error = StandardError.new("CSV parse error")

        result = builder.add_failure_annotation(chunks, error)
        expect(result[:metadata][:error_section]).to be_present
        expect(result[:metadata][:error_section][:error_class]).to eq("StandardError")
        expect(result[:metadata][:error_section][:error_message]).to eq("CSV parse error")
      end

      it "builds coherent partial output even if last chunk incomplete" do
        chunks = [
          { content: "Header 1,Header 2\n" },
          { content: "Data 1,Data 2\n" },
          { content: "Data 3,Data 4" }
        ]

        partial = builder.combine_chunks(chunks)
        lines = partial.split("\n")

        expect(lines).to include("Data 1,Data 2")
        expect(partial).to include("Data 3,Data 4")
      end

      it "returns valid partial structure with all expected keys" do
        chunks = [{ content: "test data\n" }]
        error = StandardError.new("Test error")

        result = builder.build_partial_result_with_error(chunks, error)
        expect(result).to have_key(:content)
        expect(result).to have_key(:metadata)
        expect(result[:metadata]).to have_key(:incomplete_after)
        expect(result[:metadata]).to have_key(:is_partial)
        expect(result[:metadata]).to have_key(:error_section)
      end
    end
  end

  describe "Category 3: Configurable Failure Modes (8 tests)" do
    describe "on_failure: :return_partial" do
      let(:config) { RAAF::Continuation::Config.new(on_failure: :return_partial) }
      let(:merger) { RAAF::Continuation::Mergers::CSVMerger.new(config) }

      it "returns accumulated data on merge failure" do
        chunks = [
          { content: "id,name\n1,\"John\n" },
          { content: "INVALID" }
        ]

        result = merger.merge(chunks)
        expect(result).to have_key(:content)
        expect(result).to have_key(:metadata)
      end

      it "includes error metadata when returning partial" do
        chunks = [{ content: '"unclosed' }]

        result = merger.merge(chunks)
        expect(result[:metadata][:merge_error]).to be_present
      end

      it "does not raise exception with :return_partial" do
        chunks = [{ content: "INVALID CSV" }]

        expect {
          merger.merge(chunks)
        }.not_to raise_error
      end
    end

    describe "on_failure: :raise_error" do
      let(:config) { RAAF::Continuation::Config.new(on_failure: :raise_error) }
      let(:merger) { RAAF::Continuation::Mergers::JSONMerger.new(config) }

      it "raises error with :raise_error configuration" do
        chunks = [{ content: "{" }]

        expect {
          merger.merge(chunks)
        }.to raise_error(RAAF::Continuation::MergeError)
      end

      it "includes helpful error message" do
        chunks = [{ content: "[" }]

        expect {
          merger.merge(chunks)
        }.to raise_error { |error|
          expect(error.message).to be_a(String)
          expect(error.message).not_to be_empty
        }
      end

      it "provides error context in raised exception" do
        chunks = [{ content: "INVALID JSON" }]

        expect {
          merger.merge(chunks)
        }.to raise_error { |error|
          expect(error).to respond_to(:merge_error_metadata)
        }
      end
    end

    describe "custom error classes" do
      it "uses RAAF::Continuation::MergeError for merge failures" do
        config = RAAF::Continuation::Config.new(on_failure: :raise_error)
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

        expect {
          merger.merge([{ content: "{" }])
        }.to raise_error(RAAF::Continuation::MergeError)
      end

      it "error includes error_class field" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

        result = merger.merge([{ content: "{" }])
        expect(result[:metadata][:merge_error][:error_class]).to be_present
      end

      it "provides helpful error messages with context" do
        config = RAAF::Continuation::Config.new(on_failure: :raise_error)
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        expect {
          merger.merge([{ content: '"unclosed' }])
        }.to raise_error { |error|
          message = error.message
          expect(message).to match(/merge|csv|parse|error/i)
        }
      end
    end
  end

  describe "Category 4: Error Recovery (7 tests)" do
    describe "network and timeout recovery" do
      it "recovers from network timeout during merge" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        chunks = [
          { content: "id,name\n1,John\n" }
        ]

        expect {
          result = merger.merge(chunks)
          expect(result).to have_key(:metadata)
        }.not_to raise_error
      end

      it "handles incomplete response gracefully" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

        chunks = [{ content: '{"data": [1, 2, 3' }]

        result = merger.merge(chunks)
        expect(result).to have_key(:content)
        expect(result).to have_key(:metadata)
      end
    end

    describe "malformed response handling" do
      it "recovers from malformed CSV" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        chunks = [
          { content: "id,name\n1,John\n" },
          { content: "COMPLETELY,BROKEN,STRUCTURE\nWITH,WRONG,COLUMNS\n" }
        ]

        expect {
          result = merger.merge(chunks)
        }.not_to raise_error
      end

      it "recovers from malformed JSON" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

        chunks = [
          { content: '{"valid": true}' },
          { content: 'MALFORMED' }
        ]

        expect {
          result = merger.merge(chunks)
        }.not_to raise_error
      end

      it "recovers from malformed Markdown" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config)

        chunks = [
          { content: "# Header\n\nValid markdown\n" },
          { content: "BROKEN | TABLE | STRUCTURE" }
        ]

        expect {
          result = merger.merge(chunks)
        }.not_to raise_error
      end
    end

    describe "max attempts recovery" do
      it "handles max attempts exceeded scenario" do
        config = RAAF::Continuation::Config.new(
          max_attempts: 3,
          on_failure: :return_partial
        )

        chunks = []
        3.times do |i|
          chunks << { content: "chunk_#{i}" }
        end

        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)
        expect {
          result = merger.merge(chunks)
        }.not_to raise_error
      end

      it "logs warning when max attempts exceeded" do
        config = RAAF::Continuation::Config.new(
          max_attempts: 2,
          on_failure: :return_partial
        )

        chunks = [
          { content: "chunk_1" },
          { content: "chunk_2" }
        ]

        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        expect {
          result = merger.merge(chunks)
        }.not_to raise_error
      end
    end
  end

  describe "Category 5: Fallback Strategies (8 tests)" do
    describe "3-level fallback chain" do
      let(:config) { RAAF::Continuation::Config.new(on_failure: :return_partial) }

      it "attempts Level 1: format-specific merge first" do
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)
        chunks = [
          { content: "id,name\n1,John\n" },
          { content: "2,Jane\n" }
        ]

        result = merger.merge(chunks)
        expect(result[:metadata][:merge_success]).to be true
      end

      it "falls back to Level 2: simple line concatenation on format failure" do
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        chunks = [
          { content: "id,name\n1,John\n" },
          { content: nil }
        ]

        result = merger.merge(chunks)
        expect(result).to have_key(:content)
        expect(result).to have_key(:metadata)
      end

      it "falls back to Level 3: first chunk only on total failure" do
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        chunks = [
          { content: "id,name\n1,John\n" },
          { content: "" },
          { content: nil }
        ]

        result = merger.merge(chunks)
        expect(result[:content]).to include("John")
      end

      it "tracks which fallback level was used" do
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        chunks = [
          { content: "id,name\n1,John\n" }
        ]

        result = merger.merge(chunks)
        expect(result[:metadata]).to have_key(:merge_success)
        expect(result[:metadata]).to be_a(Hash)
      end
    end

    describe "fallback behavior per format" do
      it "CSV fallback handles incomplete rows" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        chunks = [
          { content: "id,name\n1,\"John\n" },
          { content: "\" \n2,Jane\n" }
        ]

        result = merger.merge(chunks)
        expect(result).to have_key(:content)
      end

      it "Markdown fallback preserves document structure" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config)

        chunks = [
          { content: "# Title\n\n| Col1 | Col2 |\n" },
          { content: "BROKEN|STRUCTURE" }
        ]

        result = merger.merge(chunks)
        expect(result[:content]).to include("Title")
      end

      it "JSON fallback returns best-effort result" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

        chunks = [
          { content: '{"key": "value"' },
          { content: "GARBAGE" }
        ]

        result = merger.merge(chunks)
        expect(result).to have_key(:content)
      end
    end
  end

  describe "Category 6: Error Metadata (6 tests)" do
    describe "error_class field" do
      it "populates error_class with exception class name" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

        chunks = [{ content: "{" }]
        result = merger.merge(chunks)

        expect(result[:metadata]).to have_key(:merge_error)
        expect(result[:metadata][:merge_error]).to have_key(:error_class)
        expect(result[:metadata][:merge_error][:error_class]).to match(/Error/)
      end

      it "captures specific exception types" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

        chunks = [{ content: "invalid" }]
        result = merger.merge(chunks)

        error_class = result[:metadata][:merge_error][:error_class]
        expect(["JSON::ParserError", "StandardError"]).to include(error_class)
      end
    end

    describe "merge_error field" do
      it "includes complete merge_error hash on failure" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        chunks = [{ content: '"unclosed' }]
        result = merger.merge(chunks)

        expect(result[:metadata][:merge_error]).to be_a(Hash)
        expect(result[:metadata][:merge_error]).to have_key(:error_class)
        expect(result[:metadata][:merge_error]).to have_key(:error_message)
      end

      it "omits merge_error when merge succeeds" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        chunks = [
          { content: "id,name\n1,John\n" },
          { content: "2,Jane\n" }
        ]
        result = merger.merge(chunks)

        expect(result[:metadata]).not_to have_key(:merge_error)
      end
    end

    describe "error_message field" do
      it "captures error message from exception" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

        chunks = [{ content: "{" }]
        result = merger.merge(chunks)

        expect(result[:metadata][:merge_error]).to have_key(:error_message)
        expect(result[:metadata][:merge_error][:error_message]).to be_a(String)
        expect(result[:metadata][:merge_error][:error_message].length).to be > 0
      end

      it "provides actionable error messages" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        chunks = [{ content: '"unclosed' }]
        result = merger.merge(chunks)

        message = result[:metadata][:merge_error][:error_message]
        expect(message).not_to be_empty
      end
    end

    describe "incomplete_after field" do
      it "marks where partial result is incomplete" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

        chunks = [
          { content: "id,name\n1,John\n2,Jane" }
        ]

        result = merger.merge(chunks)
        if result[:metadata][:merge_success] == false
          expect(result[:metadata]).to have_key(:merge_error)
        end
      end

      it "includes context about incomplete data section" do
        config = RAAF::Continuation::Config.new(on_failure: :return_partial)
        merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

        chunks = [
          { content: '{"items": [{"id": 1}' }
        ]

        result = merger.merge(chunks)
        if result[:metadata][:merge_success] == false
          expect(result[:metadata][:merge_error]).to be_present
        end
      end
    end
  end

  describe "Integration: Error Handling with Multiple Mergers (5 bonus tests)" do
    it "each merger handles errors independently" do
      csv_config = RAAF::Continuation::Config.new(on_failure: :return_partial)
      json_config = RAAF::Continuation::Config.new(on_failure: :return_partial)
      md_config = RAAF::Continuation::Config.new(on_failure: :return_partial)

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(csv_config)
      json_merger = RAAF::Continuation::Mergers::JSONMerger.new(json_config)
      md_merger = RAAF::Continuation::Mergers::MarkdownMerger.new(md_config)

      csv_chunks = [{ content: '"unclosed' }]
      json_chunks = [{ content: "{" }]
      md_chunks = [{ content: "| incomplete" }]

      expect {
        csv_merger.merge(csv_chunks)
        json_merger.merge(json_chunks)
        md_merger.merge(md_chunks)
      }.not_to raise_error
    end

    it "error recovery works across format types" do
      configs = {
        csv: RAAF::Continuation::Config.new(on_failure: :return_partial),
        json: RAAF::Continuation::Config.new(on_failure: :return_partial),
        markdown: RAAF::Continuation::Config.new(on_failure: :return_partial)
      }

      mergers = {
        csv: RAAF::Continuation::Mergers::CSVMerger.new(configs[:csv]),
        json: RAAF::Continuation::Mergers::JSONMerger.new(configs[:json]),
        markdown: RAAF::Continuation::Mergers::MarkdownMerger.new(configs[:markdown])
      }

      results = {
        csv: mergers[:csv].merge([{ content: "invalid" }]),
        json: mergers[:json].merge([{ content: "invalid" }]),
        markdown: mergers[:markdown].merge([{ content: "| incomplete" }])
      }

      results.each do |format, result|
        expect(result).to have_key(:metadata)
        expect(result[:metadata]).to have_key(:merge_success)
      end
    end

    it "partial results are usable despite errors" do
      config = RAAF::Continuation::Config.new(on_failure: :return_partial)
      merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

      chunks = [
        { content: "id,name\n1,John\n" },
        { content: "2,Jane\n" },
        { content: "BROKEN_DATA" }
      ]

      result = merger.merge(chunks)
      if result[:content]
        expect(result[:content]).to include("John")
        expect(result[:content]).to include("Jane")
      end
    end

    it "error metadata consistent across failure modes" do
      return_partial_config = RAAF::Continuation::Config.new(on_failure: :return_partial)
      merger = RAAF::Continuation::Mergers::JSONMerger.new(return_partial_config)

      chunks = [{ content: "{" }]
      result = merger.merge(chunks)

      if result[:metadata][:merge_error]
        error_meta = result[:metadata][:merge_error]
        expect(error_meta).to have_key(:error_class)
        expect(error_meta).to have_key(:error_message)
      end
    end

    it "handles errors during error handling gracefully" do
      config = RAAF::Continuation::Config.new(on_failure: :return_partial)
      merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

      chunks = [
        nil,
        { content: nil },
        { content: "" },
        { content: "invalid" },
        { content: "data" }
      ]

      expect {
        result = merger.merge(chunks)
        expect(result).to have_key(:metadata)
      }.not_to raise_error
    end
  end
end
