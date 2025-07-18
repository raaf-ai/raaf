# frozen_string_literal: true

module RAAF
  module Tools
    module Basic
      ##
      # Text processing tools for AI agents
      #
      # Provides essential text manipulation capabilities including word counting,
      # text summarization, formatting, searching, replacement, and validation.
      #
      class TextTools
        include RAAF::Logger

        class << self
          ##
          # Word count tool
          #
          # @return [RAAF::FunctionTool] Word counting tool
          #
          def word_count
            RAAF::FunctionTool.new(
              method(:count_words),
              name: "word_count",
              description: "Count words, characters, and lines in text",
              parameters: {
                type: "object",
                properties: {
                  text: {
                    type: "string",
                    description: "The text to analyze"
                  }
                },
                required: ["text"]
              }
            )
          end

          ##
          # Text summarization tool
          #
          # @return [RAAF::FunctionTool] Text summarization tool
          #
          def text_summarize
            RAAF::FunctionTool.new(
              method(:summarize_text),
              name: "text_summarize",
              description: "Create a summary of the given text",
              parameters: {
                type: "object",
                properties: {
                  text: {
                    type: "string",
                    description: "The text to summarize"
                  },
                  max_length: {
                    type: "integer",
                    description: "Maximum summary length in characters",
                    default: 500
                  }
                },
                required: ["text"]
              }
            )
          end

          ##
          # Text formatting tool
          #
          # @return [RAAF::FunctionTool] Text formatting tool
          #
          def text_format
            RAAF::FunctionTool.new(
              method(:format_text),
              name: "text_format",
              description: "Format text with various transformations",
              parameters: {
                type: "object",
                properties: {
                  text: {
                    type: "string",
                    description: "The text to format"
                  },
                  format: {
                    type: "string",
                    enum: ["uppercase", "lowercase", "capitalize", "title", "sentence"],
                    description: "Format type to apply"
                  }
                },
                required: ["text", "format"]
              }
            )
          end

          ##
          # Text search tool
          #
          # @return [RAAF::FunctionTool] Text search tool
          #
          def text_search
            RAAF::FunctionTool.new(
              method(:search_text),
              name: "text_search",
              description: "Search for patterns in text",
              parameters: {
                type: "object",
                properties: {
                  text: {
                    type: "string",
                    description: "The text to search in"
                  },
                  pattern: {
                    type: "string",
                    description: "The pattern to search for"
                  },
                  case_sensitive: {
                    type: "boolean",
                    description: "Whether search is case sensitive",
                    default: false
                  }
                },
                required: ["text", "pattern"]
              }
            )
          end

          ##
          # Text replacement tool
          #
          # @return [RAAF::FunctionTool] Text replacement tool
          #
          def text_replace
            RAAF::FunctionTool.new(
              method(:replace_text),
              name: "text_replace",
              description: "Replace patterns in text",
              parameters: {
                type: "object",
                properties: {
                  text: {
                    type: "string",
                    description: "The text to modify"
                  },
                  pattern: {
                    type: "string",
                    description: "The pattern to replace"
                  },
                  replacement: {
                    type: "string",
                    description: "The replacement text"
                  },
                  global: {
                    type: "boolean",
                    description: "Replace all occurrences",
                    default: true
                  }
                },
                required: ["text", "pattern", "replacement"]
              }
            )
          end

          ##
          # Text validation tool
          #
          # @return [RAAF::FunctionTool] Text validation tool
          #
          def text_validate
            RAAF::FunctionTool.new(
              method(:validate_text),
              name: "text_validate",
              description: "Validate text format (email, URL, etc.)",
              parameters: {
                type: "object",
                properties: {
                  text: {
                    type: "string",
                    description: "The text to validate"
                  },
                  validation_type: {
                    type: "string",
                    enum: ["email", "url", "phone", "credit_card", "uuid"],
                    description: "Type of validation to perform"
                  }
                },
                required: ["text", "validation_type"]
              }
            )
          end

          private

          def count_words(text:)
            return "Empty text provided" if text.nil? || text.empty?

            words = text.split(/\s+/).length
            characters = text.length
            characters_no_spaces = text.gsub(/\s/, "").length
            lines = text.split(/\n/).length
            paragraphs = text.split(/\n\s*\n/).length

            {
              words: words,
              characters: characters,
              characters_no_spaces: characters_no_spaces,
              lines: lines,
              paragraphs: paragraphs
            }.to_json
          end

          def summarize_text(text:, max_length: 500)
            return "Empty text provided" if text.nil? || text.empty?

            # Simple extractive summarization
            sentences = text.split(/[.!?]+/).reject(&:empty?)
            return text if sentences.length <= 2

            # Score sentences by word frequency
            word_freq = {}
            text.downcase.split(/\s+/).each { |word| word_freq[word] = word_freq[word].to_i + 1 }

            sentence_scores = sentences.map do |sentence|
              words = sentence.downcase.split(/\s+/)
              score = words.sum { |word| word_freq[word] || 0 } / words.length.to_f
              [sentence.strip, score]
            end

            # Select top sentences
            top_sentences = sentence_scores.sort_by { |_, score| -score }
                                         .first([sentences.length / 2, 3].max)
                                         .map(&:first)

            summary = top_sentences.join(". ") + "."
            summary.length > max_length ? summary[0..max_length-4] + "..." : summary
          end

          def format_text(text:, format:)
            return "Empty text provided" if text.nil? || text.empty?

            case format
            when "uppercase"
              text.upcase
            when "lowercase"
              text.downcase
            when "capitalize"
              text.capitalize
            when "title"
              text.split.map(&:capitalize).join(" ")
            when "sentence"
              text.split(". ").map(&:capitalize).join(". ")
            else
              "Unknown format type: #{format}"
            end
          end

          def search_text(text:, pattern:, case_sensitive: false)
            return "Empty text provided" if text.nil? || text.empty?

            search_text = case_sensitive ? text : text.downcase
            search_pattern = case_sensitive ? pattern : pattern.downcase

            matches = []
            offset = 0

            while (index = search_text.index(search_pattern, offset))
              matches << {
                match: text[index, pattern.length],
                position: index,
                line: text[0..index].count("\n") + 1
              }
              offset = index + 1
            end

            {
              pattern: pattern,
              matches: matches.length,
              found: matches
            }.to_json
          end

          def replace_text(text:, pattern:, replacement:, global: true)
            return "Empty text provided" if text.nil? || text.empty?

            if global
              text.gsub(pattern, replacement)
            else
              text.sub(pattern, replacement)
            end
          end

          def validate_text(text:, validation_type:)
            return "Empty text provided" if text.nil? || text.empty?

            case validation_type
            when "email"
              valid = text.match?(/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)
              { valid: valid, type: "email", message: valid ? "Valid email" : "Invalid email format" }
            when "url"
              valid = text.match?(%r{\Ahttps?://[\S]+\z})
              { valid: valid, type: "url", message: valid ? "Valid URL" : "Invalid URL format" }
            when "phone"
              valid = text.match?(/\A[\d\s\-\(\)\+]{10,}\z/)
              { valid: valid, type: "phone", message: valid ? "Valid phone format" : "Invalid phone format" }
            when "credit_card"
              # Basic Luhn algorithm check
              digits = text.gsub(/\D/, "")
              valid = digits.length >= 13 && luhn_valid?(digits)
              { valid: valid, type: "credit_card", message: valid ? "Valid credit card" : "Invalid credit card" }
            when "uuid"
              valid = text.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
              { valid: valid, type: "uuid", message: valid ? "Valid UUID" : "Invalid UUID format" }
            else
              { valid: false, type: "unknown", message: "Unknown validation type: #{validation_type}" }
            end.to_json
          end

          def luhn_valid?(digits)
            sum = 0
            digits.reverse.chars.each_with_index do |digit, index|
              n = digit.to_i
              n *= 2 if index.odd?
              n = n.digits.sum if n > 9
              sum += n
            end
            sum % 10 == 0
          end
        end
      end
    end
  end
end