# frozen_string_literal: true

require_relative "../../../../../lib/raaf/tool"

module RAAF
  module Tools
    module Unified
      # Document Tool
      #
      # Manages document operations including creation, reading, updating,
      # and analysis of various document formats.
      #
      class DocumentTool < RAAF::Tool
        configure description: "Manage and analyze documents"

        parameters do
          property :action, type: "string",
                  enum: ["read", "create", "update", "analyze", "convert"],
                  description: "Action to perform"
          property :path, type: "string", description: "Document path"
          property :content, type: "string", description: "Document content (for create/update)"
          property :format, type: "string",
                  enum: ["text", "markdown", "pdf", "html", "json"],
                  description: "Document format"
          property :analysis_type, type: "string",
                  enum: ["summary", "keywords", "sentiment", "structure"],
                  description: "Type of analysis to perform"
          required :action
        end

        def initialize(storage_path: "./documents", **options)
          super(**options)
          @storage_path = storage_path
          FileUtils.mkdir_p(@storage_path) unless Dir.exist?(@storage_path)
        end

        def call(action:, path: nil, content: nil, format: "text", analysis_type: nil)
          case action
          when "read"
            read_document(path, format)
          when "create"
            create_document(path, content, format)
          when "update"
            update_document(path, content)
          when "analyze"
            analyze_document(path, analysis_type || "summary")
          when "convert"
            convert_document(path, format)
          else
            "Invalid action: #{action}"
          end
        end

        private

        def read_document(path, format)
          raise ArgumentError, "Path required for reading" unless path
          
          full_path = File.join(@storage_path, path)
          return "Document not found: #{path}" unless File.exist?(full_path)

          content = File.read(full_path)
          
          case format
          when "markdown"
            # Could use a markdown parser here
            content
          when "json"
            JSON.parse(content)
          else
            content
          end
        end

        def create_document(path, content, format)
          raise ArgumentError, "Path and content required" unless path && content

          full_path = File.join(@storage_path, path)
          FileUtils.mkdir_p(File.dirname(full_path))

          formatted_content = format_content(content, format)
          File.write(full_path, formatted_content)

          "Document created: #{path}"
        end

        def update_document(path, content)
          raise ArgumentError, "Path and content required" unless path && content

          full_path = File.join(@storage_path, path)
          return "Document not found: #{path}" unless File.exist?(full_path)

          File.write(full_path, content)
          "Document updated: #{path}"
        end

        def analyze_document(path, analysis_type)
          raise ArgumentError, "Path required for analysis" unless path

          full_path = File.join(@storage_path, path)
          return "Document not found: #{path}" unless File.exist?(full_path)

          content = File.read(full_path)

          case analysis_type
          when "summary"
            generate_summary(content)
          when "keywords"
            extract_keywords(content)
          when "sentiment"
            analyze_sentiment(content)
          when "structure"
            analyze_structure(content)
          else
            "Unknown analysis type: #{analysis_type}"
          end
        end

        def convert_document(path, target_format)
          raise ArgumentError, "Path required for conversion" unless path

          full_path = File.join(@storage_path, path)
          return "Document not found: #{path}" unless File.exist?(full_path)

          content = File.read(full_path)
          converted = format_content(content, target_format)

          new_path = path.sub(/\.[^.]+$/, ".#{target_format}")
          new_full_path = File.join(@storage_path, new_path)
          File.write(new_full_path, converted)

          "Document converted and saved as: #{new_path}"
        end

        def format_content(content, format)
          case format
          when "json"
            { content: content, created_at: Time.now.iso8601 }.to_json
          when "html"
            "<html><body>#{content.gsub("\n", "<br>")}</body></html>"
          when "markdown"
            content # Already in markdown
          else
            content
          end
        end

        def generate_summary(content)
          # Simplified summary generation
          lines = content.lines
          word_count = content.split.length
          
          "Document Summary:\n" \
          "- Length: #{word_count} words\n" \
          "- Lines: #{lines.length}\n" \
          "- First line: #{lines.first&.strip}\n"
        end

        def extract_keywords(content)
          # Simple keyword extraction
          words = content.downcase.split(/\W+/)
          word_freq = words.tally.sort_by { |_, count| -count }
          
          top_keywords = word_freq.first(10).map(&:first)
          "Top keywords: #{top_keywords.join(", ")}"
        end

        def analyze_sentiment(content)
          # Placeholder for sentiment analysis
          "Sentiment analysis would require ML model integration"
        end

        def analyze_structure(content)
          lines = content.lines
          paragraphs = content.split(/\n\n+/)
          
          "Document Structure:\n" \
          "- Paragraphs: #{paragraphs.length}\n" \
          "- Lines: #{lines.length}\n" \
          "- Characters: #{content.length}\n"
        end
      end

      # Report Tool - Specialized document tool for generating reports
      #
      class ReportTool < DocumentTool
        configure name: "report",
                 description: "Generate and manage analytical reports"

        def initialize(**options)
          super(storage_path: "./reports", **options)
        end

        def call(action:, path: nil, content: nil, format: "markdown", analysis_type: nil)
          # Add report-specific formatting
          if action == "create" && content
            content = add_report_header(content)
          end
          
          super
        end

        private

        def add_report_header(content)
          header = "# Report Generated: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}\n\n"
          header + content
        end
      end
    end
  end
end