# frozen_string_literal: true

require "find"
require "digest"
require_relative "../../../../../lib/raaf/tool"
require_relative "../../../../../lib/raaf/tool/native"

module RAAF
  module Tools
    module Unified
      # Hosted file search using OpenAI's infrastructure
      #
      # This native tool provides access to OpenAI's hosted file search capability,
      # allowing agents to search through files uploaded to the OpenAI platform.
      #
      class HostedFileSearchTool < RAAF::Tool::Native
        configure name: "file_search",
                 description: "Search through files hosted on OpenAI platform"

        attr_reader :file_ids, :ranking_options

        def initialize(file_ids: [], ranking_options: nil, **options)
          super(**options)
          @file_ids = Array(file_ids)
          @ranking_options = ranking_options
        end

        native_config do
          file_search true
        end

        def to_tool_definition
          {
            type: "file_search",
            name: name,
            file_search: {
              file_ids: @file_ids,
              ranking_options: @ranking_options
            }.compact
          }
        end
      end

      # Local file system search tool
      #
      # Searches local files by content, filename, or both with regex support
      # and intelligent filtering.
      #
      class FileSearchTool < RAAF::Tool
        configure description: "Search for files and content within files using regex patterns"

        parameters do
          property :query, type: "string", description: "Search query string (supports regex)"
          property :search_type, type: "string", 
                  enum: ["content", "filename", "both"],
                  description: "Type of search to perform"
          property :file_pattern, type: "string",
                  description: "Optional file pattern filter (e.g., '*.rb')"
          required :query
        end

        def initialize(search_paths: ["."], file_extensions: nil, max_results: 10, **options)
          super(**options)
          @search_paths = Array(search_paths)
          @file_extensions = file_extensions
          @max_results = max_results
          @file_cache = {}
        end

        def call(query:, search_type: "content", file_pattern: nil)
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
          return true if File.basename(path).start_with?(".")
          return true if binary_file?(path)
          return true if File.size(path) > 10_000_000 # Skip files > 10MB
          false
        end

        def binary_file?(path)
          return false unless File.exist?(path)
          sample = File.read(path, 512)
          return false if sample.empty?
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
          @file_cache.clear if @file_cache.length > 100
          content
        rescue Encoding::UndefinedConversionError
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
end