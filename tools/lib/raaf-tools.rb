# frozen_string_literal: true

require "zeitwerk"
require "raaf-core"
require "raaf-dsl"

# Load version before Zeitwerk setup
require_relative "raaf/tools/version"

# Set up Zeitwerk loader for RAAF tools
loader = Zeitwerk::Loader.for_gem
loader.tag = "raaf-tools"

# Configure inflections for acronyms and special cases
loader.inflector.inflect(
  "mcp_tool" => "MCPTool",
  "pii" => "PII"
)

# Setup the loader
loader.setup

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

# Eager load if requested
loader.eager_load if ENV['RAAF_EAGER_LOAD'] == 'true'
