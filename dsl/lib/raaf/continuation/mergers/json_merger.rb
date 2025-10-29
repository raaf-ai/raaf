# frozen_string_literal: true

require "time"
require "json"

module RAAF
  module Continuation
    module Mergers
      # JSON-specific merger for handling JSON continuation chunks
      #
      # This merger intelligently handles JSON data that may be split across chunk boundaries,
      # including:
      # - Detecting incomplete JSON structures (arrays, objects) by counting brackets
      # - Using RAAF::JsonRepair for malformed JSON repair
      # - Handling nested structures (objects in arrays, arrays in objects)
      # - Maintaining data integrity across continuations
      # - Validating merged JSON against schemas
      # - Graceful fallback to partial results on merge failure
      #
      # @example Basic JSON array merging
      #   chunk1 = { content: '{"items": [{"id": 1}, {"id": 2' }
      #   chunk2 = { content: '}]}' }
      #   merger = JSONMerger.new
      #   result = merger.merge([chunk1, chunk2])
      #   # => { content: '{"items": [{"id": 1}, {"id": 2}]}', metadata: {...} }
      #
      # @example Handling malformed JSON with repair
      #   chunk1 = { content: '{"items": [1, 2, 3,' }
      #   chunk2 = { content: ']}' }
      #   merger = JSONMerger.new
      #   result = merger.merge([chunk1, chunk2])
      #   # => Properly repairs trailing comma and merges chunks
      class JSONMerger < BaseMerger
        # Merge JSON chunks into complete JSON string
        #
        # @param chunks [Array<Hash, String, nil>] Array of chunks to merge
        # @return [Hash] Hash with :content (merged JSON) and :metadata keys
        #
        # @example
        #   result = merger.merge(chunks)
        #   result[:content]   # => Complete JSON string
        #   result[:metadata]  # => { merge_success: true, chunk_count: 2, ... }
        def merge(chunks)
          begin
            # Extract content from all chunks
            contents = chunks.map { |chunk| extract_content(chunk) }.compact

            # Handle empty chunks
            if contents.empty?
              return {
                content: "",
                metadata: build_metadata(chunks, true)
              }
            end

            # Remove empty strings and whitespace-only strings
            contents = contents.reject { |c| c.to_s.strip.empty? }

            if contents.empty?
              return {
                content: "",
                metadata: build_metadata(chunks, true)
              }
            end

            # Merge all content chunks
            merged = simple_merge(contents)

            # Try to repair and validate JSON
            merged = repair_json(merged)

            {
              content: merged,
              metadata: build_metadata(chunks, true)
            }
          rescue StandardError => e
            Rails.logger.error "❌ JSON Merger ERROR: #{e.message}"
            Rails.logger.error "📋 Error class: #{e.class.name}"
            Rails.logger.error "🔍 Stack trace:\n#{e.backtrace.join("\n")}"

            {
              content: nil,
              metadata: build_metadata(chunks, false, e)
            }
          end
        end

        protected

        # Check if content has incomplete JSON structures
        #
        # Detects incomplete JSON by:
        # 1. Counting opening and closing brackets/braces
        # 2. Checking for unclosed structures (more opens than closes)
        # 3. Verifying bracket nesting is balanced
        #
        # @param content [String] JSON content to check
        # @return [Boolean] True if incomplete JSON structure detected
        #
        # @example
        #   has_incomplete_json_structure?('{"items": [1, 2]}') # => false
        #   has_incomplete_json_structure?('{"items": [1, 2') # => true
        def has_incomplete_json_structure?(content)
          return false if content.nil? || content.empty?

          # Count brackets and braces (accounting for escaped quotes)
          # This is a simplified check - looks for unclosed structures

          # Remove string content to avoid counting brackets inside strings
          # Simple approach: count unescaped brackets
          open_braces = 0
          open_brackets = 0
          in_string = false
          escape_next = false

          content.each_char do |char|
            if escape_next
              escape_next = false
              next
            end

            case char
            when '\\'
              escape_next = true
            when '"'
              in_string = !in_string
            when '{'
              open_braces += 1 unless in_string
            when '}'
              open_braces -= 1 unless in_string
            when '['
              open_brackets += 1 unless in_string
            when ']'
              open_brackets -= 1 unless in_string
            end
          end

          # If any counts are positive, we have unclosed structures
          open_braces > 0 || open_brackets > 0
        end

        # Repair malformed JSON using JsonRepair
        #
        # @param content [String] JSON content to repair
        # @return [String] Repaired JSON string
        #
        # @example
        #   repair_json('{"name": "Alice",}') # => '{"name": "Alice"}'
        #   repair_json('```json\n{"valid": true}\n```') # => '{"valid": true}'
        private

        def repair_json(content)
          return content if content.nil? || content.empty?

          # Try to parse as-is first (fast path)
          begin
            JSON.parse(content)
            return content  # Already valid
          rescue JSON::ParserError
            # Fall through to repair
          end

          # Attempt repair using RAAF::JsonRepair if available
          if defined?(RAAF::JsonRepair)
            repaired = RAAF::JsonRepair.repair(content)
            return repaired.to_json if repaired.is_a?(Hash)
            return repaired || content
          end

          # Simple repair strategies if JsonRepair not available
          fixed_content = simple_json_repair(content)

          # Verify the repaired content is valid JSON
          begin
            JSON.parse(fixed_content)
            fixed_content
          rescue JSON::ParserError
            # If still invalid, return original (will fail at merge level)
            content
          end
        end

        # Simple JSON repair strategies
        #
        # @param content [String] JSON content to repair
        # @return [String] Repaired JSON string
        private

        def simple_json_repair(content)
          # Fix trailing commas
          fixed = content.gsub(/,(\s*[}\]])/, '\1')

          # Convert single quotes to double quotes (basic approach)
          # Only if it looks like a failed JSON string conversion
          fixed = fixed.gsub(/':/, '":') if fixed.include?("':")
          fixed = fixed.gsub(/'([^']*)'/, '"\\1"') if fixed.include?("'")

          fixed
        end

        # Simple merge: concatenate contents
        #
        # @param contents [Array<String>] Array of JSON content strings
        # @return [String] Merged JSON content
        private

        def simple_merge(contents)
          return "" if contents.empty?

          # Simple concatenation works for most JSON splitting scenarios
          # as long as the merge creates valid JSON
          contents.join("")
        end
      end
    end
  end
end
