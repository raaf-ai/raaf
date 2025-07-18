# frozen_string_literal: true

# Predefined configurations for WebSearch tool to make common setups easier
#
# @example Using preset configurations in agents
#   class NewsAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::AgentDsl
#
#     # Use high-context search for detailed news analysis
#     uses_tool :web_search, WebSearchPresets.detailed_search
#   end
#
#   class QuickFactAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::AgentDsl
#
#     # Use quick search for simple fact-checking
#     uses_tool :web_search, WebSearchPresets.quick_search
#   end
#
module RAAF

  module DSL

    module Tools

      module WebSearchPresets

        # Quick search configuration for simple queries and fact-checking
        # Uses low context size for faster responses
        def self.quick_search(user_location: nil)
          {
            user_location: user_location,
            search_context_size: "low"
          }
        end

        # Standard search configuration with balanced performance and detail
        # Uses medium context size - good for most use cases
        def self.standard_search(user_location: nil)
          {
            user_location: user_location,
            search_context_size: "medium"
          }
        end

        # Detailed search configuration for comprehensive research
        # Uses high context size for thorough analysis
        def self.detailed_search(user_location: nil)
          {
            user_location: user_location,
            search_context_size: "high"
          }
        end

      end

    end

  end

end
