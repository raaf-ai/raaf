# frozen_string_literal: true

require "find"
require "digest"
require "raaf/function_tool"

##
# File Search Tools for RAAF
#
# This module provides two complementary file search implementations:
# - HostedFileSearchTool: Uses OpenAI's hosted file search API
# - FileSearchTool: Local file system search with content matching
#
# @author RAAF (Ruby AI Agents Factory) Team
# @since 0.1.0
module RAAF
  module Tools
    ##
    # Hosted file search tool for OpenAI API
    #
    # This tool provides access to OpenAI's hosted file search capability,
    # allowing agents to search through files that have been uploaded to
    # the OpenAI platform. This is the recommended approach for production
    # applications with large document sets.
    #
    # @example Basic hosted file search
    #   tool = HostedFileSearchTool.new(file_ids: ["file-123", "file-456"])
    #   agent.add_tool(tool)
    #
    # @example With ranking options
    #   tool = HostedFileSearchTool.new(
    #     file_ids: ["file-123"],
    #     ranking_options: {
    #       score_threshold: 0.7,
    #       ranker: "auto"
    #     }
    #   )
    #
    # @see https://platform.openai.com/docs/assistants/tools/file-search OpenAI File Search documentation
    class HostedFileSearchTool
      attr_reader :file_ids, :ranking_options

      ##
      # Initialize hosted file search tool
      #
      # @param file_ids [Array<String>] list of OpenAI file IDs to search
      # @param ranking_options [Hash, nil] optional ranking configuration
      #
      # @example Basic initialization
      #   tool = HostedFileSearchTool.new(file_ids: ["file-abc123"])
      #
      # @example With ranking options
      #   tool = HostedFileSearchTool.new(
      #     file_ids: ["file-abc123", "file-def456"],
      #     ranking_options: { score_threshold: 0.8 }
      #   )
      def initialize(file_ids: [], ranking_options: nil)
        @file_ids = Array(file_ids)
        @ranking_options = ranking_options
      end

      ##
      # Tool name for OpenAI API
      #
      # @return [String] the tool name
      def name
        "file_search"
      end

      ##
      # Convert to OpenAI tool definition format
      #
      # @return [Hash] tool definition for OpenAI API
      #
      # @example Tool definition output
      #   {
      #     type: "file_search",
      #     name: "file_search",
      #     file_search: {
      #       file_ids: ["file-123"],
      #       ranking_options: { score_threshold: 0.7 }
      #     }
      #   }
      def to_tool_definition
        {
          type: "file_search",
          name: "file_search",
          file_search: {
            file_ids: @file_ids,
            ranking_options: @ranking_options
          }.compact
        }
      end
    end

    ##
    # Local file search tool implementation
    #
    # This tool provides local file system search capabilities with content
    # matching, filename searching, and intelligent file filtering. It's designed
    # for development environments and scenarios where files are available locally.
    #
    # == Features
    #
    # * **Content Search**: Search within file contents using regex patterns
    # * **Filename Search**: Find files by filename patterns
    # * **Combined Search**: Search both content and filenames simultaneously
    # * **File Filtering**: Skip binary files, large files, and hidden files
    # * **Caching**: Intelligent file content caching for performance
    # * **Context**: Provides surrounding lines for content matches
    #
    # == Search Types
    #
    # * `content`: Search within file contents (default)
    # * `filename`: Search filenames only
    # * `both`: Search both content and filenames
    #
    # @example Basic local file search
    #   tool = FileSearchTool.new(search_paths: ["./src", "./docs"])
    #   agent.add_tool(tool)
    #
    # @example With file type filtering
    #   tool = FileSearchTool.new(
    #     search_paths: ["./"],
    #     file_extensions: [".rb", ".yml", ".md"],
    #     max_results: 20
    #   )
    #
    # @example Usage in agent conversation
    #   # Agent will call: search_files(query: "def initialize", search_type: "content")
    #   # Returns: Formatted results with file paths, line numbers, and context
    class FileSearchTool < FunctionTool
      ##
      # Initialize local file search tool
      #
      # @param search_paths [Array<String>] directories to search (default: current directory)
      # @param file_extensions [Array<String>, nil] allowed file extensions (e.g., [".rb", ".txt"])
      # @param max_results [Integer] maximum number of results to return
      #
      # @example Search specific directories with file filtering
      #   tool = FileSearchTool.new(
      #     search_paths: ["./app", "./lib", "./config"],
      #     file_extensions: [".rb", ".yml", ".json"],
      #     max_results: 25
      #   )
      def initialize(search_paths: ["."], file_extensions: nil, max_results: 10)
        @search_paths = Array(search_paths)
        @file_extensions = file_extensions
        @max_results = max_results
        @file_cache = {}

        super(method(:search_files),
              name: "file_search",
              description: "Search for files and content within files using regex patterns",
              parameters: file_search_parameters)
      end

      ##
      # Search files based on query and search type
      #
      # This is the main search method called by agents. It supports multiple
      # search strategies and returns formatted results with context.
      #
      # @param query [String] search query (supports regex patterns)
      # @param search_type [String] type of search ("content", "filename", or "both")
      # @param file_pattern [String, nil] optional file pattern filter (e.g., "*.rb")
      # @return [String] formatted search results
      #
      # @example Content search
      #   search_files(query: "def initialize", search_type: "content")
      #
      # @example Filename search with pattern
      #   search_files(query: "config", search_type: "filename", file_pattern: "*.yml")
      #
      # @example Combined search
      #   search_files(query: "database", search_type: "both")
      def search_files(query:, search_type: "content", file_pattern: nil)
        case search_type.downcase
        when "content"
          search_file_content(query, file_pattern)
        when "filename"
          search_file_names(query, file_pattern)
        when "both"
          content_results = search_file_content(query, file_pattern)
          name_results = search_file_names(query, file_pattern)
          merge_results(content_results, name_results)
        else
          raise ArgumentError, "Invalid search_type. Use 'content', 'filename', or 'both'"
        end
      end

      private

      def file_search_parameters
        {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search query string"
            },
            search_type: {
              type: "string",
              enum: %w[content filename both],
              description: "Type of search to perform",
              default: "content"
            },
            file_pattern: {
              type: "string",
              description: "Optional file pattern to filter results (e.g., '*.rb', '*.txt')"
            }
          },
          required: ["query"]
        }
      end

      def search_file_content(query, file_pattern = nil)
        results = []
        regex = Regexp.new(query, Regexp::IGNORECASE)

        get_searchable_files(file_pattern).each do |file_path|
          next unless File.readable?(file_path)

          begin
            content = read_file_cached(file_path)
            matches = find_content_matches(content, regex, file_path)
            results.concat(matches)

            break if results.length >= @max_results
          rescue StandardError
            # Skip files that can't be read
            next
          end
        end

        format_results(results.first(@max_results))
      end

      def search_file_names(query, file_pattern = nil)
        results = []
        regex = Regexp.new(query, Regexp::IGNORECASE)

        get_searchable_files(file_pattern).each do |file_path|
          filename = File.basename(file_path)
          if filename.match?(regex)
            results << {
              file: file_path,
              match_type: "filename",
              match: filename,
              line_number: nil,
              context: nil
            }
          end

          break if results.length >= @max_results
        end

        format_results(results)
      end

      def get_searchable_files(file_pattern = nil)
        files = []

        @search_paths.each do |search_path|
          next unless Dir.exist?(search_path)

          Find.find(search_path) do |path|
            next unless File.file?(path)
            next if skip_file?(path)
            next if file_pattern && !File.fnmatch(file_pattern, File.basename(path))
            next if @file_extensions && !@file_extensions.include?(File.extname(path))

            files << path
          end
        end

        files
      end

      def skip_file?(path)
        # Skip binary files, hidden files, and common non-text files
        return true if File.basename(path).start_with?(".")
        return true if binary_file?(path)
        return true if File.size(path) > 10_000_000 # Skip files larger than 10MB

        false
      end

      def binary_file?(path)
        # Simple heuristic to detect binary files
        return false unless File.exist?(path)

        sample = File.read(path, 512)
        return false if sample.empty?

        # Check for null bytes (common in binary files)
        sample.include?("\x00")
      rescue StandardError
        true
      end

      def read_file_cached(file_path)
        mtime = File.mtime(file_path)
        cache_key = "#{file_path}:#{mtime.to_i}"

        return @file_cache[cache_key] if @file_cache[cache_key]

        content = File.read(file_path, encoding: "UTF-8")
        @file_cache[cache_key] = content

        # Keep cache size reasonable
        @file_cache.clear if @file_cache.length > 100

        content
      rescue Encoding::UndefinedConversionError
        # Try reading as binary and converting
        File.read(file_path, encoding: "ISO-8859-1").encode("UTF-8", invalid: :replace, undef: :replace)
      end

      def find_content_matches(content, regex, file_path)
        matches = []

        content.lines.each_with_index do |line, index|
          next unless line.match?(regex)

          matches << {
            file: file_path,
            match_type: "content",
            match: line.strip,
            line_number: index + 1,
            context: get_line_context(content.lines, index)
          }
        end

        matches
      end

      def get_line_context(lines, match_index, context_lines = 2)
        start_index = [0, match_index - context_lines].max
        end_index = [lines.length - 1, match_index + context_lines].min

        context = []
        (start_index..end_index).each do |i|
          prefix = i == match_index ? ">>> " : "    "
          context << "#{prefix}#{i + 1}: #{lines[i].strip}"
        end

        context.join("\n")
      end

      def merge_results(content_results, name_results)
        all_results = content_results + name_results

        # Remove duplicates based on file path
        unique_results = {}
        all_results.each { |result| unique_results[result[:file]] ||= result }

        format_results(unique_results.values.first(@max_results))
      end

      def format_results(results)
        if results.empty?
          "No matches found for the search query."
        else
          summary = "Found #{results.length} matches:\n\n"

          results.each do |result|
            summary += "File: #{result[:file]}\n"
            summary += "Type: #{result[:match_type]}\n"
            summary += "Line: #{result[:line_number]}\n" if result[:line_number]
            summary += "Match: #{result[:match]}\n"

            summary += "Context:\n#{result[:context]}\n" if result[:context]

            summary += "\n#{"-" * 50}\n\n"
          end

          summary
        end
      end
    end
  end
end
