#!/usr/bin/env ruby
# frozen_string_literal: true

# Web Search Example
#
# This example demonstrates how to use the built-in web search tool
# with the RAAF DSL.

require_relative "../lib/raaf-dsl"

# Ensure TAVILY_API_KEY is set
unless ENV["TAVILY_API_KEY"]
  puts "Warning: TAVILY_API_KEY not set. Web search will not work."
  puts "Get your API key from https://tavily.com"
  exit 1
end

# Create a research agent with web search capabilities
research_agent = RAAF::DSL::AgentBuilder.build do
  name "ResearchAgent"
  instructions <<~INSTRUCTIONS
    You are a research assistant that helps users find information on the web.
    Use web search to find current, accurate information.
    Summarize findings clearly and cite your sources.
  INSTRUCTIONS
  model "gpt-4o"

  # Enable web search with configuration
  use_web_search do
    api_key ENV.fetch("TAVILY_API_KEY", nil)
    max_results 5
    include_raw_content true
    search_depth "advanced" # basic or advanced
  end

  # Add a tool to format citations
  tool :format_citation do |title, url, snippet|
    {
      citation: "[#{title}](#{url})",
      summary: snippet
    }
  end
end

puts "=== Research Agent Created ==="
puts "Tools available: #{research_agent.tools.map(&:name).join(', ')}"

# Create a runner
runner = RAAF::Runner.new(agent: research_agent)

# Example research queries
queries = [
  "What are the latest developments in quantum computing?",
  "Find recent news about renewable energy innovations",
  "What are the current best practices for Ruby on Rails security?"
]

puts "\n=== Research Examples ===\n"

queries.each_with_index do |query, i|
  puts "\n--- Query #{i + 1}: #{query} ---"

  result = runner.run(query)

  # Display the agent's response
  puts "\nAgent Response:"
  puts result.messages.last[:content]

  # Check if web search was used
  if result.messages.any? { |m| m[:tool_calls]&.any? { |tc| tc[:name] == "web_search" } }
    puts "\n✓ Web search tool was used"
  end

  puts "\n" + ("=" * 50)
end

# Example: Create a specialized news agent
news_agent = RAAF::DSL::AgentBuilder.build do
  name "NewsAgent"
  instructions <<~INSTRUCTIONS
    You are a news aggregator that finds the latest news on specific topics.
    Focus on finding news from the last 24-48 hours.
    Organize findings by relevance and recency.
  INSTRUCTIONS
  model "gpt-4o"

  # Configure web search for news
  use_web_search do
    api_key ENV.fetch("TAVILY_API_KEY", nil)
    max_results 10
    search_depth "basic" # Faster for news
  end
end

puts "\n=== News Agent Example ===\n"

news_result = RAAF::Runner.new(agent: news_agent).run(
  "Find the latest news about artificial intelligence startups"
)

puts news_result.messages.last[:content]

# Example: Academic research agent with specific domains
academic_agent = RAAF::DSL::AgentBuilder.build do
  name "AcademicAgent"
  instructions <<~INSTRUCTIONS
    You are an academic research assistant.
    Focus on peer-reviewed sources and academic publications.
    Provide detailed citations in academic format.
  INSTRUCTIONS
  model "gpt-4o"

  use_web_search do
    api_key ENV.fetch("TAVILY_API_KEY", nil)
    max_results 5
    include_raw_content true
    search_depth "advanced"
    # You could add domain filtering here if the API supports it
  end
end

puts "\n=== Academic Research Example ===\n"

academic_result = RAAF::Runner.new(agent: academic_agent).run(
  "Find recent research papers on large language models and their applications in education"
)

puts academic_result.messages.last[:content]
