# frozen_string_literal: true

require 'json'

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
      # @return [Hash, nil] Parsed JSON as hash with symbolized keys, or nil if unrepairable
      def repair(input)
        return input if input.is_a?(Hash)
        return nil unless input.is_a?(String)
        
        # Try direct parse first - fastest path for valid JSON
        parsed = try_parse(input)
        return parsed if parsed
        
        # Fix common JSON syntax issues
        fixed = fix_common_issues(input)
        parsed = try_parse(fixed) if fixed
        return parsed if parsed
        
        # Extract JSON from markdown code blocks
        extracted = extract_from_markdown(input)
        parsed = try_parse(extracted) if extracted
        return parsed if parsed
        
        # Extract any JSON-like structure from text
        json_like = extract_json_structure(input)
        try_parse(json_like) if json_like
      end

      # Extract valid JSON structure from mixed content (text + JSON)
      # @param content [String] Content that may contain JSON
      # @return [Hash, nil] First valid JSON structure found, or nil
      def extract_json_from_content(content)
        # Try to find complete JSON objects or arrays
        json_patterns = [
          /\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/m,  # Nested objects
          /\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\]/m,  # Nested arrays
          /\{[^{}]*\}/m,  # Simple objects
          /\[[^\[\]]*\]/m  # Simple arrays
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

      # Safely attempt JSON parsing with symbolized keys
      # @param str [String] JSON string to parse
      # @return [Hash, nil] Parsed hash or nil if parsing fails
      def try_parse(str)
        return nil unless str.is_a?(String) && !str.strip.empty?
        
        JSON.parse(str, symbolize_names: true)
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
        fixed = fixed.gsub(/,\s*}/, '}')
        fixed = fixed.gsub(/,\s*\]/, ']')  # Fixed regex escape for closing bracket
        
        # Fix single quotes to double quotes in keys
        fixed = fixed.gsub(/(['"])([^'"]*)\1\s*:/, '"\2":')
        
        # Fix single quotes in string values
        fixed = fixed.gsub(/:\s*'([^']*)'/, ': "\1"')
        
        # Remove newlines within JSON (but preserve them in string values)
        # This is a simple approach - could be enhanced for edge cases
        unless fixed.include?('\\n')
          fixed = fixed.gsub(/\n/, ' ')
        end
        
        # Fix missing quotes around unquoted keys
        fixed = fixed.gsub(/(\w+)\s*:/, '"\1":')
        
        # Fix double-quoted values that should be numbers or booleans
        fixed = fixed.gsub(/:\s*"(\d+\.?\d*)"/, ': \1')  # Numbers
        fixed = fixed.gsub(/:\s*"(true|false|null)"/, ': \1')  # Booleans/null
        
        fixed
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
          return content if content.match?(/^\s*[\{\[]/)
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