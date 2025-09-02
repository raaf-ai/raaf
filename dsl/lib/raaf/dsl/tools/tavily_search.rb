# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "base"

# Tavily Search Tool for AI Agent DSL
#
# Provides reliable web search functionality using Tavily's API,
# designed specifically for AI applications with clean, structured results.
# This tool is executable and can be used by both DSL agents and core RAAF.
#
# @example Basic usage in an agent
#   class MyAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::AgentDsl
#
#     uses_tool :tavily_search
#   end
#
# @example Direct usage
#   tool = RAAF::DSL::Tools::TavilySearch.new
#   result = tool.call(query: "Ruby AI frameworks")
#
# @example With custom configuration
#   class MyAgent < RAAF::DSL::Agents::Base
#     include RAAF::DSL::AgentDsl
#
#     uses_tool :tavily_search,
#       search_depth: "advanced",
#       max_results: 10,
#       include_domains: ["github.com", "stackoverflow.com"]
#   end
#
module RAAF
  module DSL
    module Tools
      class TavilySearch < Base
        # Valid search depth options
        VALID_SEARCH_DEPTHS = %w[basic advanced].freeze

        # Default configuration
        DEFAULT_CONFIG = {
          search_depth: "basic",
          max_results: 5,
          include_answer: false,
          include_raw_content: false,
          exclude_domains: [],
          include_domains: [],
          timeout: 30
        }.freeze

        def initialize(options = {})
          super(DEFAULT_CONFIG.merge(options || {}))
          validate_options!
        end

        # Returns the standardized tool name for Tavily search functionality
        #
        # @return [String] The tool name "tavily_search"
        def tool_name
          "tavily_search"
        end

        # Execute the Tavily search
        #
        # This method performs the actual API call to Tavily following Ruby's
        # callable convention. It can be used by both DSL agents and core RAAF.
        #
        # @param query [String] Search query
        # @param search_depth [String] "basic" or "advanced"
        # @param max_results [Integer] Number of results (1-20)
        # @param include_answer [Boolean] Include AI-generated summary
        # @param include_domains [Array<String>] Domains to include
        # @param exclude_domains [Array<String>] Domains to exclude
        # @return [Hash] Search results
        #
        def call(query:, search_depth: nil, max_results: nil, include_answer: nil,
                 include_domains: nil, exclude_domains: nil)
          # Use provided values or fall back to configured options
          search_depth ||= options[:search_depth]
          max_results ||= options[:max_results]
          include_answer = options[:include_answer] if include_answer.nil?
          include_domains ||= options[:include_domains]
          exclude_domains ||= options[:exclude_domains]

          # DEBUG: Log search query construction
          puts "\n🔍 [TAVILY SEARCH] Query Construction:"
          puts "   Query: #{query.inspect}"
          puts "   Search Depth: #{search_depth}"
          puts "   Max Results: #{max_results}"
          puts "   Include Answer: #{include_answer}"
          puts "   Include Domains: #{include_domains&.any? ? include_domains.join(', ') : 'None'}"
          puts "   Exclude Domains: #{exclude_domains&.any? ? exclude_domains.join(', ') : 'None'}"

          # Build request parameters
          params = {
            api_key: api_key,
            query: query,
            search_depth: search_depth,
            max_results: max_results,
            include_answer: include_answer,
            include_raw_content: options[:include_raw_content]
          }

          # Add domain filters if provided
          params[:include_domains] = include_domains if include_domains&.any?
          params[:exclude_domains] = exclude_domains if exclude_domains&.any?

          # DEBUG: Log final request parameters (without API key)
          debug_params = params.dup
          debug_params[:api_key] = "[REDACTED]"
          puts "\n📤 [TAVILY SEARCH] Request Parameters:"
          puts "   #{debug_params.inspect}"

          # Make the API request
          puts "\n⏳ [TAVILY SEARCH] Making API request to Tavily..."
          start_time = Time.now
          response = make_request(params)
          end_time = Time.now
          
          # DEBUG: Log API response details
          puts "\n📥 [TAVILY SEARCH] API Response (#{((end_time - start_time) * 1000).round(2)}ms):"
          if response["error"]
            puts "   ❌ ERROR: #{response['error']}"
          else
            puts "   ✅ SUCCESS"
            puts "   Results Count: #{(response['results'] || []).length}"
            puts "   Has Answer: #{response['answer'] ? 'Yes' : 'No'}"
            puts "   Follow-up Questions: #{(response['follow_up_questions'] || []).length}"
            
            # Log basic info about each result
            if response["results"]&.any?
              puts "   📋 Results Summary:"
              response["results"].each_with_index do |result, index|
                puts "      #{index + 1}. #{result['title']} (Score: #{result['score']})"
                puts "         URL: #{result['url']}"
                puts "         Content Length: #{result['content']&.length || 0} chars"
              end
            end
          end
          
          # Return structured results
          formatted_response = format_response(response, query)
          
          # DEBUG: Log formatted response
          puts "\n🔄 [TAVILY SEARCH] Formatted Response:"
          puts "   Success: #{formatted_response[:success]}"
          puts "   Results Count: #{formatted_response[:results_count] || 0}"
          puts "   Has Answer: #{formatted_response[:answer] ? 'Yes' : 'No'}"
          
          formatted_response
        end

        # Alias for compatibility
        alias execute call

        protected

        def build_tool_definition
          {
            type: "function",
            function: {
              name: tool_name,
              description: "Search the web for current information using Tavily API. Returns structured results with titles, URLs, content summaries, and relevance scores.",
              parameters: {
                type: "object",
                properties: {
                  query: {
                    type: "string",
                    description: "The search query. Supports site: operators (e.g., 'site:github.com Ruby AI tools')"
                  },
                  search_depth: {
                    type: "string",
                    enum: VALID_SEARCH_DEPTHS,
                    description: "Search depth - 'basic' for quick results, 'advanced' for comprehensive search"
                  },
                  max_results: {
                    type: "integer",
                    minimum: 1,
                    maximum: 20,
                    description: "Maximum number of results to return"
                  },
                  include_domains: {
                    type: "array",
                    items: { type: "string" },
                    description: "Only include results from these domains"
                  },
                  exclude_domains: {
                    type: "array",
                    items: { type: "string" },
                    description: "Exclude results from these domains"
                  }
                },
                required: ["query"],
                additionalProperties: false
              }
            }
          }
        end

        private

        def validate_options!
          if options[:search_depth] && !VALID_SEARCH_DEPTHS.include?(options[:search_depth])
            raise ArgumentError,
                  "Invalid search_depth: #{options[:search_depth]}. Must be one of: #{VALID_SEARCH_DEPTHS.join(', ')}"
          end

          return unless options[:max_results] && (options[:max_results] < 1 || options[:max_results] > 20)

          raise ArgumentError, "Invalid max_results: #{options[:max_results]}. Must be between 1 and 20"
        end

        def api_key
          ENV["TAVILY_API_KEY"] || raise("TAVILY_API_KEY environment variable not set")
        end

        def make_request(params)
          uri = URI("https://api.tavily.com/search")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.read_timeout = options[:timeout]
          http.open_timeout = options[:timeout]

          request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
          request.body = params.to_json

          response = http.request(request)
          JSON.parse(response.body)
        rescue => e
          { "error" => e.message }
        end

        def format_response(response, query)
          if response["error"]
            {
              success: false,
              error: response["error"],
              query: query,
              results: []
            }
          else
            {
              success: true,
              query: query,
              results_count: (response["results"] || []).length,
              results: response["results"] || [],
              answer: response["answer"],
              follow_up_questions: response["follow_up_questions"] || []
            }
          end
        end

        # Application metadata for enhanced tool definition
        def application_metadata
          metadata = {}

          metadata[:search_depth] = options[:search_depth]
          metadata[:max_results] = options[:max_results]

          metadata[:include_domains] = options[:include_domains] if options[:include_domains].any?

          metadata[:exclude_domains] = options[:exclude_domains] if options[:exclude_domains].any?

          metadata
        end
      end
    end
  end
end
