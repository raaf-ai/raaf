# frozen_string_literal: true

# RAAF Unified Tools
#
# This file provides a single entry point for all migrated tools
# using the new unified tool architecture.
#
# All tools inherit from RAAF::Tool and follow convention over configuration

require_relative "../../../../lib/raaf/tool"
require_relative "../../../../lib/raaf/tool/api"
require_relative "../../../../lib/raaf/tool/native"
require_relative "../../../../lib/raaf/tool_registry"

# Load all unified tools
require_relative "unified/file_search"
require_relative "unified/web_search"
require_relative "unified/tavily_search"
require_relative "unified/scrapfly"
require_relative "unified/code_interpreter"
require_relative "unified/local_shell"
require_relative "unified/vector_search"
require_relative "unified/document"
require_relative "unified/image_generator"

module RAAF
  module Tools
    # Unified tool collection with all migrated tools
    module Unified
      # List of all available tools
      AVAILABLE_TOOLS = {
        # File and Search Tools
        file_search: FileSearchTool,
        hosted_file_search: HostedFileSearchTool,
        
        # Web Search Tools
        web_search: WebSearchTool,
        tavily_search: TavilySearchTool,
        
        # ScrapFly Tools
        scrapfly_page_fetch: ScrapflyPageFetchTool,
        scrapfly_extract: ScrapflyExtractTool,
        scrapfly_screenshot: ScrapflyScreenshotTool,
        
        # Code and Shell Tools
        code_interpreter: CodeInterpreterTool,
        local_shell: LocalShellTool,
        advanced_shell: AdvancedShellTool,
        
        # Vector Tools
        vector_search: VectorSearchTool,
        vector_index: VectorIndexTool,
        
        # Document Tools
        document: DocumentTool,
        report: ReportTool,
        
        # Image Tools
        image_generator: ImageGeneratorTool
      }.freeze

      # Tool categories for organization
      TOOL_CATEGORIES = {
        search: [:file_search, :hosted_file_search, :web_search, :tavily_search, :vector_search],
        web: [:scrapfly_page_fetch, :scrapfly_extract, :scrapfly_screenshot],
        code: [:code_interpreter, :local_shell, :advanced_shell],
        document: [:document, :report],
        media: [:image_generator],
        data: [:vector_search, :vector_index]
      }.freeze

      # Get tool class by name
      #
      # @param name [Symbol, String] Tool name
      # @return [Class, nil] Tool class if found
      def self.get_tool(name)
        AVAILABLE_TOOLS[name.to_sym]
      end

      # List tools by category
      #
      # @param category [Symbol] Category name
      # @return [Array<Symbol>] Tool names in category
      def self.tools_in_category(category)
        TOOL_CATEGORIES[category.to_sym] || []
      end

      # Get all native tools (executed by OpenAI)
      #
      # @return [Hash<Symbol, Class>] Native tool classes
      def self.native_tools
        AVAILABLE_TOOLS.select do |_, klass|
          klass < RAAF::Tool::Native
        end
      end

      # Get all API tools (external services)
      #
      # @return [Hash<Symbol, Class>] API tool classes
      def self.api_tools
        AVAILABLE_TOOLS.select do |_, klass|
          klass < RAAF::Tool::API
        end
      end

      # Get all function tools (local execution)
      #
      # @return [Hash<Symbol, Class>] Function tool classes
      def self.function_tools
        AVAILABLE_TOOLS.reject do |_, klass|
          klass < RAAF::Tool::Native || klass < RAAF::Tool::API
        end
      end

      # Register all tools in the global registry
      #
      # This ensures tools are discoverable by name
      def self.register_all!
        AVAILABLE_TOOLS.each do |name, klass|
          RAAF::ToolRegistry.register(name, klass)
        end
      end

      # Create tool instance by name with options
      #
      # @param name [Symbol, String] Tool name
      # @param options [Hash] Tool initialization options
      # @return [RAAF::Tool, nil] Tool instance if found
      def self.create_tool(name, **options)
        tool_class = get_tool(name)
        tool_class&.new(**options)
      end

      # Load tool presets for common configurations
      #
      # @return [Hash<Symbol, Proc>] Tool factory methods
      def self.tool_presets
        {
          # Web research toolkit
          web_research: -> {
            [
              create_tool(:web_search),
              create_tool(:tavily_search),
              create_tool(:scrapfly_page_fetch)
            ]
          },
          
          # File analysis toolkit
          file_analysis: -> {
            [
              create_tool(:file_search),
              create_tool(:document),
              create_tool(:code_interpreter)
            ]
          },
          
          # Development toolkit
          development: -> {
            [
              create_tool(:local_shell, safe_mode: true),
              create_tool(:file_search),
              create_tool(:code_interpreter)
            ]
          },
          
          # Data analysis toolkit
          data_analysis: -> {
            [
              create_tool(:code_interpreter),
              create_tool(:vector_search),
              create_tool(:document)
            ]
          }
        }
      end
    end
  end
end

# Auto-register all tools on load
RAAF::Tools::Unified.register_all!