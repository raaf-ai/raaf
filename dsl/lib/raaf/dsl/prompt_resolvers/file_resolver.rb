# frozen_string_literal: true

require_relative "../prompt_resolver"
require "yaml"
require "erb"

module RAAF
  module DSL
    module PromptResolvers
      ##
      # Unified resolver for file-based prompts (Markdown, ERB templates, etc.)
      #
      # This resolver handles multiple file formats for prompt definitions:
      # - Plain Markdown (.md, .markdown) with {{variable}} interpolation
      # - ERB-processed Markdown (.md.erb, .markdown.erb) with full Ruby capabilities
      # - YAML frontmatter for metadata in any format
      # - Section markers for system/user message separation
      #
      # @example Plain Markdown with interpolation
      #   # prompts/greeting.md
      #   ---
      #   id: greeting
      #   version: 1.0
      #   ---
      #   # System
      #   You are a {{tone}} assistant named {{name}}.
      #
      #   # User
      #   Please greet the user.
      #
      # @example ERB template with Ruby logic
      #   # prompts/analysis.md.erb
      #   ---
      #   id: data-analysis
      #   ---
      #   # System
      #   You analyze <%= data_type %> data.
      #
      #   Skills:
      #   <% skills.each do |skill| %>
      #   - <%= skill %>
      #   <% end %>
      #
      # @example Using HTML comment sections
      #   <!-- system -->
      #   You are an assistant.
      #
      #   <!-- user -->
      #   Help me with this task.
      #
      # @example Configuration
      #   RAAF::DSL.configure_prompts do |config|
      #     config.enable_resolver :file,
      #       priority: 100,
      #       paths: ["prompts", "app/prompts"],
      #       extensions: [".md", ".md.erb", ".prompt"]
      #   end
      #
      class FileResolver < PromptResolver
        ##
        # Initialize a new file resolver
        #
        # @param paths [Array<String>] directories to search for prompt files
        # @param extensions [Array<String>] supported file extensions
        # @param erb_extensions [Array<String>] extensions that should be processed with ERB
        # @param options [Hash] additional options passed to parent
        #
        def initialize(**options)
          super(name: :file, **options)
          @paths = options[:paths] || ["prompts"]
          @extensions = options[:extensions] || [".md", ".markdown", ".md.erb", ".markdown.erb"]
          @erb_extensions = options[:erb_extensions] || [".erb", ".md.erb", ".markdown.erb"]
        end

        ##
        # Check if the spec references a supported file type
        #
        # @param prompt_spec [String, Hash] file path or hash with file specification
        # @return [Boolean] true if this resolver can handle the specification
        #
        # @example String specs
        #   can_resolve?("greeting.md")           # => true
        #   can_resolve?("template.md.erb")       # => true
        #   can_resolve?("prompts/welcome")       # => true (if file exists)
        #
        # @example Hash specs
        #   can_resolve?(type: :file, file: "greeting.md")      # => true
        #   can_resolve?(template: "analysis.md.erb")           # => true
        #
        def can_resolve?(prompt_spec)
          case prompt_spec
          when String
            # Check if it ends with any supported extension or exists as a file
            @extensions.any? { |ext| prompt_spec.end_with?(ext) } ||
              file_exists?(prompt_spec)
          when Hash
            # Support hash specs with file/path/template keys
            prompt_spec[:type] == :file ||
              %i[file path template].any? { |key| prompt_spec[key] && can_resolve?(prompt_spec[key]) }
          else
            false
          end
        end

        ##
        # Resolve file to RAAF::Prompt
        #
        # @param prompt_spec [String, Hash] file specification
        # @param context [Hash] variables for interpolation/ERB processing
        # @return [Prompt, nil] resolved prompt or nil if cannot resolve
        #
        # @example Simple resolution
        #   prompt = resolver.resolve("greeting.md", name: "Alice", tone: "friendly")
        #
        # @example ERB template resolution
        #   prompt = resolver.resolve("report.md.erb",
        #     data: sales_data,
        #     period: "Q1 2024",
        #     metrics: [:revenue, :growth]
        #   )
        #
        def resolve(prompt_spec, context = {})
          return nil unless can_resolve?(prompt_spec)

          file_path = case prompt_spec
                      when String
                        find_file(prompt_spec)
                      when Hash
                        find_file(prompt_spec[:file] || prompt_spec[:path] || prompt_spec[:template])
                      end

          return nil unless file_path && File.exist?(file_path)

          build_prompt_from_file(file_path, context)
        rescue StandardError => e
          log_error("Failed to resolve file prompt", error: e.message, file: file_path)
          nil
        end

        private

        ##
        # Check if a file exists in any of the configured paths
        #
        # @param name [String] file name to check
        # @return [Boolean] true if file exists
        #
        def file_exists?(name)
          find_file(name) != nil
        end

        ##
        # Find a file in the configured paths
        #
        # @param name [String] file name to find
        # @return [String, nil] full path to file or nil if not found
        #
        # The search order is:
        # 1. Exact path (if absolute or exists relative to current directory)
        # 2. Each configured path + exact name
        # 3. Each configured path + name + each extension
        #
        def find_file(name)
          return name if File.exist?(name)

          # Try each path and extension combination
          @paths.each do |path|
            # Try exact name first
            file_path = File.join(path, name)
            return file_path if File.exist?(file_path)

            # Try with each extension
            @extensions.each do |ext|
              file_path = File.join(path, "#{name}#{ext}")
              return file_path if File.exist?(file_path)
            end
          end

          nil
        end

        ##
        # Build a Prompt object from a file
        #
        # @param file_path [String] path to the prompt file
        # @param context [Hash] variables for interpolation/ERB
        # @return [Prompt] the constructed prompt
        #
        # Processing steps:
        # 1. Read file content
        # 2. Process ERB if applicable (.erb extension)
        # 3. Parse YAML frontmatter if present
        # 4. Extract system/user sections
        # 5. Apply variable interpolation (for non-ERB files)
        # 6. Build Prompt object with messages and metadata
        #
        def build_prompt_from_file(file_path, context)
          content = File.read(file_path)

          # Process ERB if needed
          content = process_erb(content, context) if should_process_erb?(file_path)

          # Parse frontmatter if present
          metadata = {}
          prompt_content = content

          if content.start_with?("---\n")
            parts = content.split("---\n", 3)
            if parts.length >= 3
              metadata = YAML.safe_load(parts[1]) || {}
              prompt_content = parts[2].strip
            end
          end

          # Extract sections (system/user) or use whole content
          system_content, user_content = extract_sections(prompt_content)

          # Apply simple interpolation for non-ERB files
          unless should_process_erb?(file_path)
            system_content = interpolate(system_content, context) if system_content
            user_content = interpolate(user_content, context) if user_content
            prompt_content = interpolate(prompt_content, context) if !system_content && !user_content
          end

          # Build messages
          messages = []

          messages << { role: "system", content: system_content } if system_content && !system_content.strip.empty?

          if user_content && !user_content.strip.empty?
            messages << { role: "user", content: user_content }
          elsif messages.empty?
            # If no sections found, treat whole content as user message
            messages << { role: "user", content: prompt_content }
          end

          # Create prompt
          Prompt.new(
            id: metadata["id"] || File.basename(file_path, ".*").sub(/\.md$/, ""),
            version: metadata["version"] || "1.0",
            messages: messages,
            variables: extract_variables(prompt_content, context),
            metadata: metadata
          )
        end

        ##
        # Check if a file should be processed with ERB
        #
        # @param file_path [String] path to check
        # @return [Boolean] true if file has ERB extension
        #
        def should_process_erb?(file_path)
          @erb_extensions.any? { |ext| file_path.end_with?(ext) }
        end

        ##
        # Process content through ERB template engine
        #
        # @param content [String] ERB template content
        # @param context [Hash] variables made available to template
        # @return [String] processed content
        #
        def process_erb(content, context)
          erb_context = ErbContext.new(context)
          erb = ERB.new(content, trim_mode: "-")
          erb.result(erb_context.get_binding)
        end

        ##
        # Extract system and user sections from content
        #
        # @param content [String] prompt content
        # @return [Array<String, String>] [system_content, user_content]
        #
        # Supports two section formats:
        # 1. Markdown headers: # System and # User
        # 2. HTML comments: <!-- system --> and <!-- user -->
        #
        # @example Markdown format
        #   # System
        #   You are an assistant.
        #
        #   # User
        #   Help me with this.
        #
        # @example HTML comment format
        #   <!-- system -->
        #   You are an assistant.
        #
        #   <!-- user -->
        #   Help me with this.
        #
        def extract_sections(content)
          system_content = nil
          user_content = nil

          # Look for section markers
          if content =~ /^#+\s*system\s*$/i
            content.split(/^#+\s*(?:system|user)\s*$/i)
            system_parts = content.scan(/^#+\s*system\s*$(.*?)(?=^#+\s*user\s*$|\z)/mi)
            user_parts = content.scan(/^#+\s*user\s*$(.*?)(?=^#+\s*system\s*$|\z)/mi)

            system_content = system_parts.map { |part| part[0].strip }.join("\n\n") unless system_parts.empty?
            user_content = user_parts.map { |part| part[0].strip }.join("\n\n") unless user_parts.empty?
          elsif content.include?("<!-- system -->") || content.include?("<!-- user -->")
            # HTML comment style sections
            system_parts = content.scan(/<!--\s*system\s*-->(.*?)(?=<!--\s*user\s*-->|\z)/mi)
            user_parts = content.scan(/<!--\s*user\s*-->(.*?)(?=<!--\s*system\s*-->|\z)/mi)

            system_content = system_parts.map { |part| part[0].strip }.join("\n\n") unless system_parts.empty?
            user_content = user_parts.map { |part| part[0].strip }.join("\n\n") unless user_parts.empty?
          end

          [system_content, user_content]
        end

        ##
        # Interpolate variables in content using {{variable}} syntax
        #
        # @param content [String, nil] content with variable placeholders
        # @param context [Hash] variables to substitute
        # @return [String, nil] interpolated content
        #
        # @example
        #   interpolate("Hello {{name}}!", name: "Alice")
        #   # => "Hello Alice!"
        #
        def interpolate(content, context)
          return nil unless content

          # Simple variable interpolation for {{variable}} syntax
          content.gsub(/\{\{(\w+)\}\}/) do |match|
            var_name = ::Regexp.last_match(1).to_sym
            context[var_name] || match
          end
        end

        ##
        # Extract and merge variables from content and context
        #
        # @param content [String, nil] content to scan for variables
        # @param context [Hash] provided context variables
        # @return [Hash] merged variables
        #
        # For plain files: extracts {{variable}} patterns and merges with context
        # For ERB files: returns the full context (as ERB has access to all)
        #
        def extract_variables(content, context)
          # For ERB files, use the provided context
          # For simple files, find {{variable}} patterns
          if content
            found_vars = content.scan(/\{\{(\w+)\}\}/).flatten.uniq
            vars = {}
            found_vars.each { |var| vars[var.to_sym] = context[var.to_sym] }
            vars.merge(context)
          else
            context
          end
        end

        ##
        # Context wrapper for ERB template evaluation
        #
        # This class provides a clean binding context for ERB templates with:
        # - Dynamic method generation for each context variable
        # - Helper methods for common formatting tasks
        # - Safe evaluation environment
        #
        # @example Using in ERB template
        #   <%= list(items) %>
        #   <%= code_block(snippet, "ruby") %>
        #   <%= if_present(value, "Value: ") %>
        #
        class ErbContext
          def initialize(variables = {})
            @variables = variables

            # Define methods for each variable
            variables.each do |key, value|
              define_singleton_method(key) { value }
            end
          end

          def get_binding
            binding
          end

          # Helper methods available in templates

          ##
          # HTML escape text for safety
          #
          # @param text [String] text to escape
          # @return [String] escaped text
          #
          def h(text)
            ERB::Util.html_escape(text)
          end

          ##
          # Convert object to pretty-printed JSON
          #
          # @param object [Object] object to convert
          # @return [String] formatted JSON
          #
          def json(object)
            JSON.pretty_generate(object)
          end

          ##
          # Create a bulleted list
          #
          # @param items [Array] items to list
          # @param bullet [String] bullet character
          # @return [String] formatted list
          #
          def list(items, bullet = "-")
            items.map { |item| "#{bullet} #{item}" }.join("\n")
          end

          ##
          # Create a numbered list
          #
          # @param items [Array] items to list
          # @return [String] numbered list
          #
          def numbered_list(items)
            items.each_with_index.map { |item, i| "#{i + 1}. #{item}" }.join("\n")
          end

          ##
          # Create a markdown code block
          #
          # @param content [String] code content
          # @param language [String] syntax highlighting language
          # @return [String] formatted code block
          #
          def code_block(content, language = "")
            "```#{language}\n#{content}\n```"
          end

          ##
          # Create a markdown table
          #
          # @param headers [Array<String>] table headers
          # @param rows [Array<Array>] table rows
          # @return [String] formatted markdown table
          #
          def table(headers, rows)
            header_row = "| #{headers.join(' | ')} |"
            separator = "| " + headers.map { |h| "-" * h.length }.join(" | ") + " |"

            data_rows = rows.map do |row|
              "| #{row.map(&:to_s).join(' | ')} |"
            end

            [header_row, separator, *data_rows].join("\n")
          end

          ##
          # Conditionally include content if value is present
          #
          # @param value [Object] value to check
          # @param prefix [String] text to prepend if present
          # @param suffix [String] text to append if present
          # @return [String] formatted text or empty string
          #
          # @example
          #   <%= if_present(user.title, "Title: ", "\n") %>
          #
          def if_present(value, prefix = "", suffix = "")
            return "" if value.nil? || value.to_s.strip.empty?

            "#{prefix}#{value}#{suffix}"
          end

          ##
          # Indent text by specified spaces
          #
          # @param text [String] text to indent
          # @param spaces [Integer] number of spaces
          # @return [String] indented text
          #
          def indent(text, spaces = 2)
            text.lines.map { |line| (" " * spaces) + line }.join
          end

          ##
          # Wrap text to specified width
          #
          # @param text [String] text to wrap
          # @param width [Integer] maximum line width
          # @return [String] wrapped text
          #
          def wrap(text, width = 80)
            text.scan(/.{1,#{width}}(?:\s|$)/).join("\n")
          end
        end
      end
    end
  end
end
