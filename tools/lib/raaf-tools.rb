# frozen_string_literal: true

require "raaf-core"
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
# @author Ruby AI Agents Factory Team
# @since 1.0.0
module RAAF
  module Tools
    # Version is now defined in raaf/tools/version.rb
  end
end
