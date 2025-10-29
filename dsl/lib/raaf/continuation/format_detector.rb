# frozen_string_literal: true

module RAAF
  module Continuation
    # FormatDetector analyzes content to automatically detect the output format
    #
    # This class determines whether content is CSV, Markdown, or JSON format
    # by analyzing structural characteristics. It's used when continuation
    # support is configured with `output_format: :auto`.
    #
    # @example Detecting format from content
    #   detector = FormatDetector.new
    #
    #   csv_content = "id,name,email\n1,Alice,alice@example.com\n2,Bob,bob@example.com"
    #   format, confidence = detector.detect(csv_content)
    #   # => [:csv, 0.95]
    #
    #   markdown_content = "# Report\n\n| ID | Name |\n|---|---|\n| 1 | Alice |"
    #   format, confidence = detector.detect(markdown_content)
    #   # => [:markdown, 0.90]
    #
    #   json_content = '{"items": [{"id": 1, "name": "Alice"}]}'
    #   format, confidence = detector.detect(json_content)
    #   # => [:json, 0.98]
    class FormatDetector
      # Detect the format of the given content
      #
      # @param content [String] Content to analyze
      # @return [Array<Symbol, Float>] Format (:csv, :markdown, :json) and confidence (0.0-1.0)
      #
      # @example
      #   detector = FormatDetector.new
      #   format, confidence = detector.detect(some_content)
      #   # => [:csv, 0.85]
      def detect(content)
        return [:unknown, 0.0] if content.nil? || content.strip.empty?

        # Calculate scores for each format
        csv_score = calculate_csv_score(content)
        markdown_score = calculate_markdown_score(content)
        json_score = calculate_json_score(content)

        # Determine which format has the highest score
        scores = {
          csv: csv_score,
          markdown: markdown_score,
          json: json_score
        }

        detected_format = scores.max_by { |_format, score| score }
        format_symbol = detected_format[0]
        confidence = [detected_format[1], 1.0].min  # Clamp to 1.0

        # Only return if confidence is reasonable (> 0.3)
        confidence > 0.3 ? [format_symbol, confidence] : [:unknown, confidence]
      rescue StandardError => e
        Rails.logger.debug "FormatDetector error: #{e.message}"
        [:unknown, 0.0]
      end

      private

      # Calculate CSV format score
      #
      # @param content [String] Content to analyze
      # @return [Float] Format score (0.0-1.0)
      private

      def calculate_csv_score(content)
        score = 0.0

        # Check for pipe separators (strong indicator of NOT CSV)
        if content.include?("|")
          return score - 0.5  # Heavy penalty for pipes
        end

        lines = content.split("\n").reject { |l| l.strip.empty? }
        return score if lines.empty?

        # Check first line as potential header
        first_line = lines[0]
        if first_line.include?(",")
          score += 0.3
          score += 0.15
        end

        # Check for consistent column counts
        if lines.length > 2
          column_counts = lines.map { |line| count_csv_columns(line) }
          consistent = column_counts.uniq.length <= 2 # Allow 1-2 different counts for headers
          score += 0.4 if consistent
        end

        # Check for quoted fields (CSV indicator)
        if content.include?('"')
          score += 0.15
        end

        # Penalize if content looks like JSON or Markdown
        score -= 0.3 if content.include?("{") || content.include?("[")
        score -= 0.2 if content.include?("# ") || content.include?("```")

        [[score, 0.0].max, 1.0].min
      end

      # Count columns in a CSV line
      #
      # @param line [String] CSV line to analyze
      # @return [Integer] Number of columns detected
      private

      def count_csv_columns(line)
        # Simple comma count, accounting for quoted fields
        in_quotes = false
        comma_count = 0

        line.each_char do |char|
          case char
          when '"'
            in_quotes = !in_quotes
          when ','
            comma_count += 1 unless in_quotes
          end
        end

        comma_count + 1  # Add 1 because n commas = n+1 columns
      end

      # Calculate Markdown format score
      #
      # @param content [String] Content to analyze
      # @return [Float] Format score (0.0-1.0)
      private

      def calculate_markdown_score(content)
        score = 0.0

        # Check for code blocks
        if content.include?("```") || content.include?("~~~")
          score += 0.35
        end

        # Check for headings
        if content.include?("# ") || content.include?("## ") || content.include?("### ")
          score += 0.30
        end

        # Check for tables (pipes with consistent structure)
        if content.include?("|")
          lines = content.split("\n")
          pipe_lines = lines.select { |l| l.include?("|") }
          if pipe_lines.length >= 2
            # Check if we have header + separator pattern
            if pipe_lines[0].include?("|") && pipe_lines[1].include?("---")
              score += 0.35
            else
              score += 0.25
            end
          end
        end

        # Check for emphasis markers
        if content.include?("**") || content.include?("_")
          score += 0.15
        elsif content.include?("*")
          # Single asterisks are more common in regular text
          score += 0.05
        end

        # Check for list items
        if content.include?("\n- ") || content.include?("\n* ") || content.include?("\n+ ")
          score += 0.15
        end

        # Penalize if it looks like JSON
        if content.lstrip.start_with?("{") || content.lstrip.start_with?("[")
          score -= 0.3
        end

        [[score, 0.0].max, 1.0].min
      end

      # Calculate JSON format score
      #
      # @param content [String] Content to analyze
      # @return [Float] Format score (0.0-1.0)
      private

      def calculate_json_score(content)
        score = 0.0
        stripped = content.lstrip

        # Check for opening bracket or brace
        if stripped.start_with?("{")
          score += 0.30
        elsif stripped.start_with?("[")
          score += 0.30
        else
          # Not JSON-like
          return score
        end

        # Check for key-value pattern
        if stripped.include?('"') && stripped.include?(":")
          score += 0.25
        end

        # Try to parse as JSON (strong indicator)
        begin
          JSON.parse(content)
          score += 0.40
        rescue JSON::ParserError
          # Invalid JSON, but might still be incomplete
          # Give partial credit if it has the structure
          if stripped.count("{") > 0 || stripped.count("[") > 0
            score += 0.15
          end
        end

        # Penalize if it looks like CSV or Markdown
        score -= 0.2 if content.include?("|") && !stripped.start_with?("[{")
        score -= 0.1 if content.include?("# ") || content.include?("```")

        [[score, 0.0].max, 1.0].min
      end
    end
  end
end
