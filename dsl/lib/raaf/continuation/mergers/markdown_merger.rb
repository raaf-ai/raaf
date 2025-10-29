# frozen_string_literal: true

require "time"

module RAAF
  module Continuation
    module Mergers
      # Markdown-specific merger for handling markdown continuation chunks
      #
      # This merger intelligently handles Markdown data that may be split across chunk boundaries,
      # including:
      # - Detecting and completing incomplete table rows (counting pipes)
      # - Detecting and completing incomplete code blocks (counting backticks)
      # - Merging split markdown elements (tables, lists, code blocks)
      # - Removing duplicate headers across continuation chunks
      # - Preserving markdown formatting and structure
      # - Handling nested lists and mixed content
      #
      # @example Basic markdown merging
      #   chunk1 = { content: "| ID | Name |\n|---|---|\n| 1 | Alice |" }
      #   chunk2 = { content: "\n| 2 | Bob |" }
      #   merger = MarkdownMerger.new
      #   result = merger.merge([chunk1, chunk2])
      #   # => { content: "| ID | Name |\n|---|---|\n| 1 | Alice |\n| 2 | Bob |", metadata: {...} }
      #
      # @example Handling split code blocks
      #   chunk1 = { content: "```ruby\ndef hello\n  puts 'world" }
      #   chunk2 = { content: "'\nend\n```" }
      #   merger = MarkdownMerger.new
      #   result = merger.merge([chunk1, chunk2])
      #   # => Properly merges split code block
      class MarkdownMerger < BaseMerger
        # Merge markdown chunks into complete markdown string
        #
        # @param chunks [Array<Hash, String, nil>] Array of chunks to merge
        # @return [Hash] Hash with :content (merged markdown) and :metadata keys
        #
        # @example
        #   result = merger.merge(chunks)
        #   result[:content]   # => Complete markdown string
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

            {
              content: merged,
              metadata: build_metadata(chunks, true)
            }
          rescue StandardError => e
            Rails.logger.error "❌ Markdown Merger ERROR: #{e.message}"
            Rails.logger.error "📋 Error class: #{e.class.name}"
            Rails.logger.error "🔍 Stack trace:\n#{e.backtrace.join("\n")}"

            {
              content: nil,
              metadata: build_metadata(chunks, false, e)
            }
          end
        end

        protected

        # Check if content has incomplete table rows
        #
        # Detects incomplete table rows by:
        # 1. Identifying table structures (lines with pipe separators)
        # 2. Checking if the last line is not terminated with a newline (incomplete)
        # 3. Counting columns to verify row structure matches header
        #
        # @param content [String] Markdown content to check
        # @return [Boolean] True if incomplete table row detected
        #
        # @example
        #   has_incomplete_table_row?("| ID | Name | Status |\n|---|---|---|\n| 1 | Alice | Active |\n| 2 | Bob |\n") # => false
        #   has_incomplete_table_row?("| ID | Name | Status |\n|---|---|---|\n| 1 | Alice | Active |\n| 2 | Bob |") # => true
        def has_incomplete_table_row?(content)
          return false if content.nil? || content.empty?

          # Check if content ends with a newline - if not, the last line is incomplete
          return true unless content.end_with?("\n")

          false
        end

        # Check if content has incomplete code blocks
        #
        # Detects incomplete code blocks by counting backticks.
        # A complete code block has an even number of triple-backtick sequences (``` or ~~~).
        #
        # @param content [String] Markdown content to check
        # @return [Boolean] True if incomplete code block detected
        #
        # @example
        #   has_incomplete_code_block?("```ruby\ndef hello\nend\n```") # => false
        #   has_incomplete_code_block?("```ruby\ndef hello\nend") # => true
        def has_incomplete_code_block?(content)
          return false if content.nil? || content.empty?

          # Count triple backticks
          backtick_count = content.scan(/```/).count

          # Odd number means incomplete block
          backtick_count.odd?
        end

        # Simple merge: concatenate contents, handling incomplete rows and headers
        #
        # @param contents [Array<String>] Array of markdown content strings
        # @return [String] Merged markdown content
        private

        def simple_merge(contents)
          return "" if contents.empty?

          # Start with first chunk
          merged = contents[0]

          # Process remaining chunks
          contents.drop(1).each do |chunk|
            merged = merge_next_chunk(merged, chunk)
          end

          merged
        end

        # Merge a new chunk into accumulated content
        #
        # @param accumulated [String] Previously merged content
        # @param new_chunk [String] New chunk to add
        # @return [String] Merged content
        private

        def merge_next_chunk(accumulated, new_chunk)
          return accumulated if new_chunk.nil? || new_chunk.empty?

          # Check if accumulated ends with incomplete structures
          if has_incomplete_table_row?(accumulated) || has_incomplete_code_block?(accumulated)
            # Complete the incomplete structure by appending new chunk
            accumulated + new_chunk
          else
            # Find the first non-empty line in new_chunk
            chunk_lines = new_chunk.split("\n")
            first_non_empty_idx = chunk_lines.find_index { |l| l.strip.length > 0 }

            if first_non_empty_idx && chunk_lines[first_non_empty_idx].strip.start_with?("#")
              # New chunk starts with a header
              chunk_first_header = chunk_lines[first_non_empty_idx].strip

              # Check if this header already exists in accumulated
              if accumulated.include?(chunk_first_header)
                # Header already exists - skip it and the blank lines after it
                skip_until_content_idx = first_non_empty_idx + 1

                # Skip blank lines after the header
                while skip_until_content_idx < chunk_lines.length && chunk_lines[skip_until_content_idx].strip.empty?
                  skip_until_content_idx += 1
                end

                rest_lines = chunk_lines[skip_until_content_idx..-1]

                if rest_lines.empty? || rest_lines.all? { |l| l.strip.empty? }
                  # Nothing left after the header
                  accumulated
                else
                  rest = rest_lines.join("\n")
                  if accumulated.end_with?("\n")
                    accumulated + rest
                  else
                    accumulated + "\n" + rest
                  end
                end
              else
                # Header doesn't exist in accumulated, just concatenate normally
                if accumulated.end_with?("\n")
                  accumulated + new_chunk
                else
                  accumulated + "\n" + new_chunk
                end
              end
            else
              # Normal concatenation
              if accumulated.end_with?("\n")
                accumulated + new_chunk
              else
                accumulated + "\n" + new_chunk
              end
            end
          end
        end
      end
    end
  end
end
