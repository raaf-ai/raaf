# frozen_string_literal: true

require "raaf-core"
require_relative "raaf/tools/web_search_tool"
require_relative "raaf/tools/file_search_tool"

##
# RAAF Tools - Basic tool integration framework
#
# This gem provides basic tools for RAAF agents including web search
# and file search capabilities. These are the fundamental tools needed
# for most agent workflows.
#
# == Available Tools
#
# * WebSearchTool - Search the web for information
# * FileSearchTool - Search through files and documents
#
# == Usage
#
#   require 'raaf-tools'
#
#   # Create agent with web search
#   agent = RubyAIAgentsFactory::Agent.new(
#     name: "Research Assistant",
#     instructions: "Help with research tasks",
#     model: "gpt-4o"
#   )
#
#   # Add web search tool
#   web_search = RubyAIAgentsFactory::Tools::WebSearchTool.new
#   agent.add_tool(web_search)
#
#   # Add file search tool
#   file_search = RubyAIAgentsFactory::Tools::FileSearchTool.new
#   agent.add_tool(file_search)
#
# == Tool Configuration
#
# Tools can be configured with various options:
#
#   web_search = RubyAIAgentsFactory::Tools::WebSearchTool.new(
#     max_results: 10,
#     timeout: 30
#   )
#
# @author Ruby AI Agents Factory Team
# @since 1.0.0
module RubyAIAgentsFactory
  module Tools
    # Tools gem version
    VERSION = "0.1.0"
  end
end
