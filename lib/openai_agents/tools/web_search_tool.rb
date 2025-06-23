# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../function_tool"

module OpenAIAgents
  module Tools
    # OpenAI hosted web search tool - matches Python specification exactly
    # Reference: https://github.com/openai/openai-agents-python
    # Uses OpenAI Responses API for actual web search functionality
    class WebSearchTool < FunctionTool
      BASE_URL = "https://api.openai.com/v1/responses"
      
      attr_reader :user_location, :search_context_size

      def initialize(user_location: nil, search_context_size: "medium", api_key: nil)
        @user_location = normalize_user_location(user_location)
        @search_context_size = validate_search_context_size(search_context_size)
        @api_key = api_key || ENV["OPENAI_API_KEY"]
        
        raise ArgumentError, "OpenAI API key is required for web search" unless @api_key

        super(method(:web_search),
              name: "web_search_preview",
              description: "Search the web for current information using OpenAI's hosted web search",
              parameters: web_search_parameters)
      end

      def web_search(query:, stream: false)
        if stream
          search_with_streaming(query)
        else
          search_with_responses_api(query)
        end
      rescue StandardError => e
        "Web search error: #{e.message}"
      end

      def search_with_streaming(query, &block)
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
              if line.start_with?("data: ")
                data = line[6..-1]
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
        end

        accumulated_content
      end

      def to_tool_definition
        {
          type: "web_search",
          name: "web_search",
          web_search: {
            user_location: @user_location,
            search_context_size: @search_context_size
          }.compact
        }
      end

      private

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
          error_data = JSON.parse(response.body) rescue {}
          error_msg = error_data.dig("error", "message") || "Bad request"
          raise "API Error: #{error_msg}"
        else
          raise "API Error: #{response.code} - #{response.body}"
        end
      end

      def extract_search_results(data)
        # Extract the final output from the response
        if data["output"] && data["output"].any?
          content = data["output"][0]
          if content["content"] && content["content"].any?
            return content["content"][0]["text"]
          end
        end

        # Fallback if structure is different
        if data["text"]
          return data["text"]
        end

        "Web search completed but no results returned."
      end

      def process_stream_event(event)
        # Extract content from streaming event (based on a.rb implementation)
        if event["output"] && event["output"][0] && event["output"][0]["content"]
          content = event["output"][0]["content"][0]["text"]
          return content if content
        end
        nil
      end

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

      def validate_search_context_size(size)
        valid_sizes = %w[low medium high]
        unless valid_sizes.include?(size)
          raise ArgumentError, "search_context_size must be one of: #{valid_sizes.join(', ')}"
        end
        size
      end
    end
  end
end