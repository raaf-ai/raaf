# frozen_string_literal: true

require "json"

module RAAF

  # Utilities for repairing and extracting JSON from malformed text
  # Implements fault-tolerant JSON parsing with common fix patterns
  #
  # This module handles common LLM output issues:
  # - JSON wrapped in markdown code blocks
  # - Trailing commas in objects and arrays
  # - Single quotes instead of double quotes
  # - Mixed text content with JSON embedded
  # - Malformed JSON structures that can be repaired
  #
  # Usage:
  #   JsonRepair.repair('{"name": "John",}')  # => { name: "John" }
  #   JsonRepair.repair('```json\n{"valid": true}\n```')  # => { valid: true }
  module JsonRepair

    class << self

      # Attempt to repair and parse malformed JSON
      # @param input [String, Hash] Input to repair - strings are parsed, hashes returned as-is
      # @return [ActiveSupport::HashWithIndifferentAccess, nil] Parsed JSON with indifferent access, or nil if unrepairable
      def repair(input)
        return input if input.is_a?(Hash)
        return nil unless input.is_a?(String)

        # Each candidate is a progressively more aggressive attempt at isolating
        # the JSON: the input itself, then the contents of a markdown code
        # block, then any JSON-shaped run of text. Every candidate gets the
        # syntax fixes applied, so a code block holding a trailing comma is
        # still repairable.
        candidates = [input, extract_from_markdown(input), extract_json_structure(input)]

        candidates.compact.each do |candidate|
          parsed = try_parse(candidate) || try_parse(fix_common_issues(candidate))
          return parsed if parsed
        end

        nil
      end

      # Extract valid JSON structure from mixed content (text + JSON)
      # @param content [String] Content that may contain JSON
      # @return [ActiveSupport::HashWithIndifferentAccess, nil] First valid JSON structure with indifferent access, or nil
      def extract_json_from_content(content)
        # Try to find complete JSON objects or arrays
        json_patterns = [
          /\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/m, # Nested objects
          /\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\]/m, # Nested arrays
          /\{[^{}]*\}/m, # Simple objects
          /\[[^\[\]]*\]/m # Simple arrays
        ]

        json_patterns.each do |pattern|
          matches = content.scan(pattern)
          matches.each do |match|
            parsed = try_parse(match)
            return parsed if parsed
          end
        end

        nil
      end

      private

      # Safely attempt JSON parsing with indifferent access
      # @param str [String] JSON string to parse
      # @return [ActiveSupport::HashWithIndifferentAccess, nil] Parsed hash with indifferent access or nil if parsing fails
      def try_parse(str)
        return nil unless str.is_a?(String) && !str.strip.empty?

        parsed = JSON.parse(str)
        Utils.indifferent_access(parsed)
      rescue JSON::ParserError
        nil
      end

      # Fix common JSON syntax issues
      # @param str [String] Malformed JSON string
      # @return [String] JSON string with common issues fixed
      def fix_common_issues(str)
        # Remove leading/trailing whitespace and normalize
        fixed = str.strip

        # Fix trailing commas in objects and arrays
        # This handles the common case where LLMs add trailing commas before closing braces/brackets
        fixed = fixed.gsub(/,\s*}/, "}")
        fixed = fixed.gsub(/,\s*\]/, "]") # Fixed regex escape for closing bracket

        # Fix single quotes to double quotes in keys
        fixed = fixed.gsub(/(['"])([^'"]*)\1\s*:/, '"\2":')

        # Fix single quotes in string values. The closing quote is the last one
        # before a delimiter, so an apostrophe inside the value ("John O'Brien")
        # does not cut the string short.
        fixed = fixed.gsub(/:\s*'(.*?)'(?=\s*[,}\]]|\s*$)/, ': "\1"')

        # Remove newlines within JSON (but preserve them in string values)
        # This is a simple approach - could be enhanced for edge cases
        fixed = fixed.gsub("\n", " ") unless fixed.include?('\\n')

        # Fix missing quotes around unquoted keys
        fixed.gsub(/(\w+)\s*:/, '"\1":')
      end

      # Extract JSON from markdown code blocks
      # @param str [String] Text that may contain markdown code blocks
      # @return [String, nil] JSON content from first valid code block
      def extract_from_markdown(str)
        # Look for ```json blocks first
        json_match = str.match(/```(?:json)?\s*\n?(.*?)\n?```/m)
        return json_match[1].strip if json_match

        # Look for any ``` code blocks that might contain JSON
        code_match = str.match(/```\s*\n?(.*?)\n?```/m)
        if code_match
          content = code_match[1].strip
          # Check if it looks like JSON (starts with { or [)
          return content if content.match?(/^\s*[{\[]/)
        end

        nil
      end

      # Extract JSON structure from free text
      # @param str [String] Text that may contain JSON objects/arrays
      # @return [String, nil] First JSON-like structure found
      def extract_json_structure(str)
        # Find the most complete JSON object (prefer nested over simple)
        json_candidates = []

        # Look for complete JSON objects with proper braces
        str.scan(/\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/m) do |match|
          json_candidates << match
        end

        # Look for JSON arrays
        str.scan(/\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\]/m) do |match|
          json_candidates << match
        end

        # Return the longest candidate (likely most complete)
        json_candidates.max_by(&:length)
      end

    end

  end

end
