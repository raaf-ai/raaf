# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../function_tool"

module RubyAIAgentsFactory
  module Tools
    ##
    # OpenAI hosted web search tool - matches Python specification exactly
    #
    # WebSearchTool provides web search capabilities through OpenAI's hosted
    # web search service via the Responses API. This tool allows agents to
    # search for current information on the web.
    #
    # Features:
    # - Real-time web search through OpenAI's infrastructure
    # - Location-aware search results
    # - Configurable search context size
    # - Streaming support for real-time results
    # - Python SDK compatibility
    #
    # @example Basic usage
    #   tool = WebSearchTool.new
    #   result = tool.web_search(query: "latest AI news")
    #
    # @example With location and context size
    #   tool = WebSearchTool.new(
    #     user_location: "San Francisco, CA",
    #     search_context_size: "high"
    #   )
    #
    # @example Streaming results
    #   tool.search_with_streaming("weather forecast") do |chunk|
    #     print chunk  # Real-time results
    #   end
    #
    # Reference: https://github.com/openai/openai-agents-python
    # Uses OpenAI Responses API for actual web search functionality
    class WebSearchTool < FunctionTool
      # OpenAI Responses API endpoint for web search
      BASE_URL = "https://api.openai.com/v1/responses"

      # @!attribute [r] user_location
      #   @return [String, Hash, nil] User's location for location-aware results
      # @!attribute [r] search_context_size
      #   @return [String] Search context size ("low", "medium", "high")
      attr_reader :user_location, :search_context_size

      ##
      # Initialize a new web search tool
      #
      # @param user_location [String, Hash, nil] User location for location-aware search
      #   Can be a string like "San Francisco, CA" or a hash with location details
      # @param search_context_size [String] Amount of context to include ("low", "medium", "high")
      # @param api_key [String, nil] OpenAI API key (defaults to OPENAI_API_KEY env var)
      # @raise [ArgumentError] if API key is missing or parameters are invalid
      #
      def initialize(user_location: nil, search_context_size: "medium", api_key: nil)
        @user_location = normalize_user_location(user_location)
        @search_context_size = validate_search_context_size(search_context_size)
        @api_key = api_key || ENV.fetch("OPENAI_API_KEY", nil)

        raise ArgumentError, "OpenAI API key is required for web search" unless @api_key

        super(method(:web_search),
              name: "web_search",
              description: "Search the web for current information using OpenAI's hosted web search",
              parameters: web_search_parameters)
      end

      ##
      # Perform a web search
      #
      # @param query [String] The search query
      # @param stream [Boolean] Whether to stream results (not used in non-streaming mode)
      # @return [String] Search results or error message
      #
      # @example
      #   results = tool.web_search(query: "Ruby programming tutorials")
      #
      def web_search(query:, stream: false)
        # Use OpenAI's hosted web search through Responses API
        search_with_responses_api(query)
      rescue StandardError => e
        "Web search error: #{e.message}"
      end

      ##
      # Perform a streaming web search
      #
      # Streams search results in real-time as they become available.
      # Useful for providing immediate feedback to users during searches.
      #
      # @param query [String] The search query
      # @yield [String] Yields content chunks as they arrive
      # @return [String] Accumulated search results
      #
      # @example Stream results to console
      #   tool.search_with_streaming("latest tech news") do |chunk|
      #     print chunk
      #   end
      #
      def search_with_streaming(query)
        uri = URI(BASE_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"

        body = {
          model: "gpt-4o",
          input: query,
          stream: true,
          tools: [
            {
              type: "web_search",
              web_search: {
                user_location: @user_location,
                search_context_size: @search_context_size
              }.compact
            }
          ]
        }

        request.body = body.to_json

        accumulated_content = String.new

        # Handle SSE streaming
        http.request(request) do |response|
          response.read_body do |chunk|
            # Process Server-Sent Events
            chunk.split("\n").each do |line|
              next unless line.start_with?("data: ")

              data = line[6..]
              next if data == "[DONE]"

              begin
                event = JSON.parse(data)
                content = process_stream_event(event)
                if content
                  accumulated_content << content
                  yield(content) if block_given?
                end
              rescue JSON::ParserError
                # Skip invalid JSON
              end
            end
          end
        end

        accumulated_content
      end

      ##
      # Returns the tool definition for OpenAI function calling
      #
      # @return [Hash] Tool definition in OpenAI format
      #
      def to_tool_definition
        {
          type: "function",
          name: "web_search",
          function: {
            name: "web_search",
            description: "Search the web for current information using OpenAI's hosted web search",
            parameters: web_search_parameters
          }
        }
      end

      private

      ##
      # Defines the parameters schema for the web search function
      #
      # @return [Hash] JSON Schema for web search parameters
      # @private
      #
      def web_search_parameters
        {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search query string"
            }
          },
          required: ["query"]
        }
      end

      ##
      # Performs web search using the OpenAI Responses API
      #
      # @param query [String] The search query
      # @return [String] Search results
      # @raise [RuntimeError] on API errors
      # @private
      #
      def search_with_responses_api(query)
        uri = URI(BASE_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"

        # Build request body with web search tool
        body = {
          model: "gpt-4o",
          input: query,
          tools: [
            {
              type: "web_search",
              web_search: {
                user_location: @user_location,
                search_context_size: @search_context_size
              }.compact
            }
          ]
        }

        request.body = body.to_json

        response = http.request(request)
        handle_response(response)
      end

      ##
      # Handles HTTP response from the API
      #
      # @param response [Net::HTTPResponse] The HTTP response
      # @return [String] Extracted search results
      # @raise [RuntimeError] on various API errors
      # @private
      #
      def handle_response(response)
        case response.code
        when "200"
          data = JSON.parse(response.body)
          extract_search_results(data)
        when "401"
          raise "Authentication failed. Check your OpenAI API key."
        when "429"
          raise "Rate limit exceeded. Please try again later."
        when "400"
          error_data = begin
            JSON.parse(response.body)
          rescue StandardError
            {}
          end
          error_msg = error_data.dig("error", "message") || "Bad request"
          raise "API Error: #{error_msg}"
        else
          raise "API Error: #{response.code} - #{response.body}"
        end
      end

      ##
      # Extracts search results from API response data
      #
      # @param data [Hash] Parsed API response
      # @return [String] Extracted text content or fallback message
      # @private
      #
      def extract_search_results(data)
        # Extract the final output from the response
        if data["output"]&.any?
          content = data["output"][0]
          return content["content"][0]["text"] if content["content"]&.any?
        end

        # Fallback if structure is different
        return data["text"] if data["text"]

        "Web search completed but no results returned."
      end

      ##
      # Processes a single streaming event
      #
      # @param event [Hash] Parsed SSE event data
      # @return [String, nil] Extracted text content or nil
      # @private
      #
      def process_stream_event(event)
        # Extract content from streaming event (based on a.rb implementation)
        if event["output"] && event["output"][0] && event["output"][0]["content"]
          content = event["output"][0]["content"][0]["text"]
          return content if content
        end
        nil
      end

      ##
      # Normalizes user location input to a consistent format
      #
      # @param location [String, Hash, nil] User location input
      # @return [String, Hash, nil] Normalized location
      # @raise [ArgumentError] if location type is invalid
      # @private
      #
      # @example String format
      #   normalize_user_location("San Francisco, CA")
      #   # => "San Francisco, CA"
      #
      # @example Hash format (Python-style)
      #   normalize_user_location({ "type" => "approximate", "city" => "New York" })
      #   # => { "type" => "approximate", "city" => "New York" }
      #
      def normalize_user_location(location)
        return nil if location.nil?

        case location
        when String
          # Support simple string format like "San Francisco, CA"
          location
        when Hash
          # Support Python-style hash format like {"type": "approximate", "city": "New York"}
          location
        else
          raise ArgumentError, "user_location must be a String or Hash"
        end
      end

      ##
      # Validates search context size parameter
      #
      # @param size [String] Context size to validate
      # @return [String] The validated size
      # @raise [ArgumentError] if size is invalid
      # @private
      #
      def validate_search_context_size(size)
        valid_sizes = %w[low medium high]
        unless valid_sizes.include?(size)
          raise ArgumentError, "search_context_size must be one of: #{valid_sizes.join(", ")}"
        end

        size
      end
    end
  end
end
