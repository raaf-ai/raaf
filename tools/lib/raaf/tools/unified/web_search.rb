# frozen_string_literal: true

require_relative "../../../../../lib/raaf/tool/native"

module RAAF
  module Tools
    module Unified
      # Native OpenAI web search tool
      #
      # Executed by OpenAI's infrastructure to search the web for current information.
      # This is the recommended approach for web searching in production.
      #
      class WebSearchTool < RAAF::Tool::Native
        configure name: "web_search",
                 description: "Search the web for current information using OpenAI's infrastructure"

        def initialize(user_location: nil, search_context_size: "auto", **options)
          super(**options)
          @user_location = user_location
          @search_context_size = search_context_size
        end

        native_config do
          web_search true
        end

        def to_tool_definition
          config = {}
          config[:user_location] = @user_location if @user_location
          config[:search_context_size] = @search_context_size if @search_context_size
          
          {
            type: "web_search",
            web_search: config.empty? ? true : config
          }
        end
      end
    end
  end
end