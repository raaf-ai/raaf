# frozen_string_literal: true

require "redcarpet"

module RAAF
  module Rails
    module Tracing
      module MarkdownRenderer
        extend self

        # Safe markdown renderer configuration
        def renderer
          @renderer ||= Redcarpet::Markdown.new(
            Redcarpet::Render::HTML.new(
              filter_html: true,       # Filter out raw HTML
              no_images: false,        # Allow images
              no_links: false,         # Allow links
              no_styles: true,         # No inline styles
              safe_links_only: true,   # Only safe links
              with_toc_data: false,    # No table of contents
              hard_wrap: true,         # Convert line breaks
              link_attributes: { target: "_blank", rel: "noopener noreferrer" }
            ),
            # Enable useful markdown features
            autolink: true,            # Auto-link URLs
            tables: true,              # Enable tables
            fenced_code_blocks: true,  # Enable ```code``` blocks
            strikethrough: true,       # Enable ~~strikethrough~~
            superscript: false,        # Disable superscript
            underline: false,          # Disable underline
            highlight: false,          # Disable highlighting
            quote: true,               # Enable > quotes
            footnotes: false,          # Disable footnotes
            disable_indented_code_blocks: false
          )
        end

        # Convert markdown text to HTML
        #
        # Always returns HTML marked safe, including for text that carries no
        # markdown at all. Returning that text as-is made the promise in this
        # method's name false twice over: every caller hands the result to
        # Phlex's `raw`, which under Phlex 2 rejects an unsafe object outright —
        # an evaluation result whose details were written as one plain sentence
        # raised `You passed an unsafe object to raw` and took the whole page
        # with it — and a caller that marked it safe itself would have injected
        # whatever an agent had written straight into the page.
        def markdown_to_html(text)
          return "".html_safe if text.blank?
          return escape_to_html(text) unless looks_like_markdown?(text)

          begin
            rendered = renderer.render(text.to_s)
            rendered.present? ? rendered.html_safe : escape_to_html(text)
          rescue StandardError => e
            # Fallback to plain text if markdown rendering fails
            Rails.logger.warn "Markdown rendering failed: #{e.message}"
            escape_to_html(text)
          end
        end

        # Plain text as HTML: escaped, with newlines kept as breaks so it reads
        # the way the hard_wrap renderer above would have rendered it.
        def escape_to_html(text)
          ERB::Util.html_escape(text.to_s).gsub("\n", "<br>").html_safe
        end

        # Check if text looks like it might contain markdown
        def looks_like_markdown?(text)
          return false unless text.is_a?(String)
          return false if text.blank?

          # Simple heuristics to detect markdown
          markdown_patterns = [
            /^#+ /,           # Headers
            /\*\*.*\*\*/,     # Bold
            /\*.*\*/,         # Italic
            /```/,            # Code blocks
            /`.*`/,           # Inline code
            /^\* /,           # Lists
            /^\d+\. /,        # Numbered lists
            /^> /, # Quotes
            /\[.*\]\(.*\)/,   # Links
            /\n\n/            # Multiple line breaks
          ]

          markdown_patterns.any? { |pattern| text.match?(pattern) }
        end

        # Check if content should be treated as JSON
        def looks_like_json?(content)
          return false unless content.is_a?(String)

          stripped = content.strip
          (stripped.start_with?("{") && stripped.end_with?("}")) ||
            (stripped.start_with?("[") && stripped.end_with?("]"))
        end

        # Format content based on detected type
        def format_content(content, force_type: nil)
          case force_type&.to_sym
          when :markdown
            markdown_to_html(content)
          when :json
            format_json_content(content)
          when :plain
            content
          else
            # Auto-detect content type
            if looks_like_json?(content)
              format_json_content(content)
            elsif looks_like_markdown?(content)
              markdown_to_html(content)
            else
              content
            end
          end
        end

        private

        # Format JSON content (borrowed from existing implementation)
        # Also handles Ruby hash-like syntax (without quotes around keys)
        def format_json_content(content)
          case content
          when String
            # Strip markdown code fences if present (```json ... ``` or ``` ... ```)
            cleaned = strip_markdown_code_fences(content)
            begin
              # First try standard JSON parsing
              parsed = JSON.parse(cleaned)
              JSON.pretty_generate(parsed)
            rescue JSON::ParserError
              # Try to convert Ruby hash-like syntax to JSON
              converted = convert_ruby_hash_to_json(cleaned)
              if converted == cleaned
                # If no conversion needed but still failed, format with indentation
                format_hash_like_content(cleaned)
              else
                begin
                  parsed = JSON.parse(converted)
                  JSON.pretty_generate(parsed)
                rescue JSON::ParserError
                  # If conversion also fails, format the cleaned content with indentation
                  format_hash_like_content(cleaned)
                end
              end
            end
          when Hash, Array
            JSON.pretty_generate(content)
          else
            content.to_s
          end
        end

        # Strip markdown code fences from content
        # Handles: ```json\n{...}\n``` or ```\n{...}\n``` or `{...}`
        def strip_markdown_code_fences(content)
          return content unless content.is_a?(String)

          stripped = content.strip

          # Handle triple backtick code blocks: ```json\n...\n``` or ```\n...\n```
          if stripped.start_with?("```")
            # Remove opening fence (```json or ```)
            stripped = stripped.sub(/\A```[a-z]*\s*\n?/, "")
            # Remove closing fence
            stripped = stripped.sub(/\n?```\s*\z/, "")
            return stripped.strip
          end

          # Handle single backtick wrapped content: `{...}`
          return stripped[1..-2].strip if stripped.start_with?("`") && stripped.end_with?("`")

          # Handle content that starts with backtick but doesn't end with one
          # (partial markdown fence)
          return stripped[1..-1].strip if stripped.start_with?("`")

          content
        end

        # Convert Ruby hash-like syntax to valid JSON
        # e.g., {name:value} -> {"name":"value"}
        def convert_ruby_hash_to_json(content)
          return content unless content.is_a?(String)

          result = content.dup

          # Add quotes around unquoted keys (word characters followed by colon)
          # This handles: {key:value} -> {"key":value}
          result = result.gsub(/([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)(\s*:)/) do
            "#{::Regexp.last_match(1)}\"#{::Regexp.last_match(2)}\"#{::Regexp.last_match(3)}"
          end

          # Add quotes around unquoted string values
          # This is trickier - we need to identify unquoted values
          # For now, handle common cases like :value after colon that aren't numbers/booleans/null
          result = result.gsub(/:(\s*)([a-zA-Z_][a-zA-Z0-9_\-.\/\s@]*)([,}\]])/) do
            value = ::Regexp.last_match(2).strip
            # Check if it's a boolean, null, or number
            if %w[true false null].include?(value.downcase) || value.match?(/^-?\d+\.?\d*$/)
              ":#{::Regexp.last_match(1)}#{value}#{::Regexp.last_match(3)}"
            else
              ":#{::Regexp.last_match(1)}\"#{value}\"#{::Regexp.last_match(3)}"
            end
          end

          result
        end

        # Format hash-like content with proper indentation for readability
        def format_hash_like_content(content)
          return content unless content.is_a?(String)

          indent_level = 0
          result = ""
          i = 0

          while i < content.length
            char = content[i]

            case char
            when "{", "["
              result += char + "\n"
              indent_level += 1
              result += "  " * indent_level
            when "}", "]"
              result += "\n"
              indent_level -= 1
              result += ("  " * indent_level) + char
            when ","
              result += char + "\n"
              result += "  " * indent_level
            when ":"
              result += ": "
            else
              result += char unless char == " " && result.end_with?("  ")
            end

            i += 1
          end

          result
        end
      end
    end
  end
end
