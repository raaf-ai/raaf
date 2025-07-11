#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates the WebSearchTool integration with OpenAI Agents Ruby.
# WebSearchTool provides access to OpenAI's hosted web search functionality,
# enabling agents to search the web for current information and real-time data.
# This tool uses OpenAI's Responses API to perform web searches securely and efficiently,
# making it ideal for agents that need up-to-date information.

require_relative "../lib/openai_agents"

# OpenAI API key is required for web search functionality
unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  exit 1
end

puts "=== Web Search Tool Example ==="
puts

# ============================================================================
# TOOL SETUP
# ============================================================================

# Create a web search tool instance
# This tool integrates with OpenAI's hosted web search service
web_search_tool = OpenAIAgents::Tools::WebSearchTool.new(
  user_location: "San Francisco, CA",  # Optional: helps with location-specific searches
  search_context_size: "medium"        # Options: low, medium, high
)

puts "Web search tool initialized:"
puts "- User location: #{web_search_tool.user_location}"
puts "- Search context size: #{web_search_tool.search_context_size}"
puts

# ============================================================================
# EXAMPLE 1: BASIC WEB SEARCH
# ============================================================================

puts "1. Basic web search:"

# Create an agent with web search capability
search_agent = OpenAIAgents::Agent.new(
  name: "WebSearchAgent",
  instructions: "You are a research assistant with access to web search. Use web search to find current information and answer questions with up-to-date data.",
  model: "gpt-4o"
)

# Add the web search tool to the agent
search_agent.add_tool(web_search_tool)

# Create runner for the search agent
runner = OpenAIAgents::Runner.new(agent: search_agent)

# Test basic web search functionality
begin
  basic_search_messages = [{
    role: "user",
    content: "What are the latest developments in artificial intelligence this week?"
  }]

  result = runner.run(basic_search_messages)
  puts "Search result: #{result.final_output}"
rescue StandardError => e
  puts "Basic search error: #{e.message}"
  puts "This might be due to API limitations or network issues."
end

puts

# ============================================================================
# EXAMPLE 2: CURRENT EVENTS AGENT
# ============================================================================

puts "2. Current events agent:"

# Create an agent specialized for current events
news_agent = OpenAIAgents::Agent.new(
  name: "NewsAgent",
  instructions: "You are a news and current events assistant. Always search for the most recent information and provide accurate, up-to-date news summaries.",
  model: "gpt-4o"
)

# Add web search tool for current information
news_agent.add_tool(web_search_tool)

# Create runner for news agent
news_runner = OpenAIAgents::Runner.new(agent: news_agent)

# Test current events search
begin
  news_messages = [{
    role: "user",
    content: "What are the major technology news stories from this week?"
  }]

  news_result = news_runner.run(news_messages)
  puts "News summary: #{news_result.final_output}"
rescue StandardError => e
  puts "News search error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 3: RESEARCH ASSISTANT WITH MULTIPLE TOOLS
# ============================================================================

puts "3. Research assistant with multiple tools:"

# Define additional research tools
def analyze_search_results(results:, analysis_type: "summary")
  # Simulate analysis of search results
  case analysis_type.downcase
  when "summary"
    "Summary analysis of search results: Key findings extracted and synthesized."
  when "sources"
    "Source analysis: Credibility assessment and citation information provided."
  when "trends"
    "Trend analysis: Patterns and trends identified from search results."
  else
    "Analysis type '#{analysis_type}' not supported."
  end
end

def fact_check(claim:, sources: [])
  # Simulate fact-checking functionality
  "Fact-check result for claim: '#{claim}' - Analysis based on #{sources.size} sources."
end

# Create a comprehensive research agent
research_agent = OpenAIAgents::Agent.new(
  name: "ResearchAgent",
  instructions: "You are a comprehensive research assistant. Use web search to find current information, then analyze and fact-check the results. Always provide citations and source information.",
  model: "gpt-4o"
)

# Add multiple research tools
research_agent.add_tool(web_search_tool)
research_agent.add_tool(method(:analyze_search_results))
research_agent.add_tool(method(:fact_check))

# Create runner for research agent
research_runner = OpenAIAgents::Runner.new(agent: research_agent)

# Test comprehensive research
begin
  research_messages = [{
    role: "user",
    content: "Research the current state of renewable energy adoption globally. I need a summary with fact-checked information and source analysis."
  }]

  research_result = research_runner.run(research_messages)
  puts "Research result: #{research_result.final_output}"
rescue StandardError => e
  puts "Research error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 4: LOCATION-SPECIFIC SEARCH
# ============================================================================

puts "4. Location-specific search:"

# Create a location-aware web search tool
location_tool = OpenAIAgents::Tools::WebSearchTool.new(
  user_location: "New York, NY",
  search_context_size: "high"  # Use high context for detailed local information
)

# Create a local information agent
local_agent = OpenAIAgents::Agent.new(
  name: "LocalInfoAgent",
  instructions: "You are a local information assistant. Use web search to find location-specific information and provide relevant local context.",
  model: "gpt-4o"
)

# Add location-aware search tool
local_agent.add_tool(location_tool)

# Create runner for local agent
local_runner = OpenAIAgents::Runner.new(agent: local_agent)

# Test location-specific search
begin
  local_messages = [{
    role: "user",
    content: "What are the best restaurants that opened in New York this month?"
  }]

  local_result = local_runner.run(local_messages)
  puts "Local search result: #{local_result.final_output}"
rescue StandardError => e
  puts "Local search error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 5: STREAMING WEB SEARCH
# ============================================================================

puts "5. Streaming web search:"

# Create a streaming search tool
streaming_tool = OpenAIAgents::Tools::WebSearchTool.new(
  search_context_size: "medium"
)

# Test streaming search functionality
begin
  puts "Streaming search results:"
  
  # Use the streaming capability of the web search tool
  streaming_tool.search_with_streaming("latest developments in quantum computing") do |chunk|
    print chunk
    $stdout.flush
  end
  
  puts "\nStreaming search completed."
rescue StandardError => e
  puts "Streaming search error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 6: MULTI-QUERY RESEARCH
# ============================================================================

puts "6. Multi-query research:"

# Create an agent that performs multiple related searches
multi_query_agent = OpenAIAgents::Agent.new(
  name: "MultiQueryAgent",
  instructions: "You are a thorough research assistant. When given a complex topic, break it down into multiple specific search queries to gather comprehensive information.",
  model: "gpt-4o"
)

# Add web search tool
multi_query_agent.add_tool(web_search_tool)

# Create runner
multi_query_runner = OpenAIAgents::Runner.new(agent: multi_query_agent)

# Test multi-query research
begin
  multi_query_messages = [{
    role: "user",
    content: "I need comprehensive information about electric vehicle market trends. Please research market size, major players, recent developments, and future projections."
  }]

  multi_query_result = multi_query_runner.run(multi_query_messages)
  puts "Multi-query research result: #{multi_query_result.final_output}"
rescue StandardError => e
  puts "Multi-query research error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 7: SEARCH CONTEXT SIZE COMPARISON
# ============================================================================

puts "7. Search context size comparison:"

# Test different context sizes
context_sizes = ["low", "medium", "high"]

context_sizes.each do |size|
  puts "\nTesting context size: #{size}"
  
  begin
    # Create tool with specific context size
    context_tool = OpenAIAgents::Tools::WebSearchTool.new(
      search_context_size: size
    )
    
    # Create agent with this tool
    context_agent = OpenAIAgents::Agent.new(
      name: "ContextAgent",
      instructions: "You are a search assistant. Use web search to find information about the given topic.",
      model: "gpt-4o"
    )
    
    context_agent.add_tool(context_tool)
    context_runner = OpenAIAgents::Runner.new(agent: context_agent)
    
    # Test search with this context size
    context_messages = [{
      role: "user",
      content: "What is the current price of Bitcoin?"
    }]
    
    context_result = context_runner.run(context_messages)
    puts "Context size #{size} result: #{context_result.final_output[0..200]}..."
    
  rescue StandardError => e
    puts "Context size #{size} error: #{e.message}"
  end
end

puts

# ============================================================================
# EXAMPLE 8: ERROR HANDLING AND FALLBACKS
# ============================================================================

puts "8. Error handling and fallbacks:"

# Define a fallback search method
def fallback_search(query:)
  "Fallback search result for: '#{query}' - Using cached or alternative data sources."
end

# Create an agent with fallback capabilities
fallback_agent = OpenAIAgents::Agent.new(
  name: "FallbackAgent",
  instructions: "You are a resilient search assistant. Use web search primarily, but fall back to alternative methods if web search fails.",
  model: "gpt-4o"
)

# Add both web search and fallback tools
fallback_agent.add_tool(web_search_tool)
fallback_agent.add_tool(method(:fallback_search))

# Create runner
fallback_runner = OpenAIAgents::Runner.new(agent: fallback_agent)

# Test fallback capabilities
begin
  fallback_messages = [{
    role: "user",
    content: "Search for information about machine learning algorithms. If web search fails, use fallback methods."
  }]

  fallback_result = fallback_runner.run(fallback_messages)
  puts "Fallback search result: #{fallback_result.final_output}"
rescue StandardError => e
  puts "Fallback search error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 9: SEARCH RESULT VALIDATION
# ============================================================================

puts "9. Search result validation:"

# Define validation tools
def validate_search_results(results:, validation_type: "accuracy")
  case validation_type.downcase
  when "accuracy"
    "Accuracy validation: Cross-referenced with multiple sources for verification."
  when "recency"
    "Recency validation: Checked publication dates and freshness of information."
  when "relevance"
    "Relevance validation: Assessed alignment with search query and user intent."
  else
    "Validation type '#{validation_type}' not supported."
  end
end

# Create a validation-focused agent
validation_agent = OpenAIAgents::Agent.new(
  name: "ValidationAgent",
  instructions: "You are a meticulous search assistant. Always validate search results for accuracy, recency, and relevance before presenting them.",
  model: "gpt-4o"
)

# Add search and validation tools
validation_agent.add_tool(web_search_tool)
validation_agent.add_tool(method(:validate_search_results))

# Create runner
validation_runner = OpenAIAgents::Runner.new(agent: validation_agent)

# Test validation workflow
begin
  validation_messages = [{
    role: "user",
    content: "Search for recent scientific breakthroughs in medicine and validate the accuracy and recency of the findings."
  }]

  validation_result = validation_runner.run(validation_messages)
  puts "Validation result: #{validation_result.final_output}"
rescue StandardError => e
  puts "Validation error: #{e.message}"
end

puts

# ============================================================================
# CONFIGURATION DISPLAY
# ============================================================================

puts "=== Web Search Tool Configuration ==="
puts "Tool: #{web_search_tool.class.name}"
puts "User location: #{web_search_tool.user_location || 'Not specified'}"
puts "Search context size: #{web_search_tool.search_context_size}"
puts "API endpoint: #{OpenAIAgents::Tools::WebSearchTool::BASE_URL}"
puts "Authentication: Using OPENAI_API_KEY environment variable"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Example Complete ==="
puts
puts "Key Web Search Tool Features:"
puts "1. OpenAI hosted web search through Responses API"
puts "2. Configurable search context size (low, medium, high)"
puts "3. Location-aware search capabilities"
puts "4. Streaming search results for real-time updates"
puts "5. Integration with multi-tool research workflows"
puts "6. Error handling and fallback mechanisms"
puts "7. Search result validation and verification"
puts "8. Current events and real-time information access"
puts
puts "Best Practices:"
puts "- Use appropriate context size for your use case"
puts "- Specify user location for location-specific searches"
puts "- Implement fallback mechanisms for reliability"
puts "- Validate search results for accuracy and relevance"
puts "- Consider rate limits and API usage costs"
puts "- Use streaming for real-time applications"
puts "- Combine with other tools for comprehensive research"
puts "- Handle errors gracefully with user-friendly messages"
puts
puts "Context Size Guidelines:"
puts "- Low: Fast, basic search results"
puts "- Medium: Balanced speed and detail (recommended)"
puts "- High: Comprehensive, detailed search results"
puts "- Consider API costs when choosing context size"