# frozen_string_literal: true

# Example usage of the new RAAF DSL-based tools
#
# This file demonstrates how to use the new clean DSL tools that provide
# an 80%+ code reduction compared to the original implementations.

require "raaf-tools"

puts "=== RAAF New DSL Tools Usage Examples ==="
puts

# Example 1: API Tools Usage
puts "1. API Tools - External Service Integration"
puts "=" * 50

# Tavily Search Tool
puts ">> TavilySearch Tool"
tavily_tool = RAAF::Tools::API::TavilySearch.new
puts "   Tool name: #{tavily_tool.name}"
puts "   Enabled: #{tavily_tool.enabled?}"
puts "   Usage: tool.call(query: 'Ruby AI frameworks')"
puts

# ScrapFly Page Fetch Tool
puts ">> ScrapflyPageFetch Tool"
scrapfly_fetch_tool = RAAF::Tools::API::ScrapflyPageFetch.new
puts "   Tool name: #{scrapfly_fetch_tool.name}"
puts "   Enabled: #{scrapfly_fetch_tool.enabled?}"
puts "   Usage: tool.call(url: 'https://example.com', format: 'markdown')"
puts

# ScrapFly Extract Tool
puts ">> ScrapflyExtract Tool"
scrapfly_extract_tool = RAAF::Tools::API::ScrapflyExtract.new
puts "   Tool name: #{scrapfly_extract_tool.name}"
puts "   Enabled: #{scrapfly_extract_tool.enabled?}"
puts "   Usage: tool.call(url: 'https://company.com', fields: ['name', 'description'])"
puts

# ScrapFly Screenshot Tool
puts ">> ScrapflyScreenshot Tool"
scrapfly_screenshot_tool = RAAF::Tools::API::ScrapflyScreenshot.new
puts "   Tool name: #{scrapfly_screenshot_tool.name}"
puts "   Enabled: #{scrapfly_screenshot_tool.enabled?}"
puts "   Usage: tool.call(url: 'https://example.com', format: 'png')"
puts

# Example 2: Native Tools Usage
puts "2. Native Tools - OpenAI Infrastructure"
puts "=" * 50

# Web Search Native Tool
puts ">> WebSearch Native Tool"
web_search_tool = RAAF::Tools::Native::WebSearch.new(
  user_location: "San Francisco, CA",
  search_context_size: "high"
)
puts "   Tool name: #{web_search_tool.name}"
puts "   Enabled: #{web_search_tool.enabled?}"
puts "   Native: #{web_search_tool.native?}"
puts "   Usage: Executed by OpenAI infrastructure (no local call method)"
puts

# Code Interpreter Native Tool
puts ">> CodeInterpreter Native Tool"
code_interpreter_tool = RAAF::Tools::Native::CodeInterpreter.new(
  timeout: 60,
  memory_limit: "512MB"
)
puts "   Tool name: #{code_interpreter_tool.name}"
puts "   Enabled: #{code_interpreter_tool.enabled?}"
puts "   Native: #{code_interpreter_tool.native?}"
puts "   Usage: Executed by OpenAI infrastructure (no local call method)"
puts

# Example 3: Tool Definitions for Agents
puts "3. Tool Definitions for Agent Integration"
puts "=" * 50

puts ">> TavilySearch Tool Definition:"
tavily_definition = tavily_tool.to_tool_definition
puts "   Type: #{tavily_definition[:type]}"
puts "   Function name: #{tavily_definition[:function][:name]}"
puts "   Parameters: #{tavily_definition[:function][:parameters][:required]}"
puts

puts ">> WebSearch Native Tool Definition:"
websearch_definition = web_search_tool.to_tool_definition
puts "   Type: #{websearch_definition[:type]}"
puts "   Configuration: #{websearch_definition[:web_search]}"
puts

# Example 4: Migration Benefits
puts "4. Migration Benefits"
puts "=" * 50
puts "✅ 80%+ code reduction from original implementations"
puts "✅ Zero boilerplate - clean DSL-based definitions"
puts "✅ Consistent `call` method convention for API tools"
puts "✅ Built-in HTTP methods via Tool::API base class"
puts "✅ Native OpenAI tool support via Tool::Native"
puts "✅ Automatic tool definition generation"
puts "✅ Environment-based configuration"
puts "✅ Comprehensive error handling"
puts

# Example 5: Agent Integration Pattern
puts "5. Agent Integration Pattern"
puts "=" * 50
puts <<~RUBY
  # Example agent setup with new tools
  agent = RAAF::Agent.new(name: "Research Assistant")
  
  # Add API tools for external data
  agent.add_tool(RAAF::Tools::API::TavilySearch.new)
  agent.add_tool(RAAF::Tools::API::ScrapflyPageFetch.new)
  
  # Add native tools for OpenAI features
  agent.add_tool(RAAF::Tools::Native::WebSearch.new)
  agent.add_tool(RAAF::Tools::Native::CodeInterpreter.new)
  
  # Tools are automatically configured and ready to use
  result = agent.run("Search for Ruby AI frameworks and analyze the code examples")
RUBY

puts "=" * 70
puts "All tools loaded and demonstrated successfully!"
puts "Set TAVILY_API_KEY and SCRAPFLY_API_KEY environment variables to enable API tools."