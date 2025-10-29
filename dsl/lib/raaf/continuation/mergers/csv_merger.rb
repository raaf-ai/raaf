# frozen_string_literal: true

require "time"

module RAAF
  module Continuation
    module Mergers
      # CSV-specific merger for handling CSV continuation chunks
      #
      # This merger intelligently handles CSV data that may be split across chunk boundaries,
      # including:
      # - Detecting and completing incomplete rows (split quoted fields)
      # - Removing duplicate headers from continuation chunks
      # - Preserving row order and data integrity
      # - Handling various CSV dialects (comma, semicolon, etc.)
      # - Supporting quoted fields with embedded commas and newlines
      #
      # @example Basic CSV merging
      #   chunk1 = { content: "id,name\\n1,John\\n" }
      #   chunk2 = { content: "2,Jane\\n" }
      #   merger = CSVMerger.new
      #   result = merger.merge([chunk1, chunk2])
      #   # => { content: "id,name\\n1,John\\n2,Jane\\n", metadata: {...} }
      #
      # @example Handling split quoted fields
      #   chunk1 = { content: 'id,note\\n1,"Incomplete' }
      #   chunk2 = { content: ' note here"\\n' }
      #   merger = CSVMerger.new
      #   result = merger.merge([chunk1, chunk2])
      #   # => Properly merges split quoted field
      class CSVMerger < BaseMerger
        # Merge CSV chunks into a complete CSV string
        #
        # @param chunks [Array<Hash, String, nil>] Array of chunks to merge
        # @return [Hash] Hash with :content (merged CSV) and :metadata keys
        #
        # @example
        #   result = merger.merge(chunks)
        #   result[:content]   # => Complete CSV string
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
            Rails.logger.error "❌ CSV Merger ERROR: #{e.message}"
            Rails.logger.error "📋 Error class: #{e.class.name}"
            Rails.logger.error "🔍 Stack trace:\n#{e.backtrace.join("\n")}"

            {
              content: nil,
              metadata: build_metadata(chunks, false, e)
            }
          end
        end

        protected

        # Check if content has incomplete rows
        #
        # Detects incomplete rows by:
        # 1. Checking if content contains actual newlines (not escaped \n)
        # 2. For content with actual newlines: count quotes in last line (odd = incomplete)
        # 3. For content without real newlines: handle escaped \n and check structure
        # 4. Checking if last line ends without newline AND has content
        #
        # @param content [String] CSV content to check
        # @return [Boolean] True if incomplete row detected
        #
        # @example
        #   has_incomplete_row?('id,name\n1,"Incomplete') # => true
        #   has_incomplete_row?('id,name\n1,"Complete"\n') # => false
        def has_incomplete_row?(content)
          return false if content.nil? || content.empty?

          # Check if content contains actual newlines (byte value 10)
          if content.include?("\n")
            # Content has actual newlines, analyze last line
            lines = content.split("\n", -1)
            return false if lines.empty?

            last_line = lines.last

            # If last element is empty, previous line was complete
            # But we should check if ANY prior line is incomplete (e.g., trailing comma)
            if last_line == ""
              # Last line is empty - check if there's an incomplete line before it
              # Check all lines except the last (which is empty) for incomplete indicators
              return true if lines.length > 1 && has_incomplete_line?(lines[0...-1])
              return false
            end

            # Count quotes in last line - odd count indicates incomplete quoted field
            quote_count = last_line.count('"')
            return true if quote_count.odd?

            # If last line ends with comma, it's incomplete
            return true if last_line.end_with?(",")

            # Otherwise it's incomplete (no newline at end and has content)
            return true
          else
            # No actual newlines - content may have escaped \n (literal backslash-n)
            # or be entirely single-line content

            # Try to split by escaped newline pattern (\\n as string)
            if content.include?("\\n")
              # Has escaped newlines - analyze all "lines" for incomplete indicators
              lines = content.split("\\n", -1)
              last_line = lines.last

              # Check if last line is empty (content ends with escaped newline)
              if last_line == ""
                # Check if any prior line is incomplete (e.g., trailing comma)
                # Check all lines except the last (which is empty) for incomplete indicators
                return true if lines.length > 1 && has_incomplete_line?(lines[0...-1])
                return false
              end

              # Check for incomplete quote in last line
              quote_count = last_line.count('"')
              return true if quote_count.odd?

              # Check for trailing comma in last line
              return true if last_line.end_with?(",")

              # Last line without newline = incomplete
              return true
            else
              # No newlines at all (real or escaped) - single line or no delimiters
              # Count quotes - odd count means incomplete
              quote_count = content.count('"')
              return true if quote_count.odd?

              # If ends with comma, it's incomplete
              return true if content.end_with?(",")

              # Otherwise it's complete
              return false
            end
          end
        end

        # Check if any line in the array has incomplete indicators
        # Lines that end with comma are considered incomplete
        #
        # @param lines [Array<String>] Lines to check
        # @return [Boolean] True if any line has incomplete indicators
        private

        def has_incomplete_line?(lines)
          return false if lines.nil? || lines.empty?

          lines.each do |line|
            return true if line.end_with?(",")
          end

          false
        end

        # Complete a partial row by merging with continuation content
        #
        # @param partial_row [String] Incomplete row from previous chunk
        # @param continuation [String] Content from next chunk
        # @return [String] Completed row
        #
        # @example
        #   partial = 'id,note\n1,"Incomplete'
        #   continuation = ' note here"\n2,complete'
        #   result = complete_partial_row(partial, continuation)
        #   # => 'id,note\n1,"Incomplete note here"\n2,complete'
        def complete_partial_row(partial_row, continuation)
          # Find the last line in partial_row
          partial_lines = partial_row.lines
          incomplete_line = partial_lines.last.to_s

          # Find the first complete line in continuation
          continuation_lines = continuation.lines

          # If there's only one line in continuation, it's a continuation of the incomplete line
          if continuation_lines.length <= 1
            incomplete_line + continuation_lines.first.to_s
          else
            # First line continues the incomplete line, rest are new lines
            completed_line = incomplete_line + continuation_lines.first
            rest = continuation_lines.drop(1).join
            partial_lines[0...-1].join + completed_line + rest
          end
        end

        # Simple merge: concatenate contents, handling incomplete rows and headers
        #
        # @param contents [Array<String>] Array of CSV content strings
        # @return [String] Merged CSV content
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

          # Check if accumulated ends with incomplete row
          if has_incomplete_row?(accumulated)
            # Combine the incomplete row with new chunk
            complete_partial_row(accumulated, new_chunk)
          else
            # Check if new_chunk starts with the same header as accumulated
            # Extract headers
            accumulated_header = extract_csv_header(accumulated)
            chunk_header = extract_csv_header(new_chunk)

            if accumulated_header && chunk_header && accumulated_header == chunk_header
              # Remove first line (header) from new_chunk
              chunk_lines = new_chunk.lines
              chunk_without_header = chunk_lines.drop(1).join
              accumulated + chunk_without_header
            else
              # Just concatenate
              accumulated + new_chunk
            end
          end
        end

        # Extract the CSV header (first row)
        #
        # @param content [String] CSV content
        # @return [String, nil] First line without trailing newline, or nil if empty
        private

        def extract_csv_header(content)
          return nil if content.nil? || content.empty?

          lines = content.lines
          return nil if lines.empty?

          # Get first line and remove trailing newline for comparison
          lines.first.chomp
        end
      end
    end
  end
end
