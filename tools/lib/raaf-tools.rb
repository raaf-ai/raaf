# frozen_string_literal: true

require "raaf-core"
require "raaf-dsl"
require_relative "raaf/tools/version"

# Core tools
require_relative "raaf/tools/web_search_tool"
require_relative "raaf/tools/file_search_tool"

# Basic tools
require_relative "raaf/tools/basic/math_tools"
require_relative "raaf/tools/basic/text_tools"

# Advanced tools
require_relative "raaf/tools/advanced/code_interpreter"
require_relative "raaf/tools/advanced/computer_tool"
require_relative "raaf/tools/code_interpreter_tool"
require_relative "raaf/tools/computer_tool"
require_relative "raaf/tools/confluence_tool"
require_relative "raaf/tools/document_tool"
require_relative "raaf/tools/local_shell_tool"
require_relative "raaf/tools/vector_search_tool"

# New DSL-based API tools
require_relative "raaf/tools/api/tavily_search"
require_relative "raaf/tools/api/scrapfly_page_fetch"
require_relative "raaf/tools/api/scrapfly_extract"
require_relative "raaf/tools/api/scrapfly_screenshot"

# New DSL-based Native tools
require_relative "raaf/tools/native/web_search"
require_relative "raaf/tools/native/code_interpreter"
require_relative "raaf/tools/native/image_generator"

# Unified tools
require_relative "raaf/tools/api/web_page_fetch"

##
# RAAF Tools - Comprehensive tool integration framework
#
# This gem provides all tools for RAAF agents including basic utilities,
# web search, file operations, and advanced enterprise tools.
#
# == Available Tool Categories
#
# === Core Tools
# * WebSearchTool - Search the web for information
# * FileSearchTool - Search through files and documents
#
# === Basic Tools
# * MathTools - Mathematical calculations and operations
# * TextTools - Text processing and manipulation
#
# === Advanced Tools
# * CodeInterpreterTool - Execute and interpret code
# * ComputerTool - Control computer interfaces
# * ConfluenceTool - Integrate with Confluence
# * DocumentTool - Process various document formats
# * LocalShellTool - Execute shell commands
# * VectorSearchTool - Vector-based search capabilities
#
# === New DSL-based API Tools
# * API::TavilySearch - Advanced web search using Tavily API
# * API::ScrapflyPageFetch - Web scraping with JavaScript rendering
# * API::ScrapflyExtract - Structured data extraction from web pages
# * API::ScrapflyScreenshot - Web page screenshot capture
# * API::WebPageFetch - Unified web fetching with intelligent service selection
#
# === New DSL-based Native Tools
# * Native::WebSearch - OpenAI hosted web search (native execution)
# * Native::CodeInterpreter - OpenAI code interpreter (native execution)
# * Native::ImageGenerator - DALL-E image generation (native execution)
#
# == Usage
#
#   require 'raaf-tools'
#
#   # Create agent with tools
#   agent = RAAF::Agent.new(
#     name: "Multi-Tool Assistant",
#     instructions: "Help with various tasks using available tools",
#     model: "gpt-4o"
#   )
#
#   # Add basic tools
#   agent.add_tool(RAAF::Tools::WebSearchTool.new)
#   agent.add_tool(RAAF::Tools::Basic::MathTools.new)
#   agent.add_tool(RAAF::Tools::Basic::TextTools.new)
#
#   # Add advanced tools
#   agent.add_tool(RAAF::Tools::CodeInterpreterTool.new)
#   agent.add_tool(RAAF::Tools::DocumentTool.new)
#
#   # Add new DSL-based API tools
#   agent.add_tool(RAAF::Tools::API::TavilySearch.new)
#   agent.add_tool(RAAF::Tools::API::ScrapflyPageFetch.new)
#   agent.add_tool(RAAF::Tools::API::ScrapflyExtract.new)
#
#   # Add new DSL-based Native tools  
#   agent.add_tool(RAAF::Tools::Native::WebSearch.new)
#   agent.add_tool(RAAF::Tools::Native::CodeInterpreter.new)
#
# @author Ruby AI Agents Factory Team
# @since 1.0.0
module RAAF
  module Tools
    # Version is now defined in raaf/tools/version.rb
  end
end
