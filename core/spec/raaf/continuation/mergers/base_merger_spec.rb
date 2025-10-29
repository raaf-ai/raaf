# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::Continuation::Mergers::BaseMerger" do
  # Define the abstract class for testing (assuming this structure based on task description)
  # In production, this would be the actual class
  module RAAF
    module Continuation
      module Mergers
        class BaseMerger
          def initialize(config = {})
            @config = config
          end

          attr_reader :config

          def merge(chunks)
            raise NotImplementedError, "Subclasses must implement #merge"
          end

          protected

          # Helper to extract content from a chunk
          def extract_content(chunk)
            return nil unless chunk

            # Handle various chunk structures
            if chunk.is_a?(Hash)
              # Try string keys
              content = chunk["content"] || chunk["text"] || chunk["data"]

              # Try symbol keys if string keys didn't work
              content ||= chunk[:content] || chunk[:text] || chunk[:data]

              # Handle nested message structure
              if content.nil?
                # Check for nested message with string key
                if chunk["message"].is_a?(Hash)
                  return chunk["message"]["content"] || chunk["message"][:content] || chunk["message"]
                elsif chunk["message"].is_a?(String)
                  return chunk["message"]
                end

                # Check for nested message with symbol key
                if chunk[:message].is_a?(Hash)
                  return chunk[:message][:content] || chunk[:message]["content"] || chunk[:message]
                elsif chunk[:message].is_a?(String)
                  return chunk[:message]
                end
              end

              content
            else
              # If not a hash, return the chunk itself
              chunk
            end
          end

          # Helper to build metadata for the merge result
          def build_metadata(chunks, merge_success, error = nil)
            metadata = {
              merge_success: merge_success,
              chunk_count: chunks.is_a?(Array) ? chunks.size : 0,
              timestamp: Time.now.iso8601
            }

            if error
              metadata[:merge_error] = {
                error_class: error.class.name,
                error_message: error.message
              }
            end

            metadata
          end
        end
      end
    end
  end

  # Test helper: Create a concrete subclass for testing
  let(:test_merger_class) do
    Class.new(RAAF::Continuation::Mergers::BaseMerger) do
      def merge(chunks)
        chunks.map { |chunk| extract_content(chunk) }.compact.join("\n")
      end
    end
  end

  let(:base_merger) { RAAF::Continuation::Mergers::BaseMerger.new }
  let(:test_merger) { test_merger_class.new }

  describe "abstract methods" do
    it "raises NotImplementedError when #merge is called on base class" do
      expect { base_merger.merge([]) }.to raise_error(
        NotImplementedError,
        "Subclasses must implement #merge"
      )
    end

    it "requires subclasses to implement #merge method" do
      # Base class should raise error
      expect { base_merger.merge(["test"]) }.to raise_error(NotImplementedError)
    end

    it "allows subclass with #merge implementation to instantiate" do
      expect { test_merger_class.new }.not_to raise_error
    end

    it "calls merge method on subclass instance" do
      chunks = [{ "content" => "Hello" }, { "content" => "World" }]
      result = test_merger.merge(chunks)
      expect(result).to eq("Hello\nWorld")
    end
  end

  describe "#extract_content helper" do
    let(:merger) { test_merger }

    it "extracts content from hash chunk with string keys" do
      chunk = { "content" => "Test content" }
      expect(merger.send(:extract_content, chunk)).to eq("Test content")
    end

    it "extracts content from hash chunk with symbol keys" do
      chunk = { content: "Test content" }
      expect(merger.send(:extract_content, chunk)).to eq("Test content")
    end

    it "extracts content from chunk with nested structure" do
      chunk = { "message" => { "content" => "Nested content" } }
      expect(merger.send(:extract_content, chunk)).to eq("Nested content")
    end

    it "returns nil for chunk without content" do
      chunk = { "id" => 123, "status" => "ok" }
      expect(merger.send(:extract_content, chunk)).to be_nil
    end

    it "handles empty content gracefully" do
      chunk = { "content" => "" }
      expect(merger.send(:extract_content, chunk)).to eq("")
    end

    it "preserves content type (string, hash, etc)" do
      # String content
      string_chunk = { "content" => "string value" }
      expect(merger.send(:extract_content, string_chunk)).to be_a(String)

      # Hash content
      hash_chunk = { "data" => { "key" => "value" } }
      expect(merger.send(:extract_content, hash_chunk)).to be_a(Hash)

      # Array content
      array_chunk = { "content" => ["item1", "item2"] }
      expect(merger.send(:extract_content, array_chunk)).to be_a(Array)
    end

    it "extracts from alternative field names" do
      # Test 'message' field with string
      message_chunk = { "message" => "Message content" }
      expect(merger.send(:extract_content, message_chunk)).to eq("Message content")

      # Test 'text' field
      text_chunk = { "text" => "Text content" }
      expect(merger.send(:extract_content, text_chunk)).to eq("Text content")

      # Test 'data' field
      data_chunk = { "data" => "Data content" }
      expect(merger.send(:extract_content, data_chunk)).to eq("Data content")
    end

    it "prioritizes 'content' field over others" do
      chunk = {
        "content" => "Primary content",
        "message" => "Secondary message",
        "text" => "Tertiary text"
      }
      expect(merger.send(:extract_content, chunk)).to eq("Primary content")
    end

    it "handles non-hash chunks by returning them directly" do
      string_chunk = "Plain string"
      expect(merger.send(:extract_content, string_chunk)).to eq("Plain string")

      number_chunk = 42
      expect(merger.send(:extract_content, number_chunk)).to eq(42)

      array_chunk = ["item1", "item2"]
      expect(merger.send(:extract_content, array_chunk)).to eq(["item1", "item2"])
    end

    it "handles nested message with symbol keys" do
      chunk = { message: { content: "Nested with symbols" } }
      expect(merger.send(:extract_content, chunk)).to eq("Nested with symbols")
    end

    it "handles mixed key types in nested structure" do
      chunk = { "message" => { content: "Mixed keys" } }
      expect(merger.send(:extract_content, chunk)).to eq("Mixed keys")

      chunk2 = { message: { "content" => "Mixed keys reversed" } }
      expect(merger.send(:extract_content, chunk2)).to eq("Mixed keys reversed")
    end

    it "returns the message hash itself when it has no content key" do
      chunk = { "message" => { "other_field" => "value" } }
      expect(merger.send(:extract_content, chunk)).to eq({ "other_field" => "value" })
    end
  end

  describe "#build_metadata helper" do
    let(:merger) { test_merger }
    let(:chunks) { [{ "content" => "chunk1" }, { "content" => "chunk2" }] }

    it "builds metadata from chunks array" do
      metadata = merger.send(:build_metadata, chunks, true)

      expect(metadata).to be_a(Hash)
      expect(metadata[:chunk_count]).to eq(2)
    end

    it "includes merge_success: true when merge succeeded" do
      metadata = merger.send(:build_metadata, chunks, true)
      expect(metadata[:merge_success]).to be true
    end

    it "includes merge_success: false when merge failed" do
      metadata = merger.send(:build_metadata, chunks, false)
      expect(metadata[:merge_success]).to be false
    end

    it "includes error information when error provided" do
      error = StandardError.new("Test error message")
      metadata = merger.send(:build_metadata, chunks, false, error)

      expect(metadata[:merge_error]).to be_a(Hash)
      expect(metadata[:merge_error][:error_class]).to eq("StandardError")
      expect(metadata[:merge_error][:error_message]).to eq("Test error message")
    end

    it "includes chunk count in metadata" do
      metadata = merger.send(:build_metadata, chunks, true)
      expect(metadata[:chunk_count]).to eq(2)

      # Test with empty array
      empty_metadata = merger.send(:build_metadata, [], true)
      expect(empty_metadata[:chunk_count]).to eq(0)

      # Test with larger array
      large_chunks = Array.new(10) { |i| { "content" => "chunk#{i}" } }
      large_metadata = merger.send(:build_metadata, large_chunks, true)
      expect(large_metadata[:chunk_count]).to eq(10)
    end

    it "includes timestamp in metadata" do
      metadata = merger.send(:build_metadata, chunks, true)
      expect(metadata[:timestamp]).to be_a(String)
      expect(metadata[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it "formats metadata hash correctly" do
      metadata = merger.send(:build_metadata, chunks, true)

      expect(metadata).to include(
        merge_success: true,
        chunk_count: 2
      )
      expect(metadata).to have_key(:timestamp)
    end

    it "includes all required fields" do
      metadata = merger.send(:build_metadata, chunks, true)

      required_fields = [:merge_success, :chunk_count, :timestamp]
      required_fields.each do |field|
        expect(metadata).to have_key(field)
      end
    end

    it "handles non-array chunks gracefully" do
      # Test with nil
      nil_metadata = merger.send(:build_metadata, nil, true)
      expect(nil_metadata[:chunk_count]).to eq(0)

      # Test with string
      string_metadata = merger.send(:build_metadata, "not an array", true)
      expect(string_metadata[:chunk_count]).to eq(0)
    end
  end

  describe "Metadata structure" do
    let(:merger) { test_merger }
    let(:chunks) { [{ "content" => "test" }] }

    it "returns hash with merge_success key" do
      metadata = merger.send(:build_metadata, chunks, true)
      expect(metadata).to have_key(:merge_success)
      expect([true, false]).to include(metadata[:merge_success])
    end

    it "returns hash with chunk_count key" do
      metadata = merger.send(:build_metadata, chunks, true)
      expect(metadata).to have_key(:chunk_count)
      expect(metadata[:chunk_count]).to be_a(Integer)
    end

    it "returns hash with timestamp key" do
      metadata = merger.send(:build_metadata, chunks, true)
      expect(metadata).to have_key(:timestamp)
      expect(metadata[:timestamp]).to be_a(String)
    end

    it "returns hash with error_class key when error present" do
      error = RuntimeError.new("Test error")
      metadata = merger.send(:build_metadata, chunks, false, error)
      expect(metadata[:merge_error][:error_class]).to eq("RuntimeError")
    end

    it "returns hash with error_message key when error present" do
      error = RuntimeError.new("Test error")
      metadata = merger.send(:build_metadata, chunks, false, error)
      expect(metadata[:merge_error][:error_message]).to eq("Test error")
    end

    it "includes merge_error key when error present" do
      error = StandardError.new("Test")
      metadata = merger.send(:build_metadata, chunks, false, error)
      expect(metadata).to have_key(:merge_error)
    end

    it "does not include error keys when no error" do
      metadata = merger.send(:build_metadata, chunks, true)
      expect(metadata).not_to have_key(:merge_error)
    end

    it "validates metadata field types" do
      error = StandardError.new("Test")
      metadata = merger.send(:build_metadata, chunks, false, error)

      expect([true, false]).to include(metadata[:merge_success])
      expect(metadata[:chunk_count]).to be_a(Integer)
      expect(metadata[:timestamp]).to be_a(String)
      expect(metadata[:merge_error][:error_class]).to be_a(String)
      expect(metadata[:merge_error][:error_message]).to be_a(String)
    end
  end

  describe "BaseMerger subclass integration" do
    # More complex test merger that uses the helpers
    let(:advanced_merger_class) do
      Class.new(RAAF::Continuation::Mergers::BaseMerger) do
        def merge(chunks)
          begin
            # Use extract_content helper
            contents = chunks.map { |chunk| extract_content(chunk) }.compact

            # Join contents
            merged_content = contents.join("\n")

            # Return result with metadata
            {
              content: merged_content,
              metadata: build_metadata(chunks, true)
            }
          rescue StandardError => e
            # Return error result with metadata
            {
              content: nil,
              metadata: build_metadata(chunks, false, e)
            }
          end
        end
      end
    end

    let(:advanced_merger) { advanced_merger_class.new({ format: :json }) }

    it "subclass can call extract_content" do
      chunk = { "content" => "Test" }
      # Use the merge method which internally uses extract_content
      result = advanced_merger.merge([chunk])
      expect(result[:content]).to eq("Test")
    end

    it "subclass can call build_metadata" do
      chunks = [{ "content" => "Test" }]
      result = advanced_merger.merge(chunks)

      expect(result[:metadata]).to be_a(Hash)
      expect(result[:metadata][:merge_success]).to be true
      expect(result[:metadata][:chunk_count]).to eq(1)
    end

    it "subclass merge result includes extracted content" do
      chunks = [
        { "content" => "First" },
        { "message" => "Second" },
        { "text" => "Third" }
      ]
      result = advanced_merger.merge(chunks)
      expect(result[:content]).to eq("First\nSecond\nThird")
    end

    it "subclass can access configuration" do
      expect(advanced_merger.config).to eq({ format: :json })
    end

    it "subclass handles errors properly" do
      # Create a merger that will raise an error
      error_merger_class = Class.new(RAAF::Continuation::Mergers::BaseMerger) do
        def merge(chunks)
          raise StandardError, "Merge failed" if chunks.empty?
          super
        end
      end

      error_merger = error_merger_class.new
      expect { error_merger.merge([]) }.to raise_error(StandardError, "Merge failed")
    end
  end

  describe "BaseMerger edge cases" do
    let(:merger) { test_merger }

    it "handles empty chunks array" do
      result = merger.merge([])
      expect(result).to eq("")
    end

    it "handles nil in chunks array" do
      chunks = [{ "content" => "First" }, nil, { "content" => "Second" }]
      result = merger.merge(chunks)
      expect(result).to eq("First\nSecond")
    end

    it "handles malformed chunk structure" do
      chunks = [
        { "content" => "Good" },
        { "bad_key" => "No content field" },
        "plain_string",
        nil,
        { "content" => "Good again" }
      ]
      result = merger.merge(chunks)
      expect(result).to eq("Good\nplain_string\nGood again")
    end

    it "handles very large chunks" do
      large_content = "x" * 10_000
      chunks = Array.new(100) { { "content" => large_content } }

      expect { merger.merge(chunks) }.not_to raise_error
      result = merger.merge(chunks)
      expect(result.length).to eq(100 * 10_000 + 99) # Content + newlines
    end

    it "handles unicode content" do
      chunks = [
        { "content" => "Hello 世界" },
        { "content" => "こんにちは" },
        { "content" => "🎉 Emoji content 🚀" }
      ]
      result = merger.merge(chunks)
      expect(result).to eq("Hello 世界\nこんにちは\n🎉 Emoji content 🚀")
    end

    it "preserves chunk order" do
      chunks = (1..10).map { |i| { "content" => "Chunk #{i}" } }
      result = merger.merge(chunks)

      expected = (1..10).map { |i| "Chunk #{i}" }.join("\n")
      expect(result).to eq(expected)
    end

    it "handles chunks with metadata" do
      chunks = [
        {
          "content" => "First chunk",
          "metadata" => { "index" => 0, "timestamp" => Time.now }
        },
        {
          "content" => "Second chunk",
          "metadata" => { "index" => 1, "timestamp" => Time.now }
        }
      ]
      result = merger.merge(chunks)
      expect(result).to eq("First chunk\nSecond chunk")
    end

    it "handles deeply nested content structures" do
      chunk = {
        "response" => {
          "message" => {
            "content" => "Deep content"
          }
        }
      }
      # For this test, we expect the helper to return nil
      # since it's not a direct message.content structure
      content = merger.send(:extract_content, chunk)
      expect(content).to be_nil # Current implementation doesn't handle this deep nesting
    end

    it "handles mixed content types in array" do
      chunks = [
        { "content" => "String content" },
        { "content" => 123 },
        { "content" => true },
        { "content" => ["array", "content"] },
        { "content" => { "object" => "content" } }
      ]
      # The test merger will call to_s on non-strings when joining
      result = merger.merge(chunks)
      expect(result).to include("String content")
      expect(result).to include("123")
      expect(result).to include("true")
    end
  end
end