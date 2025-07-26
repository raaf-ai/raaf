# frozen_string_literal: true

require_relative "../lib/raaf-dsl"

# Prompt class for WebSearchAgent
class WebSearchPrompt < RAAF::DSL::Prompts::Base
  def system
    <<~SYSTEM
      You are a helpful assistant that can search the web for current information.

      When users ask questions that require up-to-date information, use the web_search tool
      to find relevant and current data.

      Always provide accurate information based on your search results and cite when#{' '}
      information comes from web searches.
    SYSTEM
  end

  def user
    "Hello there! Please help me search for information."
  end
end
