# frozen_string_literal: true

require "raaf-core"
require "raaf-dsl"
require_relative "raaf/tools/version"

# Core tools (alphabetically organized)
require_relative "raaf/tools/code_interpreter_tool"
require_relative "raaf/tools/computer_tool"
require_relative "raaf/tools/confluence_tool"
require_relative "raaf/tools/document_tool"
require_relative "raaf/tools/file_search_tool"
require_relative "raaf/tools/local_shell_tool"
require_relative "raaf/tools/perplexity_tool"
require_relative "raaf/tools/tavily_search_tool"
require_relative "raaf/tools/vector_search_tool"
require_relative "raaf/tools/web_search_tool"

# Basic tools
require_relative "raaf/tools/basic/math_tools"
require_relative "raaf/tools/basic/text_tools"

##
# RAAF Tools - Simplified tool integration framework
#
# This gem provides core tools for RAAF agents with a flat, consistent architecture.
# All tools follow convention over configuration with simple Ruby classes.
#
# == Available Tool Categories
#
# === Core Tools
# * CodeInterpreterTool - Execute and interpret code
# * ComputerTool - Control computer interfaces
# * ConfluenceTool - Integrate with Confluence
# * DocumentTool - Process various document formats
# * FileSearchTool - Search through files and documents
# * LocalShellTool - Execute shell commands
# * PerplexityTool - Web-grounded search with citations
# * TavilySearchTool - Advanced web search using Tavily API
# * VectorSearchTool - Vector-based search capabilities
# * WebSearchTool - Search the web for information
#
# === Basic Tools
# * Basic::MathTools - Mathematical calculations and operations
# * Basic::TextTools - Text processing and manipulation
#
# == Usage
#
#   require 'raaf-tools'
#
#   # Create agent with tools
#   agent = RAAF::Agent.new(
#     name: "Assistant",
#     instructions: "Help with various tasks using available tools",
#     model: "gpt-4o"
#   )
#
#   # Use tools with simple syntax
#   agent.uses_tool :perplexity        # Discovers RAAF::Tools::PerplexityTool
#   agent.uses_tool :tavily_search     # Discovers RAAF::Tools::TavilySearchTool
#   agent.uses_tool :code_interpreter  # Discovers RAAF::Tools::CodeInterpreterTool
#
# @author Ruby AI Agents Factory Team
# @since 1.0.0
module RAAF
  module Tools
    # Version is defined in raaf/tools/version.rb
  end
end
