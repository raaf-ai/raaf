# frozen_string_literal: true

require_relative "../lib/ai_agent_dsl"
require_relative "web_search_prompt"

# Example agent demonstrating web search capabilities
class WebSearchAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl

  agent_name "web_search_agent"

  # Basic web search with default settings
  uses_tool :web_search

  # Configure the prompt class (REQUIRED)
  prompt_class WebSearchPrompt

  def agent_name
    "Web Search Assistant"
  end

  def build_schema
    {
      type: "object",
      properties: {
        response: { type: "string" },
        sources: {
          type: "array",
          items: { type: "string" }
        }
      },
      required: ["response"],
      additionalProperties: false
    }
  end
end

# Example agent with custom web search configuration
class NewsAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl

  agent_name "news_agent"

  # Use detailed search for comprehensive news analysis
  uses_tool :web_search,
            user_location: "San Francisco, CA",
            search_context_size: "high"

  def agent_name
    "News Research Assistant"
  end

  def build_instructions(_context = {})
    <<~INSTRUCTIONS
      You are a news research assistant specializing in current events and breaking news.

      Use web search to find the latest information about:
      - Breaking news stories
      - Market updates
      - Technology developments
      - Political events

      Provide comprehensive analysis based on multiple sources when possible.
    INSTRUCTIONS
  end
end

# Example agent using preset configurations
class TechAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::AgentDsl

  agent_name "tech_agent"

  # Use tech-focused preset configuration
  uses_tool :web_search, RAAF::DSL::Tools::WebSearchPresets.tech_search

  def agent_name
    "Technology Research Assistant"
  end

  def build_instructions(_context = {})
    <<~INSTRUCTIONS
      You are a technology research assistant focused on the latest developments#{' '}
      in the tech industry.

      Search for information about:
      - New product launches
      - Startup funding rounds
      - Technology trends
      - Developer tools and frameworks
      - AI and machine learning advances

      Provide technical insights and analysis based on current information.
    INSTRUCTIONS
  end
end
